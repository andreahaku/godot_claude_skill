@tool
extends EditorPlugin

## GodotClaudeSkill - EditorPlugin
## WebSocket server for Claude Code integration.
## Enables AI-driven control of the Godot editor with full UndoRedo support.

const WS_PORT := 9080
const PLUGIN_VERSION := "1.1.0"

var _ws: GodotClaudeWS
var _router: CommandRouter
var _undo: UndoHelper
var _bridge_server: BridgeServer
var _event_bus: EventBus
var _game_was_running: bool = false

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

	# Initialize event bus for push notifications
	_event_bus = EventBus.new()
	_event_bus.name = "EventBus"
	add_child(_event_bus)

	# Connect event bus to WebSocket for push delivery
	_event_bus.event_emitted.connect(_on_event)
	_ws.peer_disconnected.connect(_event_bus.remove_peer)

	# Connect editor signals for automatic event emission
	var ei_signals = get_editor_interface()
	ei_signals.get_resource_filesystem().filesystem_changed.connect(func(): _event_bus.emit_event("filesystem_changed", {}))
	# Scene change detection
	get_tree().node_added.connect(func(node: Node):
		if _event_bus.get_subscribers_for_event("node_added").size() > 0:
			var root = ei_signals.get_edited_scene_root()
			if root and node.is_inside_tree() and root.is_ancestor_of(node):
				_event_bus.emit_event("node_added", {"name": str(node.name), "type": node.get_class()})
	)
	get_tree().node_removed.connect(func(node: Node):
		if _event_bus.get_subscribers_for_event("node_removed").size() > 0:
			_event_bus.emit_event("node_removed", {"name": str(node.name), "type": node.get_class()})
	)

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
		[TemplateHandler, [ei, _undo]],
		[DebugHandler, [ei, self]],
	]

	for config in handler_configs:
		var handler = _create_handler(config[0], config[1])
		if handler:
			_handlers.append(handler)
			var commands := handler.get_commands()
			_router.register_all(commands, handler)
			# Mark commands from undo-using handlers as undoable (merge with existing metadata)
			if _undo in config[1]:
				for cmd in commands:
					var meta := _router.get_command_metadata(cmd)
					if not meta.has("undoable"):
						meta["undoable"] = true
					if not meta.has("safe_for_batch"):
						meta["safe_for_batch"] = true
					_router.register_metadata(cmd, meta)

	# Register meta commands
	_router.register("list_commands", _list_commands)
	_router.register("get_command_info", _get_command_info)
	_router.register("describe_command", _describe_command)
	_router.register("describe_category", _describe_category)
	_router.register("search_commands", _search_commands)
	_router.register("get_version", _get_version)
	_router.register("health_check", _health_check)
	_router.register("doctor", _doctor)
	_router.register("batch_execute", _router.batch_execute)
	# Register subscription commands (intercepted in _on_command before router, but
	# registered here so they appear in list_commands / search_commands)
	_router.register("subscribe", func(p): return {})
	_router.register("unsubscribe", func(p): return {})
	_router.register("get_subscriptions", func(p): return {})

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
	if _event_bus:
		remove_child(_event_bus)
		_event_bus = null
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
	# Detect game start/stop
	if _event_bus:
		var ei = get_editor_interface()
		var game_running := ei.is_playing_scene()
		if game_running and not _game_was_running:
			_event_bus.emit_event("game_started", {"scene": ei.get_playing_scene()})
		elif not game_running and _game_was_running:
			_event_bus.emit_event("game_stopped", {})
		_game_was_running = game_running


func _on_command(id: String, command: String, params: Dictionary) -> void:
	# Handle subscription commands before router (need raw peer_id)
	var peer_id: int = params.get("_peer_id", -1)
	if command == "subscribe":
		var events: Array = params.get("events", [])
		if events.is_empty():
			_ws.send_response(peer_id, id, false, null, "events array is required", "MISSING_PARAM")
			return
		var result = _event_bus.subscribe(peer_id, events)
		_ws.send_response(peer_id, id, true, result)
		return
	elif command == "unsubscribe":
		var result = _event_bus.unsubscribe(peer_id)
		_ws.send_response(peer_id, id, true, result)
		return
	elif command == "get_subscriptions":
		var result = {"events": _event_bus.get_subscriptions(peer_id)}
		_ws.send_response(peer_id, id, true, result)
		return
	_router.handle(id, command, params)


