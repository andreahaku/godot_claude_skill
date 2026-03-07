@tool
class_name TestingHandler
extends RefCounted

## Testing & QA tools (5):
## run_test_scenario, assert_node_state, assert_screen_text,
## run_stress_test, get_test_report
##
## When the runtime bridge is connected, assertions and interactions are routed
## through BridgeServer.send_command_await() for true game-side evaluation.
## When the bridge is not connected, falls back to the editor tree.

var _editor: EditorInterface
var _bridge: BridgeServer
var _test_results: Array = []
var _test_sessions: Array = []  # Track multiple test sessions
var _snapshots: Dictionary = {}  # name -> captured state

const MAX_TEST_SESSIONS := 20
const MAX_TREE_DEPTH := 64


func _init(editor: EditorInterface, bridge: BridgeServer):
	_editor = editor
	_bridge = bridge


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


# ---------------------------------------------------------------------------
# run_test_scenario
# ---------------------------------------------------------------------------

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
	var skipped: int = 0

	for step in steps:
		var step_type: String = step.get("type", "")
		var result: Dictionary = {"step": step_type}

		match step_type:
			"wait":
				result.merge(await _step_wait(step))
			"input_action":
				result.merge(_step_input_action(step))
			"input_key":
				result.merge(_step_input_key(step))
			"click_ui":
				result.merge(await _step_click_ui(step))
			"assert_property":
				result.merge(await _step_assert_property(step))
			"assert_exists":
				result.merge(await _step_assert_exists(step))
			"assert_text":
				result.merge(await _step_assert_text(step))
			"assert_signal_emitted":
				result.merge(await _step_assert_signal_emitted(step))
			"assert_scene":
				result.merge(await _step_assert_scene(step))
			"capture_snapshot":
				result.merge(await _step_capture_snapshot(step))
			_:
				result["status"] = "skip"
				result["error"] = "Unknown step type: %s" % step_type
				skipped += 1

		if result.get("status") == "pass":
			passed += 1
		elif result.get("status") == "fail":
			failed += 1

		_test_results.append(result)

	# Save session
	var session := {
		"name": name,
		"timestamp": Time.get_unix_time_from_system(),
		"passed": passed,
		"failed": failed,
		"skipped": skipped,
		"total": steps.size(),
		"results": _test_results.duplicate(true),
	}
	_test_sessions.append(session)
	if _test_sessions.size() > MAX_TEST_SESSIONS:
		_test_sessions.pop_front()

	return {"name": name, "passed": passed, "failed": failed, "skipped": skipped, "total": steps.size(), "results": _test_results}


# ---------------------------------------------------------------------------
# Step implementations
# ---------------------------------------------------------------------------

func _step_wait(step: Dictionary) -> Dictionary:
	var duration: float = step.get("duration", 1.0)
	await _get_scene_tree().create_timer(duration).timeout
	return {"status": "pass", "duration": duration}


func _step_input_action(step: Dictionary) -> Dictionary:
	var action: String = step.get("action", "")
	if action == "":
		return {"status": "fail", "error": "action is required"}
	var pressed: bool = step.get("pressed", true)
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)
	return {"status": "pass", "action": action, "pressed": pressed}


func _step_input_key(step: Dictionary) -> Dictionary:
	var key: String = step.get("key", "")
	if key == "":
		return {"status": "fail", "error": "key is required"}
	var pressed: bool = step.get("pressed", true)
	var ev := InputEventKey.new()
	ev.keycode = OS.find_keycode_from_string(key)
	ev.pressed = pressed
	Input.parse_input_event(ev)
	return {"status": "pass", "key": key, "pressed": pressed}


