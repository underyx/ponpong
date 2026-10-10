## Registers the game's input actions at runtime, so project.godot never has
## to carry hand-written InputMap entries. Godot's built-in ui_accept,
## ui_cancel and ui_left/right/up/down already carry Enter, Space, Esc, the
## arrows, the d-pad, the left stick and the A and B buttons; this adds the
## match actions, the pause and fullscreen keys, and WASD on the ui_* set so
## menus and the zone cursor take them too.
class_name InputSetup
extends RefCounted

## Joypad deadzone for the actions registered here.
const DEADZONE := 0.5

const WASD := {"ui_up": KEY_W, "ui_left": KEY_A, "ui_down": KEY_S, "ui_right": KEY_D}


## Idempotent: the first call registers everything, later calls return at once.
static func register() -> void:
	if InputMap.has_action("pause"):
		return
	_add("pause", [_key(KEY_ESCAPE), _joy(JOY_BUTTON_START)])
	_add("aim_back", [_key(KEY_BACKSPACE), _joy(JOY_BUTTON_B), _mouse(MOUSE_BUTTON_RIGHT)])
	_add("card_prev", [_key(KEY_Q), _joy(JOY_BUTTON_LEFT_SHOULDER)])
	_add("card_next", [_key(KEY_E), _joy(JOY_BUTTON_RIGHT_SHOULDER)])
	_add("card_1", [_key(KEY_1)])
	_add("card_2", [_key(KEY_2)])
	_add("card_3", [_key(KEY_3)])
	_add("card_4", [_key(KEY_4)])
	_add("fullscreen", [_key(KEY_F11)])
	for action in WASD:
		if InputMap.has_action(action):
			InputMap.action_add_event(action, _key(WASD[action]))


## The index of the card_N action an event is pressing, or -1.
static func card_index(event: InputEvent) -> int:
	for i in 4:
		if event.is_action_pressed("card_%d" % (i + 1)):
			return i
	return -1


static func _add(action: String, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEADZONE)
	for e in events:
		InputMap.action_add_event(action, e)


## Physical keys, so WASD is where the hand expects it on any layout.
static func _key(keycode: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = keycode
	return e


static func _joy(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


static func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e
