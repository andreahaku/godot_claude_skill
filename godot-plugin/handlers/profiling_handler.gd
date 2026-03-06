class_name ProfilingHandler
extends RefCounted

## Profiling tools (2):
## get_performance_monitors, get_editor_performance

var _editor: EditorInterface


func _init(editor: EditorInterface):
	_editor = editor


func get_commands() -> Dictionary:
	return {
		"get_performance_monitors": get_performance_monitors,
		"get_editor_performance": get_editor_performance,
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
