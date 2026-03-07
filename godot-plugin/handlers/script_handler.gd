@tool
class_name ScriptHandler
extends RefCounted

## Script tools (10):
## list_scripts, read_script, create_script,
## edit_script, attach_script, get_open_scripts,
## patch_script, validate_script, validate_scripts,
## get_script_diagnostics

var _editor: EditorInterface
var _undo: UndoHelper


func _init(editor: EditorInterface, undo: UndoHelper):
	_editor = editor
	_undo = undo


func get_commands() -> Dictionary:
	return {
		"list_scripts": {
			"handler": list_scripts,
			"description": "List all script files in the project",
			"params": {
				"path": {"type": "string", "default": "res://", "description": "Directory to search for scripts"},
				"max_results": {"type": "int", "default": 500, "description": "Maximum number of scripts to return"},
			},
			"metadata": {
				"safe_for_batch": true,
			},
		},
		"read_script": {
			"handler": read_script,
			"description": "Read the source code of a script file",
			"params": {
				"path": {"type": "string", "required": true, "description": "Path to the script file (e.g., res://scripts/player.gd)"},
			},
			"metadata": {
				"safe_for_batch": true,
			},
		},
		"create_script": {
			"handler": create_script,
			"description": "Create a new GDScript file with optional content",
			"params": {
				"path": {"type": "string", "required": true, "description": "Path for the new script file"},
				"content": {"type": "string", "default": "", "description": "Script content (auto-generated template if empty)"},
				"base_class": {"type": "string", "default": "Node", "description": "Base class for the auto-generated template"},
				"class_name": {"type": "string", "default": "", "description": "Class name declaration for the auto-generated template"},
			},
			"metadata": {
				"persistent": true,
				"undoable": false,
				"safe_for_batch": true,
			},
		},
		"edit_script": {
			"handler": edit_script,
			"description": "Edit an existing script via search/replace, line insertion, or full replacement",
			"params": {
				"path": {"type": "string", "required": true, "description": "Path to the script file to edit"},
				"search": {"type": "string", "default": "", "description": "Text to search for (used with replace)"},
				"replace": {"type": "string", "default": "", "description": "Replacement text (used with search)"},
				"insert_at_line": {"type": "int", "default": -1, "description": "Line number to insert at (0-indexed, used with insert_text)"},
				"insert_text": {"type": "string", "default": "", "description": "Text to insert (used with insert_at_line)"},
				"new_content": {"type": "string", "default": "", "description": "Complete new content to replace the entire file"},
			},
			"metadata": {
				"persistent": true,
				"undoable": false,
				"safe_for_batch": true,
			},
		},
		"attach_script": {
			"handler": attach_script,
			"description": "Attach an existing script file to a node",
			"params": {
				"node_path": {"type": "string", "required": true, "description": "Path to the target node"},
				"script_path": {"type": "string", "required": true, "description": "Path to the script file to attach"},
			},
			"metadata": {
				"undoable": true,
				"safe_for_batch": true,
			},
		},
		"get_open_scripts": {
			"handler": get_open_scripts,
			"description": "List all scripts currently open in the script editor",
			"params": {},
			"metadata": {
				"safe_for_batch": true,
			},
		},
		"patch_script": {
			"handler": patch_script,
			"description": "Apply multiple patch operations to a script (replace ranges, blocks, insert before/after markers)",
			"params": {
				"path": {"type": "string", "required": true, "description": "Path to the script file to patch"},
				"expected_hash": {"type": "string", "default": "", "description": "MD5 hash of current content for conflict detection"},
				"operations": {"type": "array", "required": true, "description": "Array of patch operations: replace_range, replace_exact_block, insert_before_marker, insert_after_marker, append_to_class"},
			},
			"metadata": {
				"persistent": true,
				"undoable": false,
				"safe_for_batch": true,
			},
		},
		"validate_script": {
			"handler": validate_script,
			"description": "Check if a GDScript file compiles without errors",
			"params": {
				"path": {"type": "string", "required": true, "description": "Path to the script file to validate"},
			},
			"metadata": {
				"safe_for_batch": true,
			},
		},
		"validate_scripts": {
			"handler": validate_scripts,
			"description": "Validate all scripts in a directory for compilation errors",
			"params": {
				"path": {"type": "string", "default": "res://", "description": "Directory to scan for scripts"},
				"max_results": {"type": "int", "default": 100, "description": "Maximum number of scripts to validate"},
			},
			"metadata": {
				"safe_for_batch": true,
			},
		},
		"get_script_diagnostics": {
			"handler": get_script_diagnostics,
			"description": "Get detailed diagnostics for a script (compilation status, dependencies, warnings)",
			"params": {
				"path": {"type": "string", "required": true, "description": "Path to the script file to diagnose"},
			},
			"metadata": {
				"safe_for_batch": true,
			},
		},
	}


