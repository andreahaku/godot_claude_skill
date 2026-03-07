# NOT @tool -- this runs in the game process, not the editor
extends Node

## Runtime bridge that runs inside the game process.
## Connects back to the editor plugin via WebSocket to enable
## real game introspection and manipulation.
##
## This script is added as an autoload to the game project.
## When the game runs, it connects to the BridgeServer in the editor
## on port 9081 and responds to commands for scene inspection,
## property manipulation, input injection, and screenshots.

const BRIDGE_PORT := 9081
const RECONNECT_INTERVAL := 2.0
const MAX_DEPTH := 64
const LOG_BUFFER_SIZE := 256

var _ws: WebSocketPeer
var _connected: bool = false
var _reconnect_timer: float = 0.0
var _handshake_sent: bool = false


func _ready() -> void:
	print("[RuntimeBridge] Initializing game-side bridge...")
	_connect_to_editor()


func _connect_to_editor() -> void:
	_ws = WebSocketPeer.new()
	var url := "ws://127.0.0.1:%d" % BRIDGE_PORT
	var err := _ws.connect_to_url(url)
	if err != OK:
		push_warning("[RuntimeBridge] Failed to initiate connection to editor: %s" % error_string(err))
		_connected = false
		_handshake_sent = false
	else:
		print("[RuntimeBridge] Connecting to editor at %s..." % url)


func _process(delta: float) -> void:
	if _ws == null:
		return

	_ws.poll()

	var state := _ws.get_ready_state()

	match state:
		WebSocketPeer.STATE_CONNECTING:
			pass  # Still connecting, wait

		WebSocketPeer.STATE_OPEN:
			if not _handshake_sent:
				_send_handshake()
				_handshake_sent = true
				_connected = true
				_reconnect_timer = 0.0
				print("[RuntimeBridge] Connected to editor bridge")

			# Process incoming commands
			while _ws.get_available_packet_count() > 0:
				var packet := _ws.get_packet()
				var data := packet.get_string_from_utf8()
				_handle_message(data)

		WebSocketPeer.STATE_CLOSING:
			pass  # Wait for close to complete

		WebSocketPeer.STATE_CLOSED:
			if _connected:
				print("[RuntimeBridge] Disconnected from editor bridge")
			_connected = false
			_handshake_sent = false
			_ws = null

			# Attempt reconnection after interval
			_reconnect_timer += delta
			if _reconnect_timer >= RECONNECT_INTERVAL:
				_reconnect_timer = 0.0
				_connect_to_editor()
			return

	# Handle reconnect when ws is null (initial connection failed)
	if not _connected and _ws == null:
		_reconnect_timer += delta
		if _reconnect_timer >= RECONNECT_INTERVAL:
			_reconnect_timer = 0.0
			_connect_to_editor()


func _send_handshake() -> void:
	var handshake := {
		"type": "bridge",
		"version": "1.0",
		"godot_version": "%s.%s.%s" % [
			Engine.get_version_info().major,
			Engine.get_version_info().minor,
			Engine.get_version_info().patch
		],
	}
	_ws.send_text(JSON.stringify(handshake))


func _handle_message(data: String) -> void:
	var json := JSON.new()
	var err := json.parse(data)
	if err != OK:
		_send_error("", "Invalid JSON: %s" % json.get_error_message(), "PARSE_ERROR")
		return

	var msg = json.get_data()
	if not msg is Dictionary:
		_send_error("", "Message must be a JSON object", "PARSE_ERROR")
		return

	var id: String = str(msg.get("id", ""))
	var command: String = msg.get("command", "")
	var params: Dictionary = msg.get("params", {})

	if command == "":
		_send_error(id, "Missing 'command' field", "MISSING_COMMAND")
		return

	# Route command — some commands are async (e.g. capture_screenshot)
	if command == "bridge_capture_screenshot":
		var result: Dictionary = await _capture_screenshot(params)
		_send_response(id, result)
	else:
		var result: Dictionary = _handle_command(command, params)
		_send_response(id, result)


