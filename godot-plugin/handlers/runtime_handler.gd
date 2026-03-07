@tool
class_name RuntimeHandler
extends RefCounted

const TypeParser = preload("res://addons/godot_claude_skill/utils/type_parser.gd")

## Runtime Analysis tools (16):
## get_game_scene_tree, get_game_node_properties, set_game_node_properties,
## execute_game_script, capture_frames, monitor_properties,
## start_recording, stop_recording, replay_recording,
## find_nodes_by_script, get_autoload, find_ui_elements,
## click_button_by_text, wait_for_node, batch_get_properties,
## get_bridge_status
##
## Architecture: Commands that need the running game process are routed through
## the runtime bridge (BridgeServer -> RuntimeBridge). The bridge runs as a
## WebSocket client inside the game process and connects back to the editor on
## port 9081. This gives true game-side introspection rather than accessing the
## editor's SceneTree via Engine.get_main_loop().
##
## Commands that don't require the running game (find_nodes_by_script on the
## editor tree, get_autoload, batch_get_properties on editor tree) fall back to
## the editor tree when the bridge is not connected.

const MAX_RECORDING_EVENTS := 10000
const MAX_RECORDING_DURATION := 300.0  # 5 minutes in seconds

var _editor: EditorInterface
var _bridge
var _recording_events: Array = []
var _is_recording: bool = false
var _recording_start_time: float = 0.0
var _recording_max_events: int = 10000
var _recording_max_duration: float = 300.0


func _init(editor: EditorInterface, bridge):
	_editor = editor
	_bridge = bridge


func get_commands() -> Dictionary:
	return {
		"get_game_scene_tree": get_game_scene_tree,
		"get_game_node_properties": get_game_node_properties,
		"set_game_node_properties": set_game_node_properties,
		"execute_game_script": execute_game_script,
		"capture_frames": capture_frames,
		"monitor_properties": monitor_properties,
		"start_recording": start_recording,
		"stop_recording": stop_recording,
		"replay_recording": replay_recording,
		"find_nodes_by_script": find_nodes_by_script,
		"get_autoload": get_autoload,
		"find_ui_elements": find_ui_elements,
		"click_button_by_text": click_button_by_text,
		"wait_for_node": wait_for_node,
		"batch_get_properties": batch_get_properties,
		"get_bridge_status": get_bridge_status,
	}


func _get_scene_tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _require_playing() -> Dictionary:
	if not _editor.is_playing_scene():
		return {"error": "No game is currently running. Use play_scene first.", "code": "NOT_PLAYING"}
	return {}


func _require_bridge() -> Dictionary:
	var check := _require_playing()
	if check.has("error"):
		return check
	if not _bridge.is_bridge_connected():
		return {
			"error": "Runtime bridge is not connected. The game is running but the bridge autoload has not connected. Ensure GodotClaudeRuntimeBridge is added as an autoload in the game project.",
			"code": "BRIDGE_NOT_CONNECTED",
		}
	return {}


# ---------------------------------------------------------------------------
# Bridge status
# ---------------------------------------------------------------------------

func get_bridge_status(params: Dictionary) -> Dictionary:
	return {
		"game_running": _editor.is_playing_scene(),
		"bridge_connected": _bridge.is_bridge_connected(),
		"bridge_info": _bridge.get_bridge_info(),
	}


# ---------------------------------------------------------------------------
# Commands routed through the runtime bridge
# ---------------------------------------------------------------------------

func get_game_scene_tree(params: Dictionary) -> Dictionary:
	var check := _require_bridge()
	if check.has("error"):
		# Fall back to editor tree if bridge not connected but game is playing
		if _editor.is_playing_scene() and not _bridge.is_bridge_connected():
			return _fallback_get_game_scene_tree(params)
		return check

	var bridge_params: Dictionary = {}
	if params.has("max_depth"):
		bridge_params["max_depth"] = params["max_depth"]

	return await _bridge.send_command_await("bridge_get_scene_tree", bridge_params)


