class_name GodotClaudeWS
extends Node

## WebSocket server for receiving commands from Claude Code.
## Listens on ws://localhost:9080 by default.
## Supports heartbeat, auto-reconnect detection, and JSON-RPC style messaging.

signal command_received(id: String, command: String, params: Dictionary)

const DEFAULT_PORT := 9080
const HEARTBEAT_INTERVAL := 5.0

var _server: TCPServer
var _peers: Dictionary = {} # peer_id -> StreamPeerTCP
var _ws_peers: Dictionary = {} # peer_id -> WebSocketPeer
var _port: int = DEFAULT_PORT
var _next_peer_id: int = 0
var _heartbeat_timer: float = 0.0

func _init(port: int = DEFAULT_PORT):
	_port = port


func start() -> Error:
	_server = TCPServer.new()
	var err = _server.listen(_port, "127.0.0.1")
	if err != OK:
		push_error("[GodotClaude] Failed to start WebSocket server on port %d: %s" % [_port, error_string(err)])
		return err
	print("[GodotClaude] WebSocket server listening on ws://127.0.0.1:%d" % _port)
	return OK


func stop() -> void:
	for peer_id in _ws_peers:
		var ws: WebSocketPeer = _ws_peers[peer_id]
		ws.close(1000, "Server shutting down")
	_ws_peers.clear()
	_peers.clear()
	if _server:
		_server.stop()
		_server = null
	print("[GodotClaude] WebSocket server stopped")


func poll() -> void:
	if _server == null:
		return

	# Accept new TCP connections
	while _server.is_connection_available():
		var tcp = _server.take_connection()
		if tcp:
			var peer_id = _next_peer_id
			_next_peer_id += 1
			_peers[peer_id] = tcp

			var ws = WebSocketPeer.new()
			ws.accept_stream(tcp)
			_ws_peers[peer_id] = ws
			print("[GodotClaude] New connection: peer_%d" % peer_id)

	# Poll all WebSocket peers
	var to_remove: Array[int] = []
	for peer_id in _ws_peers:
		var ws: WebSocketPeer = _ws_peers[peer_id]
		ws.poll()

		var state = ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			while ws.get_available_packet_count() > 0:
				var data = ws.get_packet().get_string_from_utf8()
				_handle_message(peer_id, data)
		elif state == WebSocketPeer.STATE_CLOSING:
			pass
		elif state == WebSocketPeer.STATE_CLOSED:
			var code = ws.get_close_code()
			var reason = ws.get_close_reason()
			print("[GodotClaude] Peer %d disconnected: %d %s" % [peer_id, code, reason])
			to_remove.append(peer_id)

	for peer_id in to_remove:
		_ws_peers.erase(peer_id)
		_peers.erase(peer_id)


func send_response(peer_id: int, id: String, success: bool, result: Variant = null, error_msg: String = "", error_code: String = "", suggestions: Array = []) -> void:
	var response: Dictionary = {
		"id": id,
		"success": success,
	}
	if success:
		response["result"] = result if result != null else {}
	else:
		response["error"] = error_msg
		if error_code != "":
			response["code"] = error_code
		if suggestions.size() > 0:
			response["suggestions"] = suggestions

	var json_str = JSON.stringify(response)
	_send_to_peer(peer_id, json_str)


func broadcast_response(id: String, success: bool, result: Variant = null, error_msg: String = "") -> void:
	for peer_id in _ws_peers:
		send_response(peer_id, id, success, result, error_msg)


func _send_to_peer(peer_id: int, data: String) -> void:
	if _ws_peers.has(peer_id):
		var ws: WebSocketPeer = _ws_peers[peer_id]
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(data)


func _handle_message(peer_id: int, data: String) -> void:
	var json = JSON.new()
	var err = json.parse(data)
	if err != OK:
		send_response(peer_id, "", false, null, "Invalid JSON: " + json.get_error_message(), "PARSE_ERROR")
		return

	var msg = json.get_data()
	if not msg is Dictionary:
		send_response(peer_id, "", false, null, "Message must be a JSON object", "PARSE_ERROR")
		return

	var id: String = str(msg.get("id", ""))

	# Handle heartbeat / ping
	var command: String = msg.get("command", "")
	if command == "ping":
		send_response(peer_id, id, true, {"pong": true, "timestamp": Time.get_unix_time_from_system()})
		return

	if command == "":
		send_response(peer_id, id, false, null, "Missing 'command' field", "MISSING_COMMAND")
		return

	var params: Dictionary = msg.get("params", {})

	# Store peer_id in params so handlers can respond
	params["_peer_id"] = peer_id

	command_received.emit(id, command, params)
