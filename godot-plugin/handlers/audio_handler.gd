@tool
class_name AudioHandler
extends RefCounted

## Audio tools (12):
## get_audio_bus_layout, add_audio_bus, remove_audio_bus, set_audio_bus,
## add_audio_bus_effect, add_audio_player, get_audio_info,
## import_audio_asset, get_audio_asset_info, attach_audio_stream,
## create_audio_bus_if_missing, create_audio_randomizer

var _editor: EditorInterface
var _undo: UndoHelper
var _scan_helper: ScanHelper


func _init(editor: EditorInterface, undo: UndoHelper):
	_editor = editor
	_undo = undo
	_scan_helper = ScanHelper.new(editor)


func get_commands() -> Dictionary:
	return {
		"get_audio_bus_layout": get_audio_bus_layout,
		"add_audio_bus": add_audio_bus,
		"remove_audio_bus": remove_audio_bus,
		"set_audio_bus": set_audio_bus,
		"add_audio_bus_effect": add_audio_bus_effect,
		"add_audio_player": add_audio_player,
		"get_audio_info": get_audio_info,
		"import_audio_asset": import_audio_asset,
		"get_audio_asset_info": get_audio_asset_info,
		"attach_audio_stream": attach_audio_stream,
		"create_audio_bus_if_missing": create_audio_bus_if_missing,
		"create_audio_randomizer": create_audio_randomizer,
	}


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


func remove_audio_bus(params: Dictionary) -> Dictionary:
	var bus_name: String = params.get("name", "")
	if bus_name == "":
		return {"error": "name is required", "code": "MISSING_PARAM"}
	if bus_name == "Master":
		return {"error": "Cannot remove Master bus", "code": "INVALID_TYPE"}

	var idx = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return {"error": "Bus not found: %s" % bus_name, "code": "BUS_NOT_FOUND"}

	AudioServer.remove_bus(idx)
	return {"removed": bus_name}


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

	var parent = NodeFinder.find(_editor, parent_path) if parent_path != "" else root

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
	_undo.add_do_method(parent, &"add_child", [player])
	_undo.add_do_method(player, &"set_owner", [root])
	_undo.add_do_reference(player)
	_undo.add_undo_method(parent, &"remove_child", [player])
	_undo.commit_action()

	return {"node_path": str(root.get_path_to(player)), "bus": bus, "is_3d": is_3d}