func get_game_node_properties(params: Dictionary) -> Dictionary:
	var check := _require_bridge()
	if check.has("error"):
		if _editor.is_playing_scene() and not _bridge.is_bridge_connected():
			return _fallback_get_game_node_properties(params)
		return check

	var node_path: String = params.get("node_path", "")
	if node_path == "":
		return {"error": "node_path parameter is required", "code": "MISSING_PARAM"}

	return await _bridge.send_command_await("bridge_get_node_properties", {"node_path": node_path})


func set_game_node_properties(params: Dictionary) -> Dictionary:
	var check := _require_bridge()
	if check.has("error"):
		if _editor.is_playing_scene() and not _bridge.is_bridge_connected():
			return _fallback_set_game_node_properties(params)
		return check

	var node_path: String = params.get("node_path", "")
	var properties: Dictionary = params.get("properties", {})
	if node_path == "" or properties.is_empty():
		return {"error": "node_path and properties are required", "code": "MISSING_PARAM"}

	return await _bridge.send_command_await("bridge_set_node_properties", {
		"node_path": node_path,
		"properties": properties,
	})


func execute_game_script(params: Dictionary) -> Dictionary:
	var check := _require_bridge()
	if check.has("error"):
		if _editor.is_playing_scene() and not _bridge.is_bridge_connected():
			return _fallback_execute_game_script(params)
		return check

	var code: String = params.get("code", "")
	if code == "":
		return {"error": "code parameter is required", "code": "MISSING_PARAM"}

	return await _bridge.send_command_await("bridge_execute_script", {"code": code})


func capture_frames(params: Dictionary) -> Dictionary:
	var check := _require_bridge()
	if check.has("error"):
		if _editor.is_playing_scene() and not _bridge.is_bridge_connected():
			return await _fallback_capture_frames(params)
		return check

	var count: int = params.get("count", 1)
	var interval: float = params.get("interval", 0.5)
	var save_dir: String = params.get("save_dir", "res://.claude_captures")

	# For multiple frames, capture them one at a time through the bridge
	var frames: Array = []
	for i in range(count):
		if i > 0:
			await Engine.get_main_loop().create_timer(interval).timeout

		var save_path := "%s/frame_%03d.png" % [save_dir, i]
		var result: Dictionary = await _bridge.send_command_await("bridge_capture_screenshot", {"save_path": save_path})
		if result.has("error"):
			frames.append({"frame": i, "error": result["error"]})
		else:
			frames.append({"frame": i, "path": result.get("path", save_path), "global_path": result.get("global_path", "")})

	return {"frames": frames, "count": frames.size()}


func monitor_properties(params: Dictionary) -> Dictionary:
	var check := _require_bridge()
	if check.has("error"):
		if _editor.is_playing_scene() and not _bridge.is_bridge_connected():
			return await _fallback_monitor_properties(params)
		return check

	var node_path: String = params.get("node_path", "")
	var properties: Array = params.get("properties", [])
	var duration: float = params.get("duration", 2.0)
	var interval: float = params.get("interval", 0.1)

	if node_path == "" or properties.is_empty():
		return {"error": "node_path and properties are required", "code": "MISSING_PARAM"}

	# Sample properties repeatedly through the bridge
	var timeline: Array = []
	var elapsed: float = 0.0
	while elapsed < duration:
		var result: Dictionary = await _bridge.send_command_await("bridge_get_node_properties", {"node_path": node_path})
		if result.has("error"):
			return result

		var snapshot: Dictionary = {"time": elapsed}
		var all_props: Dictionary = result.get("properties", {})
		for prop in properties:
			snapshot[prop] = all_props.get(prop, null)
		timeline.append(snapshot)

		await Engine.get_main_loop().create_timer(interval).timeout
		elapsed += interval

	return {"node_path": node_path, "timeline": timeline, "samples": timeline.size()}


