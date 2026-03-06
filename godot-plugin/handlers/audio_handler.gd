@tool
class_name AudioHandler
extends RefCounted

## Audio tools (6):
## get_audio_bus_layout, add_audio_bus, set_audio_bus,
## add_audio_bus_effect, add_audio_player, get_audio_info

var _editor: EditorInterface
var _undo: UndoHelper


func _init(editor: EditorInterface, undo: UndoHelper):
	_editor = editor
	_undo = undo


func get_commands() -> Dictionary:
	return {
		"get_audio_bus_layout": get_audio_bus_layout,
		"add_audio_bus": add_audio_bus,
		"set_audio_bus": set_audio_bus,
		"add_audio_bus_effect": add_audio_bus_effect,
		"add_audio_player": add_audio_player,
		"get_audio_info": get_audio_info,
	}


func _find_node(path: String) -> Node:
	var root = _editor.get_edited_scene_root()
	if root == null:
		return null
	if path == "" or path == root.name:
		return root
	return root.get_node_or_null(path)


func get_audio_bus_layout(params: Dictionary) -> Dictionary:
	var buses: Array = []
	for i in range(AudioServer.bus_count):
		var effects: Array = []
		for e in range(AudioServer.get_bus_effect_count(i)):
			effects.append({
				"name": AudioServer.get_bus_effect(i, e).get_class(),
				"enabled": AudioServer.is_bus_effect_enabled(i, e),
			})
		buses.append({
			"index": i,
			"name": AudioServer.get_bus_name(i),
			"volume_db": AudioServer.get_bus_volume_db(i),
			"mute": AudioServer.is_bus_mute(i),
			"solo": AudioServer.is_bus_solo(i),
			"send": AudioServer.get_bus_send(i),
			"effects": effects,
		})
	return {"buses": buses, "count": buses.size()}


func add_audio_bus(params: Dictionary) -> Dictionary:
	var bus_name: String = params.get("name", "NewBus")
	var send_to: String = params.get("send_to", "Master")
	var volume_db: float = params.get("volume_db", 0.0)

	AudioServer.add_bus()
	var idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send_to)
	AudioServer.set_bus_volume_db(idx, volume_db)

	return {"name": bus_name, "index": idx, "send_to": send_to}


func set_audio_bus(params: Dictionary) -> Dictionary:
	var bus_name: String = params.get("name", "")
	var volume_db = params.get("volume_db", null)
	var mute = params.get("mute", null)
	var solo = params.get("solo", null)
	var send_to: String = params.get("send_to", "")

	if bus_name == "":
		return {"error": "name is required", "code": "MISSING_PARAM"}

	var idx = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return {"error": "Bus not found: %s" % bus_name, "code": "BUS_NOT_FOUND"}

	var changed: Dictionary = {}
	if volume_db != null:
		AudioServer.set_bus_volume_db(idx, float(volume_db))
		changed["volume_db"] = float(volume_db)
	if mute != null:
		AudioServer.set_bus_mute(idx, bool(mute))
		changed["mute"] = bool(mute)
	if solo != null:
		AudioServer.set_bus_solo(idx, bool(solo))
		changed["solo"] = bool(solo)
	if send_to != "":
		AudioServer.set_bus_send(idx, send_to)
		changed["send_to"] = send_to

	return {"name": bus_name, "changed": changed}


func add_audio_bus_effect(params: Dictionary) -> Dictionary:
	var bus_name: String = params.get("bus_name", "Master")
	var effect_type: String = params.get("effect_type", "")

	if effect_type == "":
		return {"error": "effect_type is required", "code": "MISSING_PARAM"}

	var idx = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return {"error": "Bus not found: %s" % bus_name, "code": "BUS_NOT_FOUND"}

	var effect: AudioEffect
	match effect_type.to_lower():
		"reverb":
			effect = AudioEffectReverb.new()
		"delay":
			effect = AudioEffectDelay.new()
		"compressor":
			effect = AudioEffectCompressor.new()
		"eq", "equalizer":
			effect = AudioEffectEQ10.new()
		"limiter":
			effect = AudioEffectLimiter.new()
		"amplify":
			effect = AudioEffectAmplify.new()
		"chorus":
			effect = AudioEffectChorus.new()
		"phaser":
			effect = AudioEffectPhaser.new()
		"distortion":
			effect = AudioEffectDistortion.new()
		"low_pass", "lowpass":
			effect = AudioEffectLowPassFilter.new()
		"high_pass", "highpass":
			effect = AudioEffectHighPassFilter.new()
		"band_pass", "bandpass":
			effect = AudioEffectBandPassFilter.new()
		_:
			return {"error": "Unknown effect type: %s" % effect_type, "code": "INVALID_TYPE",
				"suggestions": ["Available: reverb, delay, compressor, eq, limiter, amplify, chorus, phaser, distortion, low_pass, high_pass, band_pass"]}

	AudioServer.add_bus_effect(idx, effect)
	return {"bus": bus_name, "effect": effect.get_class(), "effect_index": AudioServer.get_bus_effect_count(idx) - 1}


func add_audio_player(params: Dictionary) -> Dictionary:
	var parent_path: String = params.get("parent_path", "")
	var node_name: String = params.get("name", "AudioPlayer")
	var audio_file: String = params.get("audio_file", "")
	var bus: String = params.get("bus", "Master")
	var is_3d: bool = params.get("is_3d", false)
	var autoplay: bool = params.get("autoplay", false)

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var parent = _find_node(parent_path) if parent_path != "" else root

	var player: Node
	if is_3d:
		var p = AudioStreamPlayer3D.new()
		p.name = node_name
		p.bus = bus
		p.autoplay = autoplay
		player = p
	else:
		var p = AudioStreamPlayer2D.new() if parent is Node2D else AudioStreamPlayer.new()
		p.name = node_name
		p.bus = bus
		p.autoplay = autoplay
		player = p

	if audio_file != "":
		if not audio_file.begins_with("res://"):
			audio_file = "res://" + audio_file
		if ResourceLoader.exists(audio_file):
			var stream = load(audio_file) as AudioStream
			if stream:
				player.stream = stream

	_undo.create_action("Add Audio Player")
	_undo.add_do_method(parent.add_child.bind(player))
	_undo.add_do_method(player.set_owner.bind(root))
	_undo.add_do_reference(player)
	_undo.add_undo_method(parent.remove_child.bind(player))
	_undo.commit_action()

	return {"node_path": str(root.get_path_to(player)), "bus": bus, "is_3d": is_3d}


func get_audio_info(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var start = _find_node(node_path) if node_path != "" else root
	var players: Array = []
	_find_audio_players(start, players)

	return {"players": players, "count": players.size()}


func _find_audio_players(node: Node, results: Array) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		var info: Dictionary = {
			"name": str(node.name),
			"type": node.get_class(),
			"path": str(node.get_path()),
			"bus": node.bus,
			"autoplay": node.autoplay,
		}
		if node.stream:
			info["stream"] = node.stream.resource_path
		results.append(info)
	for child in node.get_children():
		_find_audio_players(child, results)
