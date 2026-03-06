@tool
class_name Scene3DHandler
extends RefCounted

## 3D Scene tools (6):
## add_mesh_instance, setup_lighting, set_material_3d,
## setup_environment, setup_camera_3d, add_gridmap

var _editor: EditorInterface
var _undo: UndoHelper


func _init(editor: EditorInterface, undo: UndoHelper):
	_editor = editor
	_undo = undo


func get_commands() -> Dictionary:
	return {
		"add_mesh_instance": add_mesh_instance,
		"setup_lighting": setup_lighting,
		"set_material_3d": set_material_3d,
		"setup_environment": setup_environment,
		"setup_camera_3d": setup_camera_3d,
		"add_gridmap": add_gridmap,
	}


func _find_node(path: String) -> Node:
	var root = _editor.get_edited_scene_root()
	if root == null:
		return null
	if path == "" or path == root.name:
		return root
	return root.get_node_or_null(path)


func add_mesh_instance(params: Dictionary) -> Dictionary:
	var parent_path: String = params.get("parent_path", "")
	var mesh_type: String = params.get("mesh_type", "box")
	var node_name: String = params.get("name", "MeshInstance3D")
	var position = params.get("position", "Vector3(0, 0, 0)")
	var size = params.get("size", null)
	var scene_file: String = params.get("scene_file", "")

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open", "code": "NO_SCENE"}

	var parent = _find_node(parent_path) if parent_path != "" else root
	if parent == null:
		return {"error": "Parent not found: %s" % parent_path, "code": "NODE_NOT_FOUND"}

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = TypeParser.parse_value(position) if position is String else Vector3.ZERO

	if scene_file != "":
		# Import .glb/.gltf
		if not scene_file.begins_with("res://"):
			scene_file = "res://" + scene_file
		if ResourceLoader.exists(scene_file):
			var packed = load(scene_file) as PackedScene
			if packed:
				var instance = packed.instantiate()
				instance.name = node_name
				_undo.create_action("Add 3D Scene: %s" % node_name)
				_undo.add_do_method(parent, &"add_child", [instance])
				_undo.add_do_method(instance, &"set_owner", [root])
				_undo.add_do_reference(instance)
				_undo.add_undo_method(parent, &"remove_child", [instance])
				_undo.commit_action()
				return {"node_path": str(root.get_path_to(instance)), "source": scene_file}
	else:
		# Create primitive mesh
		var mesh: Mesh
		match mesh_type.to_lower():
			"box":
				mesh = BoxMesh.new()
				if size:
					mesh.size = TypeParser.parse_value(size)
			"sphere":
				mesh = SphereMesh.new()
				if size:
					mesh.radius = TypeParser.parse_value(size) if size is String else float(size)
			"cylinder":
				mesh = CylinderMesh.new()
			"capsule":
				mesh = CapsuleMesh.new()
			"plane", "quad":
				mesh = PlaneMesh.new()
				if size:
					var s = TypeParser.parse_value(size)
					if s is Vector2:
						mesh.size = s
			"torus":
				mesh = TorusMesh.new()
			_:
				mesh = BoxMesh.new()
		mesh_instance.mesh = mesh

	_undo.create_action("Add Mesh: %s" % node_name)
	_undo.add_do_method(parent, &"add_child", [mesh_instance])
	_undo.add_do_method(mesh_instance, &"set_owner", [root])
	_undo.add_do_reference(mesh_instance)
	_undo.add_undo_method(parent, &"remove_child", [mesh_instance])
	_undo.commit_action()

	return {"node_path": str(root.get_path_to(mesh_instance)), "mesh_type": mesh_type}


func setup_lighting(params: Dictionary) -> Dictionary:
	var parent_path: String = params.get("parent_path", "")
	var preset: String = params.get("preset", "sun")

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var parent = _find_node(parent_path) if parent_path != "" else root
	if parent == null:
		return {"error": "Parent not found", "code": "NODE_NOT_FOUND"}

	var lights: Array = []

	match preset.to_lower():
		"sun", "outdoor":
			var light = DirectionalLight3D.new()
			light.name = "Sun"
			light.rotation_degrees = Vector3(-45, -30, 0)
			light.shadow_enabled = true
			light.light_energy = 1.0
			lights.append(light)
		"indoor":
			var light = OmniLight3D.new()
			light.name = "IndoorLight"
			light.position = Vector3(0, 3, 0)
			light.omni_range = 10.0
			light.shadow_enabled = true
			lights.append(light)
		"dramatic":
			var key = DirectionalLight3D.new()
			key.name = "KeyLight"
			key.rotation_degrees = Vector3(-30, -45, 0)
			key.light_energy = 1.2
			key.shadow_enabled = true
			lights.append(key)

			var fill = OmniLight3D.new()
			fill.name = "FillLight"
			fill.position = Vector3(3, 2, 3)
			fill.light_energy = 0.4
			fill.light_color = Color(0.8, 0.9, 1.0)
			lights.append(fill)

			var rim = SpotLight3D.new()
			rim.name = "RimLight"
			rim.position = Vector3(-2, 3, -2)
			rim.rotation_degrees = Vector3(-45, 135, 0)
			rim.light_energy = 0.8
			lights.append(rim)

	_undo.create_action("Setup Lighting: %s" % preset)
	for light in lights:
		_undo.add_do_method(parent, &"add_child", [light])
		_undo.add_do_method(light, &"set_owner", [root])
		_undo.add_do_reference(light)
		_undo.add_undo_method(parent, &"remove_child", [light])
	_undo.commit_action()

	var created: Array = []
	for light in lights:
		created.append(str(root.get_path_to(light)))

	return {"preset": preset, "created": created}