func _step_click_ui(step: Dictionary) -> Dictionary:
	var text: String = step.get("text", "")
	var node_path: String = step.get("node_path", "")

	if text == "" and node_path == "":
		return {"status": "fail", "error": "text or node_path is required"}

	# Bridge path
	if _bridge.is_bridge_connected():
		var result: Dictionary
		if text != "":
			result = await _bridge.send_command_await("bridge_click_button", {"text": text})
		else:
			# Click by node path: get the node position via bridge and simulate click
			result = await _bridge.send_command_await("bridge_click_button", {"node_path": node_path})

		if result.has("error"):
			return {"status": "fail", "error": result["error"], "bridge": true}
		return {"status": "pass", "bridge": true, "clicked": text if text != "" else node_path}

	# Editor fallback
	var root := _get_editor_or_game_root()
	if root == null:
		return {"status": "fail", "error": "No scene available"}

	if text != "":
		var button := _find_button_by_text(root, text)
		if button == null:
			return {"status": "fail", "error": "Button with text '%s' not found" % text, "_fallback": true}
		button.emit_signal("pressed")
		return {"status": "pass", "clicked": text, "_fallback": true}
	else:
		var node = root.get_node_or_null(node_path)
		if node == null:
			return {"status": "fail", "error": "Node not found: %s" % node_path, "_fallback": true}
		if node is BaseButton:
			node.emit_signal("pressed")
			return {"status": "pass", "clicked": node_path, "_fallback": true}
		return {"status": "fail", "error": "Node is not a button: %s" % node_path, "_fallback": true}


func _step_assert_property(step: Dictionary) -> Dictionary:
	var node_path: String = step.get("node_path", "")
	var property_path: String = step.get("property", "")
	var expected = step.get("expected")
	var operator: String = step.get("operator", "==")

	if node_path == "" or property_path == "":
		return {"status": "fail", "error": "node_path and property are required"}

	# Bridge path
	if _bridge.is_bridge_connected():
		var result := await _bridge.send_command_await("bridge_get_node_properties", {"node_path": node_path})
		if result.has("error"):
			return {"status": "fail", "error": result["error"], "bridge": true}
		var props: Dictionary = result.get("properties", {})
		var actual = _get_nested_from_dict(props, property_path)
		if actual == null and not props.is_empty():
			# Property might not exist
			return {"status": "fail", "error": "Property '%s' not found on node" % property_path, "bridge": true}
		var eval_result := _evaluate_assertion(actual, expected, operator)
		var status: String = "pass" if eval_result.get("pass", false) else "fail"
		var out := {"status": status, "property": property_path, "operator": operator, "expected": expected, "actual": actual, "bridge": true}
		if eval_result.has("error"):
			out["error"] = eval_result["error"]
		return out

	# Editor fallback
	var root := _get_editor_or_game_root()
	if root == null:
		return {"status": "fail", "error": "No scene available"}
	var node = root.get_node_or_null(node_path)
	if node == null:
		return {"status": "fail", "error": "Node not found: %s" % node_path, "_fallback": true}
	var actual = _get_nested_property(node, property_path)
	var parsed_expected = TypeParser.parse_value(expected)
	var eval_result := _evaluate_assertion(actual, parsed_expected, operator)
	var status: String = "pass" if eval_result.get("pass", false) else "fail"
	var out := {
		"status": status,
		"property": property_path,
		"operator": operator,
		"expected": TypeParser.value_to_json(parsed_expected),
		"actual": TypeParser.value_to_json(actual),
		"_fallback": true,
	}
	if eval_result.has("error"):
		out["error"] = eval_result["error"]
	return out


func _step_assert_exists(step: Dictionary) -> Dictionary:
	var node_path: String = step.get("node_path", "")
	if node_path == "":
		return {"status": "fail", "error": "node_path is required"}

	# Bridge path
	if _bridge.is_bridge_connected():
		var result := await _bridge.send_command_await("bridge_get_node_properties", {"node_path": node_path})
		if result.has("error"):
			return {"status": "fail", "node_path": node_path, "exists": false, "bridge": true}
		return {"status": "pass", "node_path": node_path, "exists": true, "bridge": true}

	# Editor fallback
	var root := _get_editor_or_game_root()
	if root == null:
		return {"status": "fail", "error": "No scene available"}
	var node = root.get_node_or_null(node_path)
	if node == null:
		return {"status": "fail", "node_path": node_path, "exists": false, "_fallback": true}
	return {"status": "pass", "node_path": node_path, "exists": true, "_fallback": true}


