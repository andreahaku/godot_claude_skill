@tool
extends EditorPlugin

## GodotClaudeSkill - EditorPlugin
## WebSocket server for Claude Code integration.
## Enables AI-driven control of the Godot editor with full UndoRedo support.

const WS_PORT := 9080

var _ws: GodotClaudeWS
var _router: CommandRouter
var _undo: UndoHelper
var _bridge_server: BridgeServer

var _handlers: Array = []


func _enter_tree() -> void:
	print("[GodotClaude] Plugin initializing...")

	# Initialize WebSocket server
	_ws = GodotClaudeWS.new(WS_PORT)
	add_child(_ws)

	# Initialize UndoRedo helper
	_undo = UndoHelper.new()
	_undo.setup(get_undo_redo())

	# Initialize bridge server for runtime game communication
	_bridge_server = BridgeServer.new()
	_bridge_server.name = "BridgeServer"
	add_child(_bridge_server)
	var bridge_err = _bridge_server.start()
	if bridge_err != OK:
		push_warning("[GodotClaude] Bridge server failed to start (runtime bridge will be unavailable)")

	# Initialize router (with undo support for atomic batch mode)
	_router = CommandRouter.new(_ws, _undo)

	# Initialize all handlers and register commands
	var ei = get_editor_interface()
	var handler_configs: Array = [
		# [ClassName, args...]  — "ei" = EditorInterface, "undo" = UndoHelper, "plugin" = self
		[ProjectHandler, [ei]],
		[SceneHandler, [ei, _undo]],
		[NodeHandler, [ei, _undo]],
		[ScriptHandler, [ei, _undo]],
		[EditorHandler, [ei, self]],
		[InputHandler, [ei]],
		[RuntimeHandler, [ei, _bridge_server]],
		[AnimationHandler, [ei, _undo]],
		[AnimationTreeHandler, [ei, _undo]],
		[TileMapHandler, [ei, _undo]],
		[Scene3DHandler, [ei, _undo]],
		[PhysicsHandler, [ei, _undo]],
		[ParticlesHandler, [ei, _undo]],
		[NavigationHandler, [ei, _undo]],
		[AudioHandler, [ei, _undo]],
		[ThemeHandler, [ei, _undo]],
		[ShaderHandler, [ei, _undo]],
		[ResourceHandler, [ei]],
		[BatchHandler, [ei, _undo]],
		[TestingHandler, [ei, _bridge_server]],
		[AnalysisHandler, [ei]],
		[ProfilingHandler, [ei]],
		[AssetHandler, [ei, _undo]],
		[ExportHandler, [ei]],
	]

	for config in handler_configs:
		var handler = _create_handler(config[0], config[1])
		if handler:
			_handlers.append(handler)
			var commands := handler.get_commands()
			_router.register_all(commands, handler)
			# Mark commands from undo-using handlers as undoable
			if _undo in config[1]:
				for cmd in commands:
					_router.register_metadata(cmd, {"undoable": true, "safe_for_batch": true})

	# Register meta commands
	_router.register("list_commands", _list_commands)
	_router.register("get_command_info", _get_command_info)
	_router.register("get_version", _get_version)
	_router.register("batch_execute", _router.batch_execute)

	# Register command metadata (undoable, persistent, runtime_only, etc.)
	_register_command_metadata()

	# Connect WebSocket signal
	_ws.command_received.connect(_on_command)

	# Start server
	var err = _ws.start()
	if err == OK:
		var cmd_count = _router.get_command_list().size()
		print("[GodotClaude] Ready! %d commands available on ws://127.0.0.1:%d" % [cmd_count, WS_PORT])
	else:
		push_error("[GodotClaude] Failed to start WebSocket server")


func _exit_tree() -> void:
	if _bridge_server:
		_bridge_server.stop()
		remove_child(_bridge_server)
		_bridge_server = null
	if _ws:
		_ws.stop()
		remove_child(_ws)
		_ws = null
	print("[GodotClaude] Plugin disabled")


func _process(delta: float) -> void:
	if _ws:
		_ws.poll()
	if _bridge_server:
		_bridge_server.poll()


func _on_command(id: String, command: String, params: Dictionary) -> void:
	_router.handle(id, command, params)


