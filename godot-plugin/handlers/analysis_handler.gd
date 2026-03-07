@tool
class_name AnalysisHandler
extends RefCounted

## Code Analysis tools (7):
## find_unused_resources, analyze_signal_flow, analyze_scene_complexity,
## find_script_references, detect_circular_dependencies, get_project_statistics,
## lookup_class

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
		"lookup_class": lookup_class,
	}


func find_unused_resources(params: Dictionary) -> Dictionary:
	var resource_types: Array = params.get("types", ["tres", "res", "png", "jpg", "wav", "ogg", "mp3"])

	var max_depth: int = params.get("max_depth", 32)

	# Collect all resources
	var all_resources: Array = []
	_collect_files("res://", resource_types, all_resources, 0, max_depth)

	# Collect all references from scenes and scripts
	var referenced: Dictionary = {}
	var ref_files: Array = []
	_collect_files("res://", ["tscn", "scn", "gd", "cs", "tres"], ref_files, 0, max_depth)

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

	var max_depth: int = params.get("max_depth", 64)
	var flow: Array = []
	_map_signals(root, flow, root, 0, max_depth)
	return {"flow": flow, "count": flow.size(), "max_depth": max_depth}


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

	var max_depth: int = params.get("max_depth", 64)
	var stats: Dictionary = {"node_count": 0, "max_depth": 0, "types": {}}
	_analyze_node(root, 0, stats, max_depth)

	if path != "" and root:
		root.queue_free()

	return stats


func find_script_references(params: Dictionary) -> Dictionary:
	var script_path: String = params.get("path", "")
	if script_path == "":
		return {"error": "path is required", "code": "MISSING_PARAM"}

	var max_depth: int = params.get("max_depth", 32)
	var results: Array = []
	_search_references("res://", script_path, results, 0, max_depth)
	return {"path": script_path, "references": results, "count": results.size(), "max_depth": max_depth}


func detect_circular_dependencies(params: Dictionary) -> Dictionary:
	# Build dependency graph
	var max_depth: int = params.get("max_depth", 32)
	var graph: Dictionary = {} # path -> [dependencies]
	var all_scripts: Array = []
	_collect_files("res://", ["gd"], all_scripts, 0, max_depth)

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

	var max_depth: int = params.get("max_depth", 32)
	_gather_stats("res://", stats, 0, max_depth)

	stats["scene_count"] = stats.files.scenes
	stats["script_count"] = stats.files.scripts

	return stats