func find_ui_elements(params: Dictionary) -> Dictionary:
	var check := _require_bridge()
	if check.has("error"):
		if _editor.is_playing_scene() and not _bridge.is_bridge_connected():
			return _fallback_find_ui_elements(params)
		return check

	return await _bridge.send_command_await("bridge_find_ui_elements", {})


func click_button_by_text(params: Dictionary) -> Dictionary:
	var check := _require_bridge()
	if check.has("error"):
		if _editor.is_playing_scene() and not _bridge.is_bridge_connected():
			return _fallback_click_button_by_text(params)
		return check

	var text: String = params.get("text", "")
	if text == "":
		return {"error": "text parameter is required", "code": "MISSING_PARAM"}

	return await _bridge.send_command_await("bridge_click_button", {"text": text})


func wait_for_node(params: Dictionary) -> Dictionary:
	var check := _require_bridge()
	if check.has("error"):
		if _editor.is_playing_scene() and not _bridge.is_bridge_connected():
			return await _fallback_wait_for_node(params)
		return check

	var node_path: String = params.get("node_path", "")
	var timeout: float = params.get("timeout", 5.0)
	if node_path == "":
		return {"error": "node_path parameter is required", "code": "MISSING_PARAM"}

	# Poll the bridge repeatedly until node is found or timeout
	var elapsed: float = 0.0
	while elapsed < timeout:
		var result: Dictionary = await _bridge.send_command_await("bridge_get_node_properties", {"node_path": node_path})
		if not result.has("error"):
			return {"found": true, "node_path": node_path, "waited": elapsed}

		await Engine.get_main_loop().create_timer(0.1).timeout
		elapsed += 0.1

	return {"found": false, "timeout": timeout}


# ---------------------------------------------------------------------------
# Recording/replay (stays editor-side, uses Input.parse_input_event)
# ---------------------------------------------------------------------------

func start_recording(params: Dictionary) -> Dictionary:
	var max_events: int = params.get("max_events", MAX_RECORDING_EVENTS)
	var max_duration: float = params.get("max_duration", MAX_RECORDING_DURATION)
	_is_recording = true
	_recording_events.clear()
	_recording_start_time = Time.get_ticks_msec()
	_recording_max_events = max_events
	_recording_max_duration = max_duration
	return {"recording": true, "start_time": _recording_start_time, "max_events": max_events, "max_duration": max_duration}


func stop_recording(params: Dictionary) -> Dictionary:
	_is_recording = false
	var duration = (Time.get_ticks_msec() - _recording_start_time) / 1000.0
	return {"recording": false, "events": _recording_events.size(), "duration": duration, "events_data": _recording_events, "max_events": _recording_max_events, "max_duration": _recording_max_duration}


func replay_recording(params: Dictionary) -> Dictionary:
	var check = _require_playing()
	if check.has("error"):
		return check

	var events: Array = params.get("events", _recording_events)
	var speed: float = params.get("speed", 1.0)

	if events.is_empty():
		return {"error": "No events to replay", "code": "NO_EVENTS"}

	var replayed: int = 0
	for event_data in events:
		var delay: float = event_data.get("time", 0.0) / speed
		if delay > 0:
			await Engine.get_main_loop().create_timer(delay).timeout

		var event_type: String = event_data.get("type", "")
		match event_type:
			"key":
				var ev = InputEventKey.new()
				ev.keycode = event_data.get("keycode", KEY_NONE)
				ev.pressed = event_data.get("pressed", true)
				Input.parse_input_event(ev)
			"mouse_button":
				var ev = InputEventMouseButton.new()
				ev.position = Vector2(event_data.get("x", 0), event_data.get("y", 0))
				ev.button_index = event_data.get("button", 1)
				ev.pressed = event_data.get("pressed", true)
				Input.parse_input_event(ev)
			"mouse_motion":
				var ev = InputEventMouseMotion.new()
				ev.position = Vector2(event_data.get("x", 0), event_data.get("y", 0))
				ev.relative = Vector2(event_data.get("rel_x", 0), event_data.get("rel_y", 0))
				Input.parse_input_event(ev)
		replayed += 1

	return {"replayed": replayed}


