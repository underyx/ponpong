## The pause menu over a frozen match: Resume, Deck, Settings, Abandon Run.
## Abandon Run asks twice: the first press relabels the button, the second
## one fires. Esc or B resumes.
class_name PauseScreen
extends UiScreen

const TITLE_SIZE := 56
const ABANDON_TEXT := "Abandon Run"
const CONFIRM_TEXT := "Really abandon?"

var _resume: Button
var _abandon: Button
var _armed := false


## args: {}
func setup(p_args: Dictionary) -> void:
	super(p_args)
	back_action = "resume"
	add_child(UiKit.dim(0.55))
	var box := UiKit.vbox(10)
	box.add_child(UiKit.title("PAUSED", TITLE_SIZE))
	box.add_child(_spacer(8))
	_resume = _menu_button(box, "Resume", "resume")
	_menu_button(box, "Deck", "deck")
	_menu_button(box, "Settings", "settings")
	_abandon = UiKit.button(ABANDON_TEXT)
	_abandon.size_flags_horizontal = SIZE_SHRINK_CENTER
	_abandon.pressed.connect(_on_abandon_pressed)
	box.add_child(_abandon)
	var panel := UiKit.panel()
	panel.add_child(box)
	add_child(UiKit.center(panel))


func first_focus() -> Control:
	return _resume


## Pressing "abandon" from outside (tests) skips the confirmation on purpose:
## press() is the action, the two-step guard is for fingers.
func _on_abandon_pressed() -> void:
	if not _armed:
		_armed = true
		_abandon.text = CONFIRM_TEXT
		_abandon.add_theme_color_override("font_color", UiKit.DANGER)
		# Arming is not an action the Director hears, so it clicks here.
		Sfx.play("ui_accept")
		return
	press("abandon")


func _menu_button(box: VBoxContainer, text: String, action: String) -> Button:
	var b := UiKit.button(text)
	b.size_flags_horizontal = SIZE_SHRINK_CENTER
	_bind(b, action)
	box.add_child(b)
	return b


static func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = MOUSE_FILTER_IGNORE
	return c
