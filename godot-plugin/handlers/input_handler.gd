@tool
class_name InputHandler
extends RefCounted

## Input Simulation tools (5):
## simulate_key, simulate_mouse_click, simulate_mouse_move,
## simulate_action, simulate_sequence
##
## When the game is running and the runtime bridge is connected,
## input commands are routed through the bridge for real game-side
## injection. Otherwise, falls back to editor-side Input.parse_input_event().

var _editor: EditorInterface
var _bridge  # BridgeServer — duck-typed to avoid class_name dependency


func _init(editor: EditorInterface, bridge = null):
	_editor = editor
	_bridge = bridge


func _is_runtime_available() -> bool:
	return _bridge != null and _editor.is_playing_scene() and _bridge.is_bridge_connected()


func get_commands() -> Dictionary:
	return {
		"simulate_key": simulate_key,
		"simulate_mouse_click": simulate_mouse_click,
		"simulate_mouse_move": simulate_mouse_move,
		"simulate_action": simulate_action,
		"simulate_sequence": simulate_sequence,
	}


func simulate_key(params: Dictionary) -> Dictionary:
	var key: String = params.get("key", "")
	if key == "":
		return {"error": "key parameter is required", "code": "MISSING_PARAM"}

	# Route through runtime bridge when game is running
	if _is_runtime_available():
		var result: Dictionary = await _bridge.send_command_await("bridge_simulate_key", params)
		return result

	# Editor-side fallback
	var pressed: bool = params.get("pressed", true)
	var shift: bool = params.get("shift", false)
	var ctrl: bool = params.get("ctrl", false)
	var alt: bool = params.get("alt", false)
	var meta: bool = params.get("meta", false)

	var keycode = _string_to_keycode(key)
	if keycode == KEY_NONE:
		return {"error": "Unknown key: %s" % key, "code": "INVALID_KEY"}

	var event = InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	event.meta_pressed = meta

	Input.parse_input_event(event)

	var duration: float = params.get("duration", 0.0)
	if duration > 0.0 and pressed:
		await Engine.get_main_loop().create_timer(duration).timeout
		var release = InputEventKey.new()
		release.keycode = keycode
		release.pressed = false
		Input.parse_input_event(release)
		return {"key": key, "pressed": true, "released": true, "duration": duration, "keycode": keycode, "target": "editor"}

	# If press+release is desired, send release immediately after
	if pressed and params.get("auto_release", false):
		var release = InputEventKey.new()
		release.keycode = keycode
		release.pressed = false
		release.shift_pressed = shift
		release.ctrl_pressed = ctrl
		release.alt_pressed = alt
		release.meta_pressed = meta
		Input.parse_input_event(release)

	return {"key": key, "pressed": pressed, "keycode": keycode, "target": "editor"}


func simulate_mouse_click(params: Dictionary) -> Dictionary:
	# Route through runtime bridge when game is running
	if _is_runtime_available():
		var result: Dictionary = await _bridge.send_command_await("bridge_simulate_mouse_click", params)
		return result

	# Editor-side fallback
	var x: float = params.get("x", 0.0)
	var y: float = params.get("y", 0.0)
	var button: int = params.get("button", MOUSE_BUTTON_LEFT)
	var double_click: bool = params.get("double_click", false)

	var event = InputEventMouseButton.new()
	event.position = Vector2(x, y)
	event.global_position = Vector2(x, y)
	event.button_index = button
	event.pressed = true
	event.double_click = double_click

	Input.parse_input_event(event)

	# Release
	var release = InputEventMouseButton.new()
	release.position = Vector2(x, y)
	release.global_position = Vector2(x, y)
	release.button_index = button
	release.pressed = false
	Input.parse_input_event(release)

	return {"x": x, "y": y, "button": button, "double_click": double_click, "target": "editor"}


func simulate_mouse_move(params: Dictionary) -> Dictionary:
	# Route through runtime bridge when game is running
	if _is_runtime_available():
		var result: Dictionary = await _bridge.send_command_await("bridge_simulate_mouse_move", params)
		return result

	# Editor-side fallback
	var x: float = params.get("x", 0.0)
	var y: float = params.get("y", 0.0)
	var relative_x: float = params.get("relative_x", 0.0)
	var relative_y: float = params.get("relative_y", 0.0)

	var event = InputEventMouseMotion.new()
	event.position = Vector2(x, y)
	event.global_position = Vector2(x, y)
	event.relative = Vector2(relative_x, relative_y)

	Input.parse_input_event(event)

	return {"x": x, "y": y, "relative": TypeParser.value_to_json(event.relative), "target": "editor"}


