@tool
class_name ProfilingHandler
extends RefCounted

## Profiling tools (4):
## get_performance_monitors, get_editor_performance, snapshot_performance, get_performance_history

var _editor: EditorInterface
var _history: Array = []
const MAX_HISTORY := 100


func _init(editor: EditorInterface):
	_editor = editor


func get_commands() -> Dictionary:
	return {
		"get_performance_monitors": get_performance_monitors,
		"get_editor_performance": get_editor_performance,
		"snapshot_performance": snapshot_performance,
		"get_performance_history": get_performance_history,
	}


func get_performance_monitors(params: Dictionary) -> Dictionary:
	return {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"process_time": Performance.get_monitor(Performance.TIME_PROCESS),
		"physics_time": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS),
		"navigation_time": Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS),
		"render_objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"render_primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"render_draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"memory_static": Performance.get_monitor(Performance.MEMORY_STATIC),
		"memory_static_max": Performance.get_monitor(Performance.MEMORY_STATIC_MAX),
		"memory_message_buffer": Performance.get_monitor(Performance.MEMORY_MESSAGE_BUFFER_MAX),
		"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
		"object_resource_count": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"object_node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"object_orphan_node_count": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"physics_2d_active_objects": Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
		"physics_2d_collision_pairs": Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS),
		"physics_2d_island_count": Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT),
		"physics_3d_active_objects": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"physics_3d_collision_pairs": Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		"physics_3d_island_count": Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT),
	}


func get_editor_performance(params: Dictionary) -> Dictionary:
	return {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
	}


func snapshot_performance(params: Dictionary) -> Dictionary:
	var label: String = params.get("label", "")
	var snapshot = {
		"timestamp": Time.get_unix_time_from_system(),
		"label": label,
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"process_time": Performance.get_monitor(Performance.TIME_PROCESS),
		"physics_time": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS),
		"memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
	}
	_history.append(snapshot)
	if _history.size() > MAX_HISTORY:
		_history.pop_front()

	var result := {"snapshot": snapshot, "history_size": _history.size()}

	# Compare with previous snapshot if available
	if _history.size() >= 2:
		var prev = _history[_history.size() - 2]
		result["delta"] = {
			"fps": snapshot.fps - prev.fps,
			"process_time": snapshot.process_time - prev.process_time,
			"memory_mb": snapshot.memory_mb - prev.memory_mb,
			"objects": snapshot.objects - prev.objects,
			"nodes": snapshot.nodes - prev.nodes,
		}

	return result


func get_performance_history(params: Dictionary) -> Dictionary:
	var last_n: int = params.get("last", 0)
	var entries = _history if last_n <= 0 else _history.slice(-last_n)

	if entries.is_empty():
		return {"history": [], "count": 0, "message": "No snapshots recorded. Use snapshot_performance to record."}

	# Compute trend from first to last entry
	var first = entries[0]
	var last_entry = entries[entries.size() - 1]
	var trend := {
		"fps": last_entry.fps - first.fps,
		"process_time": last_entry.process_time - first.process_time,
		"memory_mb": last_entry.memory_mb - first.memory_mb,
		"objects": last_entry.objects - first.objects,
		"nodes": last_entry.nodes - first.nodes,
		"time_span_seconds": last_entry.timestamp - first.timestamp,
	}

	return {"history": entries, "count": entries.size(), "trend": trend}
