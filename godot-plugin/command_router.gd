@tool
class_name CommandRouter
extends RefCounted

## Routes incoming WebSocket commands to the appropriate handler.
## Each handler registers its supported commands with the router.
## Supports both regular and coroutine (async) handlers.
## Batch execution supports multiple modes: best_effort, fail_fast,
## atomic_if_supported, and dry_run.

var _handlers: Dictionary = {} # command_name -> Callable
var _categories: Dictionary = {} # command_name -> handler_class_name
var _command_metadata: Dictionary = {} # command_name -> metadata dict
var _ws: GodotClaudeWS
var _undo: UndoHelper


func _init(ws: GodotClaudeWS, undo: UndoHelper = null):
	_ws = ws
	_undo = undo


func register(command_name: String, handler: Callable, category: String = "meta") -> void:
	_handlers[command_name] = handler
	_categories[command_name] = category


func register_all(commands: Dictionary, handler_obj = null) -> void:
	var category := "unknown"
	if handler_obj:
		category = handler_obj.get_class() if handler_obj is Object else str(handler_obj)
		# RefCounted subclasses return "RefCounted" from get_class(), use script class name instead
		if handler_obj.get_script():
			var script_path: String = handler_obj.get_script().resource_path
			category = script_path.get_file().get_basename()
	for cmd in commands:
		_handlers[cmd] = commands[cmd]
		_categories[cmd] = category


func register_metadata(command_name: String, metadata: Dictionary) -> void:
	_command_metadata[command_name] = metadata


func get_command_metadata(command_name: String) -> Dictionary:
	return _command_metadata.get(command_name, {})


func handle(id: String, command: String, params: Dictionary) -> void:
	var peer_id: int = params.get("_peer_id", -1)
	params.erase("_peer_id")

	if not _handlers.has(command):
		_ws.send_response(
			peer_id, id, false, null,
			"Unknown command: %s" % command,
			"UNKNOWN_COMMAND",
			["Use 'list_commands' to see available commands"]
		)
		return

	var handler: Callable = _handlers[command]
	var start_time := Time.get_ticks_msec()
	var result = await _safe_call(handler, params, command)
	var elapsed := Time.get_ticks_msec() - start_time

	# Log command execution
	if result is Dictionary and result.has("_internal_error"):
		push_error("[GodotClaude] %s CRASHED (%dms): %s" % [command, elapsed, result._internal_error])
		_ws.send_response(
			peer_id, id, false, null,
			"Handler crashed: %s" % result._internal_error,
			"INTERNAL_ERROR"
		)
		return

	if elapsed > 1000:
		push_warning("[GodotClaude] %s took %dms" % [command, elapsed])

	if result == null:
		_ws.send_response(peer_id, id, true, {})
		return

	# Send response based on result type
	if result is Dictionary:
		if result.has("error"):
			_ws.send_response(
				peer_id, id, false, null,
				result.get("error", "Unknown error"),
				result.get("code", "HANDLER_ERROR"),
				result.get("suggestions", [])
			)
		else:
			_ws.send_response(peer_id, id, true, result)
	else:
		_ws.send_response(peer_id, id, true, {"value": result})


## Safely call a handler, catching any exceptions.
func _safe_call(handler: Callable, params: Dictionary, command_name: String) -> Variant:
	# GDScript doesn't have try/catch, but we can catch errors via a wrapper approach.
	# The best we can do is validate inputs and use defensive coding in handlers.
	# For now, call directly — Godot 4.6 will print the error but won't crash the plugin.
	var result = await handler.call(params)
	return result