func _check_recording_bounds() -> void:
	if not _is_recording:
		return

	var elapsed = (Time.get_ticks_msec() - _recording_start_time) / 1000.0
	if elapsed >= _recording_max_duration:
		_is_recording = false
		push_warning("[GodotClaude] Recording auto-stopped: max duration reached (%.0fs)" % _recording_max_duration)
		return

	if _recording_events.size() >= _recording_max_events:
		_is_recording = false
		push_warning("[GodotClaude] Recording auto-stopped: max events reached (%d)" % _recording_max_events)


# ---------------------------------------------------------------------------
# Commands that work without bridge (editor tree fallback)
# ---------------------------------------------------------------------------

func find_nodes_by_script(params: Dictionary) -> Dictionary:
	var script_path: String = params.get("script_path", "")
	if script_path == "":
		return {"error": "script_path parameter is required", "code": "MISSING_PARAM"}

	# This command works on the editor tree (no bridge needed)
	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene available", "code": "NO_SCENE"}

	var found: Array = []
	_find_by_script(root, script_path, found)
	return {"nodes": found, "count": found.size()}


func get_autoload(params: Dictionary) -> Dictionary:
	var name: String = params.get("name", "")

	var autoloads: Array = []
	for prop in ProjectSettings.get_property_list():
		if prop.name.begins_with("autoload/"):
			var al_name = prop.name.substr(9)
			if name == "" or al_name == name:
				var al_path = str(ProjectSettings.get_setting(prop.name))
				autoloads.append({"name": al_name, "path": al_path})

	if name != "" and autoloads.is_empty():
		return {"error": "Autoload not found: %s" % name, "code": "NOT_FOUND"}

	return {"autoloads": autoloads}


func batch_get_properties(params: Dictionary) -> Dictionary:
	var queries: Array = params.get("queries", [])
	if queries.is_empty():
		return {"error": "queries array is required", "code": "MISSING_PARAM"}

	# If bridge is connected and game is playing, use bridge for game-side queries
	if _editor.is_playing_scene() and _bridge.is_bridge_connected():
		var results: Array = []
		for query in queries:
			var node_path: String = query.get("node_path", "")
			var properties: Array = query.get("properties", [])
			var result: Dictionary = await _bridge.send_command_await("bridge_get_node_properties", {"node_path": node_path})
			if result.has("error"):
				results.append({"node_path": node_path, "error": result["error"]})
			else:
				var all_props: Dictionary = result.get("properties", {})
				var values: Dictionary = {}
				for prop in properties:
					values[prop] = all_props.get(prop, null)
				results.append({"node_path": node_path, "values": values})
		return {"results": results}

	# Fall back to editor tree
	var tree = _get_scene_tree()
	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene available", "code": "NO_SCENE"}

	var results: Array = []
	for query in queries:
		var node_path: String = query.get("node_path", "")
		var properties: Array = query.get("properties", [])
		var node = root.get_node_or_null(node_path)
		if node == null:
			results.append({"node_path": node_path, "error": "not found"})
			continue
		var values: Dictionary = {}
		for prop in properties:
			values[prop] = TypeParser.value_to_json(node.get(prop))
		results.append({"node_path": node_path, "values": values})

	return {"results": results}


# ---------------------------------------------------------------------------
# Fallback implementations (editor tree, used when bridge is not connected)
# These provide limited functionality using Engine.get_main_loop() which
# returns the editor's SceneTree, not the game's.
# ---------------------------------------------------------------------------

func _fallback_get_game_scene_tree(params: Dictionary) -> Dictionary:
	var tree = _get_scene_tree()
	if tree == null:
		return {"error": "Cannot access scene tree", "code": "NO_TREE"}

	var root = tree.current_scene
	if root == null:
		return {"error": "No current scene in game", "code": "NO_SCENE"}

	return {"tree": _node_to_dict(root), "_fallback": true, "_note": "Using editor tree fallback. Add GodotClaudeRuntimeBridge autoload for true game introspection."}


