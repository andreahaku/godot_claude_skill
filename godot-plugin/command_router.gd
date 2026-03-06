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
	elif result == null:
		_ws.send_response(peer_id, id, true, {})
	else:
		_ws.send_response(peer_id, id, true, {"value": result})


func get_command_list() -> Array[String]:
	var cmds: Array[String] = []
	for cmd in _handlers:
		cmds.append(cmd)
	cmds.sort()
	return cmds
