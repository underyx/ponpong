## The pause menu over a frozen match: Resume, Deck, Settings, Abandon Run.
## Abandon Run asks twice: the first press relabels the button, the second
## one fires. Esc or B resumes.
class_name PauseScreen
extends UiScreen

const TITLE_SIZE := 56
const ABANDON_TEXT := "Abandon Run"
const CONFIRM_TEXT := "Really abandon?"
## The last button over an online match: no run to abandon, just the table.
const LEAVE_TEXT := "Leave Match"
const LEAVE_CONFIRM_TEXT := "Really leave?"

var _resume: Button
var _abandon: Button
var _armed := false


## args: {"online": bool}  over an online match there is no deck to view and
## "abandon" leaves the match instead of a run.
func setup(p_args: Dictionary) -> void:
	super(p_args)
	back_action = "resume"
	add_child(UiKit.dim(0.5))
	var box := UiKit.vbox(10)
	box.add_child(UiKit.heading("PAUSED", TITLE_SIZE))
	box.add_child(UiKit.rule())
	box.add_child(UiKit.spacer(6))
	_resume = _menu_button(box, "Resume", "resume")
	if not _online():
		_menu_button(box, "Deck", "deck")
	_menu_button(box, "Settings", "settings")
	box.add_child(UiKit.spacer(2))
	_abandon = UiKit.button(LEAVE_TEXT if _online() else ABANDON_TEXT)
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
		_abandon.text = LEAVE_CONFIRM_TEXT if _online() else CONFIRM_TEXT
		_abandon.add_theme_stylebox_override("normal", UiKit.button_style(Palette.PINK, Palette.INK))
		_abandon.add_theme_stylebox_override("hover", UiKit.button_style(Palette.PINK.lightened(0.15), Palette.INK))
		_abandon.add_theme_color_override("font_color", Palette.PAPER)
		_abandon.add_theme_color_override("font_hover_color", Palette.PAPER)
		_abandon.add_theme_color_override("font_focus_color", Palette.PAPER)
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


func _online() -> bool:
	return bool(args.get("online", false))
