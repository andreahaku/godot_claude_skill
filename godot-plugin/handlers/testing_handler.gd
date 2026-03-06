class_name TestingHandler
extends RefCounted

## Testing & QA tools (5):
## run_test_scenario, assert_node_state, assert_screen_text,
## run_stress_test, get_test_report

var _editor: EditorInterface
var _test_results: Array = []


func _init(editor: EditorInterface):
	_editor = editor


func get_commands() -> Dictionary:
	return {
		"run_test_scenario": run_test_scenario,
		"assert_node_state": assert_node_state,
		"assert_screen_text": assert_screen_text,
		"run_stress_test": run_stress_test,
		"get_test_report": get_test_report,
	}


func _get_scene_tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func run_test_scenario(params: Dictionary) -> Dictionary:
	if not _editor.is_playing_scene():
		return {"error": "Game must be running. Use play_scene first.", "code": "NOT_PLAYING"}

	var name: String = params.get("name", "Test")
	var steps: Array = params.get("steps", [])
	if steps.is_empty():
		return {"error": "steps array is required", "code": "MISSING_PARAM"}

	_test_results.clear()
	var passed: int = 0
	var failed: int = 0

	for step in steps:
		var step_type: String = step.get("type", "")
		var result: Dictionary = {"step": step_type}

		match step_type:
			"wait":
				var duration: float = step.get("duration", 1.0)
				await _get_scene_tree().create_timer(duration).timeout
				result["status"] = "pass"
				passed += 1
			"assert_property":
				var node_path: String = step.get("node_path", "")
				var property: String = step.get("property", "")
				var expected = step.get("expected")
				var ar = _check_property(node_path, property, expected)
				result.merge(ar)
				if ar.get("status") == "pass":
					passed += 1
				else:
					failed += 1
			"input_action":
				var action: String = step.get("action", "")
				var pressed: bool = step.get("pressed", true)
				var ev = InputEventAction.new()
				ev.action = action
				ev.pressed = pressed
				Input.parse_input_event(ev)
				result["status"] = "pass"
				passed += 1
			"input_key":
				var key: String = step.get("key", "")
				var pressed: bool = step.get("pressed", true)
				var ev = InputEventKey.new()
				ev.keycode = OS.find_keycode_from_string(key)
				ev.pressed = pressed
				Input.parse_input_event(ev)
				result["status"] = "pass"
				passed += 1
			_:
				result["status"] = "skip"
				result["error"] = "Unknown step type"

		_test_results.append(result)

	return {"name": name, "passed": passed, "failed": failed, "total": steps.size(), "results": _test_results}


func assert_node_state(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var assertions: Dictionary = params.get("assertions", {})

	if node_path == "" or assertions.is_empty():
		return {"error": "node_path and assertions are required", "code": "MISSING_PARAM"}

	var tree = _get_scene_tree()
	var root = tree.current_scene if _editor.is_playing_scene() else _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene available", "code": "NO_SCENE"}

	var node = root.get_node_or_null(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var results: Dictionary = {}
	var all_pass: bool = true
	for prop in assertions:
		var expected = TypeParser.parse_value(assertions[prop])
		var actual = node.get(prop)
		var match_result = _values_match(actual, expected)
		results[prop] = {
			"expected": TypeParser.value_to_json(expected),
			"actual": TypeParser.value_to_json(actual),
			"pass": match_result,
		}
		if not match_result:
			all_pass = false

	return {"node_path": node_path, "all_pass": all_pass, "assertions": results}


func assert_screen_text(params: Dictionary) -> Dictionary:
	var text: String = params.get("text", "")
	var exact: bool = params.get("exact", false)

	if text == "":
		return {"error": "text is required", "code": "MISSING_PARAM"}

	var tree = _get_scene_tree()
	var root = tree.current_scene if _editor.is_playing_scene() else _editor.get_edited_scene_root()
	if root == null:
		return {"error": "No scene available", "code": "NO_SCENE"}

	var found: Array = []
	_find_text_in_controls(root, text, exact, found)

	return {
		"text": text,
		"found": not found.is_empty(),
		"matches": found,
		"count": found.size(),
	}


func run_stress_test(params: Dictionary) -> Dictionary:
	if not _editor.is_playing_scene():
		return {"error": "Game must be running", "code": "NOT_PLAYING"}

	var duration: float = params.get("duration", 5.0)
	var events_per_second: int = params.get("events_per_second", 10)
	var include_keys: bool = params.get("include_keys", true)
	var include_mouse: bool = params.get("include_mouse", true)
	var include_actions: bool = params.get("include_actions", true)

	var total_events: int = 0
	var elapsed: float = 0.0
	var interval: float = 1.0 / float(events_per_second)

	var key_codes = [KEY_A, KEY_D, KEY_W, KEY_S, KEY_SPACE, KEY_ENTER, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
	var actions = InputMap.get_actions()

	while elapsed < duration:
		var rand = randf()
		if rand < 0.4 and include_keys:
			var ev = InputEventKey.new()
			ev.keycode = key_codes[randi() % key_codes.size()]
			ev.pressed = randf() > 0.3
			Input.parse_input_event(ev)
		elif rand < 0.7 and include_mouse:
			var ev = InputEventMouseButton.new()
			ev.position = Vector2(randf() * 1920, randf() * 1080)
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = randf() > 0.3
			Input.parse_input_event(ev)
		elif include_actions and actions.size() > 0:
			var ev = InputEventAction.new()
			ev.action = actions[randi() % actions.size()]
			ev.pressed = randf() > 0.3
			Input.parse_input_event(ev)

		total_events += 1
		await _get_scene_tree().create_timer(interval).timeout
		elapsed += interval

	return {"duration": duration, "total_events": total_events, "events_per_second": events_per_second}


func get_test_report(params: Dictionary) -> Dictionary:
	var passed: int = 0
	var failed: int = 0
	var skipped: int = 0

	for r in _test_results:
		match r.get("status", ""):
			"pass":
				passed += 1
			"fail":
				failed += 1
			_:
				skipped += 1

	return {
		"total": _test_results.size(),
		"passed": passed,
		"failed": failed,
		"skipped": skipped,
		"results": _test_results,
	}


func _check_property(node_path: String, property: String, expected) -> Dictionary:
	var tree = _get_scene_tree()
	var node = tree.current_scene.get_node_or_null(node_path)
	if node == null:
		return {"status": "fail", "error": "Node not found: %s" % node_path}

	var actual = node.get(property)
	var exp = TypeParser.parse_value(expected)
	var match_result = _values_match(actual, exp)

	return {
		"status": "pass" if match_result else "fail",
		"property": property,
		"expected": TypeParser.value_to_json(exp),
		"actual": TypeParser.value_to_json(actual),
	}


func _values_match(actual, expected) -> bool:
	if actual == expected:
		return true
	# Approximate float comparison
	if actual is float and expected is float:
		return abs(actual - expected) < 0.001
	if actual is Vector2 and expected is Vector2:
		return actual.distance_to(expected) < 0.001
	if actual is Vector3 and expected is Vector3:
		return actual.distance_to(expected) < 0.001
	return false


func _find_text_in_controls(node: Node, text: String, exact: bool, results: Array) -> void:
	var node_text: String = ""
	if node is Label:
		node_text = node.text
	elif node is Button:
		node_text = node.text
	elif node is RichTextLabel:
		node_text = node.text
	elif node is LineEdit:
		node_text = node.text
	elif node is TextEdit:
		node_text = node.text

	if node_text != "":
		var found = false
		if exact:
			found = node_text == text
		else:
			found = node_text.to_lower().contains(text.to_lower())
		if found:
			results.append({"node": str(node.name), "path": str(node.get_path()), "text": node_text})

	for child in node.get_children():
		_find_text_in_controls(child, text, exact, results)
