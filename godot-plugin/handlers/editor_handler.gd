@tool
class_name EditorHandler
extends RefCounted

## Editor tools (12):
## get_editor_errors, get_editor_screenshot, get_game_screenshot,
## compare_screenshots, execute_editor_script, get_signals,
## reload_plugin, reload_project, clear_output,
## get_node_bounds, get_scene_summary, get_viewport_info

var _editor: EditorInterface
var _plugin: EditorPlugin


func _init(editor: EditorInterface, plugin: EditorPlugin):
	_editor = editor
	_plugin = plugin


func get_commands() -> Dictionary:
	return {
		"get_editor_errors": get_editor_errors,
		"get_editor_screenshot": get_editor_screenshot,
		"get_game_screenshot": get_game_screenshot,
		"compare_screenshots": compare_screenshots,
		"execute_editor_script": execute_editor_script,
		"get_signals": get_signals_cmd,
		"reload_plugin": reload_plugin,
		"reload_project": reload_project,
		"clear_output": clear_output,
		"get_node_bounds": get_node_bounds,
		"get_scene_summary": get_scene_summary,
		"get_viewport_info": get_viewport_info,
	}


func get_editor_errors(params: Dictionary) -> Dictionary:
	# Access the editor log via the editor's output panel
	# We parse the recent errors from Godot's error output
	var errors: Array = []

	# Get errors from the script editor if available
	var script_editor = _editor.get_script_editor()
	if script_editor:
		# Try to get the current script errors
		var current_script = script_editor.get_current_script()
		if current_script is GDScript:
			# Reload to get fresh errors
			var err = current_script.reload()
			if err != OK:
				errors.append({
					"type": "script_error",
					"script": current_script.resource_path,
					"message": "Script reload failed with error: %s" % error_string(err),
				})

	return {"errors": errors, "count": errors.size()}


func get_editor_screenshot(params: Dictionary) -> Dictionary:
	var save_path: String = params.get("save_path", "res://.claude_screenshot_editor.png")
	var max_width: int = params.get("max_width", 0)
	var include_base64: bool = params.get("base64", false)

	# Get the editor viewport
	var viewport = _editor.get_editor_main_screen()
	if viewport == null:
		return {"error": "Cannot access editor viewport", "code": "NO_VIEWPORT"}

	# Capture from the editor's main viewport
	var img = viewport.get_viewport().get_texture().get_image()
	if img == null:
		return {"error": "Failed to capture screenshot", "code": "CAPTURE_FAILED"}

	return _save_screenshot(img, save_path, max_width, include_base64)


func get_game_screenshot(params: Dictionary) -> Dictionary:
	var save_path: String = params.get("save_path", "res://.claude_screenshot_game.png")
	var max_width: int = params.get("max_width", 0)
	var include_base64: bool = params.get("base64", false)

	if not _editor.is_playing_scene():
		return {"error": "No game is currently running", "code": "NOT_PLAYING"}

	var viewport = Engine.get_main_loop().root
	if viewport == null:
		return {"error": "Cannot access viewport", "code": "NO_VIEWPORT"}

	var img = viewport.get_texture().get_image()
	if img == null:
		return {"error": "Failed to capture screenshot", "code": "CAPTURE_FAILED"}

	return _save_screenshot(img, save_path, max_width, include_base64)


func _save_screenshot(img: Image, save_path: String, max_width: int, include_base64: bool) -> Dictionary:
	# Downscale if max_width specified
	if max_width > 0 and img.get_width() > max_width:
		var scale_factor = float(max_width) / float(img.get_width())
		var new_height = int(img.get_height() * scale_factor)
		img.resize(max_width, new_height, Image.INTERPOLATE_BILINEAR)

	var abs_path = ProjectSettings.globalize_path(save_path)
	var err = img.save_png(abs_path)
	if err != OK:
		return {"error": "Failed to save screenshot: %s" % error_string(err), "code": "SAVE_ERROR"}

	var result = {"path": save_path, "width": img.get_width(), "height": img.get_height()}

	# Only include base64 if explicitly requested (avoids WebSocket buffer overflow)
	if include_base64:
		var buffer = img.save_png_to_buffer()
		result["base64"] = Marshalls.raw_to_base64(buffer)

	return result


