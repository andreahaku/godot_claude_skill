class_name AnalysisHandler
extends RefCounted

## Code Analysis tools (6):
## find_unused_resources, analyze_signal_flow, analyze_scene_complexity,
## find_script_references, detect_circular_dependencies, get_project_statistics

var _editor: EditorInterface


func _init(editor: EditorInterface):
	_editor = editor


func get_commands() -> Dictionary:
	return {
		"find_unused_resources": find_unused_resources,
		"analyze_signal_flow": analyze_signal_flow,
		"analyze_scene_complexity": analyze_scene_complexity,
		"find_script_references": find_script_references,
		"detect_circular_dependencies": detect_circular_dependencies,
		"get_project_statistics": get_project_statistics,
	}


func find_unused_resources(params: Dictionary) -> Dictionary:
	var resource_types: Array = params.get("types", ["tres", "res", "png", "jpg", "wav", "ogg", "mp3"])

	# Collect all resources
	var all_resources: Array = []
	_collect_files("res://", resource_types, all_resources)

	# Collect all references from scenes and scripts
	var referenced: Dictionary = {}
	var ref_files: Array = []
	_collect_files("res://", ["tscn", "scn", "gd", "cs", "tres"], ref_files)

	for f in ref_files:
		var file = FileAccess.open(f, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			file.close()
			for res_path in all_resources:
				if content.contains(res_path) or content.contains(res_path.get_file()):
					referenced[res_path] = true

	var unused: Array = []
	for res_path in all_resources:
		if not referenced.has(res_path):
			unused.append(res_path)

	return {"unused": unused, "count": unused.size(), "total_resources": all_resources.size()}


func analyze_signal_flow(params: Dictionary) -> Dictionary:
	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var flow: Array = []
	_map_signals(root, flow, root)
	return {"flow": flow, "count": flow.size()}


func analyze_scene_complexity(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")

	var root: Node
	if path != "":
		if not path.begins_with("res://"):
			path = "res://" + path
		var packed = load(path) as PackedScene
		if packed == null:
			return {"error": "Cannot load scene: %s" % path, "code": "LOAD_ERROR"}
		root = packed.instantiate()
	else:
		root = _editor.get_edited_scene_root()

	if root == null:
		return {"error": "No scene available", "code": "NO_SCENE"}

	var stats: Dictionary = {"node_count": 0, "max_depth": 0, "types": {}}
	_analyze_node(root, 0, stats)

	if path != "" and root:
		root.queue_free()

	return stats


func find_script_references(params: Dictionary) -> Dictionary:
	var script_path: String = params.get("path", "")
	if script_path == "":
		return {"error": "path is required", "code": "MISSING_PARAM"}

	var results: Array = []
	_search_references("res://", script_path, results)
	return {"path": script_path, "references": results, "count": results.size()}


func detect_circular_dependencies(params: Dictionary) -> Dictionary:
	# Build dependency graph
	var graph: Dictionary = {} # path -> [dependencies]
	var all_scripts: Array = []
	_collect_files("res://", ["gd"], all_scripts)

	for script_path in all_scripts:
		var deps: Array = []
		var file = FileAccess.open(script_path, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			file.close()
			# Find preload/load references
			var lines = content.split("\n")
			for line in lines:
				if "preload(" in line or "load(" in line:
					var start = line.find("\"")
					var end = line.rfind("\"")
					if start >= 0 and end > start:
						var ref = line.substr(start + 1, end - start - 1)
						if ref.ends_with(".gd"):
							deps.append(ref)
		graph[script_path] = deps

	# Detect cycles using DFS
	var cycles: Array = []
	var visited: Dictionary = {}
	var rec_stack: Dictionary = {}

	for node_path in graph:
		if not visited.has(node_path):
			_dfs_detect_cycle(node_path, graph, visited, rec_stack, [], cycles)

	return {"cycles": cycles, "count": cycles.size(), "scripts_analyzed": graph.size()}


func get_project_statistics(params: Dictionary) -> Dictionary:
	var stats: Dictionary = {
		"files": {"scenes": 0, "scripts": 0, "resources": 0, "images": 0, "audio": 0, "other": 0},
		"total_files": 0,
		"total_lines_of_code": 0,
		"scene_count": 0,
		"script_count": 0,
	}

	_gather_stats("res://", stats)

	stats["scene_count"] = stats.files.scenes
	stats["script_count"] = stats.files.scripts

	return stats


func _collect_files(path: String, extensions: Array, results: Array) -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.begins_with(".") or file_name == "addons":
			file_name = dir.get_next()
			continue
		var full_path = path.path_join(file_name)
		if dir.current_is_dir():
			_collect_files(full_path, extensions, results)
		else:
			var ext = file_name.get_extension().to_lower()
			if ext in extensions:
				results.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()


func _map_signals(node: Node, flow: Array, scene_root: Node) -> void:
	for sig in node.get_signal_list():
		for conn in node.get_signal_connection_list(sig.name):
			flow.append({
				"source": str(scene_root.get_path_to(node)),
				"signal": sig.name,
				"target": str(scene_root.get_path_to(conn.callable.get_object())) if conn.callable.get_object() is Node else "?",
				"method": conn.callable.get_method(),
			})
	for child in node.get_children():
		_map_signals(child, flow, scene_root)


func _analyze_node(node: Node, depth: int, stats: Dictionary) -> void:
	stats.node_count += 1
	if depth > stats.max_depth:
		stats.max_depth = depth
	var type = node.get_class()
	stats.types[type] = stats.types.get(type, 0) + 1
	for child in node.get_children():
		_analyze_node(child, depth + 1, stats)


func _search_references(path: String, target: String, results: Array) -> void:
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
			_search_references(full_path, target, results)
		else:
			var ext = file_name.get_extension().to_lower()
			if ext in ["gd", "tscn", "tres", "cs"]:
				var file = FileAccess.open(full_path, FileAccess.READ)
				if file:
					var content = file.get_as_text()
					file.close()
					if content.contains(target):
						results.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()


func _dfs_detect_cycle(node: String, graph: Dictionary, visited: Dictionary, rec_stack: Dictionary, current_path: Array, cycles: Array) -> void:
	visited[node] = true
	rec_stack[node] = true
	current_path.append(node)

	for neighbor in graph.get(node, []):
		if not visited.has(neighbor):
			_dfs_detect_cycle(neighbor, graph, visited, rec_stack, current_path, cycles)
		elif rec_stack.has(neighbor):
			var cycle_start = current_path.find(neighbor)
			if cycle_start >= 0:
				cycles.append(current_path.slice(cycle_start))

	current_path.pop_back()
	rec_stack.erase(node)


func _gather_stats(path: String, stats: Dictionary) -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.begins_with(".") or file_name == "addons":
			file_name = dir.get_next()
			continue
		var full_path = path.path_join(file_name)
		if dir.current_is_dir():
			_gather_stats(full_path, stats)
		else:
			stats.total_files += 1
			var ext = file_name.get_extension().to_lower()
			match ext:
				"tscn", "scn":
					stats.files.scenes += 1
				"gd", "cs":
					stats.files.scripts += 1
					var file = FileAccess.open(full_path, FileAccess.READ)
					if file:
						var content = file.get_as_text()
						file.close()
						stats.total_lines_of_code += content.count("\n") + 1
				"tres", "res":
					stats.files.resources += 1
				"png", "jpg", "jpeg", "webp", "svg":
					stats.files.images += 1
				"wav", "ogg", "mp3":
					stats.files.audio += 1
				_:
					stats.files.other += 1
		file_name = dir.get_next()
	dir.list_dir_end()
