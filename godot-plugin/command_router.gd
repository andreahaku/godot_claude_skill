@tool
class_name CommandRouter
extends RefCounted

## Routes incoming WebSocket commands to the appropriate handler.
## Each handler registers its supported commands with the router.
## Supports both regular and coroutine (async) handlers.

var _handlers: Dictionary = {} # command_name -> Callable
var _ws: GodotClaudeWS


func _init(ws: GodotClaudeWS):
	_ws = ws


func register(command_name: String, handler: Callable) -> void:
	_handlers[command_name] = handler


func register_all(commands: Dictionary) -> void:
	for cmd in commands:
		_handlers[cmd] = commands[cmd]


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

	# Call the handler - await supports both regular and coroutine functions
	var handler: Callable = _handlers[command]
	var result = await handler.call(params)

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


## Execute multiple commands in a single request.
## params.commands: Array of {command: String, params: Dictionary}
## Returns results array with success/error for each command.
func batch_execute(params: Dictionary) -> Dictionary:
	var commands: Array = params.get("commands", [])
	if commands.is_empty():
		return {"error": "commands array is required and must not be empty", "code": "MISSING_PARAM"}

	var results: Array = []
	var succeeded: int = 0
	var failed: int = 0

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

		if result == null:
			results.append({"index": i, "command": command, "success": true, "result": {}})
			succeeded += 1
		elif result is Dictionary and result.has("error"):
			results.append({"index": i, "command": command, "success": false, "error": result.get("error")})
			failed += 1
		elif result is Dictionary:
			results.append({"index": i, "command": command, "success": true, "result": result})
			succeeded += 1
		else:
			results.append({"index": i, "command": command, "success": true, "result": {"value": result}})
			succeeded += 1

	return {"total": commands.size(), "succeeded": succeeded, "failed": failed, "results": results}


func get_command_list() -> Array[String]:
	var cmds: Array[String] = []
	for cmd in _handlers:
		cmds.append(cmd)
	cmds.sort()
	return cmds