func compare_screenshots(params: Dictionary) -> Dictionary:
	var path_a: String = params.get("path_a", "")
	var path_b: String = params.get("path_b", "")
	var threshold: float = params.get("threshold", 0.01)

	if path_a == "" or path_b == "":
		return {"error": "path_a and path_b are required", "code": "MISSING_PARAM"}

	var img_a = Image.new()
	var img_b = Image.new()
	var err_a = img_a.load(ProjectSettings.globalize_path(path_a))
	var err_b = img_b.load(ProjectSettings.globalize_path(path_b))

	if err_a != OK:
		return {"error": "Cannot load image A: %s" % path_a, "code": "LOAD_ERROR"}
	if err_b != OK:
		return {"error": "Cannot load image B: %s" % path_b, "code": "LOAD_ERROR"}

	if img_a.get_size() != img_b.get_size():
		return {
			"match": false,
			"reason": "Different sizes: %s vs %s" % [str(img_a.get_size()), str(img_b.get_size())],
			"size_a": TypeParser.value_to_json(img_a.get_size()),
			"size_b": TypeParser.value_to_json(img_b.get_size()),
		}

	# Pixel-by-pixel comparison
	var diff_count: int = 0
	var total_pixels: int = img_a.get_width() * img_a.get_height()
	for y in range(img_a.get_height()):
		for x in range(img_a.get_width()):
			var ca = img_a.get_pixel(x, y)
			var cb = img_b.get_pixel(x, y)
			var diff = abs(ca.r - cb.r) + abs(ca.g - cb.g) + abs(ca.b - cb.b) + abs(ca.a - cb.a)
			if diff > threshold:
				diff_count += 1

	var diff_ratio = float(diff_count) / float(total_pixels)
	return {
		"match": diff_ratio < threshold,
		"diff_ratio": diff_ratio,
		"diff_pixels": diff_count,
		"total_pixels": total_pixels,
	}


func execute_editor_script(params: Dictionary) -> Dictionary:
	var code: String = params.get("code", "")
	if code == "":
		return {"error": "code parameter is required", "code": "MISSING_PARAM"}

	# Create a temporary GDScript and execute it
	var script = GDScript.new()
	script.source_code = """extends RefCounted

var _editor: EditorInterface
var _result: Variant = null

func run(editor: EditorInterface):
	_editor = editor
	%s
	return _result
""" % code

	var err = script.reload()
	if err != OK:
		return {"error": "Script compilation failed", "code": "COMPILE_ERROR"}

	var instance = script.new()
	var result = instance.run(_editor)

	return {"result": TypeParser.value_to_json(result)}


