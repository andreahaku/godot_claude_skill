@tool
class_name TemplateHandler
extends RefCounted

## Template tools (3):
## create_from_template, scaffold_script, list_templates
##
## Provides scene templates (prefab recipes) and GDScript scaffolding.
## Scene templates create pre-built node hierarchies with undo support.
## Script templates generate and attach GDScript files from configurable patterns.

var _editor: EditorInterface
var _undo: UndoHelper

var _scene_templates: Dictionary
var _script_templates: Dictionary


func _init(editor: EditorInterface, undo: UndoHelper):
	_editor = editor
	_undo = undo
	_scene_templates = {
		"platformer_player": _template_platformer_player,
		"top_down_player": _template_top_down_player,
		"enemy_basic": _template_enemy_basic,
		"ui_hud": _template_ui_hud,
		"ui_menu": _template_ui_menu,
		"rigid_body_2d": _template_rigid_body_2d,
		"area_trigger": _template_area_trigger,
		"audio_manager": _template_audio_manager,
		"camera_follow": _template_camera_follow,
		"parallax_bg": _template_parallax_bg,
		"character_3d": _template_character_3d,
		"lighting_3d": _template_lighting_3d,
	}
	_script_templates = {
		"platformer_movement": _script_platformer_movement,
		"top_down_movement": _script_top_down_movement,
		"state_machine": _script_state_machine,
		"health_system": _script_health_system,
		"inventory": _script_inventory,
		"dialogue_trigger": _script_dialogue_trigger,
		"enemy_patrol": _script_enemy_patrol,
		"camera_shake": _script_camera_shake,
		"save_load": _script_save_load,
		"audio_manager": _script_audio_manager,
	}


func get_commands() -> Dictionary:
	return {
		"create_from_template": {
			"handler": create_from_template,
			"description": "Create a pre-built node hierarchy from a template",
			"params": {
				"template": {"type": "string", "required": true, "description": "Template name (e.g., platformer_player, enemy_basic, ui_hud)"},
				"parent_path": {"type": "string", "default": "", "description": "Path to parent node (empty = scene root)"},
				"name": {"type": "string", "default": "", "description": "Custom name for the root node of the template"},
			},
			"metadata": {
				"undoable": true,
				"safe_for_batch": true,
			},
		},
		"scaffold_script": {
			"handler": scaffold_script,
			"description": "Generate and attach a GDScript from a template",
			"params": {
				"node_path": {"type": "string", "required": true, "description": "Path to the node to attach the script to"},
				"template": {"type": "string", "required": true, "description": "Script template name (e.g., platformer_movement, state_machine)"},
				"params": {"type": "dict", "default": {}, "description": "Template variables (e.g., speed, jump_force, max_health)"},
				"path": {"type": "string", "default": "", "description": "Override save path for the script file"},
			},
			"metadata": {
				"persistent": true,
				"undoable": false,
				"safe_for_batch": true,
			},
		},
		"list_templates": {
			"handler": list_templates,
			"description": "List available scene and script templates",
			"params": {},
			"metadata": {
				"safe_for_batch": true,
			},
		},
	}


# ── Commands ──────────────────────────────────────────────────────────────────


func create_from_template(params: Dictionary) -> Dictionary:
	var template_name: String = params.get("template", "")
	var parent_path: String = params.get("parent_path", "")
	var custom_name: String = params.get("name", "")

	if template_name == "":
		return {"error": "template parameter is required", "code": "MISSING_PARAM"}

	if not _scene_templates.has(template_name):
		return {"error": "Unknown scene template: %s" % template_name, "code": "INVALID_TEMPLATE",
			"available": _scene_templates.keys()}

	var root = NodeFinder.get_root(_editor)
	if root == null:
		return {"error": "No scene is currently open", "code": "NO_SCENE"}

	var parent = NodeFinder.find(_editor, parent_path) if parent_path != "" else root
	if parent == null:
		return {"error": "Parent node not found: %s" % parent_path, "code": "NODE_NOT_FOUND"}

	# Create the template hierarchy
	var template_callable: Callable = _scene_templates[template_name]
	var template_root: Node = template_callable.call(custom_name)

	# Add to scene via UndoHelper
	_undo.create_action("Create Template: %s" % template_name)
	_undo.add_do_method(parent, &"add_child", [template_root])
	_undo.add_do_method(template_root, &"set_owner", [root])
	_undo.add_do_reference(template_root)
	_undo.add_undo_method(parent, &"remove_child", [template_root])
	_undo.commit_action()

	# Set owner recursively on all children (critical for saving)
	_set_owner_recursive(template_root, root)

	# Collect children names for the response
	var children: Array = []
	for child in template_root.get_children():
		children.append(str(child.name))
		for grandchild in child.get_children():
			children.append("%s/%s" % [child.name, grandchild.name])

	return {
		"template": template_name,
		"node_path": str(root.get_path_to(template_root)),
		"node_name": str(template_root.name),
		"children": children,
	}


