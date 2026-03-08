@tool
class_name GodotClaudeWS
extends Node

## WebSocket server for receiving commands from Claude Code.
## Listens on ws://localhost:9080 by default.
## Supports heartbeat, auto-reconnect detection, and JSON-RPC style messaging.

signal command_received(id: String, command: String, params: Dictionary)
signal peer_disconnected(peer_id: int)

const DEFAULT_PORT := 9080
const HEARTBEAT_INTERVAL := 5.0
const MAX_CONNECTIONS := 32
const MAX_MESSAGE_BYTES := 16 * 1024 * 1024  # 16 MB
const HANDSHAKE_TIMEOUT := 10.0  # seconds

var _server: TCPServer
var _peers: Dictionary = {} # peer_id -> StreamPeerTCP
var _ws_peers: Dictionary = {} # peer_id -> WebSocketPeer
var _peer_meta: Dictionary = {} # peer_id -> {connected_at, last_activity, state}
var _port: int = DEFAULT_PORT
var _next_peer_id: int = 0
var _heartbeat_timer: float = 0.0
var _accepted_connections: int = 0
var _rejected_connections: int = 0
var _stale_pruned_connections: int = 0
var _last_command_at: float = 0.0
var _last_disconnect: Dictionary = {}

func _init(port: int = DEFAULT_PORT):
	_port = port
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func start() -> Error:
	_server = TCPServer.new()
	var err = _server.listen(_port, "127.0.0.1")
	if err != OK:
		push_error("[GodotClaude] Failed to start WebSocket server on port %d: %s" % [_port, error_string(err)])
		return err
	set_process(true)
	print("[GodotClaude] WebSocket server listening on ws://127.0.0.1:%d" % _port)
	return OK


func stop() -> void:
	for peer_id in _ws_peers:
		var ws: WebSocketPeer = _ws_peers[peer_id]
		ws.close(1000, "Server shutting down")
	_ws_peers.clear()
	_peers.clear()
	_peer_meta.clear()
	if _server:
		_server.stop()
		_server = null
	set_process(false)
	print("[GodotClaude] WebSocket server stopped")


func _process(_delta: float) -> void:
	poll()


func poll() -> void:
	if _server == null:
		return

	_prune_stale_peers()

	# Accept new TCP connections
	while _server.is_connection_available():
		var tcp = _server.take_connection()
		if tcp:
			if _ws_peers.size() >= MAX_CONNECTIONS:
				tcp.disconnect_from_host()
				_rejected_connections += 1
				push_warning("[GodotClaude] Connection rejected: max %d peers reached" % MAX_CONNECTIONS)
				continue

			var peer_id = _next_peer_id
			_next_peer_id += 1
			_peers[peer_id] = tcp

			var ws = WebSocketPeer.new()
			ws.accept_stream(tcp)
			_ws_peers[peer_id] = ws
			var now := Time.get_unix_time_from_system()
			_peer_meta[peer_id] = {
				"connected_at": now,
				"last_activity": now,
				"state": "connecting",
			}
			_accepted_connections += 1
			print("[GodotClaude] New connection: peer_%d (%d active)" % [peer_id, _ws_peers.size()])

	# Poll all WebSocket peers
	var to_remove: Array[int] = []
	for peer_id in _ws_peers:
		var ws: WebSocketPeer = _ws_peers[peer_id]
		ws.poll()

		var state = ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			_update_peer_meta(peer_id, "open", false)
			while ws.get_available_packet_count() > 0:
				var packet = ws.get_packet()
				_update_peer_meta(peer_id, "open", true)
				if packet.size() > MAX_MESSAGE_BYTES:
					send_response(peer_id, "", false, null,
						"Message too large: %d bytes (max %d)" % [packet.size(), MAX_MESSAGE_BYTES],
						"MESSAGE_TOO_LARGE")
					continue
				var data = packet.get_string_from_utf8()
				_handle_message(peer_id, data)
		elif state == WebSocketPeer.STATE_CLOSING:
			_update_peer_meta(peer_id, "closing", false)
		elif state == WebSocketPeer.STATE_CLOSED:
			var code = ws.get_close_code()
			var reason = ws.get_close_reason()
			_last_disconnect = {"peer_id": peer_id, "code": code, "reason": reason, "time": Time.get_unix_time_from_system()}
			print("[GodotClaude] Peer %d disconnected: %d %s" % [peer_id, code, reason])
			to_remove.append(peer_id)
		else:
			_update_peer_meta(peer_id, "connecting", false)

	for peer_id in to_remove:
		_remove_peer(peer_id, true)


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