func _on_event(event_type: String, data: Dictionary) -> void:
	var subscribers := _event_bus.get_subscribers_for_event(event_type)
	for peer_id in subscribers:
		_ws.send_event(peer_id, event_type, data)


func _list_commands(params: Dictionary) -> Dictionary:
	var include_schemas: bool = params.get("include_schemas", false)
	var cmds = _router.get_command_list()
	var categories = _router.get_command_categories()

	# Group commands by handler category
	var grouped: Dictionary = {}
	for cmd in cmds:
		var cat: String = categories.get(cmd, "meta")
		if not grouped.has(cat):
			grouped[cat] = []
		if include_schemas:
			var schema = _router.get_command_schema(cmd)
			var info: Dictionary = {"command": cmd}
			if schema.has("description") and schema.description != "":
				info["description"] = schema["description"]
			grouped[cat].append(info)
		else:
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
	var schema = _router.get_command_schema(command)
	var info: Dictionary = {"command": command, "category": categories.get(command, "meta"), "exists": true}
	if not schema.is_empty():
		if schema.get("description", "") != "":
			info["description"] = schema["description"]
		if not schema.get("params", {}).is_empty():
			info["params"] = schema["params"]
	if not metadata.is_empty():
		info["metadata"] = metadata
	return info


func _describe_command(params: Dictionary) -> Dictionary:
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
	var schema = _router.get_command_schema(command)
	var metadata = _router.get_command_metadata(command)

	var result: Dictionary = {
		"command": command,
		"category": categories.get(command, "meta"),
	}
	if not schema.is_empty():
		if schema.get("description", "") != "":
			result["description"] = schema["description"]
		if not schema.get("params", {}).is_empty():
			result["params"] = schema["params"]
	if not metadata.is_empty():
		result["metadata"] = metadata

	return result


func _describe_category(params: Dictionary) -> Dictionary:
	var category: String = params.get("category", "")
	var categories = _router.get_command_categories()

	if category == "":
		# Return all categories with command counts
		var summary: Dictionary = {}
		for cmd in categories:
			var cat: String = categories[cmd]
			if not summary.has(cat):
				summary[cat] = []
			summary[cat].append(cmd)
		return {"categories": summary}

	# Return details for a specific category
	var commands_in_cat: Array = []
	for cmd in categories:
		if categories[cmd] == category:
			var schema = _router.get_command_schema(cmd)
			var metadata = _router.get_command_metadata(cmd)
			var info: Dictionary = {"command": cmd}
			if not schema.is_empty() and schema.get("description", "") != "":
				info["description"] = schema["description"]
			if not metadata.is_empty():
				info["metadata"] = metadata
			commands_in_cat.append(info)

	if commands_in_cat.is_empty():
		# Fuzzy match category name
		var all_cats: Array = []
		for cmd in categories:
			var cat: String = categories[cmd]
			if cat not in all_cats:
				all_cats.append(cat)
		var suggestions: Array = []
		for cat in all_cats:
			if cat.to_lower().contains(category.to_lower()) or category.to_lower().contains(cat.to_lower()):
				suggestions.append(cat)
		return {"error": "Unknown category: %s" % category, "code": "UNKNOWN_CATEGORY", "suggestions": suggestions.slice(0, 5)}

	return {"category": category, "commands": commands_in_cat, "count": commands_in_cat.size()}


