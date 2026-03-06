@tool
class_name ParticlesHandler
extends RefCounted

## Particles tools (5):
## create_particles, set_particle_material, set_particle_color_gradient,
## apply_particle_preset, get_particle_info

var _editor: EditorInterface
var _undo: UndoHelper


func _init(editor: EditorInterface, undo: UndoHelper):
	_editor = editor
	_undo = undo


func get_commands() -> Dictionary:
	return {
		"create_particles": create_particles,
		"set_particle_material": set_particle_material,
		"set_particle_color_gradient": set_particle_color_gradient,
		"apply_particle_preset": apply_particle_preset,
		"get_particle_info": get_particle_info,
	}


func create_particles(params: Dictionary) -> Dictionary:
	var parent_path: String = params.get("parent_path", "")
	var is_3d: bool = params.get("is_3d", true)
	var node_name: String = params.get("name", "Particles")
	var amount: int = params.get("amount", 16)
	var lifetime: float = params.get("lifetime", 1.0)

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var parent = NodeFinder.find(_editor, parent_path) if parent_path != "" else root

	var particles: Node
	if is_3d:
		var p = GPUParticles3D.new()
		p.name = node_name
		p.amount = amount
		p.lifetime = lifetime
		p.process_material = ParticleProcessMaterial.new()
		particles = p
	else:
		var p = GPUParticles2D.new()
		p.name = node_name
		p.amount = amount
		p.lifetime = lifetime
		p.process_material = ParticleProcessMaterial.new()
		particles = p

	_undo.create_action("Create Particles: %s" % node_name)
	_undo.add_do_method(parent, &"add_child", [particles])
	_undo.add_do_method(particles, &"set_owner", [root])
	_undo.add_do_reference(particles)
	_undo.add_undo_method(parent, &"remove_child", [particles])
	_undo.commit_action()

	return {"node_path": str(root.get_path_to(particles)), "is_3d": is_3d, "amount": amount}


