@tool
class_name AnimationTreeHandler
extends RefCounted

## AnimationTree tools (8):
## create_animation_tree, get_animation_tree_structure,
## add_state_machine_state, remove_state_machine_state,
## add_state_machine_transition, remove_state_machine_transition,
## set_blend_tree_node, set_tree_parameter

var _editor: EditorInterface
var _undo: UndoHelper


func _init(editor: EditorInterface, undo: UndoHelper):
	_editor = editor
	_undo = undo


func get_commands() -> Dictionary:
	return {
		"create_animation_tree": create_animation_tree,
		"get_animation_tree_structure": get_animation_tree_structure,
		"add_state_machine_state": add_state_machine_state,
		"remove_state_machine_state": remove_state_machine_state,
		"add_state_machine_transition": add_state_machine_transition,
		"remove_state_machine_transition": remove_state_machine_transition,
		"set_blend_tree_node": set_blend_tree_node,
		"set_tree_parameter": set_tree_parameter,
	}


func _find_node(path: String) -> Node:
	var root = _editor.get_edited_scene_root()
	if root == null:
		return null
	if path == "" or path == root.name:
		return root
	return root.get_node_or_null(path)


func _get_anim_tree(node_path: String) -> AnimationTree:
	var node = _find_node(node_path)
	if node is AnimationTree:
		return node
	return null


func create_animation_tree(params: Dictionary) -> Dictionary:
	var parent_path: String = params.get("parent_path", "")
	var player_path: String = params.get("player_path", "")
	var root_type: String = params.get("root_type", "state_machine")

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open", "code": "NO_SCENE"}

	var parent = _find_node(parent_path) if parent_path != "" else root
	if parent == null:
		return {"error": "Parent not found: %s" % parent_path, "code": "NODE_NOT_FOUND"}

	var tree = AnimationTree.new()
	tree.name = "AnimationTree"

	if player_path != "":
		tree.anim_player = NodePath(player_path)

	# Create root node based on type
	match root_type:
		"state_machine":
			tree.tree_root = AnimationNodeStateMachine.new()
		"blend_tree":
			tree.tree_root = AnimationNodeBlendTree.new()
		"blend_space_1d":
			tree.tree_root = AnimationNodeBlendSpace1D.new()
		"blend_space_2d":
			tree.tree_root = AnimationNodeBlendSpace2D.new()
		_:
			tree.tree_root = AnimationNodeStateMachine.new()

	_undo.create_action("Create AnimationTree")
	_undo.add_do_method(parent.add_child.bind(tree))
	_undo.add_do_method(tree.set_owner.bind(root))
	_undo.add_do_reference(tree)
	_undo.add_undo_method(parent.remove_child.bind(tree))
	_undo.commit_action()

	return {"node_path": str(root.get_path_to(tree)), "root_type": root_type}