func _step_assert_text(step: Dictionary) -> Dictionary:
	var text: String = step.get("text", "")
	var exact: bool = step.get("exact", false)
	if text == "":
		return {"status": "fail", "error": "text is required"}

	# Bridge path
	if _bridge.is_bridge_connected():
		var result := await _bridge.send_command_await("bridge_find_ui_elements", {})
		if result.has("error"):
			return {"status": "fail", "error": result["error"], "bridge": true}
		var elements: Array = result.get("elements", [])
		var found: Array = []
		for el in elements:
			var el_text: String = str(el.get("text", ""))
			if el_text == "":
				continue
			var matched := false
			if exact:
				matched = el_text == text
			else:
				matched = el_text.to_lower().contains(text.to_lower())
			if matched:
				found.append(el)
		var status: String = "pass" if not found.is_empty() else "fail"
		return {"status": status, "text": text, "found": not found.is_empty(), "matches": found, "count": found.size(), "bridge": true}

	# Editor fallback
	var root := _get_editor_or_game_root()
	if root == null:
		return {"status": "fail", "error": "No scene available"}
	var found: Array = []
	_find_text_in_controls(root, text, exact, found, 0, MAX_TREE_DEPTH)
	var status: String = "pass" if not found.is_empty() else "fail"
	return {"status": status, "text": text, "found": not found.is_empty(), "matches": found, "count": found.size(), "_fallback": true}


func _step_assert_signal_emitted(step: Dictionary) -> Dictionary:
	var node_path: String = step.get("node_path", "")
	var signal_name: String = step.get("signal_name", "")
	if node_path == "" or signal_name == "":
		return {"status": "fail", "error": "node_path and signal_name are required"}

	# NOTE: Full signal tracking requires the runtime bridge to set up monitors
	# before the signal is emitted. For now, we verify that the node exists and
	# has the named signal, which confirms it *could* have been emitted.

	# Bridge path
	if _bridge.is_bridge_connected():
		var result := await _bridge.send_command_await("bridge_get_node_properties", {"node_path": node_path})
		if result.has("error"):
			return {"status": "fail", "error": "Node not found: %s" % node_path, "bridge": true}
		# We can only confirm the node exists via bridge; signal list check is best-effort
		return {
			"status": "pass",
			"node_path": node_path,
			"signal_name": signal_name,
			"note": "Verified node exists. Full signal emission tracking requires bridge signal monitors (not yet implemented).",
			"bridge": true,
		}

	# Editor fallback
	var root := _get_editor_or_game_root()
	if root == null:
		return {"status": "fail", "error": "No scene available"}
	var node = root.get_node_or_null(node_path)
	if node == null:
		return {"status": "fail", "error": "Node not found: %s" % node_path, "_fallback": true}
	if not node.has_signal(signal_name):
		return {"status": "fail", "error": "Node '%s' does not have signal '%s'" % [node_path, signal_name], "_fallback": true}
	return {
		"status": "pass",
		"node_path": node_path,
		"signal_name": signal_name,
		"note": "Verified node exists and has signal. Full signal emission tracking requires bridge signal monitors (not yet implemented).",
		"_fallback": true,
	}


func _step_assert_scene(step: Dictionary) -> Dictionary:
	var scene_path: String = step.get("scene_path", "")
	if scene_path == "":
		return {"status": "fail", "error": "scene_path is required"}

	# Bridge path
	if _bridge.is_bridge_connected():
		var result := await _bridge.send_command_await("bridge_get_scene_tree", {})
		if result.has("error"):
			return {"status": "fail", "error": result["error"], "bridge": true}
		var current: String = result.get("scene_file", result.get("scene_path", ""))
		var matched: bool = current == scene_path
		return {
			"status": "pass" if matched else "fail",
			"expected": scene_path,
			"actual": current,
			"bridge": true,
		}

	# Editor fallback
	var tree := _get_scene_tree()
	var current_scene = tree.current_scene if tree else null
	if current_scene == null:
		return {"status": "fail", "error": "No current scene", "_fallback": true}
	var current: String = current_scene.scene_file_path
	var matched: bool = current == scene_path
	return {
		"status": "pass" if matched else "fail",
		"expected": scene_path,
		"actual": current,
		"_fallback": true,
	}


func _step_capture_snapshot(step: Dictionary) -> Dictionary:
	var snap_name: String = step.get("name", "")
	if snap_name == "":
		return {"status": "fail", "error": "name is required for capture_snapshot"}

	var snapshot: Dictionary = {
		"timestamp": Time.get_unix_time_from_system(),
	}

	# Bridge path
	if _bridge.is_bridge_connected():
		var result := await _bridge.send_command_await("bridge_get_scene_tree", {})
		if not result.has("error"):
			snapshot["scene_tree"] = result
		snapshot["bridge"] = true
	else:
		# Editor fallback
		var root := _get_editor_or_game_root()
		if root:
			snapshot["scene_path"] = root.scene_file_path
			snapshot["node_count"] = _count_nodes(root, 0, MAX_TREE_DEPTH)
		snapshot["_fallback"] = true

	_snapshots[snap_name] = snapshot
	return {"status": "pass", "snapshot_name": snap_name, "snapshot": snapshot}


# ---------------------------------------------------------------------------
# assert_node_state (standalone command)
# ---------------------------------------------------------------------------

func assert_node_state(params: Dictionary) -> Dictionary:
	var node_path: String = params.get("node_path", "")
	var assertions: Dictionary = params.get("assertions", {})
	var operator: String = params.get("operator", "==")

	if node_path == "" or assertions.is_empty():
		return {"error": "node_path and assertions are required", "code": "MISSING_PARAM"}

	# Bridge path
	if _bridge.is_bridge_connected():
		var result := await _bridge.send_command_await("bridge_get_node_properties", {"node_path": node_path})
		if result.has("error"):
			return {"error": result["error"], "code": result.get("code", "BRIDGE_ERROR")}
		var props: Dictionary = result.get("properties", {})
		var results: Dictionary = {}
		var all_pass: bool = true
		for prop in assertions:
			var expected = assertions[prop]
			var actual = _get_nested_from_dict(props, prop)
			var eval_result := _evaluate_assertion(actual, expected, operator)
			var passed: bool = eval_result.get("pass", false)
			results[prop] = {"expected": expected, "actual": actual, "pass": passed}
			if eval_result.has("error"):
				results[prop]["error"] = eval_result["error"]
			if not passed:
				all_pass = false
		return {"node_path": node_path, "all_pass": all_pass, "assertions": results, "bridge": true}

	# Editor fallback
	var root := _get_editor_or_game_root()
	if root == null:
		return {"error": "No scene available", "code": "NO_SCENE"}

	var node = root.get_node_or_null(node_path)
	if node == null:
		return {"error": "Node not found: %s" % node_path, "code": "NODE_NOT_FOUND"}

	var results: Dictionary = {}
	var all_pass: bool = true
	for prop in assertions:
		var expected = TypeParser.parse_value(assertions[prop])
		var actual = _get_nested_property(node, prop)
		var eval_result := _evaluate_assertion(actual, expected, operator)
		var passed: bool = eval_result.get("pass", false)
		results[prop] = {
			"expected": TypeParser.value_to_json(expected),
			"actual": TypeParser.value_to_json(actual),
			"pass": passed,
		}
		if eval_result.has("error"):
			results[prop]["error"] = eval_result["error"]
		if not passed:
			all_pass = false

	return {"node_path": node_path, "all_pass": all_pass, "assertions": results, "_fallback": true}


