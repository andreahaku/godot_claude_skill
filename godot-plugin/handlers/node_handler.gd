@tool
class_name NodeHandler
extends RefCounted

## Node tools (11):
## add_node, delete_node, rename_node, duplicate_node, move_node,
## update_property, get_node_properties, add_resource,
## set_anchor_preset, connect_signal, disconnect_signal

var _editor: EditorInterface
var _undo: UndoHelper


func _init(editor: EditorInterface, undo: UndoHelper):
	_editor = editor
	_undo = undo


func get_commands() -> Dictionary:
	return {
		"add_node": {
			"handler": add_node,
			"description": "Add a new node to the scene tree",
			"params": {
				"node_type": {"type": "string", "required": true, "description": "Godot class name (e.g., Sprite2D, CharacterBody2D) or script path"},
				"node_name": {"type": "string", "default": "", "description": "Name for the new node (auto-generated if empty)"},
				"parent_path": {"type": "string", "default": "", "description": "Path to parent node (empty = scene root)"},
				"properties": {"type": "dict", "default": {}, "description": "Initial property values to set on the node"},
			},
			"metadata": {
				"undoable": true,
				"safe_for_batch": true,
			},
		},
		"delete_node": {
			"handler": delete_node,
			"description": "Delete a node from the scene tree",
			"params": {
				"node_path": {"type": "string", "required": true, "description": "Path to the node to delete"},
			},
			"metadata": {
				"undoable": true,
				"safe_for_batch": true,
			},
		},
		"rename_node": {
			"handler": rename_node,
			"description": "Rename a node in the scene tree",
			"params": {
				"node_path": {"type": "string", "required": true, "description": "Path to the node to rename"},
				"new_name": {"type": "string", "required": true, "description": "New name for the node"},
			},
			"metadata": {
				"undoable": true,
				"safe_for_batch": true,
			},
		},
		"duplicate_node": {
			"handler": duplicate_node,
			"description": "Duplicate a node and all its children",
			"params": {
				"node_path": {"type": "string", "required": true, "description": "Path to the node to duplicate"},
				"new_name": {"type": "string", "default": "", "description": "Name for the duplicated node (auto-generated if empty)"},
			},
			"metadata": {
				"undoable": true,
				"safe_for_batch": true,
			},
		},
		"move_node": {
			"handler": move_node,
			"description": "Move a node to a new parent in the scene tree",
			"params": {
				"node_path": {"type": "string", "required": true, "description": "Path to the node to move"},
				"new_parent_path": {"type": "string", "required": true, "description": "Path to the new parent node"},
			},
			"metadata": {
				"undoable": true,
				"safe_for_batch": true,
			},
		},
		"update_property": {
			"handler": update_property,
			"description": "Set a property value on a node",
			"params": {
				"node_path": {"type": "string", "required": true, "description": "Path to the target node"},
				"property": {"type": "string", "required": true, "description": "Property name to set"},
				"value": {"type": "any", "required": true, "description": "New value (supports Godot types like Vector2(x,y), Color(r,g,b,a))"},
			},
			"metadata": {
				"undoable": true,
				"safe_for_batch": true,
			},
		},
		"get_node_properties": {
			"handler": get_node_properties,
			"description": "Get all editor-visible properties of a node",
			"params": {
				"node_path": {"type": "string", "required": true, "description": "Path to the node"},
				"filter": {"type": "string", "default": "", "description": "Filter properties by name substring (case-insensitive)"},
			},
			"metadata": {
				"safe_for_batch": true,
			},
		},
		"add_resource": {
			"handler": add_resource,
			"description": "Create and assign a new resource to a node property",
			"params": {
				"node_path": {"type": "string", "required": true, "description": "Path to the target node"},
				"property": {"type": "string", "required": true, "description": "Property to assign the resource to"},
				"resource_type": {"type": "string", "required": true, "description": "Resource class name (e.g., RectangleShape2D, StyleBoxFlat)"},
				"resource_properties": {"type": "dict", "default": {}, "description": "Properties to set on the new resource"},
			},
			"metadata": {
				"undoable": true,
				"safe_for_batch": true,
			},
		},
		"set_anchor_preset": {
			"handler": set_anchor_preset,
			"description": "Set anchor preset on a Control node (e.g., full rect, center)",
			"params": {
				"node_path": {"type": "string", "required": true, "description": "Path to a Control node"},
				"preset": {"type": "int", "required": true, "description": "Anchor preset enum value (e.g., 15 = full rect)"},
			},
			"metadata": {
				"undoable": true,
				"safe_for_batch": true,
			},
		},
		"connect_signal": {
			"handler": connect_signal_cmd,
			"description": "Connect a signal from one node to a method on another node",
			"params": {
				"source_path": {"type": "string", "required": true, "description": "Path to the node emitting the signal"},
				"signal_name": {"type": "string", "required": true, "description": "Name of the signal to connect"},
				"target_path": {"type": "string", "required": true, "description": "Path to the node receiving the signal"},
				"method_name": {"type": "string", "required": true, "description": "Method name to call on the target node"},
			},
			"metadata": {
				"undoable": true,
				"safe_for_batch": true,
			},
		},
		"disconnect_signal": {
			"handler": disconnect_signal_cmd,
			"description": "Disconnect a signal connection between two nodes",
			"params": {
				"source_path": {"type": "string", "required": true, "description": "Path to the node emitting the signal"},
				"signal_name": {"type": "string", "required": true, "description": "Name of the signal to disconnect"},
				"target_path": {"type": "string", "required": true, "description": "Path to the node receiving the signal"},
				"method_name": {"type": "string", "required": true, "description": "Method name on the target node"},
			},
			"metadata": {
				"undoable": true,
				"safe_for_batch": true,
			},
		},
	}