func get_audio_info(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var start = NodeFinder.find(_editor, node_path) if node_path != "" else root
	var max_depth: int = params.get("max_depth", 64)
	var players: Array = []
	_find_audio_players(start, players, 0, max_depth)

	return {"players": players, "count": players.size(), "max_depth": max_depth}


func _find_audio_players(node: Node, results: Array, depth: int = 0, max_depth: int = 64) -> void:
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
	if depth >= max_depth:
		return
	for child in node.get_children():
		_find_audio_players(child, results, depth + 1, max_depth)


# ─── New asset management commands ───────────────────────────────────────────


func import_audio_asset(params: Dictionary) -> Dictionary:
	var audio_path: String = params.get("audio_path", "")
	if audio_path == "":
		return {"error": "audio_path is required", "code": "MISSING_PARAM"}
	if not audio_path.begins_with("res://"):
		audio_path = "res://" + audio_path

	# Trigger filesystem rescan so Godot imports the file
	_scan_helper.force_scan()

	# Check if the resource exists after scan
	if not ResourceLoader.exists(audio_path):
		return {"error": "Audio file not found after import: %s" % audio_path, "code": "IMPORT_ERROR"}

	var stream = load(audio_path)
	var info: Dictionary = {
		"audio_path": audio_path,
		"imported": true,
		"resource_type": stream.get_class() if stream else "unknown",
	}
	return info


func get_audio_asset_info(params: Dictionary) -> Dictionary:
	var audio_path: String = params.get("audio_path", "")
	if audio_path == "":
		return {"error": "audio_path is required", "code": "MISSING_PARAM"}
	if not audio_path.begins_with("res://"):
		audio_path = "res://" + audio_path

	if not ResourceLoader.exists(audio_path):
		return {"error": "Audio file not found: %s" % audio_path, "code": "FILE_NOT_FOUND"}

	var stream = load(audio_path)
	if not stream is AudioStream:
		return {"error": "Not an audio stream: %s" % audio_path, "code": "INVALID_TYPE"}

	var info: Dictionary = {
		"audio_path": audio_path,
		"resource_type": stream.get_class(),
	}

	# Duration (available on most stream types)
	if stream.has_method("get_length"):
		info["duration"] = stream.get_length()

	# Loop flag — check via meta or specific stream types
	if stream is AudioStreamWAV:
		info["loop_mode"] = (stream as AudioStreamWAV).loop_mode
		info["mix_rate"] = (stream as AudioStreamWAV).mix_rate
		info["stereo"] = (stream as AudioStreamWAV).stereo
		info["format"] = (stream as AudioStreamWAV).format
	elif stream is AudioStreamMP3:
		info["loop"] = (stream as AudioStreamMP3).loop
	elif stream is AudioStreamOggVorbis:
		info["loop"] = (stream as AudioStreamOggVorbis).loop

	# File size from ProjectSettings
	var global_path: String = ProjectSettings.globalize_path(audio_path)
	if FileAccess.file_exists(global_path):
		var f = FileAccess.open(global_path, FileAccess.READ)
		if f:
			info["file_size_bytes"] = f.get_length()
			f.close()

	# Check for manifest sidecar
	var manifest_path := audio_path.get_basename() + ".audio.json"
	var manifest_global := ProjectSettings.globalize_path(manifest_path)
	info["has_manifest"] = FileAccess.file_exists(manifest_global)
	if info["has_manifest"]:
		info["manifest_path"] = manifest_path

	return info


func attach_audio_stream(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var audio_path: String = params.get("audio_path", "")
	var bus: String = params.get("bus", "")
	var autoplay = params.get("autoplay", null)

	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}
	if audio_path == "":
		return {"error": "audio_path is required", "code": "MISSING_PARAM"}
	if not audio_path.begins_with("res://"):
		audio_path = "res://" + audio_path

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var node = NodeFinder.find(_editor, node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var is_audio_player := (node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D)
	if not is_audio_player:
		return {"error": "Node is not an audio player: %s (%s)" % [node_path, node.get_class()], "code": "WRONG_NODE_TYPE",
			"suggestions": ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D"]}

	if not ResourceLoader.exists(audio_path):
		return {"error": "Audio file not found: %s" % audio_path, "code": "FILE_NOT_FOUND"}

	var stream = load(audio_path) as AudioStream
	if stream == null:
		return {"error": "Failed to load audio stream: %s" % audio_path, "code": "IMPORT_ERROR"}

	_undo.create_action("Attach Audio Stream")

	var old_stream = node.stream
	_undo.add_do_property(node, &"stream", stream)
	_undo.add_undo_property(node, &"stream", old_stream)

	if bus != "":
		var old_bus: String = node.bus
		_undo.add_do_property(node, &"bus", bus)
		_undo.add_undo_property(node, &"bus", old_bus)

	if autoplay != null:
		var old_autoplay: bool = node.autoplay
		_undo.add_do_property(node, &"autoplay", bool(autoplay))
		_undo.add_undo_property(node, &"autoplay", old_autoplay)

	_undo.commit_action()

	var result: Dictionary = {
		"node_path": str(root.get_path_to(node)),
		"audio_path": audio_path,
		"node_type": node.get_class(),
	}
	if bus != "":
		result["bus"] = bus
	if autoplay != null:
		result["autoplay"] = bool(autoplay)
	return result


func create_audio_bus_if_missing(params: Dictionary) -> Dictionary:
	var bus_name: String = params.get("name", "")
	if bus_name == "":
		return {"error": "name is required", "code": "MISSING_PARAM"}

	var send_to: String = params.get("send_to", "Master")
	var volume_db: float = params.get("volume_db", 0.0)

	# Check if bus already exists
	var idx = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return {"name": bus_name, "index": idx, "already_exists": true}

	# Create it
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send_to)
	AudioServer.set_bus_volume_db(idx, volume_db)

	return {"name": bus_name, "index": idx, "created": true, "send_to": send_to}


func create_audio_randomizer(params: Dictionary) -> Dictionary:
	var parent_path: String = params.get("parent_path", "")
	var node_name: String = params.get("name", "AudioRandomizer")
	var audio_paths: Array = params.get("audio_paths", [])
	var bus: String = params.get("bus", "Master")
	var autoplay: bool = params.get("autoplay", false)
	var is_3d: bool = params.get("is_3d", false)

	if audio_paths.is_empty():
		return {"error": "audio_paths array is required (at least 1 path)", "code": "MISSING_PARAM"}

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var parent = NodeFinder.find(_editor, parent_path) if parent_path != "" else root

	# Create AudioStreamRandomizer resource
	var randomizer := AudioStreamRandomizer.new()

	var loaded_count := 0
	var failed: Array = []
	for path in audio_paths:
		var p: String = str(path)
		if not p.begins_with("res://"):
			p = "res://" + p
		if ResourceLoader.exists(p):
			var stream = load(p) as AudioStream
			if stream:
				randomizer.add_stream(-1, stream)
				loaded_count += 1
			else:
				failed.append(p)
		else:
			failed.append(p)

	if loaded_count == 0:
		return {"error": "No valid audio streams found in audio_paths", "code": "IMPORT_ERROR", "failed_paths": failed}

	# Create audio player node
	var player: Node
	if is_3d:
		var pl3d = AudioStreamPlayer3D.new()
		pl3d.name = node_name
		pl3d.bus = bus
		pl3d.autoplay = autoplay
		pl3d.stream = randomizer
		player = pl3d
	elif parent is Node2D:
		var pl2d = AudioStreamPlayer2D.new()
		pl2d.name = node_name
		pl2d.bus = bus
		pl2d.autoplay = autoplay
		pl2d.stream = randomizer
		player = pl2d
	else:
		var pl = AudioStreamPlayer.new()
		pl.name = node_name
		pl.bus = bus
		pl.autoplay = autoplay
		pl.stream = randomizer
		player = pl

	_undo.create_action("Create Audio Randomizer")
	_undo.add_do_method(parent, &"add_child", [player])
	_undo.add_do_method(player, &"set_owner", [root])
	_undo.add_do_reference(player)
	_undo.add_undo_method(parent, &"remove_child", [player])
	_undo.commit_action()

	var result: Dictionary = {
		"node_path": str(root.get_path_to(player)),
		"node_type": player.get_class(),
		"bus": bus,
		"stream_count": loaded_count,
	}
	if not failed.is_empty():
		result["failed_paths"] = failed
	return result
