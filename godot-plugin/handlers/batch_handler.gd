@tool
class_name BatchHandler
extends RefCounted

## Batch & Refactoring tools (6):
## find_nodes_by_type, find_signal_connections, batch_set_property,
## find_node_references, get_scene_dependencies, cross_scene_set_property

var _editor: EditorInterface
var _undo: UndoHelper


func _init(editor: EditorInterface, undo: UndoHelper):
	_editor = editor
	_undo = undo


func get_commands() -> Dictionary:
	return {
		"find_nodes_by_type": find_nodes_by_type,
		"find_signal_connections": find_signal_connections,
		"batch_set_property": batch_set_property,
		"find_node_references": find_node_references,
		"get_scene_dependencies": get_scene_dependencies,
		"cross_scene_set_property": cross_scene_set_property,
	}


func find_nodes_by_type(params: Dictionary) -> Dictionary:
	var type_name: String = params.get("type", "")
	var search_path: String = params.get("search_path", "")

	if type_name == "":
		return {"error": "type is required", "code": "MISSING_PARAM"}

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var start = NodeFinder.find(_editor, search_path) if search_path != "" else root
	var found: Array = []
	_find_by_type(start, type_name, found, root)
	return {"nodes": found, "count": found.size()}


func find_signal_connections(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var start = NodeFinder.find(_editor, node_path) if node_path != "" else root
	var connections: Array = []
	_audit_signals(start, connections, root)
	return {"connections": connections, "count": connections.size()}


func batch_set_property(params: Dictionary) -> Dictionary:
	var node_paths: Array = params.get("node_paths", [])
	var property: String = params.get("property", "")
	var value = params.get("value")

	if node_paths.is_empty() or property == "":
		return {"error": "node_paths and property are required", "code": "MISSING_PARAM"}

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var parsed = TypeParser.parse_value(value)
	var changed: Array = []
	var errors: Array = []

	_undo.create_action("Batch Set Property: %s" % property)
	for np in node_paths:
		var node = root.get_node_or_null(np)
		if node == null:
			errors.append({"path": np, "error": "not found"})
			continue
		if not property in node:
			errors.append({"path": np, "error": "property not found"})
			continue
		var old_val = node.get(property)
		_undo.add_do_property(node, StringName(property), parsed)
		_undo.add_undo_property(node, StringName(property), old_val)
		changed.append(np)
	_undo.commit_action()

	return {"changed": changed, "errors": errors, "count": changed.size()}


func find_node_references(params: Dictionary) -> Dictionary:
	var search_text: String = params.get("search", "")
	var file_types: Array = params.get("file_types", ["gd", "tscn", "tres"])
	var max_results: int = params.get("max_results", 100)

	if search_text == "":
		return {"error": "search is required", "code": "MISSING_PARAM"}

	var results: Array = []
	_search_in_files("res://", search_text, file_types, results, max_results)
	return {"results": results, "count": results.size()}


func get_scene_dependencies(params: Dictionary) -> Dictionary:
	var scene_path: String = params.get("path", "")
	if scene_path == "":
		var root = _editor.get_edited_scene_root()
		if root:
			scene_path = root.scene_file_path

	if scene_path == "":
		return {"error": "path is required or a scene must be open", "code": "MISSING_PARAM"}
	if not scene_path.begins_with("res://"):
		scene_path = "res://" + scene_path

	var deps = ResourceLoader.get_dependencies(scene_path)
	var dep_list: Array = []
	for dep in deps:
		dep_list.append(str(dep))

	return {"path": scene_path, "dependencies": dep_list, "count": dep_list.size()}


func cross_scene_set_property(params: Dictionary) -> Dictionary:
	var scene_paths: Array = params.get("scene_paths", [])
	var node_type: String = params.get("node_type", "")
	var property: String = params.get("property", "")
	var value = params.get("value")

	if scene_paths.is_empty() or property == "":
		return {"error": "scene_paths and property are required", "code": "MISSING_PARAM"}

	var parsed = TypeParser.parse_value(value)
	var results: Array = []

	for sp in scene_paths:
		if not sp.begins_with("res://"):
			sp = "res://" + sp

		if not ResourceLoader.exists(sp):
			results.append({"scene": sp, "error": "not found"})
			continue

		# Load scene, modify, save
		var packed = load(sp) as PackedScene
		if packed == null:
			results.append({"scene": sp, "error": "cannot load"})
			continue

		var instance = packed.instantiate()
		var modified: Array = [0]
		_set_property_recursive(instance, node_type, property, parsed, modified)

		# Re-pack and save
		var new_packed = PackedScene.new()
		new_packed.pack(instance)
		ResourceSaver.save(new_packed, sp)
		instance.queue_free()

		results.append({"scene": sp, "modified": modified[0]})

	_editor.get_resource_filesystem().scan()
	return {"results": results}


func _find_by_type(node: Node, type_name: String, results: Array, scene_root: Node) -> void:
	if node.is_class(type_name) or node.get_class() == type_name:
		results.append({
			"name": str(node.name),
			"type": node.get_class(),
			"path": str(scene_root.get_path_to(node)),
		})
	for child in node.get_children():
		_find_by_type(child, type_name, results, scene_root)


func _audit_signals(node: Node, results: Array, scene_root: Node) -> void:
	for sig in node.get_signal_list():
		var conns = node.get_signal_connection_list(sig.name)
		for conn in conns:
			results.append({
				"source": str(scene_root.get_path_to(node)),
				"signal": sig.name,
				"target": str(scene_root.get_path_to(conn.callable.get_object())) if conn.callable.get_object() is Node else str(conn.callable.get_object()),
				"method": conn.callable.get_method(),
			})
	for child in node.get_children():
		_audit_signals(child, results, scene_root)


func _search_in_files(path: String, search: String, file_types: Array, results: Array, max_results: int) -> void:
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
			_search_in_files(full_path, search, file_types, results, max_results)
		else:
			var ext = file_name.get_extension().to_lower()
			if ext in file_types:
				var file = FileAccess.open(full_path, FileAccess.READ)
				if file:
					var content = file.get_as_text()
					file.close()
					if content.contains(search):
						var lines = content.split("\n")
						var matching_lines: Array = []
						for i in range(lines.size()):
							if lines[i].contains(search):
								matching_lines.append({"line": i + 1, "text": lines[i].strip_edges()})
						results.append({"path": full_path, "matches": matching_lines})
		file_name = dir.get_next()
	dir.list_dir_end()


func _set_property_recursive(node: Node, type_filter: String, property: String, value: Variant, modified: Array) -> void:
	if type_filter == "" or node.is_class(type_filter):
		if property in node:
			node.set(property, value)
			modified[0] += 1
	for child in node.get_children():
		_set_property_recursive(child, type_filter, property, value, modified)
