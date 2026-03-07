@tool
class_name AssetHandler
extends RefCounted

## Asset management tools (7):
## set_sprite_texture, create_sprite_frames, create_atlas_texture,
## set_texture_import_preset, get_image_info, create_nine_patch,
## validate_spritesheet

var _editor: EditorInterface
var _undo: UndoHelper


func _init(editor: EditorInterface, undo: UndoHelper):
	_editor = editor
	_undo = undo


func get_commands() -> Dictionary:
	return {
		"set_sprite_texture": set_sprite_texture,
		"create_sprite_frames": create_sprite_frames,
		"create_atlas_texture": create_atlas_texture,
		"set_texture_import_preset": set_texture_import_preset,
		"get_image_info": get_image_info,
		"create_nine_patch": create_nine_patch,
		"validate_spritesheet": validate_spritesheet,
	}


func set_sprite_texture(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var texture_path: String = params.get("texture_path", "")

	if node_path == "" or texture_path == "":
		return {"error": "node_path and texture_path are required", "code": "MISSING_PARAM"}
	if not texture_path.begins_with("res://"):
		texture_path = "res://" + texture_path

	var node = NodeFinder.find(_editor, node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	# Trigger reimport so newly generated files are recognized
	_editor.get_resource_filesystem().scan()

	if not ResourceLoader.exists(texture_path):
		return {"error": "Texture file not found: %s. Ensure the file exists and Godot has imported it." % texture_path,
			"code": "FILE_NOT_FOUND"}

	var texture = load(texture_path) as Texture2D
	if texture == null:
		return {"error": "Cannot load as texture: %s" % texture_path, "code": "LOAD_ERROR"}

	# Handle different node types
	if "texture" in node:
		var old = node.get("texture")
		_undo.create_action("Set Texture: %s" % node.name)
		_undo.add_do_property(node, &"texture", texture)
		_undo.add_undo_property(node, &"texture", old)
		_undo.commit_action()
		return {"node_path": node_path, "texture": texture_path}
	elif node is MeshInstance3D:
		var mat = StandardMaterial3D.new()
		mat.albedo_texture = texture
		var old = node.material_override
		_undo.create_action("Set Albedo Texture: %s" % node.name)
		_undo.add_do_property(node, &"material_override", mat)
		_undo.add_undo_property(node, &"material_override", old)
		_undo.commit_action()
		return {"node_path": node_path, "texture": texture_path, "applied_as": "albedo_texture"}

	return {"error": "Node type %s doesn't support textures" % node.get_class(), "code": "WRONG_TYPE",
		"suggestions": ["Supported: Sprite2D, Sprite3D, TextureRect, MeshInstance3D, AnimatedSprite2D"]}


func create_sprite_frames(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var spritesheet_path: String = params.get("spritesheet", "")
	var frame_paths: Array = params.get("frames", [])
	var anim_name: String = params.get("animation", "default")
	var frame_width: int = params.get("frame_width", 0)
	var frame_height: int = params.get("frame_height", 0)
	var columns: int = params.get("columns", 0)
	var frame_count: int = params.get("frame_count", 0)
	var fps: float = params.get("fps", 10.0)
	var loop: bool = params.get("loop", true)
	var save_path: String = params.get("save_path", "")

	if node_path == "" and save_path == "":
		return {"error": "node_path or save_path is required", "code": "MISSING_PARAM"}
	if spritesheet_path == "" and frame_paths.is_empty():
		return {"error": "spritesheet or frames array is required", "code": "MISSING_PARAM"}

	_editor.get_resource_filesystem().scan()

	var sprite_frames = SpriteFrames.new()
	# Remove the default animation if we're creating a custom one
	if anim_name != "default" and sprite_frames.has_animation("default"):
		sprite_frames.remove_animation("default")
	if not sprite_frames.has_animation(anim_name):
		sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_speed(anim_name, fps)
	sprite_frames.set_animation_loop(anim_name, loop)

	var added_frames: int = 0

	if spritesheet_path != "":
		# Create frames from spritesheet using AtlasTexture
		if not spritesheet_path.begins_with("res://"):
			spritesheet_path = "res://" + spritesheet_path
		if not ResourceLoader.exists(spritesheet_path):
			return {"error": "Spritesheet not found: %s" % spritesheet_path, "code": "FILE_NOT_FOUND"}

		var sheet_tex = load(spritesheet_path) as Texture2D
		if sheet_tex == null:
			return {"error": "Cannot load spritesheet: %s" % spritesheet_path, "code": "LOAD_ERROR"}

		var img_width = sheet_tex.get_width()
		var img_height = sheet_tex.get_height()

		if frame_width <= 0 or frame_height <= 0:
			return {"error": "frame_width and frame_height are required for spritesheets", "code": "MISSING_PARAM"}

		if columns <= 0:
			columns = img_width / frame_width
		var rows = img_height / frame_height
		var total = columns * rows
		if frame_count > 0:
			total = mini(total, frame_count)

		for i in range(total):
			var col = i % columns
			var row = i / columns
			var atlas = AtlasTexture.new()
			atlas.atlas = sheet_tex
			atlas.region = Rect2(col * frame_width, row * frame_height, frame_width, frame_height)
			sprite_frames.add_frame(anim_name, atlas)
			added_frames += 1
	else:
		# Create frames from individual image files
		for frame_path in frame_paths:
			var fp: String = frame_path
			if not fp.begins_with("res://"):
				fp = "res://" + fp
			if not ResourceLoader.exists(fp):
				continue
			var tex = load(fp) as Texture2D
			if tex:
				sprite_frames.add_frame(anim_name, tex)
				added_frames += 1

	if added_frames == 0:
		return {"error": "No frames were created", "code": "NO_FRAMES"}

	# Save the SpriteFrames resource if requested
	if save_path != "":
		if not save_path.begins_with("res://"):
			save_path = "res://" + save_path
		if not save_path.ends_with(".tres"):
			save_path += ".tres"
		var dir_path = save_path.get_base_dir()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
		ResourceSaver.save(sprite_frames, save_path)
		_editor.get_resource_filesystem().scan()

	# Assign to node if specified
	if node_path != "":
		var node = NodeFinder.find(_editor, node_path)
		if node == null:
			return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}
		if node is AnimatedSprite2D or node is AnimatedSprite3D:
			var old = node.sprite_frames
			_undo.create_action("Set SpriteFrames: %s" % node.name)
			_undo.add_do_property(node, &"sprite_frames", sprite_frames)
			_undo.add_undo_property(node, &"sprite_frames", old)
			_undo.commit_action()
		else:
			return {"error": "Node is not AnimatedSprite2D/3D: %s" % node.get_class(), "code": "WRONG_TYPE"}

	return {"animation": anim_name, "frame_count": added_frames, "fps": fps, "loop": loop,
		"save_path": save_path if save_path != "" else null}


func create_atlas_texture(params: Dictionary) -> Dictionary:
	var source_path: String = params.get("source_path", "")
	var region_x: int = params.get("x", 0)
	var region_y: int = params.get("y", 0)
	var region_w: int = params.get("width", 0)
	var region_h: int = params.get("height", 0)
	var save_path: String = params.get("save_path", "")
	var node_path: String = params.get("node_path", "")

	if source_path == "" or region_w <= 0 or region_h <= 0:
		return {"error": "source_path, width, and height are required", "code": "MISSING_PARAM"}
	if not source_path.begins_with("res://"):
		source_path = "res://" + source_path

	_editor.get_resource_filesystem().scan()

	if not ResourceLoader.exists(source_path):
		return {"error": "Source texture not found: %s" % source_path, "code": "FILE_NOT_FOUND"}

	var source_tex = load(source_path) as Texture2D
	if source_tex == null:
		return {"error": "Cannot load texture: %s" % source_path, "code": "LOAD_ERROR"}

	var atlas = AtlasTexture.new()
	atlas.atlas = source_tex
	atlas.region = Rect2(region_x, region_y, region_w, region_h)

	if save_path != "":
		if not save_path.begins_with("res://"):
			save_path = "res://" + save_path
		if not save_path.ends_with(".tres"):
			save_path += ".tres"
		ResourceSaver.save(atlas, save_path)
		_editor.get_resource_filesystem().scan()

	if node_path != "":
		var node = NodeFinder.find(_editor, node_path)
		if node != null and "texture" in node:
			var old = node.get("texture")
			_undo.create_action("Set Atlas Texture: %s" % node.name)
			_undo.add_do_property(node, &"texture", atlas)
			_undo.add_undo_property(node, &"texture", old)
			_undo.commit_action()

	return {"region": [region_x, region_y, region_w, region_h], "source": source_path,
		"save_path": save_path if save_path != "" else null}


func set_texture_import_preset(params: Dictionary) -> Dictionary:
	var texture_path: String = params.get("texture_path", "")
	var preset: String = params.get("preset", "2d_pixel")

	if texture_path == "":
		return {"error": "texture_path is required", "code": "MISSING_PARAM"}
	if not texture_path.begins_with("res://"):
		texture_path = "res://" + texture_path

	var abs_path = ProjectSettings.globalize_path(texture_path)
	var import_path = abs_path + ".import"

	if not FileAccess.file_exists(import_path):
		# Trigger scan first so Godot creates the .import file
		_editor.get_resource_filesystem().scan()
		# Wait a bit for the scan
		if not FileAccess.file_exists(import_path):
			return {"error": "Import file not found. Ensure the texture exists and has been imported.", "code": "NOT_IMPORTED"}

	# Read the existing .import file
	var file = FileAccess.open(import_path, FileAccess.READ)
	if file == null:
		return {"error": "Cannot read import file", "code": "FILE_READ_ERROR"}
	var content = file.get_as_text()
	file.close()

	# Apply preset modifications
	match preset:
		"2d_pixel", "pixel_art":
			# Nearest neighbor filtering, no mipmaps
			content = _set_import_param(content, "process/fix_alpha_border", "false")
			content = _set_import_param(content, "process/premult_alpha", "false")
			if content.contains("flags/filter"):
				content = _set_import_param(content, "flags/filter", "false")
			# For Godot 4.x texture import format
			content = _set_import_param(content, "process/size_limit", "0")
		"2d_regular":
			content = _set_import_param(content, "process/fix_alpha_border", "true")
		"3d":
			content = _set_import_param(content, "compress/mode", "2")

	# Write back
	file = FileAccess.open(import_path, FileAccess.WRITE)
	if file == null:
		return {"error": "Cannot write import file", "code": "FILE_WRITE_ERROR"}
	file.store_string(content)
	file.close()

	# Trigger reimport
	_editor.get_resource_filesystem().reimport_files(PackedStringArray([texture_path]))

	return {"texture_path": texture_path, "preset": preset}


func get_image_info(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	if path == "":
		return {"error": "path is required", "code": "MISSING_PARAM"}
	if not path.begins_with("res://"):
		path = "res://" + path

	_editor.get_resource_filesystem().scan()

	# Try loading as texture first
	if ResourceLoader.exists(path):
		var tex = load(path) as Texture2D
		if tex:
			return {
				"path": path,
				"width": tex.get_width(),
				"height": tex.get_height(),
				"type": tex.get_class(),
				"imported": true,
			}

	# Try loading raw image
	var abs_path = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		var img = Image.new()
		var err = img.load(abs_path)
		if err == OK:
			return {
				"path": path,
				"width": img.get_width(),
				"height": img.get_height(),
				"format": img.get_format(),
				"has_alpha": img.detect_alpha() != Image.ALPHA_NONE,
				"imported": ResourceLoader.exists(path),
			}

	return {"error": "Image not found: %s" % path, "code": "FILE_NOT_FOUND"}


func create_nine_patch(params: Dictionary) -> Dictionary:
	var parent_path: String = params.get("parent_path", "")
	var texture_path: String = params.get("texture_path", "")
	var node_name: String = params.get("name", "NinePatchRect")
	var margin_left: int = params.get("margin_left", 8)
	var margin_top: int = params.get("margin_top", 8)
	var margin_right: int = params.get("margin_right", 8)
	var margin_bottom: int = params.get("margin_bottom", 8)

	if texture_path == "":
		return {"error": "texture_path is required", "code": "MISSING_PARAM"}
	if not texture_path.begins_with("res://"):
		texture_path = "res://" + texture_path

	var root = _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open", "code": "NO_SCENE"}

	_editor.get_resource_filesystem().scan()

	if not ResourceLoader.exists(texture_path):
		return {"error": "Texture not found: %s" % texture_path, "code": "FILE_NOT_FOUND"}

	var texture = load(texture_path) as Texture2D
	if texture == null:
		return {"error": "Cannot load texture: %s" % texture_path, "code": "LOAD_ERROR"}

	var parent = NodeFinder.find(_editor, parent_path) if parent_path != "" else root

	var nine_patch = NinePatchRect.new()
	nine_patch.name = node_name
	nine_patch.texture = texture
	nine_patch.patch_margin_left = margin_left
	nine_patch.patch_margin_top = margin_top
	nine_patch.patch_margin_right = margin_right
	nine_patch.patch_margin_bottom = margin_bottom

	_undo.create_action("Create NinePatchRect: %s" % node_name)
	_undo.add_do_method(parent, &"add_child", [nine_patch])
	_undo.add_do_method(nine_patch, &"set_owner", [root])
	_undo.add_do_reference(nine_patch)
	_undo.add_undo_method(parent, &"remove_child", [nine_patch])
	_undo.commit_action()

	return {"node_path": str(root.get_path_to(nine_patch)), "texture": texture_path}


func validate_spritesheet(params: Dictionary) -> Dictionary:
	var path: String = params.get("path", "")
	var frame_width: int = params.get("frame_width", 0)
	var frame_height: int = params.get("frame_height", 0)

	if path == "" or frame_width <= 0 or frame_height <= 0:
		return {"error": "path, frame_width, and frame_height are required", "code": "MISSING_PARAM"}
	if not path.begins_with("res://"):
		path = "res://" + path

	var abs_path = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return {"error": "Image not found: %s" % path, "code": "FILE_NOT_FOUND"}

	var img = Image.new()
	var err = img.load(abs_path)
	if err != OK:
		return {"error": "Cannot load image: %s" % path, "code": "LOAD_ERROR"}

	var img_width = img.get_width()
	var img_height = img.get_height()

	# Calculate grid from image dimensions
	var derived_columns = img_width / frame_width
	var derived_rows = img_height / frame_height
	var derived_total = derived_columns * derived_rows

	# Use caller-specified columns/frame_count if provided
	var columns: int = params.get("columns", derived_columns)
	var frame_count: int = params.get("frame_count", 0)
	var rows: int = derived_rows
	var total_frames: int = derived_total

	if columns != derived_columns:
		rows = ceili(float(derived_total) / columns) if columns > 0 else derived_rows
	if frame_count > 0:
		total_frames = frame_count
	else:
		total_frames = columns * rows

	# Check if dimensions divide evenly
	var warnings: Array = []
	if img_width % frame_width != 0:
		warnings.append("Image width %d is not evenly divisible by frame_width %d (remainder: %d)" % [img_width, frame_width, img_width % frame_width])
	if img_height % frame_height != 0:
		warnings.append("Image height %d is not evenly divisible by frame_height %d (remainder: %d)" % [img_height, frame_height, img_height % frame_height])

	# Validate caller-specified values against image
	if params.has("columns") and columns > derived_columns:
		warnings.append("Specified columns %d exceeds image capacity %d (image is %dpx wide, frame is %dpx)" % [columns, derived_columns, img_width, frame_width])
	if frame_count > 0 and frame_count > derived_total:
		warnings.append("Specified frame_count %d exceeds total frames in image %d (%d columns x %d rows)" % [frame_count, derived_total, derived_columns, derived_rows])

	# Analyze frame similarity — check if frames have consistent content
	# Compare average brightness/alpha of each frame
	var frame_stats: Array = []
	var empty_frames: Array = []

	var frames_scanned: int = 0
	for row in range(derived_rows):
		if frames_scanned >= total_frames:
			break
		for col in range(derived_columns):
			if frames_scanned >= total_frames:
				break
			var frame_idx = frames_scanned
			var x_start = col * frame_width
			var y_start = row * frame_height
			frames_scanned += 1

			# Sample pixels to check if frame has content
			var total_alpha: float = 0.0
			var total_brightness: float = 0.0
			var sample_count: int = 0
			var step = maxi(1, mini(frame_width, frame_height) / 8)

			for sy in range(y_start, mini(y_start + frame_height, img_height), step):
				for sx in range(x_start, mini(x_start + frame_width, img_width), step):
					var pixel = img.get_pixel(sx, sy)
					total_alpha += pixel.a
					total_brightness += (pixel.r + pixel.g + pixel.b) / 3.0
					sample_count += 1

			var avg_alpha = total_alpha / maxf(sample_count, 1)
			var avg_brightness = total_brightness / maxf(sample_count, 1)

			frame_stats.append({
				"frame": frame_idx,
				"avg_alpha": snappedf(avg_alpha, 0.01),
				"avg_brightness": snappedf(avg_brightness, 0.01),
			})

			if avg_alpha < 0.05:
				empty_frames.append(frame_idx)

	if not empty_frames.is_empty():
		warnings.append("Empty/transparent frames detected: %s" % str(empty_frames))

	var result: Dictionary = {
		"path": path,
		"image_size": [img_width, img_height],
		"frame_size": [frame_width, frame_height],
		"columns": columns,
		"rows": rows,
		"total_frames": total_frames,
		"valid": warnings.is_empty(),
		"suggested_frame_count": total_frames - empty_frames.size(),
	}
	if columns != derived_columns or total_frames != derived_total:
		result["derived_columns"] = derived_columns
		result["derived_rows"] = derived_rows
		result["derived_total_frames"] = derived_total
	if not warnings.is_empty():
		result["warnings"] = warnings
	if not empty_frames.is_empty():
		result["empty_frames"] = empty_frames
	# Only include detailed stats if there aren't too many frames
	if total_frames <= 64:
		result["frame_stats"] = frame_stats

	return result


func _set_import_param(content: String, param: String, value: String) -> String:
	var lines = content.split("\n")
	var found = false
	for i in range(lines.size()):
		if lines[i].begins_with(param + "="):
			lines[i] = param + "=" + value
			found = true
			break
	if not found:
		# Add to [params] section
		for i in range(lines.size()):
			if lines[i].begins_with("[params]"):
				lines.insert(i + 1, param + "=" + value)
				found = true
				break
		if not found:
			lines.append("[params]")
			lines.append(param + "=" + value)
	return "\n".join(lines)