func lookup_class(params: Dictionary) -> Dictionary:
	var class_name_str: String = params.get("class_name", "")
	if class_name_str == "":
		return {"error": "class_name parameter is required", "code": "MISSING_PARAM"}

	if not ClassDB.class_exists(class_name_str):
		# Try to find similar class names
		var suggestions: Array = []
		for c in ClassDB.get_class_list():
			if c.to_lower().contains(class_name_str.to_lower()):
				suggestions.append(c)
		return {"error": "Unknown class: %s" % class_name_str, "code": "UNKNOWN_CLASS", "suggestions": suggestions.slice(0, 10)}

	var result: Dictionary = {
		"class_name": class_name_str,
		"parent_class": ClassDB.get_parent_class(class_name_str),
		"is_instantiable": ClassDB.can_instantiate(class_name_str),
	}

	# Get inheritance chain
	var chain: Array = []
	var current = class_name_str
	while current != "":
		chain.append(current)
		current = ClassDB.get_parent_class(current)
	result["inheritance"] = chain

	var include_inherited: bool = params.get("include_inherited", false)
	var property_filter: String = params.get("property", "")
	var method_filter: String = params.get("method", "")

	# Properties
	if property_filter != "":
		# Look up a specific property
		var prop_list = ClassDB.class_get_property_list(class_name_str, !include_inherited)
		for prop in prop_list:
			if prop.name == property_filter:
				result["property"] = {
					"name": prop.name,
					"type": type_string(prop.type),
					"hint": prop.hint,
					"hint_string": prop.hint_string,
					"usage": prop.usage,
				}
				break
		if not result.has("property"):
			result["property_not_found"] = property_filter
	else:
		var props: Array = []
		var prop_list = ClassDB.class_get_property_list(class_name_str, !include_inherited)
		for prop in prop_list:
			if prop.usage & PROPERTY_USAGE_EDITOR or prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				props.append({
					"name": prop.name,
					"type": type_string(prop.type),
				})
		result["properties"] = props

	# Methods
	if method_filter != "":
		var method_list = ClassDB.class_get_method_list(class_name_str, !include_inherited)
		for m in method_list:
			if m.name == method_filter:
				var args: Array = []
				for arg in m.args:
					args.append({"name": arg.name, "type": type_string(arg.type)})
				result["method"] = {
					"name": m.name,
					"return_type": type_string(m.return.type) if m.has("return") else "void",
					"args": args,
				}
				break
		if not result.has("method"):
			result["method_not_found"] = method_filter
	else:
		var methods: Array = []
		var method_list = ClassDB.class_get_method_list(class_name_str, !include_inherited)
		for m in method_list:
			if m.name.begins_with("_"):
				continue  # Skip private/virtual by default
			var args: Array = []
			for arg in m.args:
				args.append({"name": arg.name, "type": type_string(arg.type)})
			methods.append({
				"name": m.name,
				"args": args,
			})
		result["methods"] = methods

	# Signals
	var signals: Array = []
	var signal_list = ClassDB.class_get_signal_list(class_name_str, !include_inherited)
	for sig in signal_list:
		var args: Array = []
		for arg in sig.args:
			args.append({"name": arg.name, "type": type_string(arg.type)})
		signals.append({
			"name": sig.name,
			"args": args,
		})
	result["signals"] = signals

	# Enums (if any)
	var enum_list = ClassDB.class_get_enum_list(class_name_str, !include_inherited)
	if not enum_list.is_empty():
		var enums: Dictionary = {}
		for enum_name in enum_list:
			var constants = ClassDB.class_get_enum_constants(class_name_str, enum_name, !include_inherited)
			var values: Dictionary = {}
			for const_name in constants:
				values[const_name] = ClassDB.class_get_integer_constant(class_name_str, const_name)
			enums[enum_name] = values
		result["enums"] = enums

	return result


func _collect_files(path: String, extensions: Array, results: Array, depth: int = 0, max_depth: int = 32) -> void:
	if depth >= max_depth:
		return
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
			_collect_files(full_path, extensions, results, depth + 1, max_depth)
		else:
			var ext = file_name.get_extension().to_lower()
			if ext in extensions:
				results.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()


func _map_signals(node: Node, flow: Array, scene_root: Node, depth: int = 0, max_depth: int = 64) -> void:
	for sig in node.get_signal_list():
		for conn in node.get_signal_connection_list(sig.name):
			flow.append({
				"source": str(scene_root.get_path_to(node)),
				"signal": sig.name,
				"target": str(scene_root.get_path_to(conn.callable.get_object())) if conn.callable.get_object() is Node else "?",
				"method": conn.callable.get_method(),
			})
	if depth >= max_depth:
		return
	for child in node.get_children():
		_map_signals(child, flow, scene_root, depth + 1, max_depth)


func _analyze_node(node: Node, depth: int, stats: Dictionary, max_depth: int = 64) -> void:
	stats.node_count += 1
	if depth > stats.max_depth:
		stats.max_depth = depth
	var type = node.get_class()
	stats.types[type] = stats.types.get(type, 0) + 1
	if depth >= max_depth:
		if node.get_child_count() > 0:
			stats["truncated_at_depth"] = max_depth
		return
	for child in node.get_children():
		_analyze_node(child, depth + 1, stats, max_depth)


func _search_references(path: String, target: String, results: Array, depth: int = 0, max_depth: int = 32) -> void:
	if depth >= max_depth:
		return
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
			_search_references(full_path, target, results, depth + 1, max_depth)
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


func _gather_stats(path: String, stats: Dictionary, depth: int = 0, max_depth: int = 32) -> void:
	if depth >= max_depth:
		return
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
			_gather_stats(full_path, stats, depth + 1, max_depth)
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
