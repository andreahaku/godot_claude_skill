@tool
class_name ResourceHandler
extends RefCounted

## Resource tools (3):
## read_resource, edit_resource, create_resource

var _editor: EditorInterface


func _init(editor: EditorInterface):
	_editor = editor


func get_commands() -> Dictionary:
	return {
		"read_resource": read_resource,
		"edit_resource": edit_resource,
		"create_resource": create_resource,
	}


func read_resource(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	if path == "":
		return {"error": "path is required", "code": "MISSING_PARAM"}
	if not path.begins_with("res://"):
		path = "res://" + path

	if not ResourceLoader.exists(path):
		return {"error": "Resource not found: %s" % path, "code": "FILE_NOT_FOUND"}

	var res = load(path)
	if res == null:
		return {"error": "Failed to load: %s" % path, "code": "LOAD_ERROR"}

	var props: Dictionary = {}
	for prop in res.get_property_list():
		if prop.usage & PROPERTY_USAGE_EDITOR or prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			props[prop.name] = TypeParser.value_to_json(res.get(prop.name))

	return {
		"path": path,
		"type": res.get_class(),
		"properties": props,
	}


func edit_resource(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	var properties: Dictionary = params.get("properties", {})

	if path == "" or properties.is_empty():
		return {"error": "path and properties are required", "code": "MISSING_PARAM"}
	if not path.begins_with("res://"):
		path = "res://" + path

	if not ResourceLoader.exists(path):
		return {"error": "Resource not found: %s" % path, "code": "FILE_NOT_FOUND"}

	var res = load(path)
	if res == null:
		return {"error": "Failed to load: %s" % path, "code": "LOAD_ERROR"}

	var changed: Dictionary = {}
	for key in properties:
		var val = TypeParser.parse_value(properties[key])
		res.set(key, val)
		changed[key] = TypeParser.value_to_json(val)

	var err = ResourceSaver.save(res, path)
	if err != OK:
		return {"error": "Failed to save: %s" % error_string(err), "code": "SAVE_ERROR"}

	_editor.get_resource_filesystem().scan()
	return {"path": path, "changed": changed}


func create_resource(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	var resource_type: String = params.get("type", "")
	var properties: Dictionary = params.get("properties", {})

	if path == "" or resource_type == "":
		return {"error": "path and type are required", "code": "MISSING_PARAM"}
	if not path.begins_with("res://"):
		path = "res://" + path
	if not path.ends_with(".tres"):
		path += ".tres"

	if not ClassDB.class_exists(resource_type):
		return {"error": "Unknown resource type: %s" % resource_type, "code": "INVALID_TYPE"}

	var res = ClassDB.instantiate(resource_type)
	if res == null:
		return {"error": "Cannot instantiate: %s" % resource_type, "code": "CANNOT_INSTANTIATE"}

	for key in properties:
		var val = TypeParser.parse_value(properties[key])
		res.set(key, val)

	var dir_path = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))

	var err = ResourceSaver.save(res, path)
	if err != OK:
		return {"error": "Failed to save: %s" % error_string(err), "code": "SAVE_ERROR"}

	_editor.get_resource_filesystem().scan()
	return {"path": path, "type": resource_type}