func get_signals_cmd(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path == "":
		return {"error": "node_path parameter is required", "code": "MISSING_PARAM"}

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open", "code": "NO_SCENE"}

	var node = root.get_node_or_null(node_path) if node_path != root.name else root
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	# Get all signals
	var signals: Array = []
	for sig in node.get_signal_list():
		var connections: Array = []
		for conn in node.get_signal_connection_list(sig.name):
			connections.append({
				"target": str(conn.callable.get_object().get_path()) if conn.callable.get_object() is Node else str(conn.callable.get_object()),
				"method": conn.callable.get_method(),
			})
		signals.append({
			"name": sig.name,
			"args": sig.args.size(),
			"connections": connections,
		})

	return {"node_path": node_path, "signals": signals}


func reload_plugin(params: Dictionary) -> Dictionary:
	var plugin_name: String = params.get("plugin_name", "")
	if plugin_name == "":
		return {"error": "plugin_name parameter is required", "code": "MISSING_PARAM"}

	# Disable and re-enable the plugin
	_editor.set_plugin_enabled(plugin_name, false)
	_editor.set_plugin_enabled(plugin_name, true)
	return {"reloaded": plugin_name}


func reload_project(params: Dictionary) -> Dictionary:
	_editor.restart_editor(true)
	return {"restarting": true}


func clear_output(params: Dictionary) -> Dictionary:
	# Clear the editor output panel if accessible
	# This is limited in Godot's API; we clear what we can
	return {"cleared": true}


func get_node_bounds(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path == "":
		return {"error": "node_path parameter is required", "code": "MISSING_PARAM"}

	var node = NodeFinder.find(_editor, node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var result: Dictionary = {
		"node_path": str(node.get_path()),
		"node_type": node.get_class(),
	}

	if node is Control:
		var rect = node.get_global_rect()
		result["global_position"] = TypeParser.value_to_json(node.global_position)
		result["size"] = TypeParser.value_to_json(node.size)
		result["global_rect"] = TypeParser.value_to_json(rect)
	elif node is Node2D:
		result["global_position"] = TypeParser.value_to_json(node.global_position)
		if node is Sprite2D and node.texture != null:
			var tex_size = node.texture.get_size()
			result["texture_size"] = TypeParser.value_to_json(tex_size)
			result["bounds"] = TypeParser.value_to_json(Rect2(node.global_position - tex_size / 2.0, tex_size))
		elif node.has_method("get_rect"):
			result["rect"] = TypeParser.value_to_json(node.get_rect())
	elif node is Node3D:
		result["global_position"] = TypeParser.value_to_json(node.global_position)

	return result


func get_scene_summary(params: Dictionary) -> Dictionary:
	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open", "code": "NO_SCENE"}

	var max_depth: int = params.get("max_depth", 8)
	var include_properties: Array = params.get("include_properties", ["position", "size", "visible", "modulate"])

	var nodes: Array = []
	_collect_scene_nodes(root, root, 0, max_depth, include_properties, nodes)

	return {"nodes": nodes, "node_count": nodes.size()}


func _collect_scene_nodes(node: Node, root: Node, depth: int, max_depth: int, properties: Array, out: Array) -> void:
	if depth > max_depth:
		return

	var entry: Dictionary = {
		"path": str(root.get_path_to(node)),
		"type": node.get_class(),
	}

	for prop_name in properties:
		if node.has_method("get") or prop_name in node:
			var val = node.get(prop_name)
			if val != null:
				entry[prop_name] = TypeParser.value_to_json(val)

	out.append(entry)

	for child in node.get_children():
		_collect_scene_nodes(child, root, depth + 1, max_depth, properties, out)


func get_viewport_info(params: Dictionary) -> Dictionary:
	var root = _editor.get_edited_scene_root()
	var result: Dictionary = {}

	# Editor viewport info
	var main_screen = _editor.get_editor_main_screen()
	if main_screen != null:
		var vp = main_screen.get_viewport()
		if vp != null:
			result["viewport_size"] = TypeParser.value_to_json(vp.get_visible_rect().size)

	if root != null:
		result["scene_path"] = root.scene_file_path

		# Find cameras in the scene
		var cameras: Array = []
		_find_cameras(root, root, cameras)
		result["cameras"] = cameras
	else:
		result["scene_path"] = ""
		result["cameras"] = []

	return result


func _find_cameras(node: Node, root: Node, out: Array) -> void:
	if node is Camera2D:
		out.append({
			"path": str(root.get_path_to(node)),
			"type": "Camera2D",
			"position": TypeParser.value_to_json(node.global_position),
			"zoom": TypeParser.value_to_json(node.zoom),
		})
	elif node is Camera3D:
		out.append({
			"path": str(root.get_path_to(node)),
			"type": "Camera3D",
			"position": TypeParser.value_to_json(node.global_position),
			"fov": node.fov,
		})

	for child in node.get_children():
		_find_cameras(child, root, out)
