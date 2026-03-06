@tool
class_name TileMapHandler
extends RefCounted

## TileMap tools (6):
## tilemap_set_cell, tilemap_fill_rect, tilemap_get_cell,
## tilemap_clear, tilemap_get_info, tilemap_get_used_cells

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