func set_material_3d(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var albedo_color: String = params.get("albedo_color", "")
	var metallic: float = params.get("metallic", 0.0)
	var roughness: float = params.get("roughness", 1.0)
	var emission_color: String = params.get("emission_color", "")
	var emission_energy: float = params.get("emission_energy", 0.0)

	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var node = _find_node(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}
	if not node is MeshInstance3D:
		return {"error": "Node is not a MeshInstance3D", "code": "WRONG_TYPE"}

	var mat = StandardMaterial3D.new()
	if albedo_color != "":
		mat.albedo_color = TypeParser.parse_value(albedo_color)
	mat.metallic = metallic
	mat.roughness = roughness
	if emission_color != "":
		mat.emission_enabled = true
		mat.emission = TypeParser.parse_value(emission_color)
		mat.emission_energy_multiplier = emission_energy

	var mi: MeshInstance3D = node
	mi.material_override = mat

	return {"node_path": node_path, "material": "StandardMaterial3D"}


func setup_environment(params: Dictionary) -> Dictionary:
	var parent_path: String = params.get("parent_path", "")
	var sky_color: String = params.get("sky_color", "")
	var fog_enabled: bool = params.get("fog_enabled", false)
	var fog_density: float = params.get("fog_density", 0.01)
	var glow_enabled: bool = params.get("glow_enabled", false)
	var ssao_enabled: bool = params.get("ssao_enabled", false)
	var ssr_enabled: bool = params.get("ssr_enabled", false)

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var parent = _find_node(parent_path) if parent_path != "" else root

	var env_node = WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var env = Environment.new()

	# Sky
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	if sky_color != "":
		sky_mat.sky_top_color = TypeParser.parse_value(sky_color)
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY

	# Fog
	if fog_enabled:
		env.fog_enabled = true
		env.fog_density = fog_density

	# Glow
	if glow_enabled:
		env.glow_enabled = true

	# SSAO
	if ssao_enabled:
		env.ssao_enabled = true

	# SSR
	if ssr_enabled:
		env.ssr_enabled = true

	env_node.environment = env

	_undo.create_action("Setup Environment")
	_undo.add_do_method(parent, &"add_child", [env_node])
	_undo.add_do_method(env_node, &"set_owner", [root])
	_undo.add_do_reference(env_node)
	_undo.add_undo_method(parent, &"remove_child", [env_node])
	_undo.commit_action()

	return {"node_path": str(root.get_path_to(env_node))}


func setup_camera_3d(params: Dictionary) -> Dictionary:
	var parent_path: String = params.get("parent_path", "")
	var position: String = params.get("position", "Vector3(0, 2, 5)")
	var look_at_target: String = params.get("look_at", "Vector3(0, 0, 0)")
	var fov: float = params.get("fov", 75.0)
	var projection: String = params.get("projection", "perspective")
	var node_name: String = params.get("name", "Camera3D")

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var parent = _find_node(parent_path) if parent_path != "" else root

	var camera = Camera3D.new()
	camera.name = node_name
	camera.position = TypeParser.parse_value(position)
	camera.fov = fov

	if projection == "orthogonal":
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL

	_undo.create_action("Add Camera3D")
	_undo.add_do_method(parent, &"add_child", [camera])
	_undo.add_do_method(camera, &"set_owner", [root])
	_undo.add_do_reference(camera)
	_undo.add_undo_method(parent, &"remove_child", [camera])
	_undo.commit_action()

	# Look at target after adding to tree
	var target = TypeParser.parse_value(look_at_target)
	if target is Vector3:
		camera.look_at(target)

	return {"node_path": str(root.get_path_to(camera)), "fov": fov, "projection": projection}


func add_gridmap(params: Dictionary) -> Dictionary:
	var parent_path: String = params.get("parent_path", "")
	var mesh_library_path: String = params.get("mesh_library", "")
	var cell_size: String = params.get("cell_size", "Vector3(2, 2, 2)")
	var node_name: String = params.get("name", "GridMap")

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	var parent = _find_node(parent_path) if parent_path != "" else root

	var gridmap = GridMap.new()
	gridmap.name = node_name
	gridmap.cell_size = TypeParser.parse_value(cell_size)

	if mesh_library_path != "":
		if not mesh_library_path.begins_with("res://"):
			mesh_library_path = "res://" + mesh_library_path
		var lib = load(mesh_library_path) as MeshLibrary
		if lib:
			gridmap.mesh_library = lib

	_undo.create_action("Add GridMap")
	_undo.add_do_method(parent, &"add_child", [gridmap])
	_undo.add_do_method(gridmap, &"set_owner", [root])
	_undo.add_do_reference(gridmap)
	_undo.add_undo_method(parent, &"remove_child", [gridmap])
	_undo.commit_action()

	return {"node_path": str(root.get_path_to(gridmap))}