func scaffold_script(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var template_name: String = params.get("template", "")
	var template_params: Dictionary = params.get("params", {})
	var path_override: String = params.get("path", "")

	if node_path == "":
		return {"error": "node_path parameter is required", "code": "MISSING_PARAM"}
	if template_name == "":
		return {"error": "template parameter is required", "code": "MISSING_PARAM"}

	if not _script_templates.has(template_name):
		return {"error": "Unknown script template: %s" % template_name, "code": "INVALID_TEMPLATE",
			"available": _script_templates.keys()}

	var root = NodeFinder.get_root(_editor)
	if root == null:
		return {"error": "No scene is currently open", "code": "NO_SCENE"}

	var node = NodeFinder.find(_editor, node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	# Generate script source
	var template_callable: Callable = _script_templates[template_name]
	var source: String = template_callable.call(template_params)

	# Determine save path
	var script_path: String = path_override
	if script_path == "":
		var node_name_clean: String = str(node.name).to_snake_case()
		script_path = "res://scripts/%s_%s.gd" % [node_name_clean, template_name]
	if not script_path.begins_with("res://"):
		script_path = "res://" + script_path
	if not script_path.ends_with(".gd"):
		script_path += ".gd"

	# Ensure directory exists
	var dir_path = script_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))

	# Write the script file
	var file = FileAccess.open(script_path, FileAccess.WRITE)
	if file == null:
		return {"error": "Failed to create script file: %s" % script_path, "code": "FILE_CREATE_ERROR"}
	file.store_string(source)
	file.close()

	# Trigger filesystem scan so Godot picks up the new file
	_editor.get_resource_filesystem().scan()

	# Load and attach the script to the node
	var script = load(script_path)
	if script == null:
		return {"error": "Failed to load created script: %s" % script_path, "code": "LOAD_ERROR"}
	node.set_script(script)

	return {
		"script_path": script_path,
		"template": template_name,
		"node_path": node_path,
		"attached": true,
	}


func list_templates(_params: Dictionary) -> Dictionary:
	var scene_list: Array = []
	for key in _scene_templates.keys():
		scene_list.append(key)

	var script_list: Array = []
	for key in _script_templates.keys():
		script_list.append(key)

	return {
		"scene_templates": scene_list,
		"script_templates": script_list,
	}


# ── Scene Templates ───────────────────────────────────────────────────────────


func _template_platformer_player(custom_name: String) -> Node:
	var root = CharacterBody2D.new()
	root.name = custom_name if custom_name != "" else "Player"

	var sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	root.add_child(sprite)

	var col = CollisionShape2D.new()
	col.name = "CollisionShape2D"
	col.shape = RectangleShape2D.new()
	root.add_child(col)

	var anim = AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	root.add_child(anim)

	var cam = Camera2D.new()
	cam.name = "Camera2D"
	root.add_child(cam)

	return root


func _template_top_down_player(custom_name: String) -> Node:
	var root = CharacterBody2D.new()
	root.name = custom_name if custom_name != "" else "Player"

	var sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	root.add_child(sprite)

	var col = CollisionShape2D.new()
	col.name = "CollisionShape2D"
	col.shape = CircleShape2D.new()
	root.add_child(col)

	var nav = NavigationAgent2D.new()
	nav.name = "NavigationAgent2D"
	root.add_child(nav)

	return root


func _template_enemy_basic(custom_name: String) -> Node:
	var root = CharacterBody2D.new()
	root.name = custom_name if custom_name != "" else "Enemy"

	var sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	root.add_child(sprite)

	var col = CollisionShape2D.new()
	col.name = "CollisionShape2D"
	col.shape = RectangleShape2D.new()
	root.add_child(col)

	var timer = Timer.new()
	timer.name = "Timer"
	timer.wait_time = 2.0
	root.add_child(timer)

	var detection = Area2D.new()
	detection.name = "DetectionZone"
	root.add_child(detection)

	var detection_col = CollisionShape2D.new()
	detection_col.name = "CollisionShape2D"
	detection_col.shape = CircleShape2D.new()
	detection.add_child(detection_col)

	return root


