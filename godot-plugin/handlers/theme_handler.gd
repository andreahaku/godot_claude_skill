@tool
class_name ThemeHandler
extends RefCounted

## Theme & UI tools (6):
## create_theme, set_theme_color, set_theme_constant,
## set_theme_font_size, set_theme_stylebox, get_theme_info

var _editor: EditorInterface
var _undo: UndoHelper


func _init(editor: EditorInterface, undo: UndoHelper):
	_editor = editor
	_undo = undo


func get_commands() -> Dictionary:
	return {
		"create_theme": create_theme,
		"set_theme_color": set_theme_color,
		"set_theme_constant": set_theme_constant,
		"set_theme_font_size": set_theme_font_size,
		"set_theme_stylebox": set_theme_stylebox,
		"get_theme_info": get_theme_info,
	}


func _find_node(path: String) -> Node:
	var root = _editor.get_edited_scene_root()
	if root == null:
		return null
	if path == "" or path == root.name:
		return root
	return root.get_node_or_null(path)


func create_theme(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	if path == "":
		return {"error": "path is required", "code": "MISSING_PARAM"}
	if not path.begins_with("res://"):
		path = "res://" + path
	if not path.ends_with(".tres"):
		path += ".tres"

	var theme = Theme.new()
	var err = ResourceSaver.save(theme, path)
	if err != OK:
		return {"error": "Failed to save theme: %s" % error_string(err), "code": "SAVE_ERROR"}

	_editor.get_resource_filesystem().scan()
	return {"path": path, "created": true}


func set_theme_color(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var color_name: String = params.get("name", "")
	var color_value: String = params.get("color", "")
	var theme_type: String = params.get("theme_type", "")

	if node_path == "" or color_name == "" or color_value == "":
		return {"error": "node_path, name, and color are required", "code": "MISSING_PARAM"}

	var node = _find_node(node_path)
	if node == null or not node is Control:
		return {"error": "Control node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var control: Control = node
	var color = TypeParser.parse_value(color_value)
	var type = theme_type if theme_type != "" else control.get_class()

	control.add_theme_color_override(color_name, color)
	return {"node_path": node_path, "name": color_name, "color": TypeParser.value_to_json(color)}


func set_theme_constant(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var const_name: String = params.get("name", "")
	var value: int = params.get("value", 0)

	if node_path == "" or const_name == "":
		return {"error": "node_path and name are required", "code": "MISSING_PARAM"}

	var node = _find_node(node_path)
	if node == null or not node is Control:
		return {"error": "Control node not found", "code": "NODE_NOT_FOUND"}

	var control: Control = node
	control.add_theme_constant_override(const_name, value)
	return {"node_path": node_path, "name": const_name, "value": value}


func set_theme_font_size(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var font_name: String = params.get("name", "font_size")
	var size: int = params.get("size", 16)

	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var node = _find_node(node_path)
	if node == null or not node is Control:
		return {"error": "Control node not found", "code": "NODE_NOT_FOUND"}

	var control: Control = node
	control.add_theme_font_size_override(font_name, size)
	return {"node_path": node_path, "name": font_name, "size": size}


func set_theme_stylebox(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var style_name: String = params.get("name", "")
	var bg_color: String = params.get("bg_color", "")
	var border_color: String = params.get("border_color", "")
	var border_width: int = params.get("border_width", 0)
	var corner_radius: int = params.get("corner_radius", 0)
	var content_margin: int = params.get("content_margin", -1)

	if node_path == "" or style_name == "":
		return {"error": "node_path and name are required", "code": "MISSING_PARAM"}

	var node = _find_node(node_path)
	if node == null or not node is Control:
		return {"error": "Control node not found", "code": "NODE_NOT_FOUND"}

	var control: Control = node
	var style = StyleBoxFlat.new()

	if bg_color != "":
		style.bg_color = TypeParser.parse_value(bg_color)
	if border_color != "":
		style.border_color = TypeParser.parse_value(border_color)
	if border_width > 0:
		style.border_width_left = border_width
		style.border_width_top = border_width
		style.border_width_right = border_width
		style.border_width_bottom = border_width
	if corner_radius > 0:
		style.corner_radius_top_left = corner_radius
		style.corner_radius_top_right = corner_radius
		style.corner_radius_bottom_left = corner_radius
		style.corner_radius_bottom_right = corner_radius
	if content_margin >= 0:
		style.content_margin_left = content_margin
		style.content_margin_top = content_margin
		style.content_margin_right = content_margin
		style.content_margin_bottom = content_margin

	control.add_theme_stylebox_override(style_name, style)
	return {"node_path": node_path, "name": style_name}


func get_theme_info(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var node = _find_node(node_path)
	if node == null or not node is Control:
		return {"error": "Control node not found", "code": "NODE_NOT_FOUND"}

	var control: Control = node
	var info: Dictionary = {
		"node_path": node_path,
		"type": control.get_class(),
		"has_theme": control.theme != null,
	}

	# List all theme overrides from property list
	var overrides: Dictionary = {"colors": {}, "constants": {}, "font_sizes": {}, "styleboxes": {}}
	for prop in control.get_property_list():
		var name: String = prop.name
		if name.begins_with("theme_override_colors/"):
			var key = name.substr(22)
			overrides.colors[key] = TypeParser.value_to_json(control.get(name))
		elif name.begins_with("theme_override_constants/"):
			var key = name.substr(25)
			overrides.constants[key] = control.get(name)
		elif name.begins_with("theme_override_font_sizes/"):
			var key = name.substr(26)
			overrides.font_sizes[key] = control.get(name)
		elif name.begins_with("theme_override_styles/"):
			var key = name.substr(22)
			overrides.styleboxes[key] = control.get(name) != null

	info["overrides"] = overrides
	return info