func send_event(peer_id: int, event_type: String, data: Dictionary) -> void:
	var msg: Dictionary = {
		"type": "event",
		"event": event_type,
		"data": data,
		"timestamp": Time.get_unix_time_from_system(),
	}
	_send_to_peer(peer_id, JSON.stringify(msg))


func broadcast_event(event_type: String, data: Dictionary) -> void:
	for peer_id in _ws_peers:
		send_event(peer_id, event_type, data)


func _send_to_peer(peer_id: int, data: String) -> void:
	if _ws_peers.has(peer_id):
		var ws: WebSocketPeer = _ws_peers[peer_id]
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			var err := ws.send_text(data)
			if err != OK:
				push_warning("[GodotClaude] Failed to send to peer %d: %s" % [peer_id, error_string(err)])
				_remove_peer(peer_id, true)


func _handle_message(peer_id: int, data: String) -> void:
	_last_command_at = Time.get_unix_time_from_system()
	_update_peer_meta(peer_id, "open", true)
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


func get_status() -> Dictionary:
	return {
		"running": _server != null,
		"port": _port,
		"active_peers": _ws_peers.size(),
		"max_connections": MAX_CONNECTIONS,
		"accepted_connections": _accepted_connections,
		"rejected_connections": _rejected_connections,
		"stale_pruned_connections": _stale_pruned_connections,
		"last_command_at": _last_command_at,
		"last_disconnect": _last_disconnect.duplicate(),
	}


func _prune_stale_peers() -> void:
	var now := Time.get_unix_time_from_system()
	var to_remove: Array[int] = []
	for peer_id in _ws_peers:
		var meta: Dictionary = _peer_meta.get(peer_id, {})
		var connected_at: float = meta.get("connected_at", now)
		var state: int = _ws_peers[peer_id].get_ready_state()
		if not _is_tcp_connected(peer_id):
			to_remove.append(peer_id)
		elif state != WebSocketPeer.STATE_OPEN and now - connected_at > HANDSHAKE_TIMEOUT:
			to_remove.append(peer_id)

	for peer_id in to_remove:
		_stale_pruned_connections += 1
		push_warning("[GodotClaude] Pruned stale peer %d" % peer_id)
		_remove_peer(peer_id, true)


func _update_peer_meta(peer_id: int, state: String, touched: bool) -> void:
	if not _peer_meta.has(peer_id):
		return
	var meta: Dictionary = _peer_meta[peer_id]
	meta["state"] = state
	if touched:
		meta["last_activity"] = Time.get_unix_time_from_system()
	_peer_meta[peer_id] = meta


func _remove_peer(peer_id: int, emit_disconnect: bool) -> void:
	if _ws_peers.has(peer_id):
		var ws: WebSocketPeer = _ws_peers[peer_id]
		if ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
			ws.close(1000, "Server cleanup")
	if _peers.has(peer_id):
		var tcp: StreamPeerTCP = _peers[peer_id]
		if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			tcp.disconnect_from_host()
	_ws_peers.erase(peer_id)
	_peers.erase(peer_id)
	_peer_meta.erase(peer_id)
	if emit_disconnect:
		peer_disconnected.emit(peer_id)


func _is_tcp_connected(peer_id: int) -> bool:
	if not _peers.has(peer_id):
		return false
	var tcp: StreamPeerTCP = _peers[peer_id]
	return tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED
