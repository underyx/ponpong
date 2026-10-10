## The first screen: the orbiting table shows through a light tint, the title
## sits on top and the buttons below it: New Run, Continue, Settings, Quit.
## Continue only appears when the Director found a save to resume.
class_name MainMenuScreen
extends UiScreen

const TINT_ALPHA := 0.25
const TITLE_SIZE := 96
const SUBTITLE_SIZE := 22
const FOOTER_SIZE := 14
const FOOTER_MARGIN := 16

var _new_run: Button


## args: {"has_save": bool, "version": "0.1.0", "last_seed": int}
func setup(p_args: Dictionary) -> void:
	super(p_args)
	back_action = ""
	add_child(UiKit.dim(TINT_ALPHA))
	var box := UiKit.vbox(10)
	box.add_child(UiKit.title("PONPONG", TITLE_SIZE))
	box.add_child(UiKit.label("a turn-based ping pong deckbuilder", SUBTITLE_SIZE, UiKit.MUTED))
	box.add_child(_spacer(18))
	_new_run = _menu_button(box, "New Run", "new_run")
	if bool(args.get("has_save", false)):
		_menu_button(box, "Continue", "continue")
	_menu_button(box, "Settings", "settings")
	_menu_button(box, "Quit", "quit")
	add_child(UiKit.center(box))
	var seed_value := int(args.get("last_seed", -1))
	var footer_text := "v%s" % String(args.get("version", ""))
	if seed_value >= 0:
		footer_text += "   ·   last seed %d" % seed_value
	var footer := UiKit.label(footer_text, FOOTER_SIZE, UiKit.MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
	footer.grow_horizontal = GROW_DIRECTION_BEGIN
	footer.grow_vertical = GROW_DIRECTION_BEGIN
	footer.position -= Vector2(FOOTER_MARGIN, FOOTER_MARGIN)
	add_child(footer)


func first_focus() -> Control:
	return _new_run


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