func list_scripts(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "res://")
	var max_results: int = params.get("max_results", 500)
	var results: Array = []
	_find_scripts(path, results, max_results)
	var truncated = results.size() >= max_results
	return {"scripts": results, "count": results.size(), "truncated": truncated}


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


# ── patch_script ──────────────────────────────────────────────────────────────

func patch_script(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	var expected_hash: String = params.get("expected_hash", "")
	var operations: Array = params.get("operations", [])

	if path == "":
		return {"error": "path is required", "code": "MISSING_PARAM"}
	if not path.begins_with("res://"):
		path = "res://" + path
	if operations.is_empty():
		return {"error": "operations array is required", "code": "MISSING_PARAM"}

	# Read current content
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Cannot open script: %s" % path, "code": "FILE_NOT_FOUND"}
	var source = file.get_as_text()
	file.close()

	# Verify hash if provided
	if expected_hash != "":
		var actual_hash = source.md5_text()
		if actual_hash != expected_hash:
			return {"error": "Script has been modified (hash mismatch)", "code": "STALE_EDIT",
				"expected_hash": expected_hash, "actual_hash": actual_hash}

	# Apply operations sequentially
	var modified = source
	var applied: Array = []
	var diff_summary: Array = []

	for i in operations.size():
		var op = operations[i]
		var op_type: String = op.get("type", "")
		var result = _apply_operation(modified, op_type, op)

		if result.has("error"):
			return {"error": "Operation %d (%s) failed: %s" % [i, op_type, result.error],
				"code": "PATCH_FAILED", "failed_operation": i, "applied": applied}

		diff_summary.append({"operation": i, "type": op_type, "description": result.get("description", "")})
		modified = result.new_content
		applied.append(i)

	# Write modified content
	file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"error": "Cannot write to script: %s" % path, "code": "FILE_WRITE_ERROR"}
	file.store_string(modified)
	file.close()

	_editor.get_resource_filesystem().scan()

	# Reload script
	var script = load(path)
	if script is GDScript:
		script.source_code = modified
		var err = script.reload()
		if err != OK:
			# Script has errors — report but don't fail (the patch was applied)
			return {"path": path, "patched": true, "operations_applied": applied.size(),
				"diff": diff_summary, "new_hash": modified.md5_text(),
				"warning": "Script has compilation errors after patching"}

	return {"path": path, "patched": true, "operations_applied": applied.size(),
		"diff": diff_summary, "new_hash": modified.md5_text()}


func _apply_operation(content: String, op_type: String, op: Dictionary) -> Dictionary:
	match op_type:
		"replace_range":
			return _op_replace_range(content, op)
		"replace_exact_block":
			return _op_replace_exact_block(content, op)
		"insert_before_marker":
			return _op_insert_before_marker(content, op)
		"insert_after_marker":
			return _op_insert_after_marker(content, op)
		"append_to_class":
			return _op_append_to_class(content, op)
		_:
			return {"error": "Unknown operation type: %s" % op_type}


func _op_replace_range(content: String, op: Dictionary) -> Dictionary:
	var start_line: int = op.get("start_line", -1)
	var end_line: int = op.get("end_line", -1)
	var new_text: String = op.get("content", "")

	if start_line < 1 or end_line < 1:
		return {"error": "start_line and end_line are required (1-indexed)"}
	if end_line < start_line:
		return {"error": "end_line must be >= start_line"}

	var lines = content.split("\n")
	if start_line > lines.size():
		return {"error": "start_line %d exceeds line count %d" % [start_line, lines.size()]}
	if end_line > lines.size():
		return {"error": "end_line %d exceeds line count %d" % [end_line, lines.size()]}

	# Convert to 0-indexed
	var before = lines.slice(0, start_line - 1)
	var after = lines.slice(end_line)

	# Build new content: before + replacement + after
	var replacement_lines = new_text.split("\n") if new_text != "" else PackedStringArray()
	# Remove trailing empty element if new_text ends with \n
	if replacement_lines.size() > 0 and new_text.ends_with("\n") and replacement_lines[-1] == "":
		replacement_lines = replacement_lines.slice(0, replacement_lines.size() - 1)

	var result_lines: PackedStringArray = []
	result_lines.append_array(before)
	result_lines.append_array(replacement_lines)
	result_lines.append_array(after)

	return {"new_content": "\n".join(result_lines),
		"description": "Replaced lines %d-%d" % [start_line, end_line]}