func _handle_command(command: String, params: Dictionary) -> Dictionary:
	match command:
		"bridge_get_scene_tree":
			return _get_scene_tree(params)
		"bridge_get_node_properties":
			return _get_node_properties(params)
		"bridge_set_node_properties":
			return _set_node_properties(params)
		"bridge_find_ui_elements":
			return _find_ui_elements(params)
		"bridge_click_button":
			return _click_button(params)
		"bridge_inject_input":
			return _inject_input(params)
		"bridge_capture_screenshot":
			return {"error": "Screenshot handled via async path", "code": "INTERNAL_ERROR"}
		"bridge_execute_script":
			return _execute_script(params)
		"bridge_get_output_log":
			return _get_output_log(params)
		_:
			return {"error": "Unknown bridge command: %s" % command, "code": "UNKNOWN_COMMAND"}


func _send_response(id: String, result: Dictionary) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	var response: Dictionary = {"id": id}
	if result.has("error"):
		response["success"] = false
		response["error"] = result["error"]
		if result.has("code"):
			response["code"] = result["code"]
	else:
		response["success"] = true
		response["result"] = result

	_ws.send_text(JSON.stringify(response))


func _send_error(id: String, error_msg: String, error_code: String) -> void:
	_send_response(id, {"error": error_msg, "code": error_code})


# ---------------------------------------------------------------------------
# Command implementations
# ---------------------------------------------------------------------------

func _get_scene_tree(params: Dictionary) -> Dictionary:
	var tree := get_tree()
	if tree == null:
		return {"error": "Cannot access scene tree", "code": "NO_TREE"}

	var root := tree.current_scene
	if root == null:
		return {"error": "No current scene", "code": "NO_SCENE"}

	var max_depth: int = params.get("max_depth", MAX_DEPTH)
	return {"tree": _node_to_dict(root, 0, max_depth)}


