@tool
class_name ExportHandler
extends RefCounted

## Export tools (3):
## list_export_presets, export_project, get_export_info

var _editor: EditorInterface


func _init(editor: EditorInterface):
	_editor = editor


func get_commands() -> Dictionary:
	return {
		"list_export_presets": list_export_presets,
		"export_project": export_project,
		"get_export_info": get_export_info,
	}


func list_export_presets(params: Dictionary) -> Dictionary:
	# Read export_presets.cfg
	var path = "res://export_presets.cfg"
	if not FileAccess.file_exists(path):
		return {"presets": [], "count": 0, "message": "No export_presets.cfg found"}

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Cannot read export_presets.cfg", "code": "FILE_READ_ERROR"}

	var content = file.get_as_text()
	file.close()

	var presets: Array = []
	var current_preset: Dictionary = {}

	for line in content.split("\n"):
		line = line.strip_edges()
		if line.begins_with("[preset."):
			if not current_preset.is_empty():
				presets.append(current_preset)
			current_preset = {}
		elif "=" in line:
			var parts = line.split("=", true, 1)
			var key = parts[0].strip_edges()
			var value = parts[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
			if key == "name":
				current_preset["name"] = value
			elif key == "platform":
				current_preset["platform"] = value
			elif key == "export_path":
				current_preset["export_path"] = value

	if not current_preset.is_empty():
		presets.append(current_preset)

	return {"presets": presets, "count": presets.size()}


func export_project(params: Dictionary) -> Dictionary:
	var preset_name: String = params.get("preset", "")
	var output_path: String = params.get("output_path", "")
	var debug: bool = params.get("debug", false)

	if preset_name == "":
		return {"error": "preset name is required", "code": "MISSING_PARAM"}

	# Find the Godot executable path
	var godot_path = OS.get_executable_path()
	var project_path = ProjectSettings.globalize_path("res://")

	var args: Array = [
		"--headless",
		"--path", project_path,
		"--export-debug" if debug else "--export-release",
		preset_name,
	]
	if output_path != "":
		args.append(output_path)

	# Note: Export is typically done via CLI. We return the command to execute.
	return {
		"command": godot_path,
		"args": args,
		"message": "Run this command to export. Export from within the editor plugin is limited.",
	}


func get_export_info(params: Dictionary) -> Dictionary:
	var godot_path = OS.get_executable_path()
	var project_path = ProjectSettings.globalize_path("res://")

	# Check for export templates
	var template_path = OS.get_user_data_dir().get_base_dir().path_join("export_templates")

	var info: Dictionary = {
		"godot_executable": godot_path,
		"project_path": project_path,
		"export_templates_path": template_path,
	}

	# Check export_presets.cfg
	if FileAccess.file_exists("res://export_presets.cfg"):
		info["has_export_presets"] = true
	else:
		info["has_export_presets"] = false
		info["suggestion"] = "No export presets configured. Use Project > Export in the Godot editor to create presets."

	return info
