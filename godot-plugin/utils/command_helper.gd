@tool
class_name CommandHelper

## Centralized validation utilities to reduce boilerplate in command handlers.
## Provides common param validation, node lookup with error context,
## and path normalization.

## Validate that all required params are present and non-empty.
## Returns empty dict on success, error dict on failure.
static func require_params(params: Dictionary, required: Array) -> Dictionary:
	for key in required:
		if not params.has(key) or str(params[key]) == "":
			return {
				"error": "%s is required" % key,
				"code": "MISSING_PARAM",
				"suggestions": ["Required parameters: %s" % ", ".join(required)],
			}
	return {}


## Get a node from the scene tree, or return an error dict with suggestions.
## Returns the Node on success, or a Dictionary with error info on failure.
static func get_node_or_error(editor: EditorInterface, path: String) -> Variant:
	var root = editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open", "code": "NO_SCENE"}
	var node = NodeFinder.find(editor, path)
	if node == null:
		return NodeFinder.require_node(editor, path)  # Returns error dict with suggestions
	return node


## Get the scene root or return an error dict.
static func get_scene_root_or_error(editor: EditorInterface) -> Variant:
	var root = editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open", "code": "NO_SCENE"}
	return root


## Normalize a resource path (ensure res:// prefix).
static func normalize_path(path: String, extension: String = "") -> String:
	if not path.begins_with("res://"):
		path = "res://" + path
	if extension != "" and not path.ends_with(extension):
		path += extension
	return path


## Check if a resource exists, returning an error dict if not.
static func require_resource(path: String) -> Dictionary:
	var norm := normalize_path(path)
	if not ResourceLoader.exists(norm):
		return {"error": "Resource not found: %s" % norm, "code": "FILE_NOT_FOUND"}
	return {}


## Get a node, with a specific parent path and optional type validation.
## Returns the Node on success, or a Dictionary with error info.
static func get_child_node_or_error(editor: EditorInterface, parent_path: String, child_name: String = "") -> Variant:
	var root = editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open", "code": "NO_SCENE"}

	var parent = NodeFinder.find(editor, parent_path) if parent_path != "" else root
	if parent == null:
		return NodeFinder.require_node(editor, parent_path)

	if child_name != "":
		var child = parent.get_node_or_null(child_name)
		if child == null:
			var children: Array = []
			for c in parent.get_children():
				children.append(str(c.name))
			return {
				"error": "Child node not found: %s in %s" % [child_name, parent_path],
				"code": "NODE_NOT_FOUND",
				"available_children": children,
			}
		return child

	return parent