func _list_commands(params: Dictionary) -> Dictionary:
	var cmds = _router.get_command_list()
	var categories = _router.get_command_categories()

	# Group commands by handler category
	var grouped: Dictionary = {}
	for cmd in cmds:
		var cat: String = categories.get(cmd, "meta")
		if not grouped.has(cat):
			grouped[cat] = []
		grouped[cat].append(cmd)

	return {"commands": cmds, "count": cmds.size(), "categories": grouped}


func _get_command_info(params: Dictionary) -> Dictionary:
	var command: String = params.get("command", "")
	if command == "":
		return {"error": "command parameter is required", "code": "MISSING_PARAM"}

	var cmds = _router.get_command_list()
	if command not in cmds:
		# Fuzzy match — find similar command names
		var suggestions: Array = []
		for cmd in cmds:
			if cmd.contains(command) or command.contains(cmd):
				suggestions.append(cmd)
		return {"error": "Unknown command: %s" % command, "code": "UNKNOWN_COMMAND", "suggestions": suggestions.slice(0, 5)}

	var categories = _router.get_command_categories()
	var metadata = _router.get_command_metadata(command)
	var info: Dictionary = {"command": command, "category": categories.get(command, "meta"), "exists": true}
	if not metadata.is_empty():
		info["metadata"] = metadata
	return info


func _get_version(params: Dictionary) -> Dictionary:
	return {
		"plugin_version": "1.0.0",
		"godot_version": "%s.%s.%s" % [Engine.get_version_info().major, Engine.get_version_info().minor, Engine.get_version_info().patch],
		"commands": _router.get_command_list().size(),
	}


func _register_command_metadata() -> void:
	# Runtime-only commands (require game to be running)
	var runtime_commands: Array[String] = [
		"get_game_scene_tree", "get_game_node_properties", "set_game_node_properties",
		"execute_game_script", "capture_frames", "monitor_properties",
		"find_ui_elements", "click_button_by_text", "wait_for_node",
		"start_recording", "stop_recording", "replay_recording",
		"run_test_scenario", "run_stress_test",
	]
	for cmd in runtime_commands:
		var meta := _router.get_command_metadata(cmd)
		meta["runtime_only"] = true
		meta["safe_for_batch"] = true
		_router.register_metadata(cmd, meta)

	# Persistent commands that write to disk (not undoable via UndoRedo)
	var persistent_commands: Array[String] = [
		"create_script", "edit_script",
		"create_scene", "save_scene", "delete_scene",
		"cross_scene_set_property",
	]
	for cmd in persistent_commands:
		var meta := _router.get_command_metadata(cmd)
		meta["persistent"] = true
		meta["undoable"] = false
		meta["safe_for_batch"] = true
		_router.register_metadata(cmd, meta)

	# Export commands: persistent and destructive
	var export_commands: Array[String] = [
		"export_project",
	]
	for cmd in export_commands:
		var meta := _router.get_command_metadata(cmd)
		meta["persistent"] = true
		meta["destructive"] = true
		meta["undoable"] = false
		meta["safe_for_batch"] = true
		_router.register_metadata(cmd, meta)

	# Meta/read-only commands: safe, not undoable (nothing to undo)
	var readonly_commands: Array[String] = [
		"list_commands", "get_command_info", "get_version", "batch_execute",
		"list_scripts", "read_script", "get_open_scripts",
		"get_scene_tree", "get_scene_file_content",
		"get_node_properties",
		"list_animations", "get_animation_info",
		"find_nodes_by_type", "find_signal_connections",
		"find_node_references", "get_scene_dependencies",
		"list_export_presets", "get_export_info",
		"get_bridge_status",
	]
	for cmd in readonly_commands:
		var meta := _router.get_command_metadata(cmd)
		if not meta.has("safe_for_batch"):
			meta["safe_for_batch"] = true
		_router.register_metadata(cmd, meta)


func _create_handler(handler_class, args: Array):
	match args.size():
		1:
			return handler_class.new(args[0])
		2:
			return handler_class.new(args[0], args[1])
		_:
			push_error("[GodotClaude] Unsupported handler constructor arity: %d" % args.size())
			return null
