@tool
class_name BridgeServer
extends Node

## Accepts WebSocket connections from the runtime bridge running in the game process.
## Forwards commands from the editor to the game and routes responses back.
##
## The bridge server listens on port 9081 (separate from the main WS server on 9080).
## Only one bridge connection (the game process) is accepted at a time.
## Commands are sent with unique IDs and responses are matched by ID.

signal bridge_connected()
signal bridge_disconnected()
signal bridge_response_received(id: String, result: Dictionary)

const BRIDGE_PORT := 9081
const REQUEST_TIMEOUT := 10.0  # seconds
const LONG_TIMEOUT := 60.0  # seconds — for replay, frame capture, etc.
## Commands that may take longer than the default timeout
const LONG_RUNNING_COMMANDS: Array[String] = [
	"bridge_replay_recording", "bridge_simulate_sequence", "bridge_capture_screenshot",
]

var _server: TCPServer
var _bridge_peer: WebSocketPeer
var _bridge_tcp: StreamPeerTCP
var _pending_requests: Dictionary = {}  # id_str -> {time: float, command: String}
var _is_bridge_connected: bool = false
var _next_request_id: int = 0
var _handshake_received: bool = false
var _bridge_info: Dictionary = {}  # Info from the bridge handshake

# Opt-in tracing for debugging bridge round-trips
var _trace_enabled: bool = false
var _trace_log: Array = []  # Array of {command, id, duration_ms, success, error}
const MAX_TRACE_LOG := 200


func start() -> Error:
	_server = TCPServer.new()
	var err := _server.listen(BRIDGE_PORT, "127.0.0.1")
	if err != OK:
		push_error("[BridgeServer] Failed to start on port %d: %s" % [BRIDGE_PORT, error_string(err)])
		return err
	print("[BridgeServer] Listening on ws://127.0.0.1:%d for game bridge connections" % BRIDGE_PORT)
	return OK


func stop() -> void:
	if _bridge_peer and _bridge_peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_bridge_peer.close(1000, "Server shutting down")
	_bridge_peer = null
	_bridge_tcp = null
	_is_bridge_connected = false
	_handshake_received = false
	_pending_requests.clear()
	if _server:
		_server.stop()
		_server = null
	print("[BridgeServer] Stopped")


func poll() -> void:
	if _server == null:
		return

	# Accept new TCP connections
	while _server.is_connection_available():
		var tcp := _server.take_connection()
		if tcp:
			if _is_bridge_connected:
				# Only one bridge at a time; reject new connections
				tcp.disconnect_from_host()
				push_warning("[BridgeServer] Rejected additional bridge connection (already connected)")
				continue

			_bridge_tcp = tcp
			_bridge_peer = WebSocketPeer.new()
			_bridge_peer.accept_stream(tcp)
			print("[BridgeServer] New bridge connection accepted, waiting for handshake...")

	# Poll the bridge peer
	if _bridge_peer:
		_bridge_peer.poll()

		var state := _bridge_peer.get_ready_state()
		match state:
			WebSocketPeer.STATE_OPEN:
				while _bridge_peer.get_available_packet_count() > 0:
					var packet := _bridge_peer.get_packet()
					var data := packet.get_string_from_utf8()
					_handle_bridge_message(data)

			WebSocketPeer.STATE_CLOSING:
				pass

			WebSocketPeer.STATE_CLOSED:
				if _is_bridge_connected:
					print("[BridgeServer] Bridge disconnected (code: %d)" % _bridge_peer.get_close_code())
					_is_bridge_connected = false
					_handshake_received = false
					_bridge_info.clear()
					# Fail all pending requests
					_fail_pending_requests("Bridge disconnected")
					bridge_disconnected.emit()
				_bridge_peer = null
				_bridge_tcp = null

	# Timeout stale pending requests
	_check_timeouts()


func is_bridge_connected() -> bool:
	return _is_bridge_connected and _handshake_received


func get_bridge_info() -> Dictionary:
	return _bridge_info.duplicate()


func set_trace_enabled(enabled: bool) -> void:
	_trace_enabled = enabled
	if enabled:
		print("[BridgeServer] Command tracing enabled")
	else:
		print("[BridgeServer] Command tracing disabled")


func get_trace_log(last: int = 0) -> Array:
	if last > 0 and last < _trace_log.size():
		return _trace_log.slice(_trace_log.size() - last)
	return _trace_log.duplicate()


func clear_trace_log() -> void:
	_trace_log.clear()


## Send a command to the game bridge and return the request ID.
## Listen for bridge_response_received signal with matching ID to get the result.
func send_command(command: String, params: Dictionary = {}) -> String:
	if not is_bridge_connected():
		return ""

	var request_id := str(_next_request_id)
	_next_request_id += 1

	var message := {
		"id": request_id,
		"command": command,
		"params": params,
	}

	_bridge_peer.send_text(JSON.stringify(message))

	_pending_requests[request_id] = {
		"time": Time.get_unix_time_from_system(),
		"command": command,
	}

	return request_id