func _template_ui_hud(custom_name: String) -> Node:
	var root = CanvasLayer.new()
	root.name = custom_name if custom_name != "" else "HUD"

	var margin = MarginContainer.new()
	margin.name = "MarginContainer"
	root.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.name = "HBoxContainer"
	margin.add_child(hbox)

	var health_label = Label.new()
	health_label.name = "HealthLabel"
	health_label.text = "HP: 100"
	hbox.add_child(health_label)

	var score_label = Label.new()
	score_label.name = "ScoreLabel"
	score_label.text = "Score: 0"
	hbox.add_child(score_label)

	return root


func _template_ui_menu(custom_name: String) -> Node:
	var root = Control.new()
	root.name = custom_name if custom_name != "" else "Menu"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.add_child(vbox)

	var start_btn = Button.new()
	start_btn.name = "StartButton"
	start_btn.text = "Start"
	vbox.add_child(start_btn)

	var options_btn = Button.new()
	options_btn.name = "OptionsButton"
	options_btn.text = "Options"
	vbox.add_child(options_btn)

	var quit_btn = Button.new()
	quit_btn.name = "QuitButton"
	quit_btn.text = "Quit"
	vbox.add_child(quit_btn)

	return root


func _template_rigid_body_2d(custom_name: String) -> Node:
	var root = RigidBody2D.new()
	root.name = custom_name if custom_name != "" else "RigidBody2D"

	var sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	root.add_child(sprite)

	var col = CollisionShape2D.new()
	col.name = "CollisionShape2D"
	col.shape = RectangleShape2D.new()
	root.add_child(col)

	return root


func _template_area_trigger(custom_name: String) -> Node:
	var root = Area2D.new()
	root.name = custom_name if custom_name != "" else "AreaTrigger"

	var col = CollisionShape2D.new()
	col.name = "CollisionShape2D"
	col.shape = RectangleShape2D.new()
	root.add_child(col)

	return root


func _template_audio_manager(custom_name: String) -> Node:
	var root = Node.new()
	root.name = custom_name if custom_name != "" else "AudioManager"

	var bgm = AudioStreamPlayer.new()
	bgm.name = "BGM"
	root.add_child(bgm)

	var sfx = AudioStreamPlayer.new()
	sfx.name = "SFX"
	root.add_child(sfx)

	return root


func _template_camera_follow(custom_name: String) -> Node:
	var root = Camera2D.new()
	root.name = custom_name if custom_name != "" else "Camera2D"
	root.position_smoothing_enabled = true
	root.position_smoothing_speed = 5.0

	return root


func _template_parallax_bg(custom_name: String) -> Node:
	var root = ParallaxBackground.new()
	root.name = custom_name if custom_name != "" else "ParallaxBackground"

	var layer = ParallaxLayer.new()
	layer.name = "ParallaxLayer"
	layer.motion_scale = Vector2(0.5, 0.5)
	root.add_child(layer)

	var sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	layer.add_child(sprite)

	return root


func _template_character_3d(custom_name: String) -> Node:
	var root = CharacterBody3D.new()
	root.name = custom_name if custom_name != "" else "Player3D"

	var mesh = MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	mesh.mesh = BoxMesh.new()
	root.add_child(mesh)

	var col = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	col.shape = BoxShape3D.new()
	root.add_child(col)

	var cam = Camera3D.new()
	cam.name = "Camera3D"
	root.add_child(cam)

	return root


func _template_lighting_3d(custom_name: String) -> Node:
	var root = Node3D.new()
	root.name = custom_name if custom_name != "" else "Lighting"

	var world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = Environment.new()
	root.add_child(world_env)

	var dir_light = DirectionalLight3D.new()
	dir_light.name = "DirectionalLight3D"
	root.add_child(dir_light)

	var omni_light = OmniLight3D.new()
	omni_light.name = "OmniLight3D"
	root.add_child(omni_light)

	return root


# ── Script Templates ──────────────────────────────────────────────────────────


func _script_platformer_movement(p: Dictionary) -> String:
	var speed = p.get("speed", 200)
	var jump_force = p.get("jump_force", -400)
	var gravity = p.get("gravity", 800)
	return 'extends CharacterBody2D

@export var speed := %s.0
@export var jump_force := %s.0
@export var gravity := %s.0

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_force

	var direction := Input.get_axis("move_left", "move_right")
	velocity.x = direction * speed

	move_and_slide()