func set_particle_material(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var direction: String = params.get("direction", "")
	var initial_velocity_min: float = params.get("initial_velocity_min", 0.0)
	var initial_velocity_max: float = params.get("initial_velocity_max", 5.0)
	var gravity: String = params.get("gravity", "")
	var spread: float = params.get("spread", 45.0)
	var emission_shape: int = params.get("emission_shape", 0)

	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var node = NodeFinder.find(_editor, node_path)
	if node == null:
		return {"error": "Node not found", "code": "NODE_NOT_FOUND"}

	var mat: ParticleProcessMaterial
	if node is GPUParticles3D:
		mat = node.process_material as ParticleProcessMaterial
	elif node is GPUParticles2D:
		mat = node.process_material as ParticleProcessMaterial
	else:
		return {"error": "Node is not a particle emitter", "code": "WRONG_TYPE"}

	if mat == null:
		mat = ParticleProcessMaterial.new()

	if direction != "":
		mat.direction = TypeParser.parse_value(direction)
	mat.initial_velocity_min = initial_velocity_min
	mat.initial_velocity_max = initial_velocity_max
	if gravity != "":
		mat.gravity = TypeParser.parse_value(gravity)
	mat.spread = spread
	mat.emission_shape = emission_shape

	if node is GPUParticles3D:
		node.process_material = mat
	elif node is GPUParticles2D:
		node.process_material = mat

	return {"node_path": node_path, "material_set": true}


func set_particle_color_gradient(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var stops: Array = params.get("stops", [])

	if node_path == "" or stops.is_empty():
		return {"error": "node_path and stops are required", "code": "MISSING_PARAM"}

	var node = NodeFinder.find(_editor, node_path)
	if node == null:
		return {"error": "Node not found", "code": "NODE_NOT_FOUND"}

	var mat: ParticleProcessMaterial
	if node is GPUParticles3D:
		mat = node.process_material as ParticleProcessMaterial
	elif node is GPUParticles2D:
		mat = node.process_material as ParticleProcessMaterial
	else:
		return {"error": "Not a particle emitter", "code": "WRONG_TYPE"}

	if mat == null:
		return {"error": "No process material set", "code": "NO_MATERIAL"}

	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array()
	gradient.colors = PackedColorArray()

	for stop in stops:
		var offset: float = stop.get("offset", 0.0)
		var color = TypeParser.parse_value(stop.get("color", "#ffffff"))
		gradient.add_point(offset, color)

	var tex = GradientTexture1D.new()
	tex.gradient = gradient
	mat.color_ramp = tex

	return {"node_path": node_path, "stops": stops.size()}


func apply_particle_preset(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var preset: String = params.get("preset", "")

	if node_path == "" or preset == "":
		return {"error": "node_path and preset are required", "code": "MISSING_PARAM"}

	var node = NodeFinder.find(_editor, node_path)
	if node == null:
		return {"error": "Node not found", "code": "NODE_NOT_FOUND"}

	var mat = ParticleProcessMaterial.new()

	match preset.to_lower():
		"fire":
			mat.direction = Vector3(0, 1, 0)
			mat.initial_velocity_min = 2.0
			mat.initial_velocity_max = 5.0
			mat.gravity = Vector3(0, -0.5, 0)
			mat.spread = 15.0
			var gradient = Gradient.new()
			gradient.add_point(0.0, Color(1.0, 0.8, 0.0))
			gradient.add_point(0.5, Color(1.0, 0.3, 0.0))
			gradient.add_point(1.0, Color(0.3, 0.0, 0.0, 0.0))
			var tex = GradientTexture1D.new()
			tex.gradient = gradient
			mat.color_ramp = tex
		"smoke":
			mat.direction = Vector3(0, 1, 0)
			mat.initial_velocity_min = 0.5
			mat.initial_velocity_max = 2.0
			mat.gravity = Vector3(0, 0.5, 0)
			mat.spread = 30.0
			var gradient = Gradient.new()
			gradient.add_point(0.0, Color(0.5, 0.5, 0.5, 0.8))
			gradient.add_point(1.0, Color(0.3, 0.3, 0.3, 0.0))
			var tex = GradientTexture1D.new()
			tex.gradient = gradient
			mat.color_ramp = tex
		"rain":
			mat.direction = Vector3(0, -1, 0)
			mat.initial_velocity_min = 10.0
			mat.initial_velocity_max = 15.0
			mat.gravity = Vector3(0, -9.8, 0)
			mat.spread = 5.0
			mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			mat.emission_box_extents = Vector3(10, 0, 10)
		"snow":
			mat.direction = Vector3(0, -1, 0)
			mat.initial_velocity_min = 0.5
			mat.initial_velocity_max = 1.5
			mat.gravity = Vector3(0, -1.0, 0)
			mat.spread = 60.0
			mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			mat.emission_box_extents = Vector3(10, 0, 10)
		"sparks":
			mat.direction = Vector3(0, 1, 0)
			mat.initial_velocity_min = 3.0
			mat.initial_velocity_max = 8.0
			mat.gravity = Vector3(0, -9.8, 0)
			mat.spread = 90.0
			var gradient = Gradient.new()
			gradient.add_point(0.0, Color(1.0, 0.9, 0.5))
			gradient.add_point(1.0, Color(1.0, 0.3, 0.0, 0.0))
			var tex = GradientTexture1D.new()
			tex.gradient = gradient
			mat.color_ramp = tex
		_:
			return {"error": "Unknown preset: %s" % preset, "code": "INVALID_PRESET",
				"suggestions": ["Available: fire, smoke, rain, snow, sparks"]}

	if node is GPUParticles3D:
		node.process_material = mat
	elif node is GPUParticles2D:
		node.process_material = mat

	return {"node_path": node_path, "preset": preset}


func get_particle_info(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var node = NodeFinder.find(_editor, node_path)
	if node == null:
		return {"error": "Node not found", "code": "NODE_NOT_FOUND"}

	var info: Dictionary = {"node_path": node_path, "type": node.get_class()}

	if node is GPUParticles3D:
		info["amount"] = node.amount
		info["lifetime"] = node.lifetime
		info["emitting"] = node.emitting
		info["one_shot"] = node.one_shot
		if node.process_material is ParticleProcessMaterial:
			var mat: ParticleProcessMaterial = node.process_material
			info["direction"] = TypeParser.value_to_json(mat.direction)
			info["spread"] = mat.spread
			info["gravity"] = TypeParser.value_to_json(mat.gravity)
			info["initial_velocity"] = [mat.initial_velocity_min, mat.initial_velocity_max]
	elif node is GPUParticles2D:
		info["amount"] = node.amount
		info["lifetime"] = node.lifetime
		info["emitting"] = node.emitting
		info["one_shot"] = node.one_shot

	return info