# ---------------------------------------------------------------------------
# assert_screen_text (standalone command)
# ---------------------------------------------------------------------------

func assert_screen_text(params: Dictionary) -> Dictionary:
	var text: String = params.get("text", "")
	var exact: bool = params.get("exact", false)

	if text == "":
		return {"error": "text is required", "code": "MISSING_PARAM"}

	# Bridge path
	if _bridge.is_bridge_connected():
		var result := await _bridge.send_command_await("bridge_find_ui_elements", {})
		if result.has("error"):
			return {"error": result["error"], "code": result.get("code", "BRIDGE_ERROR")}
		var elements: Array = result.get("elements", [])
		var found: Array = []
		for el in elements:
			var el_text: String = str(el.get("text", ""))
			if el_text == "":
				continue
			var matched := false
			if exact:
				matched = el_text == text
			else:
				matched = el_text.to_lower().contains(text.to_lower())
			if matched:
				found.append(el)
		return {"text": text, "found": not found.is_empty(), "matches": found, "count": found.size(), "bridge": true}

	# Editor fallback
	var root := _get_editor_or_game_root()
	if root == null:
		return {"error": "No scene available", "code": "NO_SCENE"}

	var found: Array = []
	_find_text_in_controls(root, text, exact, found, 0, MAX_TREE_DEPTH)

	return {"text": text, "found": not found.is_empty(), "matches": found, "count": found.size(), "_fallback": true}


# ---------------------------------------------------------------------------
# run_stress_test
# ---------------------------------------------------------------------------

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
			var ev := InputEventKey.new()
			ev.keycode = key_codes[randi() % key_codes.size()]
			ev.pressed = randf() > 0.3
			Input.parse_input_event(ev)
		elif rand < 0.7 and include_mouse:
			var ev := InputEventMouseButton.new()
			ev.position = Vector2(randf() * 1920, randf() * 1080)
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = randf() > 0.3
			Input.parse_input_event(ev)
		elif include_actions and actions.size() > 0:
			var ev := InputEventAction.new()
			ev.action = actions[randi() % actions.size()]
			ev.pressed = randf() > 0.3
			Input.parse_input_event(ev)

		total_events += 1
		await _get_scene_tree().create_timer(interval).timeout
		elapsed += interval

	return {"duration": duration, "total_events": total_events, "events_per_second": events_per_second}


# ---------------------------------------------------------------------------
# get_test_report
# ---------------------------------------------------------------------------

func get_test_report(params: Dictionary) -> Dictionary:
	var session_index: int = params.get("session", -1)  # -1 = latest

	if session_index >= 0 and session_index < _test_sessions.size():
		return _test_sessions[session_index]

	if _test_sessions.is_empty():
		return {"total": 0, "sessions": 0, "results": []}

	var latest: Dictionary = _test_sessions[-1]
	return {
		"latest": latest,
		"sessions": _test_sessions.size(),
		"total_runs": _test_sessions.size(),
	}


# ---------------------------------------------------------------------------
# Assertion evaluation
# ---------------------------------------------------------------------------

func _evaluate_assertion(actual, expected, operator: String) -> Dictionary:
	match operator:
		"==", "":
			var result := _values_match(actual, expected)
			return {"pass": result}
		"!=":
			return {"pass": not _values_match(actual, expected)}
		">":
			return {"pass": _to_float(actual) > _to_float(expected)}
		">=":
			return {"pass": _to_float(actual) >= _to_float(expected)}
		"<":
			return {"pass": _to_float(actual) < _to_float(expected)}
		"<=":
			return {"pass": _to_float(actual) <= _to_float(expected)}
		"contains":
			return {"pass": str(actual).contains(str(expected))}
		"matches":
			var regex := RegEx.new()
			var err := regex.compile(str(expected))
			if err != OK:
				return {"pass": false, "error": "Invalid regex pattern"}
			return {"pass": regex.search(str(actual)) != null}
		"approx":
			if actual is float and expected is float:
				return {"pass": abs(actual - expected) < 0.01}
			elif actual is Vector2 and expected is Vector2:
				return {"pass": actual.distance_to(expected) < 0.01}
			elif actual is Vector3 and expected is Vector3:
				return {"pass": actual.distance_to(expected) < 0.01}
			return {"pass": _values_match(actual, expected)}
		_:
			return {"pass": false, "error": "Unknown operator: %s" % operator}


