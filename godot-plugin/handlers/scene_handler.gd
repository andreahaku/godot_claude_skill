@tool
class_name SceneHandler
extends RefCounted

## Scene tools (9):
## get_scene_tree, get_scene_file_content, create_scene,
## open_scene, delete_scene, save_scene,
## add_scene_instance, play_scene, stop_scene

var _editor: EditorInterface
var _undo: UndoHelper


func _init(editor: EditorInterface, undo: UndoHelper):
	_editor = editor
	_undo = undo


func get_commands() -> Dictionary:
	return {
		"get_scene_tree": get_scene_tree,
		"get_scene_file_content": get_scene_file_content,
		"create_scene": create_scene,
		"open_scene": open_scene,
		"delete_scene": delete_scene,
		"save_scene": save_scene,
		"add_scene_instance": add_scene_instance,
		"play_scene": play_scene,
		"stop_scene": stop_scene,
	}


func get_scene_tree(params: Dictionary) -> Dictionary:
	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open", "code": "NO_SCENE"}
	var tree = _node_to_dict(root)
	return {"tree": tree}


func get_scene_file_content(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	if path == "":
		return {"error": "path parameter is required", "code": "MISSING_PARAM"}
	if not path.begins_with("res://"):
		path = "res://" + path

	var abs_path = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		if not ResourceLoader.exists(path):
			return {"error": "File not found: %s" % path, "code": "FILE_NOT_FOUND"}

	var file = FileAccess.open(abs_path, FileAccess.READ)
	if file == null:
		# Try via globalized path
		file = FileAccess.open(path, FileAccess.READ)
		if file == null:
			return {"error": "Cannot open file: %s" % path, "code": "FILE_OPEN_ERROR"}

	var content = file.get_as_text()
	file.close()
	return {"path": path, "content": content}


func create_scene(params: Dictionary) -> Dictionary:
	var scene_path: String = params.get("path", "")
	var root_type: String = params.get("root_type", "Node2D")

	if scene_path == "":
		return {"error": "path parameter is required", "code": "MISSING_PARAM"}
	if not scene_path.begins_with("res://"):
		scene_path = "res://" + scene_path
	if not scene_path.ends_with(".tscn"):
		scene_path += ".tscn"

	# Create root node
	var root = ClassDB.instantiate(root_type)
	if root == null:
		return {"error": "Cannot instantiate root type: %s" % root_type, "code": "INVALID_TYPE"}

	if root is Node:
		root.name = scene_path.get_file().get_basename()

	# Create and save packed scene
	var scene = PackedScene.new()
	var err = scene.pack(root)
	if err != OK:
		root.queue_free()
		return {"error": "Failed to pack scene: %s" % error_string(err), "code": "PACK_ERROR"}

	# Ensure directory exists
	var dir_path = scene_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))

	err = ResourceSaver.save(scene, scene_path)
	root.queue_free()
	if err != OK:
		return {"error": "Failed to save scene: %s" % error_string(err), "code": "SAVE_ERROR"}

	_editor.get_resource_filesystem().scan()

	# Auto-open the scene unless explicitly disabled
	var auto_open: bool = params.get("open", true)
	if auto_open:
		_editor.open_scene_from_path(scene_path)

	return {"path": scene_path, "root_type": root_type, "opened": auto_open}


