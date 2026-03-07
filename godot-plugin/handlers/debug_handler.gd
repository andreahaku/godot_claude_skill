@tool
class_name DebugHandler
extends RefCounted

## Debug tools (4):
## get_output_log, get_runtime_errors, set_breakpoint, clear_breakpoints

var _editor: EditorInterface
var _plugin: EditorPlugin


func _init(editor: EditorInterface, plugin: EditorPlugin):
	_editor = editor
	_plugin = plugin


func get_commands() -> Dictionary:
	return {
		"get_output_log": get_output_log,
		"get_runtime_errors": get_runtime_errors,
		"set_breakpoint": set_breakpoint,
		"clear_breakpoints": clear_breakpoints,
	}


func get_output_log(params: Dictionary) -> Dictionary:
	var lines_count: int = params.get("lines", 50)
	if lines_count <= 0:
		lines_count = 50

	var log_path := _get_log_path()
	if log_path == "":
		return {"error": "Could not determine log file path", "code": "LOG_PATH_ERROR"}

	if not FileAccess.file_exists(log_path):
		return {"error": "Log file not found at: %s" % log_path, "code": "LOG_NOT_FOUND"}

	var file := FileAccess.open(log_path, FileAccess.READ)
	if file == null:
		return {"error": "Cannot open log file: %s" % error_string(FileAccess.get_open_error()), "code": "LOG_READ_ERROR"}

	# Read all lines and return the last N
	var all_lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()

	# Remove trailing empty line from split
	if all_lines.size() > 0 and all_lines[all_lines.size() - 1] == "":
		all_lines.resize(all_lines.size() - 1)

	var total := all_lines.size()
	var start_idx := maxi(0, total - lines_count)
	var result_lines: Array = []
	for i in range(start_idx, total):
		result_lines.append(all_lines[i])

	return {
		"lines": result_lines,
		"count": result_lines.size(),
		"total_lines": total,
		"log_path": log_path,
	}


func get_runtime_errors(params: Dictionary) -> Dictionary:
	var lines_count: int = params.get("lines", 50)
	if lines_count <= 0:
		lines_count = 50

	var log_path := _get_log_path()
	if log_path == "":
		return {"error": "Could not determine log file path", "code": "LOG_PATH_ERROR"}

	if not FileAccess.file_exists(log_path):
		return {"error": "Log file not found at: %s" % log_path, "code": "LOG_NOT_FOUND"}

	var file := FileAccess.open(log_path, FileAccess.READ)
	if file == null:
		return {"error": "Cannot open log file: %s" % error_string(FileAccess.get_open_error()), "code": "LOG_READ_ERROR"}

	var content := file.get_as_text()
	file.close()

	var all_lines: PackedStringArray = content.split("\n")
	var error_keywords: PackedStringArray = ["ERROR", "SCRIPT ERROR", "push_error"]

	# Filter lines containing error keywords
	var error_lines: Array = []
	for i in range(all_lines.size()):
		var line: String = all_lines[i]
		for keyword in error_keywords:
			if line.contains(keyword):
				error_lines.append({
					"line_number": i + 1,
					"text": line,
				})
				break

	# Return only the last N error lines
	var total_errors := error_lines.size()
	if total_errors > lines_count:
		error_lines = error_lines.slice(total_errors - lines_count)

	return {
		"errors": error_lines,
		"count": error_lines.size(),
		"total_errors": total_errors,
		"log_path": log_path,
		"game_running": _editor.is_playing_scene(),
	}


func set_breakpoint(params: Dictionary) -> Dictionary:
	var script_path: String = params.get("script_path", "")
	var line: int = params.get("line", -1)

	if script_path == "":
		return {"error": "script_path parameter is required", "code": "MISSING_PARAM"}
	if line < 0:
		return {"error": "line parameter is required (0-based line number)", "code": "MISSING_PARAM"}

	# Verify the script exists
	if not ResourceLoader.exists(script_path):
		return {"error": "Script not found: %s" % script_path, "code": "SCRIPT_NOT_FOUND"}

	# Load the script resource
	var script = load(script_path)
	if script == null:
		return {"error": "Failed to load script: %s" % script_path, "code": "LOAD_ERROR"}

	# Open the script in the editor and navigate to the line.
	# EditorInterface.edit_script() opens the script at the specified line,
	# but does not programmatically toggle a breakpoint. The Godot 4.x editor
	# API does not expose a method to set breakpoints from code.
	_editor.edit_script(script, line)

	return {
		"script_path": script_path,
		"line": line,
		"navigated": true,
		"breakpoint_set": false,
		"note": "Navigated to the specified line in the script editor. Godot 4.x does not expose a public API to programmatically set breakpoints. You must click in the gutter or press F9 to toggle the breakpoint at this line.",
	}


func clear_breakpoints(params: Dictionary) -> Dictionary:
	return {
		"cleared": false,
		"note": "Breakpoint management is not available through the Godot 4.x EditorInterface API. Breakpoints must be toggled manually in the script editor (click the line gutter or press F9). To clear all breakpoints, use Debug > Clear All Breakpoints in the editor menu.",
	}


func _get_log_path() -> String:
	# Godot writes its log to <user_data_dir>/logs/godot.log
	# OS.get_user_data_dir() returns the project-specific user data path.
	var user_dir := OS.get_user_data_dir()
	if user_dir == "":
		return ""
	return user_dir.path_join("logs").path_join("godot.log")