func add_node(params: Dictionary) -> Dictionary:
	var parent_path: String = params.get("parent_path", "")
	var node_type: String = params.get("node_type", "Node")
	var node_name: String = params.get("node_name", "")
	var properties: Dictionary = params.get("properties", {})

	var root = NodeFinder.get_root(_editor)
	if root == null:
		return {"error": "No scene is currently open", "code": "NO_SCENE"}

	var parent = NodeFinder.find(_editor, parent_path) if parent_path != "" else root
	if parent == null:
		return {"error": "Parent node not found: %s" % parent_path, "code": "NODE_NOT_FOUND"}

	# Instantiate node
	var node: Node
	if ClassDB.class_exists(node_type):
		if not ClassDB.can_instantiate(node_type):
			return {"error": "Cannot instantiate: %s (abstract class)" % node_type, "code": "CANNOT_INSTANTIATE"}
		node = ClassDB.instantiate(node_type)
	else:
		# Try loading as custom script
		if ResourceLoader.exists(node_type):
			var script = load(node_type)
			if script is GDScript:
				node = script.new()
		if node == null:
			return {"error": "Unknown node type: %s" % node_type, "code": "INVALID_TYPE"}

	if node_name != "":
		node.name = node_name

	# Apply properties
	for key in properties:
		var value = TypeParser.parse_value(properties[key])
		if node.has_method("set"):
			node.set(key, value)

	_undo.create_action("Add Node: %s" % node.name)
	_undo.add_do_method(parent, &"add_child", [node])
	_undo.add_do_method(node, &"set_owner", [root])
	_undo.add_do_reference(node)
	_undo.add_undo_method(parent, &"remove_child", [node])
	_undo.commit_action()

	return {"node_path": str(root.get_path_to(node)), "node_type": node.get_class(), "node_name": str(node.name)}


