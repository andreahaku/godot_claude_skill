class_name AnimationHandler
extends RefCounted

## Animation tools (6):
## list_animations, create_animation, add_animation_track,
## set_animation_keyframe, get_animation_info, remove_animation

var _editor: EditorInterface
var _undo: UndoHelper


func _init(editor: EditorInterface, undo: UndoHelper):
	_editor = editor
	_undo = undo


func get_commands() -> Dictionary:
	return {
		"list_animations": list_animations,
		"create_animation": create_animation,
		"add_animation_track": add_animation_track,
		"set_animation_keyframe": set_animation_keyframe,
		"get_animation_info": get_animation_info,
		"remove_animation": remove_animation,
	}


func _find_node(path: String) -> Node:
	var root = _editor.get_edited_scene_root()
	if root == null:
		return null
	if path == "" or path == root.name:
		return root
	return root.get_node_or_null(path)


func _get_animation_player(node_path: String) -> AnimationPlayer:
	var node = _find_node(node_path)
	if node is AnimationPlayer:
		return node
	return null


func list_animations(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path == "":
		return {"error": "node_path to AnimationPlayer is required", "code": "MISSING_PARAM"}

	var player = _get_animation_player(node_path)
	if player == null:
		return {"error": "AnimationPlayer not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var anims: Array = []
	for anim_name in player.get_animation_list():
		var anim = player.get_animation(anim_name)
		anims.append({
			"name": anim_name,
			"length": anim.length,
			"loop_mode": anim.loop_mode,
			"track_count": anim.get_track_count(),
		})

	return {"animations": anims, "count": anims.size()}


func create_animation(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var anim_name: String = params.get("name", "")
	var length: float = params.get("length", 1.0)
	var loop: bool = params.get("loop", false)

	if node_path == "" or anim_name == "":
		return {"error": "node_path and name are required", "code": "MISSING_PARAM"}

	var player = _get_animation_player(node_path)
	if player == null:
		return {"error": "AnimationPlayer not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var anim = Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE

	var lib = player.get_animation_library("")
	if lib == null:
		lib = AnimationLibrary.new()
		player.add_animation_library("", lib)

	_undo.create_action("Create Animation: %s" % anim_name)
	_undo.add_do_method(lib.add_animation.bind(anim_name, anim))
	_undo.add_undo_method(lib.remove_animation.bind(anim_name))
	_undo.commit_action()

	return {"name": anim_name, "length": length, "loop": loop}


func add_animation_track(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var anim_name: String = params.get("animation", "")
	var track_type: String = params.get("track_type", "value")
	var target_path: String = params.get("target_path", "")
	var property: String = params.get("property", "")

	if node_path == "" or anim_name == "" or target_path == "":
		return {"error": "node_path, animation, and target_path are required", "code": "MISSING_PARAM"}

	var player = _get_animation_player(node_path)
	if player == null:
		return {"error": "AnimationPlayer not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var anim = player.get_animation(anim_name)
	if anim == null:
		return {"error": "Animation not found: %s" % anim_name, "code": "ANIM_NOT_FOUND"}

	var type_map := {
		"value": Animation.TYPE_VALUE,
		"position_2d": Animation.TYPE_POSITION_2D,
		"rotation_2d": Animation.TYPE_ROTATION_2D,
		"scale_2d": Animation.TYPE_SCALE_2D,
		"position_3d": Animation.TYPE_POSITION_3D,
		"rotation_3d": Animation.TYPE_ROTATION_3D,
		"scale_3d": Animation.TYPE_SCALE_3D,
		"bezier": Animation.TYPE_BEZIER,
		"method": Animation.TYPE_METHOD,
	}

	var anim_type = type_map.get(track_type, Animation.TYPE_VALUE)
	var track_path = target_path
	if property != "":
		track_path += ":" + property

	var track_idx = anim.add_track(anim_type)
	anim.track_set_path(track_idx, NodePath(track_path))

	return {"track_index": track_idx, "track_type": track_type, "path": track_path}


func set_animation_keyframe(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var anim_name: String = params.get("animation", "")
	var track_index: int = params.get("track_index", 0)
	var time: float = params.get("time", 0.0)
	var value = params.get("value")

	if node_path == "" or anim_name == "":
		return {"error": "node_path and animation are required", "code": "MISSING_PARAM"}

	var player = _get_animation_player(node_path)
	if player == null:
		return {"error": "AnimationPlayer not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var anim = player.get_animation(anim_name)
	if anim == null:
		return {"error": "Animation not found: %s" % anim_name, "code": "ANIM_NOT_FOUND"}

	if track_index < 0 or track_index >= anim.get_track_count():
		return {"error": "Track index out of range: %d" % track_index, "code": "INVALID_TRACK"}

	var parsed_value = TypeParser.parse_value(value)
	var key_idx = anim.track_insert_key(track_index, time, parsed_value)

	return {"track_index": track_index, "key_index": key_idx, "time": time, "value": TypeParser.value_to_json(parsed_value)}


func get_animation_info(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var anim_name: String = params.get("animation", "")

	if node_path == "" or anim_name == "":
		return {"error": "node_path and animation are required", "code": "MISSING_PARAM"}

	var player = _get_animation_player(node_path)
	if player == null:
		return {"error": "AnimationPlayer not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var anim = player.get_animation(anim_name)
	if anim == null:
		return {"error": "Animation not found: %s" % anim_name, "code": "ANIM_NOT_FOUND"}

	var tracks: Array = []
	for i in range(anim.get_track_count()):
		var track_info: Dictionary = {
			"index": i,
			"path": str(anim.track_get_path(i)),
			"type": anim.track_get_type(i),
			"key_count": anim.track_get_key_count(i),
		}
		var keys: Array = []
		for k in range(anim.track_get_key_count(i)):
			keys.append({
				"time": anim.track_get_key_time(i, k),
				"value": TypeParser.value_to_json(anim.track_get_key_value(i, k)),
			})
		track_info["keys"] = keys
		tracks.append(track_info)

	return {
		"name": anim_name,
		"length": anim.length,
		"loop_mode": anim.loop_mode,
		"tracks": tracks,
	}


func remove_animation(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var anim_name: String = params.get("animation", "")

	if node_path == "" or anim_name == "":
		return {"error": "node_path and animation are required", "code": "MISSING_PARAM"}

	var player = _get_animation_player(node_path)
	if player == null:
		return {"error": "AnimationPlayer not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	if not player.has_animation(anim_name):
		return {"error": "Animation not found: %s" % anim_name, "code": "ANIM_NOT_FOUND"}

	var lib = player.get_animation_library("")
	if lib:
		_undo.create_action("Remove Animation: %s" % anim_name)
		var anim = player.get_animation(anim_name)
		_undo.add_do_method(lib.remove_animation.bind(anim_name))
		_undo.add_undo_method(lib.add_animation.bind(anim_name, anim))
		_undo.commit_action()

	return {"removed": anim_name}
