class_name PhysicsHandler
extends RefCounted

## Physics tools (6):
## setup_collision, set_physics_layers, get_physics_layers,
## add_raycast, setup_physics_body, get_collision_info

var _editor: EditorInterface
var _undo: UndoHelper


func _init(editor: EditorInterface, undo: UndoHelper):
	_editor = editor
	_undo = undo


func get_commands() -> Dictionary:
	return {
		"setup_collision": setup_collision,
		"set_physics_layers": set_physics_layers,
		"get_physics_layers": get_physics_layers,
		"add_raycast": add_raycast,
		"setup_physics_body": setup_physics_body,
		"get_collision_info": get_collision_info,
	}


func _find_node(path: String) -> Node:
	var root = _editor.get_edited_scene_root()
	if root == null:
		return null
	if path == "" or path == root.name:
		return root
	return root.get_node_or_null(path)


func setup_collision(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var shape_type: String = params.get("shape_type", "auto")
	var shape_params: Dictionary = params.get("shape_params", {})

	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var node = _find_node(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	# Detect 2D vs 3D
	var is_3d = node is Node3D or node is CollisionObject3D
	var is_2d = node is Node2D or node is CollisionObject2D

	if not is_3d and not is_2d:
		return {"error": "Node must be a 2D or 3D physics node", "code": "WRONG_TYPE"}

	var collision_shape: Node
	var shape: Resource

	if is_3d:
		collision_shape = CollisionShape3D.new()
		match shape_type.to_lower():
			"box":
				shape = BoxShape3D.new()
				if shape_params.has("size"):
					shape.size = TypeParser.parse_value(shape_params.size)
			"sphere":
				shape = SphereShape3D.new()
				if shape_params.has("radius"):
					shape.radius = float(shape_params.radius)
			"capsule":
				shape = CapsuleShape3D.new()
				if shape_params.has("radius"):
					shape.radius = float(shape_params.radius)
				if shape_params.has("height"):
					shape.height = float(shape_params.height)
			"cylinder":
				shape = CylinderShape3D.new()
			_:
				shape = BoxShape3D.new()
		collision_shape.shape = shape
	else:
		collision_shape = CollisionShape2D.new()
		match shape_type.to_lower():
			"rectangle", "box":
				shape = RectangleShape2D.new()
				if shape_params.has("size"):
					shape.size = TypeParser.parse_value(shape_params.size)
			"circle", "sphere":
				shape = CircleShape2D.new()
				if shape_params.has("radius"):
					shape.radius = float(shape_params.radius)
			"capsule":
				shape = CapsuleShape2D.new()
				if shape_params.has("radius"):
					shape.radius = float(shape_params.radius)
				if shape_params.has("height"):
					shape.height = float(shape_params.height)
			_:
				shape = RectangleShape2D.new()
		collision_shape.shape = shape

	collision_shape.name = "CollisionShape"

	_undo.create_action("Setup Collision: %s" % node.name)
	_undo.add_do_method(node.add_child.bind(collision_shape))
	_undo.add_do_method(collision_shape.set_owner.bind(root))
	_undo.add_do_reference(collision_shape)
	_undo.add_undo_method(node.remove_child.bind(collision_shape))
	_undo.commit_action()

	return {"node_path": str(root.get_path_to(collision_shape)), "shape_type": shape_type, "is_3d": is_3d}


func set_physics_layers(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var collision_layer: int = params.get("collision_layer", -1)
	var collision_mask: int = params.get("collision_mask", -1)

	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var node = _find_node(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var changed: Dictionary = {}
	if collision_layer >= 0 and "collision_layer" in node:
		_undo.create_action("Set Physics Layers")
		_undo.add_do_property(node, &"collision_layer", collision_layer)
		_undo.add_undo_property(node, &"collision_layer", node.collision_layer)
		if collision_mask >= 0:
			_undo.add_do_property(node, &"collision_mask", collision_mask)
			_undo.add_undo_property(node, &"collision_mask", node.collision_mask)
		_undo.commit_action()
		changed["collision_layer"] = collision_layer
		if collision_mask >= 0:
			changed["collision_mask"] = collision_mask
	else:
		return {"error": "Node does not have collision_layer property", "code": "WRONG_TYPE"}

	return {"node_path": node_path, "changed": changed}


func get_physics_layers(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var node = _find_node(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	if not "collision_layer" in node:
		return {"error": "Node does not have collision layers", "code": "WRONG_TYPE"}

	return {
		"node_path": node_path,
		"collision_layer": node.collision_layer,
		"collision_mask": node.collision_mask,
		"layer_bits": _int_to_layer_array(node.collision_layer),
		"mask_bits": _int_to_layer_array(node.collision_mask),
	}


func add_raycast(params: Dictionary) -> Dictionary:
	var parent_path: String = params.get("parent_path", "")
	var target: String = params.get("target", "Vector3(0, -1, 0)")
	var node_name: String = params.get("name", "RayCast")
	var enabled: bool = params.get("enabled", true)

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var parent = _find_node(parent_path) if parent_path != "" else root
	if parent == null:
		return {"error": "Parent not found", "code": "NODE_NOT_FOUND"}

	var is_3d = parent is Node3D
	var raycast: Node

	if is_3d:
		var rc = RayCast3D.new()
		rc.name = node_name
		rc.target_position = TypeParser.parse_value(target)
		rc.enabled = enabled
		raycast = rc
	else:
		var rc = RayCast2D.new()
		rc.name = node_name
		var t = TypeParser.parse_value(target)
		if t is Vector3:
			rc.target_position = Vector2(t.x, t.y)
		elif t is Vector2:
			rc.target_position = t
		rc.enabled = enabled
		raycast = rc

	_undo.create_action("Add RayCast")
	_undo.add_do_method(parent.add_child.bind(raycast))
	_undo.add_do_method(raycast.set_owner.bind(root))
	_undo.add_do_reference(raycast)
	_undo.add_undo_method(parent.remove_child.bind(raycast))
	_undo.commit_action()

	return {"node_path": str(root.get_path_to(raycast)), "is_3d": is_3d}


func setup_physics_body(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var properties: Dictionary = params.get("properties", {})

	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var node = _find_node(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var changed: Dictionary = {}
	_undo.create_action("Setup Physics Body")
	for key in properties:
		if key in node:
			var old_val = node.get(key)
			var new_val = TypeParser.parse_value(properties[key])
			_undo.add_do_property(node, StringName(key), new_val)
			_undo.add_undo_property(node, StringName(key), old_val)
			changed[key] = TypeParser.value_to_json(new_val)
	_undo.commit_action()

	return {"node_path": node_path, "changed": changed}


func get_collision_info(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var node = _find_node(node_path) if node_path != "" else root

	var audit: Array = []
	_audit_collision(node, audit)
	return {"audit": audit, "count": audit.size()}


func _audit_collision(node: Node, results: Array) -> void:
	var info: Dictionary = {"name": str(node.name), "type": node.get_class()}
	var has_collision = false

	if "collision_layer" in node:
		info["collision_layer"] = node.collision_layer
		info["collision_mask"] = node.collision_mask
		has_collision = true

	if node is CollisionShape2D or node is CollisionShape3D:
		info["shape"] = node.shape.get_class() if node.shape else "none"
		has_collision = true

	if has_collision:
		results.append(info)

	for child in node.get_children():
		_audit_collision(child, results)


func _int_to_layer_array(value: int) -> Array:
	var layers: Array = []
	for i in range(32):
		if value & (1 << i):
			layers.append(i + 1)
	return layers