' % [speed, jump_force, gravity]


func _script_top_down_movement(p: Dictionary) -> String:
	var speed = p.get("speed", 200)
	return 'extends CharacterBody2D

@export var speed := %s.0

func _physics_process(_delta: float) -> void:
	var input := Vector2.ZERO
	input.x = Input.get_axis("move_left", "move_right")
	input.y = Input.get_axis("move_up", "move_down")

	velocity = input.normalized() * speed

	move_and_slide()
' % [speed]


func _script_state_machine(p: Dictionary) -> String:
	var states: Array = p.get("states", ["idle", "walk", "run"])
	var enum_entries := ""
	var match_entries := ""
	for i in states.size():
		var state: String = states[i]
		enum_entries += "\t%s,\n" % state.to_upper()
		match_entries += '\t\tState.%s:\n\t\t\t_%s_process(delta)\n' % [state.to_upper(), state]
	return 'extends Node

enum State {
%s}

var current_state: State = State.%s

func _process(delta: float) -> void:
	match current_state:
%s

func change_state(new_state: State) -> void:
	if new_state == current_state:
		return
	_exit_state(current_state)
	current_state = new_state
	_enter_state(current_state)


func _enter_state(_state: State) -> void:
	pass


func _exit_state(_state: State) -> void:
	pass

%s' % [enum_entries, states[0].to_upper(), match_entries, _generate_state_stubs(states)]


func _script_health_system(p: Dictionary) -> String:
	var max_health = p.get("max_health", 100)
	return 'extends Node

signal health_changed(new_health: int, max_health: int)
signal died

@export var max_health := %s

var current_health: int = max_health

func _ready() -> void:
	current_health = max_health


func take_damage(amount: int) -> void:
	current_health = max(0, current_health - amount)
	health_changed.emit(current_health, max_health)
	if current_health <= 0:
		died.emit()


func heal(amount: int) -> void:
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)


func get_health_percent() -> float:
	return float(current_health) / float(max_health)
' % [max_health]


func _script_inventory(p: Dictionary) -> String:
	var max_slots = p.get("max_slots", 20)
	return 'extends Node

signal inventory_changed
signal item_added(item_id: String, quantity: int)
signal item_removed(item_id: String, quantity: int)

@export var max_slots := %s

var items: Dictionary = {}

func add_item(item_id: String, quantity: int = 1) -> bool:
	if not items.has(item_id) and items.size() >= max_slots:
		return false
	if items.has(item_id):
		items[item_id] += quantity
	else:
		items[item_id] = quantity
	item_added.emit(item_id, quantity)
	inventory_changed.emit()
	return true


func remove_item(item_id: String, quantity: int = 1) -> bool:
	if not items.has(item_id):
		return false
	if items[item_id] < quantity:
		return false
	items[item_id] -= quantity
	if items[item_id] <= 0:
		items.erase(item_id)
	item_removed.emit(item_id, quantity)
	inventory_changed.emit()
	return true


func has_item(item_id: String, quantity: int = 1) -> bool:
	return items.has(item_id) and items[item_id] >= quantity


func get_item_count(item_id: String) -> int:
	return items.get(item_id, 0)


func clear() -> void:
	items.clear()
	inventory_changed.emit()
' % [max_slots]


func _script_dialogue_trigger(p: Dictionary) -> String:
	var dialogue_id = p.get("dialogue_id", "")
	return 'extends Area2D

signal dialogue_started(dialogue_id: String)
signal dialogue_ended(dialogue_id: String)

@export var dialogue_id := "%s"
@export var one_shot := false

var _triggered := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if one_shot and _triggered:
		return
	if body.is_in_group("player"):
		_triggered = true
		start_dialogue()


func start_dialogue() -> void:
	dialogue_started.emit(dialogue_id)


func end_dialogue() -> void:
	dialogue_ended.emit(dialogue_id)
' % [dialogue_id]


func _script_enemy_patrol(p: Dictionary) -> String:
	var speed = p.get("speed", 100)
	var wait_time = p.get("wait_time", 2.0)
	return 'extends CharacterBody2D

@export var speed := %s.0
@export var wait_time := %s
@export var patrol_points: Array[Vector2] = []

var _current_point := 0
var _waiting := false

@onready var _timer: Timer = $Timer