func simulate_action(params: Dictionary) -> Dictionary:
	var action_name: String = params.get("action", "")
	if action_name == "":
		return {"error": "action parameter is required", "code": "MISSING_PARAM"}

	# Route through runtime bridge when game is running
	if _is_runtime_available():
		var result: Dictionary = await _bridge.send_command_await("bridge_simulate_action", params)
		return result

	# Editor-side fallback
	var pressed: bool = params.get("pressed", true)
	var strength: float = params.get("strength", 1.0)
	var duration: float = params.get("duration", 0.0)

	if not InputMap.has_action(action_name):
		return {"error": "Action not found: %s" % action_name, "code": "ACTION_NOT_FOUND",
			"suggestions": ["Available actions: %s" % str(_get_action_list())]}

	var event = InputEventAction.new()
	event.action = action_name
	event.pressed = pressed
	event.strength = strength
	Input.parse_input_event(event)

	if duration > 0.0 and pressed:
		await Engine.get_main_loop().create_timer(duration).timeout
		var release = InputEventAction.new()
		release.action = action_name
		release.pressed = false
		Input.parse_input_event(release)
		return {"action": action_name, "pressed": true, "released": true, "duration": duration, "target": "editor"}

	return {"action": action_name, "pressed": pressed, "strength": strength, "target": "editor"}


func simulate_sequence(params: Dictionary) -> Dictionary:
	var steps: Array = params.get("steps", [])
	if steps.is_empty():
		return {"error": "steps array is required", "code": "MISSING_PARAM"}

	# Route entire sequence through bridge when game is running
	if _is_runtime_available():
		var result: Dictionary = await _bridge.send_command_await("bridge_simulate_sequence", params)
		return result

	# Editor-side fallback
	var results: Array = []
	for step in steps:
		var step_type: String = step.get("type", "")

		var result: Dictionary
		match step_type:
			"key":
				result = await simulate_key(step)
			"mouse_click":
				result = await simulate_mouse_click(step)
			"mouse_move":
				result = await simulate_mouse_move(step)
			"action":
				result = await simulate_action(step)
			"wait":
				var duration: float = step.get("duration", 0.1)
				await Engine.get_main_loop().create_timer(duration).timeout
				result = {"waited": duration}
			_:
				result = {"error": "Unknown step type: %s" % step_type}

		results.append(result)

	return {"steps_executed": results.size(), "results": results, "target": "editor"}


func _string_to_keycode(key_str: String) -> int:
	var upper = key_str.to_upper()
	var key_map := {
		"A": KEY_A, "B": KEY_B, "C": KEY_C, "D": KEY_D, "E": KEY_E,
		"F": KEY_F, "G": KEY_G, "H": KEY_H, "I": KEY_I, "J": KEY_J,
		"K": KEY_K, "L": KEY_L, "M": KEY_M, "N": KEY_N, "O": KEY_O,
		"P": KEY_P, "Q": KEY_Q, "R": KEY_R, "S": KEY_S, "T": KEY_T,
		"U": KEY_U, "V": KEY_V, "W": KEY_W, "X": KEY_X, "Y": KEY_Y,
		"Z": KEY_Z,
		"0": KEY_0, "1": KEY_1, "2": KEY_2, "3": KEY_3, "4": KEY_4,
		"5": KEY_5, "6": KEY_6, "7": KEY_7, "8": KEY_8, "9": KEY_9,
		"SPACE": KEY_SPACE, "ENTER": KEY_ENTER, "RETURN": KEY_ENTER,
		"ESCAPE": KEY_ESCAPE, "ESC": KEY_ESCAPE,
		"TAB": KEY_TAB, "BACKSPACE": KEY_BACKSPACE,
		"UP": KEY_UP, "DOWN": KEY_DOWN, "LEFT": KEY_LEFT, "RIGHT": KEY_RIGHT,
		"SHIFT": KEY_SHIFT, "CTRL": KEY_CTRL, "ALT": KEY_ALT,
		"F1": KEY_F1, "F2": KEY_F2, "F3": KEY_F3, "F4": KEY_F4,
		"F5": KEY_F5, "F6": KEY_F6, "F7": KEY_F7, "F8": KEY_F8,
		"F9": KEY_F9, "F10": KEY_F10, "F11": KEY_F11, "F12": KEY_F12,
		"DELETE": KEY_DELETE, "INSERT": KEY_INSERT,
		"HOME": KEY_HOME, "END": KEY_END,
		"PAGEUP": KEY_PAGEUP, "PAGEDOWN": KEY_PAGEDOWN,
	}
	return key_map.get(upper, KEY_NONE)


func _get_action_list() -> Array:
	var actions: Array = []
	for action in InputMap.get_actions():
		actions.append(str(action))
	return actions
