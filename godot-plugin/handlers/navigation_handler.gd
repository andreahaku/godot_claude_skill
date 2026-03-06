class_name NavigationHandler
extends RefCounted

## Navigation tools (5):
## setup_navigation_region, bake_navigation_mesh,
## setup_navigation_agent, set_navigation_layers, get_navigation_info

var _editor: EditorInterface
var _undo: UndoHelper


func _init(editor: EditorInterface, undo: UndoHelper):
	_editor = editor
	_undo = undo


func get_commands() -> Dictionary:
	return {
		"setup_navigation_region": setup_navigation_region,
		"bake_navigation_mesh": bake_navigation_mesh,
		"setup_navigation_agent": setup_navigation_agent,
		"set_navigation_layers": set_navigation_layers,
		"get_navigation_info": get_navigation_info,
	}


func _find_node(path: String) -> Node:
	var root = _editor.get_edited_scene_root()
	if root == null:
		return null
	if path == "" or path == root.name:
		return root
	return root.get_node_or_null(path)


func setup_navigation_region(params: Dictionary) -> Dictionary:
	var parent_path: String = params.get("parent_path", "")
	var node_name: String = params.get("name", "NavigationRegion")

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var parent = _find_node(parent_path) if parent_path != "" else root
	var is_3d = parent is Node3D

	var region: Node
	if is_3d:
		var r = NavigationRegion3D.new()
		r.name = node_name
		r.navigation_mesh = NavigationMesh.new()
		region = r
	else:
		var r = NavigationRegion2D.new()
		r.name = node_name
		r.navigation_polygon = NavigationPolygon.new()
		region = r

	_undo.create_action("Add Navigation Region")
	_undo.add_do_method(parent.add_child.bind(region))
	_undo.add_do_method(region.set_owner.bind(root))
	_undo.add_do_reference(region)
	_undo.add_undo_method(parent.remove_child.bind(region))
	_undo.commit_action()

	return {"node_path": str(root.get_path_to(region)), "is_3d": is_3d}


func bake_navigation_mesh(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var node = _find_node(node_path)
	if node == null:
		return {"error": "Node not found", "code": "NODE_NOT_FOUND"}

	if node is NavigationRegion3D:
		node.bake_navigation_mesh()
		return {"baked": true, "type": "3D"}
	elif node is NavigationRegion2D:
		node.bake_navigation_polygon()
		return {"baked": true, "type": "2D"}

	return {"error": "Node is not a NavigationRegion", "code": "WRONG_TYPE"}


func setup_navigation_agent(params: Dictionary) -> Dictionary:
	var parent_path: String = params.get("parent_path", "")
	var node_name: String = params.get("name", "NavigationAgent")
	var path_desired_distance: float = params.get("path_desired_distance", 4.0)
	var target_desired_distance: float = params.get("target_desired_distance", 4.0)
	var avoidance_enabled: bool = params.get("avoidance_enabled", false)

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var parent = _find_node(parent_path) if parent_path != "" else root
	var is_3d = parent is Node3D

	var agent: Node
	if is_3d:
		var a = NavigationAgent3D.new()
		a.name = node_name
		a.path_desired_distance = path_desired_distance
		a.target_desired_distance = target_desired_distance
		a.avoidance_enabled = avoidance_enabled
		agent = a
	else:
		var a = NavigationAgent2D.new()
		a.name = node_name
		a.path_desired_distance = path_desired_distance
		a.target_desired_distance = target_desired_distance
		a.avoidance_enabled = avoidance_enabled
		agent = a

	_undo.create_action("Add Navigation Agent")
	_undo.add_do_method(parent.add_child.bind(agent))
	_undo.add_do_method(agent.set_owner.bind(root))
	_undo.add_do_reference(agent)
	_undo.add_undo_method(parent.remove_child.bind(agent))
	_undo.commit_action()

	return {"node_path": str(root.get_path_to(agent)), "is_3d": is_3d}


func set_navigation_layers(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var navigation_layers: int = params.get("navigation_layers", 1)

	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var node = _find_node(node_path)
	if node == null:
		return {"error": "Node not found", "code": "NODE_NOT_FOUND"}

	if "navigation_layers" in node:
		_undo.create_action("Set Navigation Layers")
		_undo.add_do_property(node, &"navigation_layers", navigation_layers)
		_undo.add_undo_property(node, &"navigation_layers", node.navigation_layers)
		_undo.commit_action()
		return {"node_path": node_path, "navigation_layers": navigation_layers}

	return {"error": "Node does not have navigation_layers", "code": "WRONG_TYPE"}


func get_navigation_info(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var start_node = _find_node(node_path) if node_path != "" else root
	var audit: Array = []
	_audit_navigation(start_node, audit)
	return {"audit": audit, "count": audit.size()}


func _audit_navigation(node: Node, results: Array) -> void:
	var info: Dictionary = {}
	if node is NavigationRegion3D:
		info = {"name": str(node.name), "type": "NavigationRegion3D", "navigation_layers": node.navigation_layers}
		if node.navigation_mesh:
			info["has_mesh"] = true
	elif node is NavigationRegion2D:
		info = {"name": str(node.name), "type": "NavigationRegion2D", "navigation_layers": node.navigation_layers}
		if node.navigation_polygon:
			info["has_polygon"] = true
	elif node is NavigationAgent3D:
		info = {"name": str(node.name), "type": "NavigationAgent3D", "avoidance": node.avoidance_enabled}
	elif node is NavigationAgent2D:
		info = {"name": str(node.name), "type": "NavigationAgent2D", "avoidance": node.avoidance_enabled}

	if not info.is_empty():
		results.append(info)

	for child in node.get_children():
		_audit_navigation(child, results)