func _search_commands(params: Dictionary) -> Dictionary:
	var query: String = params.get("query", "")
	if query == "":
		return {"error": "query parameter is required", "code": "MISSING_PARAM"}

	var query_lower := query.to_lower()
	var matches: Array = []
	var categories = _router.get_command_categories()

	for cmd in _router.get_command_list():
		var score: int = 0
		# Match in command name
		if cmd.contains(query_lower):
			score += 10
		# Match in category
		var cat: String = categories.get(cmd, "")
		if cat.to_lower().contains(query_lower):
			score += 5
		# Match in description
		var schema = _router.get_command_schema(cmd)
		var desc: String = schema.get("description", "").to_lower()
		if desc.contains(query_lower):
			score += 3
		# Match in param names
		var param_schemas: Dictionary = schema.get("params", {})
		for p in param_schemas:
			if p.contains(query_lower):
				score += 1

		if score > 0:
			var info: Dictionary = {"command": cmd, "category": cat, "score": score}
			if schema.get("description", "") != "":
				info["description"] = schema["description"]
			matches.append(info)

	# Sort by score descending
	matches.sort_custom(func(a, b): return a.score > b.score)

	return {"query": query, "matches": matches.slice(0, 20), "total_matches": matches.size()}


func _get_version(params: Dictionary) -> Dictionary:
	return {
		"plugin_version": PLUGIN_VERSION,
		"godot_version": "%s.%s.%s" % [Engine.get_version_info().major, Engine.get_version_info().minor, Engine.get_version_info().patch],
		"commands": _router.get_command_list().size(),
	}


func _health_check(params: Dictionary) -> Dictionary:
	var ei = get_editor_interface()
	var scene_root = ei.get_edited_scene_root()
	return {
		"plugin_version": PLUGIN_VERSION,
		"godot_version": Engine.get_version_info(),
		"ws_status": "running" if _ws else "stopped",
		"scene_loaded": scene_root != null,
		"scene_path": scene_root.scene_file_path if scene_root else "",
		"handler_count": _handlers.size(),
		"command_count": _router.get_command_list().size(),
		"game_running": ei.is_playing_scene(),
		"bridge_connected": _bridge_server.is_bridge_connected() if _bridge_server else false,
		"undo_available": true,
	}


func _doctor(params: Dictionary) -> Dictionary:
	var checks: Array = []
	var ei = get_editor_interface()
	var scene_root = ei.get_edited_scene_root()

	checks.append({"name": "plugin_enabled", "status": "ok", "message": "Plugin is running"})

	if _ws:
		checks.append({"name": "websocket", "status": "ok", "message": "WebSocket server is active"})
	else:
		checks.append({"name": "websocket", "status": "error", "message": "WebSocket server is not running"})

	if _bridge_server:
		checks.append({"name": "bridge_server", "status": "ok", "message": "Bridge server is active"})
	else:
		checks.append({"name": "bridge_server", "status": "error", "message": "Bridge server is not available"})

	if scene_root:
		checks.append({"name": "scene_loaded", "status": "ok", "message": "Scene loaded: %s" % scene_root.scene_file_path})
	else:
		checks.append({"name": "scene_loaded", "status": "warning", "message": "No scene is currently loaded"})

	checks.append({"name": "handlers", "status": "ok", "message": "%d handlers registered" % _handlers.size()})

	var cmd_count = _router.get_command_list().size()
	checks.append({"name": "commands", "status": "ok", "message": "%d commands available" % cmd_count})

	return {"checks": checks}


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
		"list_commands", "get_command_info", "describe_command", "describe_category",
		"search_commands", "get_version", "health_check", "doctor", "batch_execute",
		"list_scripts", "read_script", "get_open_scripts",
		"get_scene_tree", "get_scene_file_content",
		"get_node_properties",
		"list_animations", "get_animation_info",
		"find_nodes_by_type", "find_signal_connections",
		"find_node_references", "get_scene_dependencies",
		"list_export_presets", "get_export_info",
		"get_bridge_status",
		"import_audio_asset", "get_audio_asset_info",
		"subscribe", "unsubscribe", "get_subscriptions",
		"get_output_log", "get_runtime_errors",
		"get_modified_files", "get_scene_diff",
		"validate_spritesheet", "get_image_info",
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
		3:
			return handler_class.new(args[0], args[1], args[2])
		_:
			push_error("[GodotClaude] Unsupported handler constructor arity: %d" % args.size())
			return null