## Execute multiple commands in a single request.
## params.commands: Array of {command: String, params: Dictionary}
## params.mode: "best_effort" (default), "fail_fast", "atomic_if_supported", "dry_run"
## Returns results array with success/error for each command.
func batch_execute(params: Dictionary) -> Dictionary:
	var commands: Array = params.get("commands", [])
	var mode: String = params.get("mode", "best_effort")

	if commands.is_empty():
		return {"error": "commands array is required and must not be empty", "code": "MISSING_PARAM"}

	if mode not in ["best_effort", "fail_fast", "atomic_if_supported", "dry_run"]:
		return {"error": "Invalid mode: %s. Use best_effort, fail_fast, atomic_if_supported, or dry_run" % mode, "code": "INVALID_MODE"}

	match mode:
		"dry_run":
			return _batch_dry_run(commands)
		"fail_fast":
			return await _batch_fail_fast(commands)
		"atomic_if_supported":
			return await _batch_atomic(commands)
		_:
			return await _batch_best_effort(commands)


## Validate all commands without executing them.
func _batch_dry_run(commands: Array) -> Dictionary:
	var results: Array = []
	var valid: int = 0
	var invalid: int = 0
	var start_time := Time.get_ticks_msec()

	for i in commands.size():
		var cmd_entry = commands[i]
		if not cmd_entry is Dictionary:
			results.append({"index": i, "valid": false, "error": "Invalid command entry"})
			invalid += 1
			continue

		var command: String = cmd_entry.get("command", "")
		var cmd_params: Dictionary = cmd_entry.get("params", {})

		if command == "":
			results.append({"index": i, "valid": false, "error": "Empty command name"})
			invalid += 1
			continue

		if not _handlers.has(command):
			results.append({"index": i, "command": command, "valid": false, "error": "Unknown command: %s" % command})
			invalid += 1
			continue

		var metadata: Dictionary = _command_metadata.get(command, {})
		results.append({
			"index": i,
			"command": command,
			"valid": true,
			"metadata": metadata,
		})
		valid += 1

	var elapsed := Time.get_ticks_msec() - start_time
	return {
		"mode": "dry_run",
		"total": commands.size(),
		"valid": valid,
		"invalid": invalid,
		"elapsed_ms": elapsed,
		"results": results,
	}


## Execute sequentially, stop at first error.
func _batch_fail_fast(commands: Array) -> Dictionary:
	var results: Array = []
	var succeeded: int = 0
	var failed: int = 0
	var start_time := Time.get_ticks_msec()

	for i in commands.size():
		var cmd_entry = commands[i]
		if not cmd_entry is Dictionary:
			results.append({"index": i, "success": false, "error": "Invalid command entry"})
			failed += 1
			break

		var command: String = cmd_entry.get("command", "")
		var cmd_params: Dictionary = cmd_entry.get("params", {})

		if command == "" or not _handlers.has(command):
			results.append({"index": i, "command": command, "success": false, "error": "Unknown command: %s" % command})
			failed += 1
			break

		var handler: Callable = _handlers[command]
		var result = await handler.call(cmd_params)
		var entry := _make_result_entry(i, command, result)
		results.append(entry)

		if not entry.success:
			failed += 1
			break
		else:
			succeeded += 1

	var elapsed := Time.get_ticks_msec() - start_time
	return {
		"mode": "fail_fast",
		"total": commands.size(),
		"executed": results.size(),
		"succeeded": succeeded,
		"failed": failed,
		"elapsed_ms": elapsed,
		"results": results,
	}


## Execute all commands, collect all results regardless of errors.
func _batch_best_effort(commands: Array) -> Dictionary:
	var results: Array = []
	var succeeded: int = 0
	var failed: int = 0
	var start_time := Time.get_ticks_msec()

	for i in commands.size():
		var cmd_entry = commands[i]
		if not cmd_entry is Dictionary:
			results.append({"index": i, "success": false, "error": "Invalid command entry"})
			failed += 1
			continue

		var command: String = cmd_entry.get("command", "")
		var cmd_params: Dictionary = cmd_entry.get("params", {})

		if command == "" or not _handlers.has(command):
			results.append({"index": i, "command": command, "success": false, "error": "Unknown command: %s" % command})
			failed += 1
			continue

		var handler: Callable = _handlers[command]
		var result = await handler.call(cmd_params)
		var entry := _make_result_entry(i, command, result)
		results.append(entry)

		if entry.success:
			succeeded += 1
		else:
			failed += 1

	var elapsed := Time.get_ticks_msec() - start_time
	return {
		"mode": "best_effort",
		"total": commands.size(),
		"succeeded": succeeded,
		"failed": failed,
		"elapsed_ms": elapsed,
		"results": results,
	}


