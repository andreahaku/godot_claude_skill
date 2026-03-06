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

	var node = NodeFinder.find(_editor, node_path)
	if node == null or not node is Control:
		return {"error": "Control node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var control: Control = node
	var color = TypeParser.parse_value(color_value)

	var had_override = control.has_theme_color_override(color_name)
	_undo.create_action("Set Theme Color: %s" % color_name)
	_undo.add_do_method(control, &"add_theme_color_override", [color_name, color])
	if had_override:
		var old_color = control.get_theme_color(color_name)
		_undo.add_undo_method(control, &"add_theme_color_override", [color_name, old_color])
	else:
		_undo.add_undo_method(control, &"remove_theme_color_override", [color_name])
	_undo.commit_action()
	return {"node_path": node_path, "name": color_name, "color": TypeParser.value_to_json(color)}


func set_theme_constant(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var const_name: String = params.get("name", "")
	var value: int = params.get("value", 0)

	if node_path == "" or const_name == "":
		return {"error": "node_path and name are required", "code": "MISSING_PARAM"}

	var node = NodeFinder.find(_editor, node_path)
	if node == null or not node is Control:
		return {"error": "Control node not found", "code": "NODE_NOT_FOUND"}

	var control: Control = node
	var had_override = control.has_theme_constant_override(const_name)
	_undo.create_action("Set Theme Constant: %s" % const_name)
	_undo.add_do_method(control, &"add_theme_constant_override", [const_name, value])
	if had_override:
		var old_val = control.get_theme_constant(const_name)
		_undo.add_undo_method(control, &"add_theme_constant_override", [const_name, old_val])
	else:
		_undo.add_undo_method(control, &"remove_theme_constant_override", [const_name])
	_undo.commit_action()
	return {"node_path": node_path, "name": const_name, "value": value}


func set_theme_font_size(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var font_name: String = params.get("name", "font_size")
	var size: int = params.get("size", 16)

	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var node = NodeFinder.find(_editor, node_path)
	if node == null or not node is Control:
		return {"error": "Control node not found", "code": "NODE_NOT_FOUND"}

	var control: Control = node
	var had_override = control.has_theme_font_size_override(font_name)
	_undo.create_action("Set Theme Font Size: %s" % font_name)
	_undo.add_do_method(control, &"add_theme_font_size_override", [font_name, size])
	if had_override:
		var old_size = control.get_theme_font_size(font_name)
		_undo.add_undo_method(control, &"add_theme_font_size_override", [font_name, old_size])
	else:
		_undo.add_undo_method(control, &"remove_theme_font_size_override", [font_name])
	_undo.commit_action()
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

	var node = NodeFinder.find(_editor, node_path)
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

	var had_override = control.has_theme_stylebox_override(style_name)
	_undo.create_action("Set Theme StyleBox: %s" % style_name)
	_undo.add_do_method(control, &"add_theme_stylebox_override", [style_name, style])
	if had_override:
		var old_style = control.get_theme_stylebox(style_name)
		_undo.add_undo_method(control, &"add_theme_stylebox_override", [style_name, old_style])
	else:
		_undo.add_undo_method(control, &"remove_theme_stylebox_override", [style_name])
	_undo.commit_action()
	return {"node_path": node_path, "name": style_name}


func get_theme_info(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var node = NodeFinder.find(_editor, node_path)
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