func _ready() -> void:
	if has_node("Timer"):
		_timer = $Timer
		_timer.wait_time = wait_time
		_timer.timeout.connect(_on_timer_timeout)
	else:
		_timer = Timer.new()
		_timer.wait_time = wait_time
		_timer.one_shot = true
		_timer.timeout.connect(_on_timer_timeout)
		add_child(_timer)


func _physics_process(_delta: float) -> void:
	if _waiting or patrol_points.is_empty():
		return

	var target := patrol_points[_current_point]
	var direction := (target - global_position).normalized()
	velocity = direction * speed

	if global_position.distance_to(target) < 5.0:
		velocity = Vector2.ZERO
		_waiting = true
		_timer.start()

	move_and_slide()


func _on_timer_timeout() -> void:
	_waiting = false
	_current_point = (_current_point + 1) %% patrol_points.size()
' % [speed, wait_time]


func _script_camera_shake(p: Dictionary) -> String:
	var decay = p.get("decay", 0.8)
	var max_offset_x = p.get("max_offset", Vector2(10, 5))
	# Handle both Vector2 and other types for max_offset
	var offset_x: float = 10.0
	var offset_y: float = 5.0
	if max_offset_x is Vector2:
		offset_x = max_offset_x.x
		offset_y = max_offset_x.y
	return 'extends Camera2D

@export var decay := %s
@export var max_offset := Vector2(%s, %s)

var _trauma := 0.0

func _process(delta: float) -> void:
	if _trauma > 0.0:
		_trauma = max(0.0, _trauma - decay * delta)
		var shake_intensity := _trauma * _trauma
		offset = Vector2(
			randf_range(-max_offset.x, max_offset.x) * shake_intensity,
			randf_range(-max_offset.y, max_offset.y) * shake_intensity,
		)
	else:
		offset = Vector2.ZERO


func add_trauma(amount: float) -> void:
	_trauma = min(1.0, _trauma + amount)


func shake(intensity: float = 0.5) -> void:
	add_trauma(intensity)
' % [decay, offset_x, offset_y]


func _script_save_load(p: Dictionary) -> String:
	var save_path = p.get("save_path", "user://savegame.cfg")
	return 'extends Node

@export var save_path := "%s"

var _data: Dictionary = {}

func save_value(section: String, key: String, value: Variant) -> void:
	if not _data.has(section):
		_data[section] = {}
	_data[section][key] = value


func load_value(section: String, key: String, default: Variant = null) -> Variant:
	if _data.has(section) and _data[section].has(key):
		return _data[section][key]
	return default


func save_to_disk() -> Error:
	var config := ConfigFile.new()
	for section in _data:
		for key in _data[section]:
			config.set_value(section, key, _data[section][key])
	return config.save(save_path)


func load_from_disk() -> Error:
	var config := ConfigFile.new()
	var err := config.load(save_path)
	if err != OK:
		return err
	_data.clear()
	for section in config.get_sections():
		_data[section] = {}
		for key in config.get_section_keys(section):
			_data[section][key] = config.get_value(section, key)
	return OK


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


func delete_save() -> Error:
	if has_save():
		return DirAccess.remove_absolute(save_path)
	return OK
' % [save_path]


func _script_audio_manager(p: Dictionary) -> String:
	var pool_size = p.get("pool_size", 8)
	return 'extends Node

@export var pool_size := %s

var _bgm_player: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _next_sfx := 0

func _ready() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BGMPlayer"
	_bgm_player.bus = "Music"
	add_child(_bgm_player)

	for i in pool_size:
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer_%%d" %% i
		player.bus = "SFX"
		add_child(player)
		_sfx_pool.append(player)


func play_bgm(stream: AudioStream, volume_db: float = 0.0) -> void:
	_bgm_player.stream = stream
	_bgm_player.volume_db = volume_db
	_bgm_player.play()


func stop_bgm() -> void:
	_bgm_player.stop()


func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	var player := _sfx_pool[_next_sfx]
	player.stream = stream
	player.volume_db = volume_db
	player.play()
	_next_sfx = (_next_sfx + 1) %% _sfx_pool.size()


func set_bgm_volume(volume_db: float) -> void:
	_bgm_player.volume_db = volume_db
' % [pool_size]


# ── Helpers ───────────────────────────────────────────────────────────────────


func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.set_owner(owner)
		_set_owner_recursive(child, owner)


func _generate_state_stubs(states: Array) -> String:
	var stubs := ""
	for state in states:
		stubs += 'func _%s_process(_delta: float) -> void:\n\tpass\n\n\n' % state
	return stubs
