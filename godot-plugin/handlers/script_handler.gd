class_name ScriptHandler
extends RefCounted

## Script tools (6):
## list_scripts, read_script, create_script,
## edit_script, attach_script, get_open_scripts

var _editor: EditorInterface
var _undo: UndoHelper


func _init(editor: EditorInterface, undo: UndoHelper):
	_editor = editor
	_undo = undo


func get_commands() -> Dictionary:
	return {
		"list_scripts": list_scripts,
		"read_script": read_script,
		"create_script": create_script,
		"edit_script": edit_script,
		"attach_script": attach_script,
		"get_open_scripts": get_open_scripts,
	}


func list_scripts(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "res://")
	var results: Array = []
	_find_scripts(path, results)
	return {"scripts": results, "count": results.size()}


func read_script(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	if path == "":
		return {"error": "path parameter is required", "code": "MISSING_PARAM"}
	if not path.begins_with("res://"):
		path = "res://" + path

	if not ResourceLoader.exists(path):
		return {"error": "Script not found: %s" % path, "code": "FILE_NOT_FOUND"}

	var script = load(path)
	if script == null:
		return {"error": "Failed to load script: %s" % path, "code": "LOAD_ERROR"}

	var source = ""
	if script is GDScript:
		source = script.source_code
	else:
		# Read file directly for non-GDScript files
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			source = file.get_as_text()
			file.close()

	return {
		"path": path,
		"source": source,
		"class_name": script.get_class() if script else "",
		"line_count": source.count("\n") + 1 if source != "" else 0,
	}


func create_script(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	var content: String = params.get("content", "")
	var base_class: String = params.get("base_class", "Node")
	var class_name_str: String = params.get("class_name", "")

	if path == "":
		return {"error": "path parameter is required", "code": "MISSING_PARAM"}
	if not path.begins_with("res://"):
		path = "res://" + path
	if not path.ends_with(".gd"):
		path += ".gd"

	# Generate default content if none provided
	if content == "":
		content = "extends %s\n" % base_class
		if class_name_str != "":
			content += "class_name %s\n" % class_name_str
		content += "\n\nfunc _ready() -> void:\n\tpass\n\n\nfunc _process(delta: float) -> void:\n\tpass\n"

	# Ensure directory exists
	var dir_path = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))

	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"error": "Failed to create file: %s" % path, "code": "FILE_CREATE_ERROR"}
	file.store_string(content)
	file.close()

	_editor.get_resource_filesystem().scan()
	return {"path": path, "created": true}


func edit_script(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	var search: String = params.get("search", "")
	var replace: String = params.get("replace", "")
	var insert_at_line: int = params.get("insert_at_line", -1)
	var insert_text: String = params.get("insert_text", "")
	var new_content: String = params.get("new_content", "")

	if path == "":
		return {"error": "path parameter is required", "code": "MISSING_PARAM"}
	if not path.begins_with("res://"):
		path = "res://" + path

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Cannot open script: %s" % path, "code": "FILE_NOT_FOUND"}

	var source = file.get_as_text()
	file.close()

	var modified = source

	if new_content != "":
		# Full replacement
		modified = new_content
	elif search != "":
		# Search and replace
		if not modified.contains(search):
			return {"error": "Search string not found in script", "code": "NOT_FOUND", "suggestions": ["Check the search string matches exactly"]}
		modified = modified.replace(search, replace)
	elif insert_at_line >= 0 and insert_text != "":
		# Insert at line
		var lines = modified.split("\n")
		if insert_at_line > lines.size():
			insert_at_line = lines.size()
		var new_lines = lines.slice(0, insert_at_line)
		new_lines.append(insert_text)
		new_lines.append_array(lines.slice(insert_at_line))
		modified = "\n".join(new_lines)
	else:
		return {"error": "Provide search/replace, insert_at_line/insert_text, or new_content", "code": "MISSING_PARAM"}

	file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"error": "Cannot write to script: %s" % path, "code": "FILE_WRITE_ERROR"}
	file.store_string(modified)
	file.close()

	_editor.get_resource_filesystem().scan()

	# Reload the script in the editor
	var script = load(path)
	if script is GDScript:
		script.source_code = modified
		script.reload()

	return {"path": path, "modified": true}


func attach_script(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var script_path: String = params.get("script_path", "")
	if node_path == "" or script_path == "":
		return {"error": "node_path and script_path are required", "code": "MISSING_PARAM"}
	if not script_path.begins_with("res://"):
		script_path = "res://" + script_path

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open", "code": "NO_SCENE"}

	var node = root.get_node_or_null(node_path) if node_path != root.name else root
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	if not ResourceLoader.exists(script_path):
		return {"error": "Script not found: %s" % script_path, "code": "FILE_NOT_FOUND"}

	var script = load(script_path)
	if script == null:
		return {"error": "Failed to load script: %s" % script_path, "code": "LOAD_ERROR"}

	var old_script = node.get_script()

	_undo.create_action("Attach Script: %s to %s" % [script_path, node.name])
	_undo.add_do_property(node, &"script", script)
	_undo.add_undo_property(node, &"script", old_script)
	_undo.commit_action()

	return {"node_path": node_path, "script_path": script_path, "attached": true}


func get_open_scripts(params: Dictionary) -> Dictionary:
	var script_editor = _editor.get_script_editor()
	if script_editor == null:
		return {"scripts": []}

	var open_scripts: Array = []
	for script in script_editor.get_open_scripts():
		open_scripts.append({
			"path": script.resource_path,
			"class": script.get_class(),
		})

	return {"scripts": open_scripts}


func _find_scripts(path: String, results: Array) -> void:
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
			_find_scripts(full_path, results)
		else:
			var ext = file_name.get_extension().to_lower()
			if ext == "gd" or ext == "cs":
				results.append({"path": full_path, "name": file_name, "type": ext})
		file_name = dir.get_next()
	dir.list_dir_end()