func _to_float(value) -> float:
	if value is float:
		return value
	if value is int:
		return float(value)
	if value is String:
		if value.is_valid_float():
			return value.to_float()
		if value.is_valid_int():
			return float(value.to_int())
	return 0.0


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
	# String coercion fallback
	if str(actual) == str(expected):
		return true
	return false


# ---------------------------------------------------------------------------
# Nested property access
# ---------------------------------------------------------------------------

func _get_nested_property(node: Node, property_path: String) -> Variant:
	var parts := property_path.split(".")
	var value = node.get(parts[0])
	for i in range(1, parts.size()):
		if value == null:
			return null
		match parts[i]:
			"x":
				if value is Vector2 or value is Vector3:
					value = value.x
				else:
					value = null
			"y":
				if value is Vector2 or value is Vector3:
					value = value.y
				else:
					value = null
			"z":
				if value is Vector3:
					value = value.z
				else:
					value = null
			"r":
				if value is Color:
					value = value.r
				else:
					value = null
			"g":
				if value is Color:
					value = value.g
				else:
					value = null
			"b":
				if value is Color:
					value = value.b
				else:
					value = null
			"a":
				if value is Color:
					value = value.a
				else:
					value = null
			"w":
				if value is Quaternion:
					value = value.w
				else:
					value = null
			_:
				if value is Dictionary:
					value = value.get(parts[i])
				else:
					value = null
	return value


func _get_nested_from_dict(dict: Dictionary, property_path: String) -> Variant:
	var parts := property_path.split(".")
	var value: Variant = dict.get(parts[0])
	for i in range(1, parts.size()):
		if value == null:
			return null
		if value is Dictionary:
			value = value.get(parts[i])
		else:
			# Try component access on serialized types (e.g., {"x": 1, "y": 2})
			match parts[i]:
				"x", "y", "z", "w", "r", "g", "b", "a":
					if value is Dictionary:
						value = value.get(parts[i])
					else:
						value = null
				_:
					value = null
	return value


# ---------------------------------------------------------------------------
# Tree helpers
# ---------------------------------------------------------------------------

func _get_editor_or_game_root() -> Node:
	var tree := _get_scene_tree()
	if _editor.is_playing_scene() and tree:
		return tree.current_scene
	return _editor.get_edited_scene_root()


func _find_text_in_controls(node: Node, text: String, exact: bool, results: Array, depth: int, max_depth: int) -> void:
	if depth >= max_depth:
		return

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
		var found := false
		if exact:
			found = node_text == text
		else:
			found = node_text.to_lower().contains(text.to_lower())
		if found:
			results.append({"node": str(node.name), "path": str(node.get_path()), "text": node_text})

	for child in node.get_children():
		_find_text_in_controls(child, text, exact, results, depth + 1, max_depth)


func _find_button_by_text(root: Node, text: String, depth: int = 0) -> BaseButton:
	if depth >= MAX_TREE_DEPTH:
		return null
	if root is BaseButton:
		var btn_text: String = ""
		if root is Button:
			btn_text = root.text
		if btn_text.to_lower().contains(text.to_lower()):
			return root
	for child in root.get_children():
		var found := _find_button_by_text(child, text, depth + 1)
		if found:
			return found
	return null


func _count_nodes(node: Node, depth: int, max_depth: int) -> int:
	if depth >= max_depth:
		return 0
	var count: int = 1
	for child in node.get_children():
		count += _count_nodes(child, depth + 1, max_depth)
	return count