func delete_node(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path == "":
		return {"error": "node_path parameter is required", "code": "MISSING_PARAM"}

	var root = NodeFinder.get_root(_editor)
	if root == null:
		return {"error": "No scene is currently open", "code": "NO_SCENE"}

	var node = NodeFinder.find(_editor, node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	if node == root:
		return {"error": "Cannot delete the root node", "code": "CANNOT_DELETE_ROOT"}

	var parent = node.get_parent()
	var index = node.get_index()

	_undo.create_action("Delete Node: %s" % node.name)
	_undo.add_do_method(parent, &"remove_child", [node])
	_undo.add_undo_method(parent, &"add_child", [node])
	_undo.add_undo_method(parent, &"move_child", [node, index])
	_undo.add_undo_method(node, &"set_owner", [root])
	_undo.add_undo_reference(node)
	_undo.commit_action()

	return {"deleted": str(node_path)}


func rename_node(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var new_name: String = params.get("new_name", "")
	if node_path == "" or new_name == "":
		return {"error": "node_path and new_name are required", "code": "MISSING_PARAM"}

	var node = NodeFinder.find(_editor, node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var old_name = node.name

	_undo.create_action("Rename Node: %s -> %s" % [old_name, new_name])
	_undo.add_do_property(node, &"name", new_name)
	_undo.add_undo_property(node, &"name", old_name)
	_undo.commit_action()

	return {"old_name": str(old_name), "new_name": new_name}


func duplicate_node(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var new_name: String = params.get("new_name", "")
	if node_path == "":
		return {"error": "node_path parameter is required", "code": "MISSING_PARAM"}

	var root = NodeFinder.get_root(_editor)
	if root == null:
		return {"error": "No scene is currently open", "code": "NO_SCENE"}

	var node = NodeFinder.find(_editor, node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var parent = node.get_parent()
	var dup = node.duplicate()
	if new_name != "":
		dup.name = new_name

	_undo.create_action("Duplicate Node: %s" % node.name)
	_undo.add_do_method(parent, &"add_child", [dup])
	_undo.add_do_method(dup, &"set_owner", [root])
	_undo.add_do_reference(dup)
	_undo.add_undo_method(parent, &"remove_child", [dup])
	_undo.commit_action()

	# Set owner for all children recursively
	_set_owner_recursive(dup, root)

	return {"original": str(node_path), "duplicate_path": str(root.get_path_to(dup))}


func move_node(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var new_parent_path: String = params.get("new_parent_path", "")
	if node_path == "" or new_parent_path == "":
		return {"error": "node_path and new_parent_path are required", "code": "MISSING_PARAM"}

	var root = NodeFinder.get_root(_editor)
	if root == null:
		return {"error": "No scene is currently open", "code": "NO_SCENE"}

	var node = NodeFinder.find(_editor, node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var new_parent = NodeFinder.find(_editor, new_parent_path)
	if new_parent == null:
		return {"error": "New parent not found: %s" % new_parent_path, "code": "NODE_NOT_FOUND"}

	var old_parent = node.get_parent()
	var old_index = node.get_index()

	_undo.create_action("Move Node: %s to %s" % [node.name, new_parent.name])
	_undo.add_do_method(old_parent, &"remove_child", [node])
	_undo.add_do_method(new_parent, &"add_child", [node])
	_undo.add_do_method(node, &"set_owner", [root])
	_undo.add_undo_method(new_parent, &"remove_child", [node])
	_undo.add_undo_method(old_parent, &"add_child", [node])
	_undo.add_undo_method(old_parent, &"move_child", [node, old_index])
	_undo.add_undo_method(node, &"set_owner", [root])
	_undo.commit_action()

	return {"node": str(node.name), "new_path": str(root.get_path_to(node))}


func update_property(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var property: String = params.get("property", "")
	var value = params.get("value")
	if node_path == "" or property == "":
		return {"error": "node_path and property are required", "code": "MISSING_PARAM"}

	var node = NodeFinder.find(_editor, node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	# Validate property exists (check property list for exact match)
	if not property in node:
		return {"error": "Property '%s' not found on %s (%s)" % [property, node.name, node.get_class()], "code": "NOT_FOUND",
			"suggestions": ["Use get_node_properties to see available properties"]}

	var parse_result = TypeParser.parse_value_strict(value)
	if not parse_result.parsed:
		return {"error": "Failed to parse value '%s' — check format (e.g. Vector2(x,y))" % str(value), "code": "PARSE_ERROR"}

	var parsed_value = parse_result.value
	var old_value = node.get(property)

	_undo.create_action("Set %s.%s" % [node.name, property])
	_undo.add_do_property(node, StringName(property), parsed_value)
	_undo.add_undo_property(node, StringName(property), old_value)
	_undo.commit_action()

	return {
		"node_path": node_path,
		"property": property,
		"old_value": TypeParser.value_to_json(old_value),
		"new_value": TypeParser.value_to_json(parsed_value),
	}


func get_node_properties(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var filter: String = params.get("filter", "")
	if node_path == "":
		return {"error": "node_path parameter is required", "code": "MISSING_PARAM"}

	var node = NodeFinder.find(_editor, node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var props: Dictionary = {}
	for prop in node.get_property_list():
		var name: String = prop.name
		if filter != "" and not name.to_lower().contains(filter.to_lower()):
			continue
		# Skip internal properties
		if prop.usage & PROPERTY_USAGE_EDITOR == 0 and prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		props[name] = {
			"value": TypeParser.value_to_json(node.get(name)),
			"type": type_string(prop.type),
			"hint": prop.hint,
		}

	return {
		"node_path": node_path,
		"node_type": node.get_class(),
		"properties": props,
	}


func add_resource(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var property: String = params.get("property", "")
	var resource_type: String = params.get("resource_type", "")
	var resource_properties: Dictionary = params.get("resource_properties", {})

	if node_path == "" or property == "" or resource_type == "":
		return {"error": "node_path, property, and resource_type are required", "code": "MISSING_PARAM"}

	var node = NodeFinder.find(_editor, node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	if not ClassDB.class_exists(resource_type):
		return {"error": "Unknown resource type: %s" % resource_type, "code": "INVALID_TYPE"}

	var resource = ClassDB.instantiate(resource_type)
	if resource == null:
		return {"error": "Cannot create resource: %s" % resource_type, "code": "CANNOT_INSTANTIATE"}

	for key in resource_properties:
		var val = TypeParser.parse_value(resource_properties[key])
		resource.set(key, val)

	var old_value = node.get(property)

	_undo.create_action("Add %s to %s.%s" % [resource_type, node.name, property])
	_undo.add_do_property(node, StringName(property), resource)
	_undo.add_undo_property(node, StringName(property), old_value)
	_undo.commit_action()

	return {"node_path": node_path, "property": property, "resource_type": resource_type}


func set_anchor_preset(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var preset: int = params.get("preset", -1)
	if node_path == "" or preset < 0:
		return {"error": "node_path and preset are required", "code": "MISSING_PARAM"}

	var node = NodeFinder.find(_editor, node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}
	if not node is Control:
		return {"error": "Node is not a Control: %s" % node_path, "code": "WRONG_TYPE"}

	var control: Control = node as Control

	# Store old values
	var old_anchors = [control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom]
	var old_offsets = [control.offset_left, control.offset_top, control.offset_right, control.offset_bottom]

	_undo.create_action("Set Anchor Preset: %s" % node.name)
	_undo.add_do_method(control, &"set_anchors_and_offsets_preset", [preset])
	_undo.add_undo_property(control, &"anchor_left", old_anchors[0])
	_undo.add_undo_property(control, &"anchor_top", old_anchors[1])
	_undo.add_undo_property(control, &"anchor_right", old_anchors[2])
	_undo.add_undo_property(control, &"anchor_bottom", old_anchors[3])
	_undo.add_undo_property(control, &"offset_left", old_offsets[0])
	_undo.add_undo_property(control, &"offset_top", old_offsets[1])
	_undo.add_undo_property(control, &"offset_right", old_offsets[2])
	_undo.add_undo_property(control, &"offset_bottom", old_offsets[3])
	_undo.commit_action()

	return {"node_path": node_path, "preset": preset}


func connect_signal_cmd(params: Dictionary) -> Dictionary:
	var source_path: String = params.get("source_path", "")
	var signal_name: String = params.get("signal_name", "")
	var target_path: String = params.get("target_path", "")
	var method_name: String = params.get("method_name", "")

	if source_path == "" or signal_name == "" or target_path == "" or method_name == "":
		return {"error": "source_path, signal_name, target_path, and method_name are required", "code": "MISSING_PARAM"}

	var source = NodeFinder.find(_editor, source_path)
	if source == null:
		return {"error": "Source node not found: %s" % source_path, "code": "NODE_NOT_FOUND"}

	var target = NodeFinder.find(_editor, target_path)
	if target == null:
		return {"error": "Target node not found: %s" % target_path, "code": "NODE_NOT_FOUND"}

	if not source.has_signal(signal_name):
		return {"error": "Signal not found: %s on %s" % [signal_name, source_path], "code": "SIGNAL_NOT_FOUND"}

	if source.is_connected(signal_name, Callable(target, method_name)):
		return {"error": "Signal already connected", "code": "ALREADY_CONNECTED"}

	_undo.create_action("Connect Signal: %s.%s -> %s.%s" % [source.name, signal_name, target.name, method_name])
	_undo.add_do_method(source, &"connect", [signal_name, Callable(target, method_name)])
	_undo.add_undo_method(source, &"disconnect", [signal_name, Callable(target, method_name)])
	_undo.commit_action()

	return {"source": source_path, "signal": signal_name, "target": target_path, "method": method_name}


func disconnect_signal_cmd(params: Dictionary) -> Dictionary:
	var source_path: String = params.get("source_path", "")
	var signal_name: String = params.get("signal_name", "")
	var target_path: String = params.get("target_path", "")
	var method_name: String = params.get("method_name", "")

	if source_path == "" or signal_name == "" or target_path == "" or method_name == "":
		return {"error": "source_path, signal_name, target_path, and method_name are required", "code": "MISSING_PARAM"}

	var source = NodeFinder.find(_editor, source_path)
	if source == null:
		return {"error": "Source node not found: %s" % source_path, "code": "NODE_NOT_FOUND"}

	var target = NodeFinder.find(_editor, target_path)
	if target == null:
		return {"error": "Target node not found: %s" % target_path, "code": "NODE_NOT_FOUND"}

	if not source.is_connected(signal_name, Callable(target, method_name)):
		return {"error": "Signal not connected", "code": "NOT_CONNECTED"}

	_undo.create_action("Disconnect Signal: %s.%s -> %s.%s" % [source.name, signal_name, target.name, method_name])
	_undo.add_do_method(source, &"disconnect", [signal_name, Callable(target, method_name)])
	_undo.add_undo_method(source, &"connect", [signal_name, Callable(target, method_name)])
	_undo.commit_action()

	return {"disconnected": true, "source": source_path, "signal": signal_name, "target": target_path, "method": method_name}


func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.set_owner(owner)
		_set_owner_recursive(child, owner)