## Wrap all undoable commands in a single undo action group.
## Non-undoable commands cause a warning; if any command fails, the action is not committed.
func _batch_atomic(commands: Array) -> Dictionary:
	var start_time := Time.get_ticks_msec()

	# Check if UndoHelper is available
	if _undo == null:
		return {"error": "atomic_if_supported requires UndoHelper but it is not available", "code": "NO_UNDO"}

	# Pre-validate and warn about non-undoable commands
	var warnings: Array = []
	for i in commands.size():
		var cmd_entry = commands[i]
		if not cmd_entry is Dictionary:
			continue
		var command: String = cmd_entry.get("command", "")
		var metadata: Dictionary = _command_metadata.get(command, {})
		if not metadata.get("undoable", false):
			warnings.append("Command '%s' (index %d) is not undoable — changes from this command cannot be rolled back" % [command, i])

	# Create a single undo action group for the entire batch
	_undo.create_action("Batch Atomic Execute (%d commands)" % commands.size())

	var results: Array = []
	var succeeded: int = 0
	var failed: int = 0
	var has_failure: bool = false

	for i in commands.size():
		var cmd_entry = commands[i]
		if not cmd_entry is Dictionary:
			results.append({"index": i, "success": false, "error": "Invalid command entry"})
			failed += 1
			has_failure = true
			break

		var command: String = cmd_entry.get("command", "")
		var cmd_params: Dictionary = cmd_entry.get("params", {})

		if command == "" or not _handlers.has(command):
			results.append({"index": i, "command": command, "success": false, "error": "Unknown command: %s" % command})
			failed += 1
			has_failure = true
			break

		var handler: Callable = _handlers[command]
		var result = await handler.call(cmd_params)
		var entry := _make_result_entry(i, command, result)
		results.append(entry)

		if not entry.success:
			failed += 1
			has_failure = true
			break
		else:
			succeeded += 1

	# Only commit if all commands succeeded
	if has_failure:
		# Do not commit — the undo action is discarded, which rolls back
		# any undoable operations that were recorded in this action group.
		# Note: non-undoable side effects (e.g., file writes) cannot be rolled back.
		_undo.commit_action(false)
	else:
		_undo.commit_action(true)

	var elapsed := Time.get_ticks_msec() - start_time
	var response: Dictionary = {
		"mode": "atomic_if_supported",
		"total": commands.size(),
		"executed": results.size(),
		"succeeded": succeeded,
		"failed": failed,
		"committed": not has_failure,
		"elapsed_ms": elapsed,
		"results": results,
	}
	if not warnings.is_empty():
		response["warnings"] = warnings
	return response


## Helper to build a standardized result entry from a handler's return value.
func _make_result_entry(index: int, command: String, result) -> Dictionary:
	if result == null:
		return {"index": index, "command": command, "success": true, "result": {}}
	elif result is Dictionary and result.has("error"):
		return {"index": index, "command": command, "success": false, "error": result.get("error")}
	elif result is Dictionary:
		return {"index": index, "command": command, "success": true, "result": result}
	else:
		return {"index": index, "command": command, "success": true, "result": {"value": result}}


func get_command_list() -> Array[String]:
	var cmds: Array[String] = []
	for cmd in _handlers:
		cmds.append(cmd)
	cmds.sort()
	return cmds


func get_command_categories() -> Dictionary:
	return _categories.duplicate()


func get_command_details() -> Dictionary:
	var details: Dictionary = {}
	for cmd in _handlers:
		details[cmd] = {
			"category": _categories.get(cmd, "meta"),
			"metadata": _command_metadata.get(cmd, {}),
		}
	return details