func open_scene(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	if path == "":
		return {"error": "path parameter is required", "code": "MISSING_PARAM"}
	if not path.begins_with("res://"):
		path = "res://" + path

	if not ResourceLoader.exists(path):
		return {"error": "Scene not found: %s" % path, "code": "FILE_NOT_FOUND"}

	_editor.open_scene_from_path(path)
	return {"path": path, "opened": true}


func delete_scene(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	if path == "":
		return {"error": "path parameter is required", "code": "MISSING_PARAM"}
	if not path.begins_with("res://"):
		path = "res://" + path

	var abs_path = ProjectSettings.globalize_path(path)
	var err = DirAccess.remove_absolute(abs_path)
	if err != OK:
		return {"error": "Failed to delete scene: %s" % error_string(err), "code": "DELETE_ERROR"}

	# Also remove .import if exists
	if FileAccess.file_exists(abs_path + ".import"):
		DirAccess.remove_absolute(abs_path + ".import")

	_editor.get_resource_filesystem().scan()
	return {"path": path, "deleted": true}


func save_scene(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")

	if path != "":
		if not path.begins_with("res://"):
			path = "res://" + path
		# Save current scene to a specific path
		var scene = _editor.get_edited_scene_root()
		if scene == null:
			return {"error": "No scene is currently open", "code": "NO_SCENE"}
		var packed = PackedScene.new()
		packed.pack(scene)
		var err = ResourceSaver.save(packed, path)
		if err != OK:
			return {"error": "Failed to save scene: %s" % error_string(err), "code": "SAVE_ERROR"}
		return {"path": path, "saved": true}
	else:
		# Save current scene to its existing path
		_editor.save_scene()
		var scene = _editor.get_edited_scene_root()
		if scene:
			return {"path": scene.scene_file_path, "saved": true}
		return {"error": "No scene to save", "code": "NO_SCENE"}


func add_scene_instance(params: Dictionary) -> Dictionary:
	var scene_path: String = params.get("scene_path", "")
	var parent_path: String = params.get("parent_path", "")

	if scene_path == "":
		return {"error": "scene_path parameter is required", "code": "MISSING_PARAM"}
	if not scene_path.begins_with("res://"):
		scene_path = "res://" + scene_path

	if not ResourceLoader.exists(scene_path):
		return {"error": "Scene not found: %s" % scene_path, "code": "FILE_NOT_FOUND"}

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open", "code": "NO_SCENE"}

	var parent: Node = root
	if parent_path != "" and parent_path != "/root":
		parent = root.get_node_or_null(parent_path)
		if parent == null:
			return {"error": "Parent node not found: %s" % parent_path, "code": "NODE_NOT_FOUND"}

	var packed = load(scene_path) as PackedScene
	if packed == null:
		return {"error": "Failed to load scene: %s" % scene_path, "code": "LOAD_ERROR"}

	var instance = packed.instantiate()
	if instance == null:
		return {"error": "Failed to instantiate scene", "code": "INSTANCE_ERROR"}

	_undo.create_action("Add Scene Instance: %s" % instance.name)
	_undo.add_do_method(parent, &"add_child", [instance])
	_undo.add_do_method(instance, &"set_owner", [root])
	_undo.add_do_reference(instance)
	_undo.add_undo_method(parent, &"remove_child", [instance])
	_undo.commit_action()

	return {"node_path": str(root.get_path_to(instance)), "scene_path": scene_path}


func play_scene(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")

	if path != "":
		if not path.begins_with("res://"):
			path = "res://" + path
		_editor.play_custom_scene(path)
		return {"playing": true, "scene": path}
	else:
		_editor.play_current_scene()
		var current = _editor.get_edited_scene_root()
		var scene_path_str = current.scene_file_path if current else ""
		return {"playing": true, "scene": scene_path_str}


func stop_scene(params: Dictionary) -> Dictionary:
	if not _editor.is_playing_scene():
		return {"error": "No scene is currently playing", "code": "NOT_PLAYING"}
	_editor.stop_playing_scene()
	return {"stopped": true}


func _node_to_dict(node: Node, depth: int = 0) -> Dictionary:
	var result: Dictionary = {
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path()) if node.is_inside_tree() else str(node.name),
	}

	if node.scene_file_path != "":
		result["scene_file"] = node.scene_file_path

	# Include script info
	var script = node.get_script()
	if script:
		result["script"] = script.resource_path if script.resource_path != "" else "(inline)"

	# Children
	var children: Array = []
	for child in node.get_children():
		children.append(_node_to_dict(child, depth + 1))
	if children.size() > 0:
		result["children"] = children

	return result