func _fallback_get_game_node_properties(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path == "":
		return {"error": "node_path parameter is required", "code": "MISSING_PARAM"}

	var tree = _get_scene_tree()
	if tree == null or tree.current_scene == null:
		return {"error": "No current scene", "code": "NO_SCENE"}

	var node = tree.current_scene.get_node_or_null(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var props: Dictionary = {}
	for prop in node.get_property_list():
		if prop.usage & PROPERTY_USAGE_EDITOR or prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			props[prop.name] = TypeParser.value_to_json(node.get(prop.name))

	return {"node_path": node_path, "properties": props, "_fallback": true}


func _fallback_set_game_node_properties(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var properties: Dictionary = params.get("properties", {})
	if node_path == "" or properties.is_empty():
		return {"error": "node_path and properties are required", "code": "MISSING_PARAM"}

	var tree = _get_scene_tree()
	if tree == null or tree.current_scene == null:
		return {"error": "No current scene", "code": "NO_SCENE"}

	var node = tree.current_scene.get_node_or_null(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var changed: Dictionary = {}
	for key in properties:
		var old_val = node.get(key)
		var new_val = TypeParser.parse_value(properties[key])
		node.set(key, new_val)
		changed[key] = {"old": TypeParser.value_to_json(old_val), "new": TypeParser.value_to_json(new_val)}

	return {"node_path": node_path, "changed": changed, "_fallback": true}


func _fallback_execute_game_script(params: Dictionary) -> Dictionary:
	var code: String = params.get("code", "")
	if code == "":
		return {"error": "code parameter is required", "code": "MISSING_PARAM"}

	var script = GDScript.new()
	script.source_code = "extends RefCounted\nvar _tree: SceneTree\nvar _result: Variant = null\n\nfunc run(tree: SceneTree):\n\t_tree = tree\n\tvar scene = tree.current_scene\n\t%s\n\treturn _result\n" % code

	var err = script.reload()
	if err != OK:
		return {"error": "Script compilation failed", "code": "COMPILE_ERROR"}

	var instance = script.new()
	var result = instance.run(_get_scene_tree())

	return {"result": TypeParser.value_to_json(result), "_fallback": true}


func _fallback_capture_frames(params: Dictionary) -> Dictionary:
	var count: int = params.get("count", 1)
	var interval: float = params.get("interval", 0.5)
	var save_dir: String = params.get("save_dir", "res://.claude_captures")

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir))

	var frames: Array = []
	for i in range(count):
		if i > 0:
			await Engine.get_main_loop().create_timer(interval).timeout

		var viewport = _get_scene_tree().root
		var img = viewport.get_texture().get_image()
		if img:
			var path = "%s/frame_%03d.png" % [save_dir, i]
			img.save_png(ProjectSettings.globalize_path(path))
			frames.append({"frame": i, "path": path})

	return {"frames": frames, "count": frames.size(), "_fallback": true, "_note": "Screenshot captured from editor viewport. Add GodotClaudeRuntimeBridge autoload for game viewport captures."}


func _fallback_monitor_properties(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var properties: Array = params.get("properties", [])
	var duration: float = params.get("duration", 2.0)
	var interval: float = params.get("interval", 0.1)

	if node_path == "" or properties.is_empty():
		return {"error": "node_path and properties are required", "code": "MISSING_PARAM"}

	var tree = _get_scene_tree()
	var node = tree.current_scene.get_node_or_null(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var timeline: Array = []
	var elapsed: float = 0.0
	while elapsed < duration:
		var snapshot: Dictionary = {"time": elapsed}
		for prop in properties:
			snapshot[prop] = TypeParser.value_to_json(node.get(prop))
		timeline.append(snapshot)
		await Engine.get_main_loop().create_timer(interval).timeout
		elapsed += interval

	return {"node_path": node_path, "timeline": timeline, "samples": timeline.size(), "_fallback": true}


func _fallback_find_ui_elements(params: Dictionary) -> Dictionary:
	var tree = _get_scene_tree()
	var root = tree.current_scene
	if root == null:
		return {"error": "No current scene", "code": "NO_SCENE"}

	var elements: Array = []
	_find_controls(root, elements)
	return {"elements": elements, "count": elements.size(), "_fallback": true}


func _fallback_click_button_by_text(params: Dictionary) -> Dictionary:
	var text: String = params.get("text", "")
	if text == "":
		return {"error": "text parameter is required", "code": "MISSING_PARAM"}

	var tree = _get_scene_tree()
	var root = tree.current_scene
	var buttons: Array = []
	_find_buttons(root, text, buttons)

	if buttons.is_empty():
		return {"error": "No button found with text: %s" % text, "code": "NOT_FOUND"}

	var button: BaseButton = buttons[0]
	button.emit_signal("pressed")

	return {"clicked": str(button.name), "text": text, "_fallback": true}


func _fallback_wait_for_node(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var timeout: float = params.get("timeout", 5.0)
	if node_path == "":
		return {"error": "node_path parameter is required", "code": "MISSING_PARAM"}

	var tree = _get_scene_tree()
	var elapsed: float = 0.0
	while elapsed < timeout:
		var node = tree.current_scene.get_node_or_null(node_path)
		if node:
			return {"found": true, "node_path": str(node.get_path()), "waited": elapsed, "_fallback": true}
		await Engine.get_main_loop().create_timer(0.1).timeout
		elapsed += 0.1

	return {"found": false, "timeout": timeout, "_fallback": true}


# ---------------------------------------------------------------------------
# Helper methods
# ---------------------------------------------------------------------------

func _node_to_dict(node: Node, depth: int = 0) -> Dictionary:
	var result := {"name": str(node.name), "type": node.get_class()}
	if node is Node2D:
		result["position"] = TypeParser.value_to_json(node.position)
	elif node is Node3D:
		result["position"] = TypeParser.value_to_json(node.position)

	if depth < 64:
		var children: Array = []
		for child in node.get_children():
			children.append(_node_to_dict(child, depth + 1))
		if not children.is_empty():
			result["children"] = children
	elif node.get_child_count() > 0:
		result["children_truncated"] = node.get_child_count()

	return result


func _find_by_script(node: Node, script_path: String, results: Array, depth: int = 0, max_depth: int = 64) -> void:
	var s = node.get_script()
	if s and s.resource_path == script_path:
		results.append({"name": str(node.name), "path": str(node.get_path())})
	if depth >= max_depth:
		return
	for child in node.get_children():
		_find_by_script(child, script_path, results, depth + 1, max_depth)


func _find_controls(node: Node, results: Array, depth: int = 0, max_depth: int = 64) -> void:
	if node is Control:
		var info: Dictionary = {
			"name": str(node.name),
			"type": node.get_class(),
			"path": str(node.get_path()),
			"visible": node.visible,
			"rect": TypeParser.value_to_json(node.get_global_rect()) if node.is_inside_tree() else null,
		}
		if node is Label:
			info["text"] = node.text
		elif node is Button:
			info["text"] = node.text
		elif node is LineEdit:
			info["text"] = node.text
			info["placeholder"] = node.placeholder_text
		results.append(info)
	if depth >= max_depth:
		return
	for child in node.get_children():
		_find_controls(child, results, depth + 1, max_depth)


func _find_buttons(node: Node, text: String, results: Array, depth: int = 0, max_depth: int = 64) -> void:
	if node is BaseButton:
		var btn_text = ""
		if node is Button:
			btn_text = node.text
		if btn_text.to_lower().contains(text.to_lower()):
			results.append(node)
	if depth >= max_depth:
		return
	for child in node.get_children():
		_find_buttons(child, text, results, depth + 1, max_depth)
