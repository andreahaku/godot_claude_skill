@tool
class_name NodeFinder

## Shared node lookup utility used by all handlers.
## Centralizes the logic for finding nodes in the edited scene tree.
## Supports unique name lookup (%Name), type-qualified paths (Path:Type),
## and fuzzy suggestion matching when nodes aren't found.

static func find(editor: EditorInterface, path: String) -> Node:
	var root = editor.get_edited_scene_root()
	if root == null:
		return null
	if path == "" or path == "." or path == root.name:
		return root

	# Support % prefix for unique name lookup
	if path.begins_with("%"):
		var unique_name := path.substr(1)
		return _find_unique_name(root, unique_name)

	# Support type-qualified paths: "Player:CharacterBody2D"
	var type_filter := ""
	if ":" in path and not path.begins_with("res://"):
		var parts := path.split(":")
		path = parts[0]
		type_filter = parts[1]

	var node = root.get_node_or_null(path)

	# Type validation if specified
	if node != null and type_filter != "":
		if not node.is_class(type_filter) and node.get_class() != type_filter:
			return null  # Type mismatch

	return node


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
		var suggestions := find_suggestions(editor, path)
		var suggestion_paths: Array = []
		for s in suggestions:
			suggestion_paths.append(s.path)

		var result: Dictionary = {"error": "Node not found: %s" % path, "code": "NODE_NOT_FOUND"}
		if not suggestion_paths.is_empty():
			result["suggestions"] = suggestion_paths

			# Add available children of the closest parent
			var parent_path := path.get_base_dir() if "/" in path else ""
			var parent := find(editor, parent_path)
			if parent:
				var children: Array = []
				for child in parent.get_children():
					children.append(str(child.name))
				result["available_children"] = children

				# Edit distance hint
				var last_part := path.get_file()
				for child_name in children:
					if _similarity_score(last_part, child_name) >= 60:
						result["hint"] = "Did you mean '%s'?" % child_name
						break

		return result
	return {}


## Normalize a resource path — ensures it starts with "res://".
static func normalize_res_path(path: String) -> String:
	if not path.begins_with("res://"):
		return "res://" + path
	return path


## Find suggestions for a path that wasn't found.
## Returns an array of {path: String, name: String, type: String, score: int}
static func find_suggestions(editor: EditorInterface, failed_path: String, max_suggestions: int = 5) -> Array:
	var root = editor.get_edited_scene_root()
	if root == null:
		return []

	var all_nodes: Array = []
	_collect_node_paths(root, root, all_nodes)

	var failed_name := failed_path.get_file()  # Last component of path
	if failed_name == "":
		failed_name = failed_path

	# Score each node by similarity
	var scored: Array = []
	for info in all_nodes:
		var score := _similarity_score(failed_name, info.name)
		# Also check against full path
		var path_score := _similarity_score(failed_path, info.path)
		score = max(score, path_score)
		if score > 0:
			info["score"] = score
			scored.append(info)

	# Sort by score descending
	scored.sort_custom(func(a, b): return a.score > b.score)

	return scored.slice(0, max_suggestions)


## Return children names at a given path (useful for error context)
static func get_children_at(editor: EditorInterface, path: String) -> Array:
	var node := find(editor, path)
	if node == null:
		return []
	var children: Array = []
	for child in node.get_children():
		children.append(str(child.name))
	return children


## Calculate similarity score (higher = more similar).
## Uses: exact match, substring, prefix match, character overlap.
static func _similarity_score(query: String, candidate: String) -> int:
	var q := query.to_lower()
	var c := candidate.to_lower()

	if q == c:
		return 100  # Exact match
	if c.contains(q):
		return 80  # Substring match
	if q.contains(c):
		return 70
	if c.begins_with(q) or q.begins_with(c):
		return 60  # Prefix match

	# Simple edit distance approximation
	# Count matching characters
	var matches := 0
	for ch in q:
		if ch in c:
			matches += 1

	var ratio := float(matches) / float(max(q.length(), 1))
	if ratio > 0.5:
		return int(ratio * 50)

	return 0


static func _collect_node_paths(node: Node, scene_root: Node, results: Array, depth: int = 0, max_depth: int = 64) -> void:
	results.append({
		"name": str(node.name),
		"path": str(scene_root.get_path_to(node)),
		"type": node.get_class(),
	})
	if depth >= max_depth:
		return
	for child in node.get_children():
		_collect_node_paths(child, scene_root, results, depth + 1, max_depth)


static func _find_unique_name(node: Node, unique_name: String) -> Node:
	if str(node.name) == unique_name and node.unique_name_in_owner:
		return node
	# Also match by name even without unique flag, as a fallback
	for child in node.get_children():
		var found := _find_unique_name(child, unique_name)
		if found:
			return found
	# Final fallback: match by name without unique flag
	if str(node.name) == unique_name:
		return node
	return null