func _op_replace_exact_block(content: String, op: Dictionary) -> Dictionary:
	var search: String = op.get("search", "")
	var replacement: String = op.get("replace", "")
	var occurrence: int = op.get("occurrence", 1)

	if search == "":
		return {"error": "search text is required"}

	# Count occurrences
	var count: int = 0
	var search_pos: int = 0
	while true:
		var idx = content.find(search, search_pos)
		if idx == -1:
			break
		count += 1
		search_pos = idx + 1

	if count == 0:
		return {"error": "Search text not found in script"}

	if occurrence == -1:
		# Replace all occurrences
		var new_content = content.replace(search, replacement)
		return {"new_content": new_content,
			"description": "Replaced all %d occurrence(s) of '%s'" % [count, _truncate(search, 40)]}

	if occurrence < 1 or occurrence > count:
		return {"error": "Requested occurrence %d but only %d found" % [occurrence, count]}

	# Replace specific occurrence
	var current: int = 0
	search_pos = 0
	var new_content = content
	while true:
		var idx = new_content.find(search, search_pos)
		if idx == -1:
			break
		current += 1
		if current == occurrence:
			new_content = new_content.substr(0, idx) + replacement + new_content.substr(idx + search.length())
			break
		search_pos = idx + 1

	return {"new_content": new_content,
		"description": "Replaced occurrence %d of '%s'" % [occurrence, _truncate(search, 40)]}


func _op_insert_before_marker(content: String, op: Dictionary) -> Dictionary:
	var marker: String = op.get("marker", "")
	var insert_content: String = op.get("content", "")

	if marker == "":
		return {"error": "marker text is required"}

	var lines = content.split("\n")
	var target_idx: int = -1

	for i in lines.size():
		if lines[i].contains(marker):
			target_idx = i
			break

	if target_idx == -1:
		return {"error": "Marker not found: '%s'" % _truncate(marker, 60)}

	# Insert content before the target line
	var insert_lines = insert_content.split("\n")
	# Remove trailing empty element if content ends with \n
	if insert_lines.size() > 0 and insert_content.ends_with("\n") and insert_lines[-1] == "":
		insert_lines = insert_lines.slice(0, insert_lines.size() - 1)

	var result_lines: PackedStringArray = []
	result_lines.append_array(lines.slice(0, target_idx))
	result_lines.append_array(insert_lines)
	result_lines.append_array(lines.slice(target_idx))

	return {"new_content": "\n".join(result_lines),
		"description": "Inserted before marker '%s' at line %d" % [_truncate(marker, 40), target_idx + 1]}


func _op_insert_after_marker(content: String, op: Dictionary) -> Dictionary:
	var marker: String = op.get("marker", "")
	var insert_content: String = op.get("content", "")

	if marker == "":
		return {"error": "marker text is required"}

	var lines = content.split("\n")
	var target_idx: int = -1

	for i in lines.size():
		if lines[i].contains(marker):
			target_idx = i
			break

	if target_idx == -1:
		return {"error": "Marker not found: '%s'" % _truncate(marker, 60)}

	# Insert content after the target line
	var insert_lines = insert_content.split("\n")
	# Remove trailing empty element if content ends with \n
	if insert_lines.size() > 0 and insert_content.ends_with("\n") and insert_lines[-1] == "":
		insert_lines = insert_lines.slice(0, insert_lines.size() - 1)

	var result_lines: PackedStringArray = []
	result_lines.append_array(lines.slice(0, target_idx + 1))
	result_lines.append_array(insert_lines)
	result_lines.append_array(lines.slice(target_idx + 1))

	return {"new_content": "\n".join(result_lines),
		"description": "Inserted after marker '%s' at line %d" % [_truncate(marker, 40), target_idx + 1]}