## Send a command and wait for the response (blocking via await).
## Returns the result dictionary or an error dictionary.
func send_command_await(command: String, params: Dictionary = {}) -> Dictionary:
	if not is_bridge_connected():
		return {"error": "Runtime bridge is not connected. Start the game first.", "code": "BRIDGE_NOT_CONNECTED"}

	var request_id := send_command(command, params)
	if request_id == "":
		return {"error": "Failed to send command to bridge", "code": "BRIDGE_SEND_FAILED"}

	var start_time := Time.get_unix_time_from_system()

	# Use longer timeout for known long-running commands
	var timeout := LONG_TIMEOUT if command in LONG_RUNNING_COMMANDS else REQUEST_TIMEOUT
	var timeout_time := start_time + timeout
	while _pending_requests.has(request_id):
		if Time.get_unix_time_from_system() > timeout_time:
			_pending_requests.erase(request_id)
			_trace_command(command, request_id, start_time, false, "TIMEOUT")
			return {"error": "Bridge request timed out after %s seconds" % str(timeout), "code": "BRIDGE_TIMEOUT"}
		# Yield for one frame so the bridge can receive the response
		await Engine.get_main_loop().process_frame

	# Response was received and stored
	var response_key := "_response_" + request_id
	if _pending_requests.has(response_key):
		var result: Dictionary = _pending_requests[response_key]
		_pending_requests.erase(response_key)
		_trace_command(command, request_id, start_time, not result.has("error"),
			result.get("error", ""))
		return result

	_trace_command(command, request_id, start_time, false, "NO_RESPONSE")
	return {"error": "No response received from bridge", "code": "BRIDGE_NO_RESPONSE"}


func _handle_bridge_message(data: String) -> void:
	var json := JSON.new()
	var err := json.parse(data)
	if err != OK:
		push_warning("[BridgeServer] Invalid JSON from bridge: %s" % json.get_error_message())
		return

	var msg = json.get_data()
	if not msg is Dictionary:
		push_warning("[BridgeServer] Bridge message must be a JSON object")
		return

	# Check for handshake
	if not _handshake_received:
		if msg.get("type", "") == "bridge":
			_handshake_received = true
			_is_bridge_connected = true
			_bridge_info = {
				"version": msg.get("version", "unknown"),
				"godot_version": msg.get("godot_version", "unknown"),
			}
			print("[BridgeServer] Bridge handshake complete (version: %s)" % _bridge_info.get("version", "unknown"))
			bridge_connected.emit()
		else:
			push_warning("[BridgeServer] Expected bridge handshake, got: %s" % data)
		return

	# Handle response to a pending request
	var id: String = str(msg.get("id", ""))
	if id == "":
		push_warning("[BridgeServer] Bridge message missing id field")
		return

	if not _pending_requests.has(id):
		push_warning("[BridgeServer] Received response for unknown request ID: %s" % id)
		return

	# Remove from pending
	_pending_requests.erase(id)

	# Extract result
	var result: Dictionary = {}
	var success: bool = msg.get("success", false)
	if success:
		result = msg.get("result", {})
	else:
		result = {
			"error": msg.get("error", "Unknown bridge error"),
			"code": msg.get("code", "BRIDGE_ERROR"),
		}

	# Store response for send_command_await
	_pending_requests["_response_" + id] = result

	# Emit signal for anyone listening
	bridge_response_received.emit(id, result)


func _check_timeouts() -> void:
	var now := Time.get_unix_time_from_system()
	var timed_out: Array[String] = []
	for id in _pending_requests:
		# Skip response storage entries
		if id.begins_with("_response_"):
			continue
		var req: Dictionary = _pending_requests[id]
		var cmd: String = req.get("command", "")
		var timeout := LONG_TIMEOUT if cmd in LONG_RUNNING_COMMANDS else REQUEST_TIMEOUT
		if now - req.get("time", now) > timeout:
			timed_out.append(id)

	for id in timed_out:
		push_warning("[BridgeServer] Request %s timed out (command: %s)" % [id, _pending_requests[id].get("command", "?")])
		_pending_requests.erase(id)
		# Store timeout error as response
		_pending_requests["_response_" + id] = {
			"error": "Bridge request timed out",
			"code": "BRIDGE_TIMEOUT",
		}
		bridge_response_received.emit(id, {"error": "Bridge request timed out", "code": "BRIDGE_TIMEOUT"})


func _fail_pending_requests(reason: String) -> void:
	var ids: Array = []
	for id in _pending_requests:
		if not id.begins_with("_response_"):
			ids.append(id)

	for id in ids:
		_pending_requests.erase(id)
		var error_result := {"error": reason, "code": "BRIDGE_DISCONNECTED"}
		_pending_requests["_response_" + id] = error_result
		bridge_response_received.emit(id, error_result)


func _trace_command(command: String, id: String, start_time: float, success: bool, error_msg: String = "") -> void:
	if not _trace_enabled:
		return

	var duration_ms := int((Time.get_unix_time_from_system() - start_time) * 1000)
	var entry := {"command": command, "id": id, "duration_ms": duration_ms, "success": success}
	if not success and error_msg != "":
		entry["error"] = error_msg

	_trace_log.append(entry)
	if _trace_log.size() > MAX_TRACE_LOG:
		_trace_log.pop_front()

	if success:
		print("[BridgeTrace] %s #%s OK (%dms)" % [command, id, duration_ms])
	else:
		print("[BridgeTrace] %s #%s FAIL (%dms): %s" % [command, id, duration_ms, error_msg])
