class_name ProjectHandler
extends RefCounted

## Project tools (7):
## get_project_info, get_filesystem_tree, search_files,
## get_project_settings, set_project_settings,
## uid_to_project_path, project_path_to_uid

var _editor: EditorInterface


func _init(editor: EditorInterface):
	_editor = editor


func get_commands() -> Dictionary:
	return {
		"get_project_info": get_project_info,
		"get_filesystem_tree": get_filesystem_tree,
		"search_files": search_files,
		"get_project_settings": get_project_settings,
		"set_project_settings": set_project_settings,
		"uid_to_project_path": uid_to_project_path,
		"project_path_to_uid": project_path_to_uid,
	}


func get_project_info(params: Dictionary) -> Dictionary:
	var project_name = ProjectSettings.get_setting("application/config/name", "Unnamed")
	var project_path = ProjectSettings.globalize_path("res://")
	var godot_version = Engine.get_version_info()

	# Count files
	var counts = {"scenes": 0, "scripts": 0, "resources": 0, "other": 0}
	_count_files("res://", counts)

	# Get autoloads
	var autoloads: Array = []
	for prop in ProjectSettings.get_property_list():
		if prop.name.begins_with("autoload/"):
			var autoload_name = prop.name.substr(9)
			var autoload_path = ProjectSettings.get_setting(prop.name)
			autoloads.append({"name": autoload_name, "path": str(autoload_path)})

	return {
		"name": project_name,
		"path": project_path,
		"godot_version": "%s.%s.%s.%s" % [godot_version.major, godot_version.minor, godot_version.patch, godot_version.status],
		"file_counts": counts,
		"autoloads": autoloads,
		"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", ""),
	}


func get_filesystem_tree(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "res://")
	var max_depth: int = params.get("max_depth", 5)
	var tree = _build_tree(path, 0, max_depth)
	return {"tree": tree}


func search_files(params: Dictionary) -> Dictionary:
	var query: String = params.get("query", "")
	var file_type: String = params.get("file_type", "")
	var max_results: int = params.get("max_results", 50)

	if query == "":
		return {"error": "query parameter is required", "code": "MISSING_PARAM"}

	var results: Array = []
	_search_recursive("res://", query, file_type, results, max_results)
	return {"results": results, "count": results.size()}


func get_project_settings(params: Dictionary) -> Dictionary:
	var keys: Array = params.get("keys", [])
	if keys.is_empty():
		return {"error": "keys array is required", "code": "MISSING_PARAM"}

	var settings: Dictionary = {}
	for key in keys:
		if ProjectSettings.has_setting(key):
			settings[key] = TypeParser.value_to_json(ProjectSettings.get_setting(key))
		else:
			settings[key] = null
	return {"settings": settings}


func set_project_settings(params: Dictionary) -> Dictionary:
	var settings: Dictionary = params.get("settings", {})
	if settings.is_empty():
		return {"error": "settings dictionary is required", "code": "MISSING_PARAM"}

	var changed: Array = []
	for key in settings:
		var value = TypeParser.parse_value(settings[key])
		ProjectSettings.set_setting(key, value)
		changed.append(key)

	var err = ProjectSettings.save()
	if err != OK:
		return {"error": "Failed to save project settings: %s" % error_string(err), "code": "SAVE_FAILED"}

	return {"changed": changed, "saved": true}


func uid_to_project_path(params: Dictionary) -> Dictionary:
	var uid_str: String = params.get("uid", "")
	if uid_str == "":
		return {"error": "uid parameter is required", "code": "MISSING_PARAM"}

	# Use ResourceUID to resolve
	var uid = ResourceUID.text_to_id(uid_str)
	if uid == ResourceUID.INVALID_ID:
		return {"error": "Invalid UID: %s" % uid_str, "code": "INVALID_UID"}

	if ResourceUID.has_id(uid):
		var path = ResourceUID.get_id_path(uid)
		return {"uid": uid_str, "path": path}
	else:
		return {"error": "UID not found: %s" % uid_str, "code": "UID_NOT_FOUND"}


func project_path_to_uid(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	if path == "":
		return {"error": "path parameter is required", "code": "MISSING_PARAM"}

	if not path.begins_with("res://"):
		path = "res://" + path

	if not ResourceLoader.exists(path):
		return {"error": "Resource not found: %s" % path, "code": "RESOURCE_NOT_FOUND"}

	var uid = ResourceLoader.get_resource_uid(path)
	if uid == ResourceUID.INVALID_ID:
		return {"error": "No UID for: %s" % path, "code": "NO_UID"}

	var uid_str = ResourceUID.id_to_text(uid)
	return {"path": path, "uid": uid_str}


func _count_files(path: String, counts: Dictionary) -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue
		var full_path = path.path_join(file_name)
		if dir.current_is_dir():
			_count_files(full_path, counts)
		else:
			var ext = file_name.get_extension().to_lower()
			if ext == "tscn" or ext == "scn":
				counts.scenes += 1
			elif ext == "gd" or ext == "cs" or ext == "gdscript":
				counts.scripts += 1
			elif ext == "tres" or ext == "res":
				counts.resources += 1
			else:
				counts.other += 1
		file_name = dir.get_next()
	dir.list_dir_end()


func _build_tree(path: String, depth: int, max_depth: int) -> Dictionary:
	var result: Dictionary = {
		"name": path.get_file() if path != "res://" else "res://",
		"path": path,
		"type": "directory",
	}

	if depth >= max_depth:
		result["truncated"] = true
		return result

	var children: Array = []
	var dir = DirAccess.open(path)
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.begins_with(".") or file_name == "addons":
			file_name = dir.get_next()
			continue
		var full_path = path.path_join(file_name)
		if dir.current_is_dir():
			children.append(_build_tree(full_path, depth + 1, max_depth))
		else:
			children.append({
				"name": file_name,
				"path": full_path,
				"type": "file",
				"extension": file_name.get_extension(),
			})
		file_name = dir.get_next()
	dir.list_dir_end()

	result["children"] = children
	return result


func _search_recursive(path: String, query: String, file_type: String, results: Array, max_results: int) -> void:
	if results.size() >= max_results:
		return

	var dir = DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "" and results.size() < max_results:
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue
		var full_path = path.path_join(file_name)
		if dir.current_is_dir():
			_search_recursive(full_path, query, file_type, results, max_results)
		else:
			var matches_type = file_type == "" or file_name.get_extension().to_lower() == file_type.to_lower()
			var matches_query = query == "*" or file_name.to_lower().contains(query.to_lower()) or full_path.to_lower().contains(query.to_lower())
			if matches_type and matches_query:
				results.append({"path": full_path, "name": file_name})
		file_name = dir.get_next()
	dir.list_dir_end()
