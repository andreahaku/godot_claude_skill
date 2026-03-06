@tool
class_name ShaderHandler
extends RefCounted

## Shader tools (6):
## create_shader, read_shader, edit_shader,
## assign_shader_material, set_shader_param, get_shader_params

var _editor: EditorInterface
var _undo: UndoHelper


func _init(editor: EditorInterface, undo: UndoHelper = null):
	_editor = editor
	_undo = undo


func get_commands() -> Dictionary:
	return {
		"create_shader": create_shader,
		"read_shader": read_shader,
		"edit_shader": edit_shader,
		"assign_shader_material": assign_shader_material,
		"set_shader_param": set_shader_param,
		"get_shader_params": get_shader_params,
	}


func create_shader(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	var shader_type: String = params.get("type", "spatial")
	var template: String = params.get("template", "")

	if path == "":
		return {"error": "path is required", "code": "MISSING_PARAM"}
	if not path.begins_with("res://"):
		path = "res://" + path
	if not path.ends_with(".gdshader"):
		path += ".gdshader"

	var code: String
	if template != "":
		code = template
	else:
		match shader_type.to_lower():
			"spatial", "3d":
				code = """shader_type spatial;

void vertex() {
}

void fragment() {
	ALBEDO = vec3(1.0);
}
"""
			"canvas_item", "2d":
				code = """shader_type canvas_item;

void vertex() {
}

void fragment() {
	COLOR = texture(TEXTURE, UV);
}
"""
			"particles":
				code = """shader_type particles;

void start() {
	VELOCITY = vec3(0.0, 1.0, 0.0);
}

void process() {
}
"""
			"sky":
				code = """shader_type sky;

void sky() {
	COLOR = vec3(0.4, 0.6, 1.0);
}
"""
			_:
				code = "shader_type spatial;\n\nvoid fragment() {\n\tALBEDO = vec3(1.0);\n}\n"

	var dir_path = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))

	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"error": "Cannot create shader file", "code": "FILE_CREATE_ERROR"}
	file.store_string(code)
	file.close()

	_editor.get_resource_filesystem().scan()
	return {"path": path, "type": shader_type}


func read_shader(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	if path == "":
		return {"error": "path is required", "code": "MISSING_PARAM"}
	if not path.begins_with("res://"):
		path = "res://" + path

	var shader = load(path) as Shader
	if shader == null:
		return {"error": "Shader not found: %s" % path, "code": "FILE_NOT_FOUND"}

	return {"path": path, "code": shader.code, "type": _shader_mode_to_string(shader)}


func edit_shader(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	var search: String = params.get("search", "")
	var replace: String = params.get("replace", "")
	var new_code: String = params.get("new_code", "")

	if path == "":
		return {"error": "path is required", "code": "MISSING_PARAM"}
	if not path.begins_with("res://"):
		path = "res://" + path

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Cannot open shader: %s" % path, "code": "FILE_NOT_FOUND"}
	var code = file.get_as_text()
	file.close()

	if new_code != "":
		code = new_code
	elif search != "":
		if not code.contains(search):
			return {"error": "Search string not found", "code": "NOT_FOUND"}
		code = code.replace(search, replace)
	else:
		return {"error": "Provide search/replace or new_code", "code": "MISSING_PARAM"}

	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(code)
	file.close()

	_editor.get_resource_filesystem().scan()
	return {"path": path, "modified": true}


func assign_shader_material(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var shader_path: String = params.get("shader_path", "")

	if node_path == "" or shader_path == "":
		return {"error": "node_path and shader_path are required", "code": "MISSING_PARAM"}
	if not shader_path.begins_with("res://"):
		shader_path = "res://" + shader_path

	var node = NodeFinder.find(_editor, node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var shader = load(shader_path) as Shader
	if shader == null:
		return {"error": "Shader not found: %s" % shader_path, "code": "FILE_NOT_FOUND"}

	var mat = ShaderMaterial.new()
	mat.shader = shader

	if node is MeshInstance3D:
		if _undo:
			var old_mat = node.material_override
			_undo.create_action("Assign Shader Material")
			_undo.add_do_method(node, &"set", ["material_override", mat])
			_undo.add_undo_method(node, &"set", ["material_override", old_mat])
			_undo.commit_action()
		else:
			node.material_override = mat
	elif node is CanvasItem:
		if _undo:
			var old_mat = node.material
			_undo.create_action("Assign Shader Material")
			_undo.add_do_method(node, &"set", ["material", mat])
			_undo.add_undo_method(node, &"set", ["material", old_mat])
			_undo.commit_action()
		else:
			node.material = mat
	else:
		return {"error": "Node type doesn't support materials", "code": "WRONG_TYPE"}

	return {"node_path": node_path, "shader_path": shader_path}


func set_shader_param(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var param_name: String = params.get("name", "")
	var value = params.get("value")

	if node_path == "" or param_name == "":
		return {"error": "node_path and name are required", "code": "MISSING_PARAM"}

	var node = NodeFinder.find(_editor, node_path)
	if node == null:
		return {"error": "Node not found", "code": "NODE_NOT_FOUND"}

	var mat: ShaderMaterial
	if node is MeshInstance3D and node.material_override is ShaderMaterial:
		mat = node.material_override
	elif node is CanvasItem and node.material is ShaderMaterial:
		mat = node.material
	else:
		return {"error": "Node does not have a ShaderMaterial", "code": "NO_SHADER"}

	var parsed = TypeParser.parse_value(value)
	if _undo:
		var old_val = mat.get_shader_parameter(param_name)
		_undo.create_action("Set Shader Param: %s" % param_name)
		_undo.add_do_method(mat, &"set_shader_parameter", [param_name, parsed])
		_undo.add_undo_method(mat, &"set_shader_parameter", [param_name, old_val])
		_undo.commit_action()
	else:
		mat.set_shader_parameter(param_name, parsed)

	return {"name": param_name, "value": TypeParser.value_to_json(parsed)}


func get_shader_params(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var node = NodeFinder.find(_editor, node_path)
	if node == null:
		return {"error": "Node not found", "code": "NODE_NOT_FOUND"}

	var mat: ShaderMaterial
	if node is MeshInstance3D and node.material_override is ShaderMaterial:
		mat = node.material_override
	elif node is CanvasItem and node.material is ShaderMaterial:
		mat = node.material
	else:
		return {"error": "No ShaderMaterial found", "code": "NO_SHADER"}

	var shader_params: Dictionary = {}
	if mat.shader:
		for param in mat.shader.get_shader_uniform_list():
			var pname: String = param.name
			shader_params[pname] = {
				"value": TypeParser.value_to_json(mat.get_shader_parameter(pname)),
				"type": type_string(param.type),
			}

	return {"node_path": node_path, "params": shader_params}


func _shader_mode_to_string(shader: Shader) -> String:
	if shader.code.begins_with("shader_type spatial"):
		return "spatial"
	elif shader.code.begins_with("shader_type canvas_item"):
		return "canvas_item"
	elif shader.code.begins_with("shader_type particles"):
		return "particles"
	elif shader.code.begins_with("shader_type sky"):
		return "sky"
	return "unknown"