func _get_node_properties(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path == "":
		return {"error": "node_path parameter is required", "code": "MISSING_PARAM"}

	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return {"error": "No current scene", "code": "NO_SCENE"}

	var node: Node = tree.current_scene.get_node_or_null(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var props: Dictionary = {}
	for prop in node.get_property_list():
		if prop.usage & PROPERTY_USAGE_EDITOR or prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			props[prop.name] = _value_to_json(node.get(prop.name))

	return {"node_path": node_path, "properties": props}


func _set_node_properties(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var properties: Dictionary = params.get("properties", {})
	if node_path == "" or properties.is_empty():
		return {"error": "node_path and properties are required", "code": "MISSING_PARAM"}

	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return {"error": "No current scene", "code": "NO_SCENE"}

	var node: Node = tree.current_scene.get_node_or_null(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var changed: Dictionary = {}
	for key in properties:
		var old_val = node.get(key)
		var new_val = _parse_value(properties[key])
		node.set(key, new_val)
		changed[key] = {"old": _value_to_json(old_val), "new": _value_to_json(new_val)}

	return {"node_path": node_path, "changed": changed}


func _find_ui_elements(params: Dictionary) -> Dictionary:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return {"error": "No current scene", "code": "NO_SCENE"}

	var elements: Array = []
	_find_controls(tree.current_scene, elements, 0, MAX_DEPTH)
	return {"elements": elements, "count": elements.size()}


func _click_button(params: Dictionary) -> Dictionary:
	var text: String = params.get("text", "")
	var button_path: String = params.get("node_path", "")

	if text == "" and button_path == "":
		return {"error": "text or node_path parameter is required", "code": "MISSING_PARAM"}

	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return {"error": "No current scene", "code": "NO_SCENE"}

	# Find by path first if provided
	if button_path != "":
		var node: Node = tree.current_scene.get_node_or_null(button_path)
		if node == null:
			return {"error": "Node not found: %s" % button_path, "code": "NODE_NOT_FOUND"}
		if node is BaseButton:
			node.emit_signal("pressed")
			var btn_text := ""
			if node is Button:
				btn_text = node.text
			return {"clicked": str(node.name), "path": str(node.get_path()), "text": btn_text}
		else:
			return {"error": "Node is not a button: %s" % button_path, "code": "NOT_A_BUTTON"}

	# Find by text
	var buttons: Array = []
	_find_buttons(tree.current_scene, text, buttons)

	if buttons.is_empty():
		return {"error": "No button found with text: %s" % text, "code": "NOT_FOUND"}

	var button: BaseButton = buttons[0]
	button.emit_signal("pressed")
	return {"clicked": str(button.name), "text": text}


func _inject_input(params: Dictionary) -> Dictionary:
	var event_type: String = params.get("type", "")
	if event_type == "":
		return {"error": "type parameter is required (key, mouse_button, mouse_motion, action)", "code": "MISSING_PARAM"}

	match event_type:
		"key":
			var ev := InputEventKey.new()
			var key_str: String = params.get("key", "")
			if key_str == "":
				return {"error": "key parameter is required for key events", "code": "MISSING_PARAM"}
			ev.keycode = _string_to_keycode(key_str)
			if ev.keycode == KEY_NONE:
				return {"error": "Unknown key: %s" % key_str, "code": "INVALID_KEY"}
			ev.pressed = params.get("pressed", true)
			ev.shift_pressed = params.get("shift", false)
			ev.ctrl_pressed = params.get("ctrl", false)
			ev.alt_pressed = params.get("alt", false)
			ev.meta_pressed = params.get("meta", false)
			Input.parse_input_event(ev)
			return {"injected": "key", "key": key_str, "pressed": ev.pressed}

		"mouse_button":
			var ev := InputEventMouseButton.new()
			ev.position = Vector2(params.get("x", 0), params.get("y", 0))
			ev.button_index = params.get("button", MOUSE_BUTTON_LEFT)
			ev.pressed = params.get("pressed", true)
			ev.double_click = params.get("double_click", false)
			Input.parse_input_event(ev)
			return {"injected": "mouse_button", "position": _value_to_json(ev.position), "button": ev.button_index}

		"mouse_motion":
			var ev := InputEventMouseMotion.new()
			ev.position = Vector2(params.get("x", 0), params.get("y", 0))
			ev.relative = Vector2(params.get("rel_x", 0), params.get("rel_y", 0))
			Input.parse_input_event(ev)
			return {"injected": "mouse_motion", "position": _value_to_json(ev.position)}

		"action":
			var action_name: String = params.get("action", "")
			if action_name == "":
				return {"error": "action parameter is required for action events", "code": "MISSING_PARAM"}
			var pressed: bool = params.get("pressed", true)
			var strength: float = params.get("strength", 1.0)
			if pressed:
				Input.action_press(action_name, strength)
			else:
				Input.action_release(action_name)
			return {"injected": "action", "action": action_name, "pressed": pressed}

		_:
			return {"error": "Unknown event type: %s. Use key, mouse_button, mouse_motion, or action" % event_type, "code": "INVALID_TYPE"}


func _capture_screenshot(params: Dictionary) -> Dictionary:
	var save_path: String = params.get("save_path", "")
	if save_path == "":
		var timestamp := str(Time.get_unix_time_from_system()).replace(".", "_")
		save_path = "user://bridge_screenshot_%s.png" % timestamp

	var viewport := get_viewport()
	if viewport == null:
		return {"error": "No viewport available", "code": "NO_VIEWPORT"}

	# We need to wait for the frame to render before capturing
	await RenderingServer.frame_post_draw

	var img := viewport.get_texture().get_image()
	if img == null:
		return {"error": "Failed to capture viewport image", "code": "CAPTURE_FAILED"}

	var global_path: String
	if save_path.begins_with("res://") or save_path.begins_with("user://"):
		global_path = ProjectSettings.globalize_path(save_path)
	else:
		global_path = save_path

	# Ensure directory exists
	var dir_path := global_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)

	var err := img.save_png(global_path)
	if err != OK:
		return {"error": "Failed to save screenshot: %s" % error_string(err), "code": "SAVE_FAILED"}

	return {
		"path": save_path,
		"global_path": global_path,
		"size": {"width": img.get_width(), "height": img.get_height()},
	}


func _execute_script(params: Dictionary) -> Dictionary:
	var code: String = params.get("code", "")
	if code == "":
		return {"error": "code parameter is required", "code": "MISSING_PARAM"}

	var script := GDScript.new()
	script.source_code = "extends RefCounted\nvar _tree: SceneTree\nvar _result: Variant = null\n\nfunc run(tree: SceneTree):\n\t_tree = tree\n\tvar scene = tree.current_scene\n\t%s\n\treturn _result\n" % code

	var err := script.reload()
	if err != OK:
		return {"error": "Script compilation failed", "code": "COMPILE_ERROR"}

	var instance = script.new()
	var result = instance.run(get_tree())

	return {"result": _value_to_json(result)}


func _get_output_log(params: Dictionary) -> Dictionary:
	# NOTE: Godot does not expose a way to programmatically capture print output
	# from within the game process. The print/push_error output goes to the
	# editor's Output panel or the OS console, but is not accessible via API.
	# This command returns a note about this limitation.
	return {
		"note": "Direct log capture is not available in the game process. Print output goes to the editor's Output panel. Use the editor-side get_editor_errors command instead.",
		"limitation": true,
	}


# ---------------------------------------------------------------------------
# Scene tree traversal helpers
# ---------------------------------------------------------------------------

func _node_to_dict(node: Node, depth: int = 0, max_depth: int = MAX_DEPTH) -> Dictionary:
	var result := {"name": str(node.name), "type": node.get_class()}

	if node is Node2D:
		result["position"] = _value_to_json(node.position)
	elif node is Node3D:
		result["position"] = _value_to_json(node.position)
	elif node is Control:
		result["position"] = _value_to_json(node.position)
		result["visible"] = node.visible

	if depth < max_depth:
		var children: Array = []
		for child in node.get_children():
			children.append(_node_to_dict(child, depth + 1, max_depth))
		if not children.is_empty():
			result["children"] = children
	elif node.get_child_count() > 0:
		result["children_truncated"] = node.get_child_count()

	return result


func _find_controls(node: Node, results: Array, depth: int = 0, max_depth: int = MAX_DEPTH) -> void:
	if depth > max_depth:
		return

	if node is Control:
		var info: Dictionary = {
			"name": str(node.name),
			"type": node.get_class(),
			"path": str(node.get_path()),
			"visible": node.visible,
		}
		if node.is_inside_tree():
			info["rect"] = _value_to_json(node.get_global_rect())
		if node is Label:
			info["text"] = node.text
		elif node is Button:
			info["text"] = node.text
		elif node is LineEdit:
			info["text"] = node.text
			info["placeholder"] = node.placeholder_text
		elif node is RichTextLabel:
			info["text"] = node.get_parsed_text()
		elif node is TextEdit:
			info["text"] = node.text
		results.append(info)

	for child in node.get_children():
		_find_controls(child, results, depth + 1, max_depth)


func _find_buttons(node: Node, text: String, results: Array) -> void:
	if node is BaseButton:
		var btn_text := ""
		if node is Button:
			btn_text = node.text
		if btn_text.to_lower().contains(text.to_lower()):
			results.append(node)
	for child in node.get_children():
		_find_buttons(child, text, results)


# ---------------------------------------------------------------------------
# Inline type parsing (simplified version of TypeParser for game-side use)
# TypeParser is part of the editor plugin and not available in the game process.
# ---------------------------------------------------------------------------

func _parse_value(value) -> Variant:
	if value == null:
		return null
	if not value is String:
		return value

	var s: String = value.strip_edges()

	# Boolean
	if s == "true":
		return true
	if s == "false":
		return false

	# null
	if s == "null" or s == "nil":
		return null

	# Integer
	if s.is_valid_int():
		return s.to_int()

	# Float
	if s.is_valid_float():
		return s.to_float()

	# Hex color
	if s.begins_with("#") and (s.length() == 7 or s.length() == 9):
		if Color.html_is_valid(s):
			return Color.html(s)
		return value

	# Vector2
	if s.begins_with("Vector2(") and s.ends_with(")"):
		var args := _extract_args(s, "Vector2")
		if args.size() == 2:
			return Vector2(args[0].strip_edges().to_float(), args[1].strip_edges().to_float())

	# Vector2i
	if s.begins_with("Vector2i(") and s.ends_with(")"):
		var args := _extract_args(s, "Vector2i")
		if args.size() == 2:
			return Vector2i(args[0].strip_edges().to_int(), args[1].strip_edges().to_int())

	# Vector3
	if s.begins_with("Vector3(") and s.ends_with(")"):
		var args := _extract_args(s, "Vector3")
		if args.size() == 3:
			return Vector3(args[0].strip_edges().to_float(), args[1].strip_edges().to_float(), args[2].strip_edges().to_float())

	# Vector3i
	if s.begins_with("Vector3i(") and s.ends_with(")"):
		var args := _extract_args(s, "Vector3i")
		if args.size() == 3:
			return Vector3i(args[0].strip_edges().to_int(), args[1].strip_edges().to_int(), args[2].strip_edges().to_int())

	# Color
	if s.begins_with("Color(") and s.ends_with(")"):
		var args := _extract_args(s, "Color")
		if args.size() == 3:
			return Color(args[0].strip_edges().to_float(), args[1].strip_edges().to_float(), args[2].strip_edges().to_float())
		if args.size() == 4:
			return Color(args[0].strip_edges().to_float(), args[1].strip_edges().to_float(), args[2].strip_edges().to_float(), args[3].strip_edges().to_float())

	# Rect2
	if s.begins_with("Rect2(") and s.ends_with(")"):
		var args := _extract_args(s, "Rect2")
		if args.size() == 4:
			return Rect2(args[0].strip_edges().to_float(), args[1].strip_edges().to_float(), args[2].strip_edges().to_float(), args[3].strip_edges().to_float())

	# NodePath
	if s.begins_with("NodePath(") and s.ends_with(")"):
		var path_str := s.substr(9, s.length() - 10).strip_edges()
		if path_str.begins_with("\"") and path_str.ends_with("\""):
			path_str = path_str.substr(1, path_str.length() - 2)
		return NodePath(path_str)

	# NodePath shorthand
	if s.begins_with("^"):
		var path_str := s
		if s.begins_with("^\""):
			path_str = s.substr(2, s.length() - 3)
		else:
			path_str = s.substr(1)
		return NodePath(path_str)

	# JSON array
	if s.begins_with("["):
		var json := JSON.new()
		if json.parse(s) == OK:
			var data = json.get_data()
			if data is Array:
				return data

	# JSON dictionary
	if s.begins_with("{"):
		var json := JSON.new()
		if json.parse(s) == OK:
			var data = json.get_data()
			if data is Dictionary:
				return data

	return value


func _extract_args(s: String, prefix: String) -> PackedStringArray:
	if not s.begins_with(prefix + "(") or not s.ends_with(")"):
		return PackedStringArray()
	var inner := s.substr(prefix.length() + 1, s.length() - prefix.length() - 2)
	return inner.split(",")


# ---------------------------------------------------------------------------
# Inline value-to-JSON serialization (mirrors TypeParser.value_to_json)
# ---------------------------------------------------------------------------

func _value_to_json(value, _depth: int = 0) -> Variant:
	if value == null:
		return null
	if _depth > 32:
		return "<max depth exceeded>"
	if value is bool or value is int or value is float or value is String:
		return value
	if value is Vector2:
		return "Vector2(%s, %s)" % [value.x, value.y]
	if value is Vector2i:
		return "Vector2i(%s, %s)" % [value.x, value.y]
	if value is Vector3:
		return "Vector3(%s, %s, %s)" % [value.x, value.y, value.z]
	if value is Vector3i:
		return "Vector3i(%s, %s, %s)" % [value.x, value.y, value.z]
	if value is Vector4:
		return "Vector4(%s, %s, %s, %s)" % [value.x, value.y, value.z, value.w]
	if value is Color:
		return "Color(%s, %s, %s, %s)" % [value.r, value.g, value.b, value.a]
	if value is Rect2:
		return "Rect2(%s, %s, %s, %s)" % [value.position.x, value.position.y, value.size.x, value.size.y]
	if value is AABB:
		return "AABB(%s, %s, %s, %s, %s, %s)" % [value.position.x, value.position.y, value.position.z, value.size.x, value.size.y, value.size.z]
	if value is Quaternion:
		return "Quaternion(%s, %s, %s, %s)" % [value.x, value.y, value.z, value.w]
	if value is Transform2D:
		return "Transform2D(%s, %s, %s, %s, %s, %s)" % [value.x.x, value.x.y, value.y.x, value.y.y, value.origin.x, value.origin.y]
	if value is Transform3D:
		var b = value.basis
		var o = value.origin
		return "Transform3D(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)" % [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, o.x, o.y, o.z]
	if value is NodePath:
		return "NodePath(\"%s\")" % str(value)
	if value is Array:
		var arr := []
		for item in value:
			arr.append(_value_to_json(item, _depth + 1))
		return arr
	if value is Dictionary:
		var dict := {}
		for key in value:
			dict[str(key)] = _value_to_json(value[key], _depth + 1)
		return dict
	if value is Resource:
		return {"_type": value.get_class(), "_path": value.resource_path}
	if value is Object:
		return {"_type": value.get_class()}
	return str(value)


# ---------------------------------------------------------------------------
# Key string to keycode mapping (simplified for game-side use)
# ---------------------------------------------------------------------------

func _string_to_keycode(key: String) -> Key:
	var upper := key.to_upper()
	match upper:
		"A": return KEY_A
		"B": return KEY_B
		"C": return KEY_C
		"D": return KEY_D
		"E": return KEY_E
		"F": return KEY_F
		"G": return KEY_G
		"H": return KEY_H
		"I": return KEY_I
		"J": return KEY_J
		"K": return KEY_K
		"L": return KEY_L
		"M": return KEY_M
		"N": return KEY_N
		"O": return KEY_O
		"P": return KEY_P
		"Q": return KEY_Q
		"R": return KEY_R
		"S": return KEY_S
		"T": return KEY_T
		"U": return KEY_U
		"V": return KEY_V
		"W": return KEY_W
		"X": return KEY_X
		"Y": return KEY_Y
		"Z": return KEY_Z
		"0": return KEY_0
		"1": return KEY_1
		"2": return KEY_2
		"3": return KEY_3
		"4": return KEY_4
		"5": return KEY_5
		"6": return KEY_6
		"7": return KEY_7
		"8": return KEY_8
		"9": return KEY_9
		"SPACE": return KEY_SPACE
		"ENTER", "RETURN": return KEY_ENTER
		"ESCAPE", "ESC": return KEY_ESCAPE
		"TAB": return KEY_TAB
		"BACKSPACE": return KEY_BACKSPACE
		"DELETE", "DEL": return KEY_DELETE
		"INSERT": return KEY_INSERT
		"HOME": return KEY_HOME
		"END": return KEY_END
		"PAGEUP", "PAGE_UP": return KEY_PAGEUP
		"PAGEDOWN", "PAGE_DOWN": return KEY_PAGEDOWN
		"UP": return KEY_UP
		"DOWN": return KEY_DOWN
		"LEFT": return KEY_LEFT
		"RIGHT": return KEY_RIGHT
		"SHIFT": return KEY_SHIFT
		"CTRL", "CONTROL": return KEY_CTRL
		"ALT": return KEY_ALT
		"META", "SUPER", "CMD": return KEY_META
		"F1": return KEY_F1
		"F2": return KEY_F2
		"F3": return KEY_F3
		"F4": return KEY_F4
		"F5": return KEY_F5
		"F6": return KEY_F6
		"F7": return KEY_F7
		"F8": return KEY_F8
		"F9": return KEY_F9
		"F10": return KEY_F10
		"F11": return KEY_F11
		"F12": return KEY_F12
		_: return KEY_NONE