func _op_append_to_class(content: String, op: Dictionary) -> Dictionary:
	var append_content: String = op.get("content", "")

	if append_content == "":
		return {"error": "content is required"}

	var new_content = content + append_content
	return {"new_content": new_content,
		"description": "Appended content to end of file"}


# ── validate_script ───────────────────────────────────────────────────────────

func validate_script(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	if path == "":
		return {"error": "path is required", "code": "MISSING_PARAM"}
	if not path.begins_with("res://"):
		path = "res://" + path

	if not ResourceLoader.exists(path):
		return {"error": "Script not found: %s" % path, "code": "FILE_NOT_FOUND"}

	var script = load(path)
	if script == null:
		return {"error": "Failed to load: %s" % path, "code": "LOAD_ERROR"}

	if script is GDScript:
		# Force reload to check for errors
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			script.source_code = file.get_as_text()
			file.close()
		var err = script.reload()
		if err != OK:
			return {"path": path, "valid": false, "error_code": err,
				"error": "Script compilation failed (error %d)" % err}

	return {"path": path, "valid": true}


# ── validate_scripts ──────────────────────────────────────────────────────────

func validate_scripts(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "res://")
	var max_results: int = params.get("max_results", 100)

	var scripts: Array = []
	_find_scripts(path, scripts, max_results)

	var valid: int = 0
	var invalid: int = 0
	var errors: Array = []

	for script_info in scripts:
		var result = validate_script({"path": script_info.path})
		if result.get("valid", false):
			valid += 1
		else:
			invalid += 1
			errors.append({"path": script_info.path, "error": result.get("error", "Unknown")})

	return {"total": scripts.size(), "valid": valid, "invalid": invalid, "errors": errors}


# ── get_script_diagnostics ────────────────────────────────────────────────────

func get_script_diagnostics(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	if path == "":
		return {"error": "path is required", "code": "MISSING_PARAM"}
	if not path.begins_with("res://"):
		path = "res://" + path

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Cannot open: %s" % path, "code": "FILE_NOT_FOUND"}
	var source = file.get_as_text()
	file.close()

	var diagnostics: Dictionary = {
		"path": path,
		"line_count": source.count("\n") + 1,
		"hash": source.md5_text(),
		"size_bytes": source.length(),
	}

	# Check for common issues
	var warnings: Array = []
	var lines = source.split("\n")

	# Check for extends
	var has_extends = false
	for line in lines:
		if line.strip_edges().begins_with("extends "):
			has_extends = true
			diagnostics["extends"] = line.strip_edges().substr(8)
			break
	if not has_extends:
		warnings.append("No 'extends' declaration found")

	# Check for class_name
	for line in lines:
		if line.strip_edges().begins_with("class_name "):
			diagnostics["class_name"] = line.strip_edges().substr(11)
			break

	# Try compilation
	var script = load(path)
	if script is GDScript:
		script.source_code = source
		var err = script.reload()
		diagnostics["compiles"] = (err == OK)
		if err != OK:
			diagnostics["compile_error"] = err

	# Find dependencies (preload/load calls)
	var deps: Array = []
	for line in lines:
		if "preload(" in line or "load(" in line:
			var start = line.find("\"")
			var end = line.rfind("\"")
			if start >= 0 and end > start:
				var dep_path = line.substr(start + 1, end - start - 1)
				deps.append(dep_path)
				if not ResourceLoader.exists(dep_path):
					warnings.append("Missing dependency: %s" % dep_path)

	diagnostics["dependencies"] = deps
	diagnostics["warnings"] = warnings

	return diagnostics


# ── Helpers ───────────────────────────────────────────────────────────────────

func _truncate(text: String, max_len: int) -> String:
	if text.length() <= max_len:
		return text
	return text.substr(0, max_len - 3) + "..."


func _find_scripts(path: String, results: Array, max_results: int = 500) -> void:
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
			_find_scripts(full_path, results, max_results)
		else:
			var ext = file_name.get_extension().to_lower()
			if ext == "gd" or ext == "cs":
				results.append({"path": full_path, "name": file_name, "type": ext})
		file_name = dir.get_next()
	dir.list_dir_end()
