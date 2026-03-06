@tool
extends EditorPlugin

## GodotClaudeSkill - EditorPlugin
## WebSocket server for Claude Code integration.
## Enables AI-driven control of the Godot editor with full UndoRedo support.

const WS_PORT := 9080

var _ws: GodotClaudeWS
var _router: CommandRouter
var _undo: UndoHelper

# Handlers
var _project_handler: ProjectHandler
var _scene_handler: SceneHandler
var _node_handler: NodeHandler
var _script_handler: ScriptHandler
var _editor_handler: EditorHandler
var _input_handler: InputHandler
var _runtime_handler: RuntimeHandler
var _animation_handler: AnimationHandler
var _animation_tree_handler: AnimationTreeHandler
var _tilemap_handler: TileMapHandler
var _scene_3d_handler: Scene3DHandler
var _physics_handler: PhysicsHandler
var _particles_handler: ParticlesHandler
var _navigation_handler: NavigationHandler
var _audio_handler: AudioHandler
var _theme_handler: ThemeHandler
var _shader_handler: ShaderHandler
var _resource_handler: ResourceHandler
var _batch_handler: BatchHandler
var _testing_handler: TestingHandler
var _analysis_handler: AnalysisHandler
var _profiling_handler: ProfilingHandler
var _asset_handler: AssetHandler
var _export_handler: ExportHandler


func _enter_tree() -> void:
	print("[GodotClaude] Plugin initializing...")

	# Initialize WebSocket server
	_ws = GodotClaudeWS.new(WS_PORT)
	add_child(_ws)

	# Initialize UndoRedo helper
	_undo = UndoHelper.new()
	_undo.setup(get_undo_redo())

	# Initialize router
	_router = CommandRouter.new(_ws)

	# Initialize all handlers and register commands
	var ei = get_editor_interface()

	_project_handler = ProjectHandler.new(ei)
	_router.register_all(_project_handler.get_commands())

	_scene_handler = SceneHandler.new(ei, _undo)
	_router.register_all(_scene_handler.get_commands())

	_node_handler = NodeHandler.new(ei, _undo)
	_router.register_all(_node_handler.get_commands())

	_script_handler = ScriptHandler.new(ei, _undo)
	_router.register_all(_script_handler.get_commands())

	_editor_handler = EditorHandler.new(ei, self)
	_router.register_all(_editor_handler.get_commands())

	_input_handler = InputHandler.new(ei)
	_router.register_all(_input_handler.get_commands())

	_runtime_handler = RuntimeHandler.new(ei)
	_router.register_all(_runtime_handler.get_commands())

	_animation_handler = AnimationHandler.new(ei, _undo)
	_router.register_all(_animation_handler.get_commands())

	_animation_tree_handler = AnimationTreeHandler.new(ei, _undo)
	_router.register_all(_animation_tree_handler.get_commands())

	_tilemap_handler = TileMapHandler.new(ei, _undo)
	_router.register_all(_tilemap_handler.get_commands())

	_scene_3d_handler = Scene3DHandler.new(ei, _undo)
	_router.register_all(_scene_3d_handler.get_commands())

	_physics_handler = PhysicsHandler.new(ei, _undo)
	_router.register_all(_physics_handler.get_commands())

	_particles_handler = ParticlesHandler.new(ei, _undo)
	_router.register_all(_particles_handler.get_commands())

	_navigation_handler = NavigationHandler.new(ei, _undo)
	_router.register_all(_navigation_handler.get_commands())

	_audio_handler = AudioHandler.new(ei, _undo)
	_router.register_all(_audio_handler.get_commands())

	_theme_handler = ThemeHandler.new(ei, _undo)
	_router.register_all(_theme_handler.get_commands())

	_shader_handler = ShaderHandler.new(ei)
	_router.register_all(_shader_handler.get_commands())

	_resource_handler = ResourceHandler.new(ei)
	_router.register_all(_resource_handler.get_commands())

	_batch_handler = BatchHandler.new(ei, _undo)
	_router.register_all(_batch_handler.get_commands())

	_testing_handler = TestingHandler.new(ei)
	_router.register_all(_testing_handler.get_commands())

	_analysis_handler = AnalysisHandler.new(ei)
	_router.register_all(_analysis_handler.get_commands())

	_profiling_handler = ProfilingHandler.new(ei)
	_router.register_all(_profiling_handler.get_commands())

	_asset_handler = AssetHandler.new(ei, _undo)
	_router.register_all(_asset_handler.get_commands())

	_export_handler = ExportHandler.new(ei)
	_router.register_all(_export_handler.get_commands())

	# Register meta commands
	_router.register("list_commands", _list_commands)
	_router.register("get_version", _get_version)
	_router.register("batch_execute", _router.batch_execute)

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
	if _ws:
		_ws.stop()
		remove_child(_ws)
		_ws = null
	print("[GodotClaude] Plugin disabled")


func _process(delta: float) -> void:
	if _ws:
		_ws.poll()


func _on_command(id: String, command: String, params: Dictionary) -> void:
	_router.handle(id, command, params)


func _list_commands(params: Dictionary) -> Dictionary:
	var cmds = _router.get_command_list()
	return {"commands": cmds, "count": cmds.size()}


func _get_version(params: Dictionary) -> Dictionary:
	return {
		"plugin_version": "1.0.0",
		"godot_version": "%s.%s.%s" % [Engine.get_version_info().major, Engine.get_version_info().minor, Engine.get_version_info().patch],
		"commands": _router.get_command_list().size(),
	}
