@tool
class_name NodeFinder

## Shared node lookup utility used by all handlers.
## Centralizes the logic for finding nodes in the edited scene tree.

static func find(editor: EditorInterface, path: String) -> Node:
	var root = editor.get_edited_scene_root()
	if root == null:
		return null
	if path == "" or path == "." or path == root.name:
		return root
	return root.get_node_or_null(path)


static func get_root(editor: EditorInterface) -> Node:
	return editor.get_edited_scene_root()


static func require_root(editor: EditorInterface) -> Dictionary:
	if editor.get_edited_scene_root() == null:
		return {"error": "No scene is currently open", "code": "NO_SCENE"}
	return {}


static func require_node(editor: EditorInterface, path: String) -> Dictionary:
	var root = editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene is currently open", "code": "NO_SCENE"}
	var node = find(editor, path)
	if node == null:
		return {"error": "Node not found: %s" % path, "code": "NODE_NOT_FOUND"}
	return {}