func get_animation_tree_structure(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var tree = _get_anim_tree(node_path)
	if tree == null:
		return {"error": "AnimationTree not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var structure = _describe_node(tree.tree_root)
	return {"node_path": node_path, "active": tree.active, "structure": structure}


func add_state_machine_state(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var state_name: String = params.get("state_name", "")
	var animation_name: String = params.get("animation", "")
	var sm_path: String = params.get("state_machine_path", "")

	if node_path == "" or state_name == "":
		return {"error": "node_path and state_name are required", "code": "MISSING_PARAM"}

	var tree = _get_anim_tree(node_path)
	if tree == null:
		return {"error": "AnimationTree not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var sm = _get_state_machine(tree, sm_path)
	if sm == null:
		return {"error": "State machine not found", "code": "SM_NOT_FOUND"}

	var anim_node: AnimationNode
	if animation_name != "":
		anim_node = AnimationNodeAnimation.new()
		anim_node.animation = animation_name
	else:
		anim_node = AnimationNodeAnimation.new()

	sm.add_node(state_name, anim_node)
	return {"state_name": state_name, "animation": animation_name}


func remove_state_machine_state(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var state_name: String = params.get("state_name", "")
	var sm_path: String = params.get("state_machine_path", "")

	if node_path == "" or state_name == "":
		return {"error": "node_path and state_name are required", "code": "MISSING_PARAM"}

	var tree = _get_anim_tree(node_path)
	if tree == null:
		return {"error": "AnimationTree not found", "code": "NODE_NOT_FOUND"}

	var sm = _get_state_machine(tree, sm_path)
	if sm == null:
		return {"error": "State machine not found", "code": "SM_NOT_FOUND"}

	if not sm.has_node(state_name):
		return {"error": "State not found: %s" % state_name, "code": "STATE_NOT_FOUND"}

	sm.remove_node(state_name)
	return {"removed": state_name}


func add_state_machine_transition(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var from_state: String = params.get("from", "")
	var to_state: String = params.get("to", "")
	var sm_path: String = params.get("state_machine_path", "")
	var advance_mode: int = params.get("advance_mode", 0)
	var advance_condition: String = params.get("advance_condition", "")

	if node_path == "" or from_state == "" or to_state == "":
		return {"error": "node_path, from, and to are required", "code": "MISSING_PARAM"}

	var tree = _get_anim_tree(node_path)
	if tree == null:
		return {"error": "AnimationTree not found", "code": "NODE_NOT_FOUND"}

	var sm = _get_state_machine(tree, sm_path)
	if sm == null:
		return {"error": "State machine not found", "code": "SM_NOT_FOUND"}

	var transition = AnimationNodeStateMachineTransition.new()
	transition.advance_mode = advance_mode
	if advance_condition != "":
		transition.advance_condition = advance_condition

	sm.add_transition(from_state, to_state, transition)
	return {"from": from_state, "to": to_state, "advance_condition": advance_condition}


func remove_state_machine_transition(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var from_state: String = params.get("from", "")
	var to_state: String = params.get("to", "")
	var sm_path: String = params.get("state_machine_path", "")

	if node_path == "" or from_state == "" or to_state == "":
		return {"error": "node_path, from, and to are required", "code": "MISSING_PARAM"}

	var tree = _get_anim_tree(node_path)
	if tree == null:
		return {"error": "AnimationTree not found", "code": "NODE_NOT_FOUND"}

	var sm = _get_state_machine(tree, sm_path)
	if sm == null:
		return {"error": "State machine not found", "code": "SM_NOT_FOUND"}

	# Find and remove the transition
	for i in range(sm.get_transition_count()):
		if sm.get_transition_from(i) == from_state and sm.get_transition_to(i) == to_state:
			sm.remove_transition_by_index(i)
			return {"removed": true, "from": from_state, "to": to_state}

	return {"error": "Transition not found: %s -> %s" % [from_state, to_state], "code": "TRANSITION_NOT_FOUND"}


func set_blend_tree_node(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var blend_node_name: String = params.get("name", "")
	var blend_type: String = params.get("type", "")

	if node_path == "" or blend_node_name == "" or blend_type == "":
		return {"error": "node_path, name, and type are required", "code": "MISSING_PARAM"}

	var tree = _get_anim_tree(node_path)
	if tree == null:
		return {"error": "AnimationTree not found", "code": "NODE_NOT_FOUND"}

	if not tree.tree_root is AnimationNodeBlendTree:
		return {"error": "Root is not a BlendTree", "code": "WRONG_TYPE"}

	var bt: AnimationNodeBlendTree = tree.tree_root

	var node: AnimationNode
	match blend_type:
		"add2":
			node = AnimationNodeAdd2.new()
		"blend2":
			node = AnimationNodeBlend2.new()
		"time_scale":
			node = AnimationNodeTimeScale.new()
		"animation":
			node = AnimationNodeAnimation.new()
			var anim_name: String = params.get("animation", "")
			if anim_name != "":
				node.animation = anim_name
		"one_shot":
			node = AnimationNodeOneShot.new()
		"transition":
			node = AnimationNodeTransition.new()
		_:
			return {"error": "Unknown blend type: %s" % blend_type, "code": "INVALID_TYPE"}

	bt.add_node(blend_node_name, node)

	# Optionally connect
	var connect_to: String = params.get("connect_to", "")
	var connect_port: int = params.get("connect_port", 0)
	if connect_to != "":
		bt.connect_node(connect_to, connect_port, blend_node_name)

	return {"name": blend_node_name, "type": blend_type}


func set_tree_parameter(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var parameter: String = params.get("parameter", "")
	var value = params.get("value")

	if node_path == "" or parameter == "":
		return {"error": "node_path and parameter are required", "code": "MISSING_PARAM"}

	var tree = _get_anim_tree(node_path)
	if tree == null:
		return {"error": "AnimationTree not found", "code": "NODE_NOT_FOUND"}

	var parsed = TypeParser.parse_value(value)
	tree.set("parameters/" + parameter, parsed)

	return {"parameter": parameter, "value": TypeParser.value_to_json(parsed)}


func _get_state_machine(tree: AnimationTree, sm_path: String) -> AnimationNodeStateMachine:
	if sm_path == "" or sm_path == "/":
		if tree.tree_root is AnimationNodeStateMachine:
			return tree.tree_root
		return null
	# Navigate nested state machines
	var parts = sm_path.split("/")
	var current = tree.tree_root
	for part in parts:
		if part == "":
			continue
		if current is AnimationNodeStateMachine:
			current = current.get_node(part)
		else:
			return null
	if current is AnimationNodeStateMachine:
		return current
	return null


func _describe_node(node: AnimationNode) -> Dictionary:
	if node == null:
		return {}
	var info := {"type": node.get_class()}
	if node is AnimationNodeStateMachine:
		var states: Array = []
		# AnimationNodeStateMachine doesn't have get_node_list, iterate known nodes
		var transitions: Array = []
		for i in range(node.get_transition_count()):
			transitions.append({
				"from": node.get_transition_from(i),
				"to": node.get_transition_to(i),
			})
		info["transitions"] = transitions
	elif node is AnimationNodeBlendTree:
		info["type"] = "BlendTree"
	elif node is AnimationNodeAnimation:
		info["animation"] = node.animation
	return info
