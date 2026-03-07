@tool
class_name TileMapHandler
extends RefCounted

## TileMap tools (8):
## tilemap_set_cell, tilemap_fill_rect, tilemap_get_cell,
## tilemap_clear, tilemap_get_info, tilemap_get_used_cells,
## create_tileset_from_image, tilemap_set_tileset

var _editor: EditorInterface
var _undo: UndoHelper


func _init(editor: EditorInterface, undo: UndoHelper):
	_editor = editor
	_undo = undo


func get_commands() -> Dictionary:
	return {
		"tilemap_set_cell": tilemap_set_cell,
		"tilemap_fill_rect": tilemap_fill_rect,
		"tilemap_get_cell": tilemap_get_cell,
		"tilemap_clear": tilemap_clear,
		"tilemap_get_info": tilemap_get_info,
		"tilemap_get_used_cells": tilemap_get_used_cells,
		"create_tileset_from_image": create_tileset_from_image,
		"tilemap_set_tileset": tilemap_set_tileset,
	}


func _get_tilemap(node_path: String) -> TileMapLayer:
	var node = NodeFinder.find(_editor, node_path)
	if node is TileMapLayer:
		return node
	return null


func tilemap_set_cell(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var x: int = params.get("x", 0)
	var y: int = params.get("y", 0)
	var source_id: int = params.get("source_id", 0)
	var atlas_x: int = params.get("atlas_x", 0)
	var atlas_y: int = params.get("atlas_y", 0)
	var alternative: int = params.get("alternative", 0)

	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var tm = _get_tilemap(node_path)
	if tm == null:
		return {"error": "TileMapLayer not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var pos = Vector2i(x, y)
	var old_source = tm.get_cell_source_id(pos)
	var old_atlas = tm.get_cell_atlas_coords(pos)
	var old_alt = tm.get_cell_alternative_tile(pos)

	_undo.create_action("Set TileMap Cell (%d, %d)" % [x, y])
	_undo.add_do_method(tm, &"set_cell", [pos, source_id, Vector2i(atlas_x, atlas_y), alternative])
	_undo.add_undo_method(tm, &"set_cell", [pos, old_source, old_atlas, old_alt])
	_undo.commit_action()
	return {"x": x, "y": y, "source_id": source_id, "atlas": [atlas_x, atlas_y]}


func tilemap_fill_rect(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var x1: int = params.get("x1", 0)
	var y1: int = params.get("y1", 0)
	var x2: int = params.get("x2", 0)
	var y2: int = params.get("y2", 0)
	var source_id: int = params.get("source_id", 0)
	var atlas_x: int = params.get("atlas_x", 0)
	var atlas_y: int = params.get("atlas_y", 0)

	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var tm = _get_tilemap(node_path)
	if tm == null:
		return {"error": "TileMapLayer not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	# Save old cells for undo
	var old_cells: Array = []
	for x in range(min(x1, x2), max(x1, x2) + 1):
		for y in range(min(y1, y2), max(y1, y2) + 1):
			var pos = Vector2i(x, y)
			old_cells.append([pos, tm.get_cell_source_id(pos), tm.get_cell_atlas_coords(pos), tm.get_cell_alternative_tile(pos)])

	_undo.create_action("Fill TileMap Rect")
	for cell in old_cells:
		var pos: Vector2i = cell[0]
		_undo.add_do_method(tm, &"set_cell", [pos, source_id, Vector2i(atlas_x, atlas_y)])
		_undo.add_undo_method(tm, &"set_cell", [pos, cell[1], cell[2], cell[3]])
	_undo.commit_action()

	return {"filled": old_cells.size(), "rect": [x1, y1, x2, y2]}


func tilemap_get_cell(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var x: int = params.get("x", 0)
	var y: int = params.get("y", 0)

	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var tm = _get_tilemap(node_path)
	if tm == null:
		return {"error": "TileMapLayer not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var source_id = tm.get_cell_source_id(Vector2i(x, y))
	var atlas_coords = tm.get_cell_atlas_coords(Vector2i(x, y))
	var alt = tm.get_cell_alternative_tile(Vector2i(x, y))

	return {"x": x, "y": y, "source_id": source_id, "atlas_coords": TypeParser.value_to_json(atlas_coords), "alternative": alt}


func tilemap_clear(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")

	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var tm = _get_tilemap(node_path)
	if tm == null:
		return {"error": "TileMapLayer not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	# Save all cells for undo
	var used_cells = tm.get_used_cells()
	var old_cells: Array = []
	for pos in used_cells:
		old_cells.append([pos, tm.get_cell_source_id(pos), tm.get_cell_atlas_coords(pos), tm.get_cell_alternative_tile(pos)])

	_undo.create_action("Clear TileMap")
	_undo.add_do_method(tm, &"clear", [])
	for cell in old_cells:
		_undo.add_undo_method(tm, &"set_cell", [cell[0], cell[1], cell[2], cell[3]])
	_undo.commit_action()
	return {"cleared": true, "cells_removed": old_cells.size()}


func tilemap_get_info(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")

	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var tm = _get_tilemap(node_path)
	if tm == null:
		return {"error": "TileMapLayer not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var tile_set = tm.tile_set
	var info: Dictionary = {
		"node_path": node_path,
		"used_cells": tm.get_used_cells().size(),
	}

	if tile_set:
		info["tile_size"] = TypeParser.value_to_json(tile_set.tile_size)
		info["sources_count"] = tile_set.get_source_count()
		var sources: Array = []
		for i in range(tile_set.get_source_count()):
			var source_id = tile_set.get_source_id(i)
			var source = tile_set.get_source(source_id)
			sources.append({"id": source_id, "type": source.get_class()})
		info["sources"] = sources

	return info


func tilemap_get_used_cells(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")

	if node_path == "":
		return {"error": "node_path is required", "code": "MISSING_PARAM"}

	var tm = _get_tilemap(node_path)
	if tm == null:
		return {"error": "TileMapLayer not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var cells: Array = []
	for cell in tm.get_used_cells():
		cells.append({"x": cell.x, "y": cell.y})

	return {"cells": cells, "count": cells.size()}


func tilemap_set_tileset(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var tileset_path: String = params.get("tileset_path", "")

	if node_path == "" or tileset_path == "":
		return {"error": "node_path and tileset_path are required", "code": "MISSING_PARAM"}

	if not tileset_path.begins_with("res://"):
		tileset_path = "res://" + tileset_path

	var tm = _get_tilemap(node_path)
	if tm == null:
		return {"error": "TileMapLayer not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	if not ResourceLoader.exists(tileset_path):
		return {"error": "TileSet not found: %s" % tileset_path, "code": "FILE_NOT_FOUND"}

	var tileset = load(tileset_path) as TileSet
	if tileset == null:
		return {"error": "Failed to load TileSet: %s" % tileset_path, "code": "LOAD_ERROR"}

	var old_tileset = tm.tile_set
	_undo.create_action("Set TileMap TileSet: %s" % tm.name)
	_undo.add_do_property(tm, &"tile_set", tileset)
	_undo.add_undo_property(tm, &"tile_set", old_tileset)
	_undo.commit_action()

	return {
		"node_path": node_path,
		"tileset_path": tileset_path,
		"tile_size": TypeParser.value_to_json(tileset.tile_size),
		"sources_count": tileset.get_source_count(),
	}


func create_tileset_from_image(params: Dictionary) -> Dictionary:
	var image_path: String = params.get("image_path", "")
	var tile_size: int = params.get("tile_size", 16)
	var tile_width: int = params.get("tile_width", tile_size)
	var tile_height: int = params.get("tile_height", tile_size)
	var save_path: String = params.get("save_path", "")
	var margin: int = params.get("margin", 0)
	var separation: int = params.get("separation", 0)

	if image_path == "":
		return {"error": "image_path is required", "code": "MISSING_PARAM"}
	if not image_path.begins_with("res://"):
		image_path = "res://" + image_path
	if save_path == "":
		save_path = image_path.get_basename() + ".tres"
	elif not save_path.begins_with("res://"):
		save_path = "res://" + save_path
	if not save_path.ends_with(".tres"):
		save_path += ".tres"

	# Ensure file is imported
	_editor.get_resource_filesystem().scan()

	if not ResourceLoader.exists(image_path):
		return {"error": "Image not found: %s" % image_path, "code": "FILE_NOT_FOUND"}

	var texture = load(image_path) as Texture2D
	if texture == null:
		return {"error": "Cannot load as texture: %s" % image_path, "code": "LOAD_ERROR"}

	var img_width = texture.get_width()
	var img_height = texture.get_height()

	# Create TileSet
	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(tile_width, tile_height)

	# Add the texture as a TileSetAtlasSource
	var atlas_source = TileSetAtlasSource.new()
	atlas_source.texture = texture
	atlas_source.texture_region_size = Vector2i(tile_width, tile_height)
	atlas_source.margins = Vector2i(margin, margin)
	atlas_source.separation = Vector2i(separation, separation)

	# Calculate grid dimensions
	var usable_width = img_width - 2 * margin
	var usable_height = img_height - 2 * margin
	var columns = usable_width / (tile_width + separation)
	var rows = usable_height / (tile_height + separation)

	# Create tiles for each grid cell
	var tile_count := 0
	for row in range(rows):
		for col in range(columns):
			atlas_source.create_tile(Vector2i(col, row))
			tile_count += 1

	var source_id = tileset.add_source(atlas_source)

	# Save the TileSet resource
	var dir_path = save_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
	var err = ResourceSaver.save(tileset, save_path)
	if err != OK:
		return {"error": "Failed to save TileSet: %s" % error_string(err), "code": "SAVE_ERROR"}

	_editor.get_resource_filesystem().scan()

	return {
		"save_path": save_path,
		"source_image": image_path,
		"tile_size": [tile_width, tile_height],
		"columns": columns,
		"rows": rows,
		"tile_count": tile_count,
		"source_id": source_id,
	}
