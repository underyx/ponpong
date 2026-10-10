## Base class of every full-screen menu the Director shows. A screen builds
## its whole tree in setup() from UiKit parts, binds each button to an action
## name with _bind(), and reports every choice through `done`. press() is the
## one way a choice leaves the screen, so a test can drive a screen by name
## without a mouse. Nothing happens in _ready: a screen is complete, and can be
## inspected, before it enters the tree.
class_name UiScreen
extends Control

## An action the player took, by name, with whatever it needs (a picked index).
signal done(action: String, data: Dictionary)

## What setup() was given; screens read it when they build and when they act.
var args: Dictionary = {}
## The action ui_cancel (Esc, gamepad B) presses; "" when there is no way back.
var back_action := ""


## Builds the screen from `p_args`. Subclasses call super first, then add
## their tree under self.
func setup(p_args: Dictionary) -> void:
	args = p_args
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)


## The control that gets focus when the screen opens: the first visible,
## focusable one in tree order unless a subclass prefers another.
func first_focus() -> Control:
	return _find_focusable(self)


## Takes `action` as if its button had been pressed.
func press(action: String, data: Dictionary = {}) -> void:
	done.emit(action, data)


## The Director took `action`: it was not a click during a fade or a
## superseded screen. A screen that wants to show the choice (the reward
## card lifting) does it here, so nothing moves for a choice that was
## dropped. The base does nothing.
func on_accepted(_action: String, _data: Dictionary) -> void:
	pass


## Routes `button` to press(action).
func _bind(button: Button, action: String) -> void:
	button.pressed.connect(press.bind(action))


func _unhandled_input(event: InputEvent) -> void:
	if back_action != "" and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		press(back_action)


## Depth-first: a control that takes focus, is visible and is not a disabled
## button, or null when the screen has none.
static func _find_focusable(node: Node) -> Control:
	for child in node.get_children():
		if child is Control:
			var c := child as Control
			var usable := c.visible and c.focus_mode == Control.FOCUS_ALL
			if usable and c is BaseButton:
				usable = not (c as BaseButton).disabled
			if usable:
				return c
		var deeper := _find_focusable(child)
		if deeper != null:
			return deeper
	return null
