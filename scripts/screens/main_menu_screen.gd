## The first screen: the orbiting hall shows through a light tint, the
## wordmark sits on top with a ball for a full stop, and the buttons below
## it: New Run, Continue, Settings, Quit. Continue only appears when the
## Director found a save to resume.
class_name MainMenuScreen
extends UiScreen

const TINT_ALPHA := 0.3
const TITLE_SIZE := 118
const SUBTITLE_SIZE := 22
const FOOTER_SIZE := 14
const FOOTER_MARGIN := 18
const BALL_SIZE := 40
## The wordmark's ball bobs this far, this fast.
const BOB := 5.0
const BOB_RATE := 1.6

var _new_run: Button
var _ball: TextureRect
var _ball_rest := Vector2.ZERO
var _time := 0.0


## args: {"has_save": bool, "version": "0.1.0", "last_seed": int}
func setup(p_args: Dictionary) -> void:
	super(p_args)
	back_action = ""
	add_child(UiKit.dim(TINT_ALPHA))
	var box := UiKit.vbox(8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_wordmark())
	var tagline := UiKit.label("a turn-based ping pong deckbuilder", SUBTITLE_SIZE, Palette.PAPER)
	tagline.name = "Tagline"
	box.add_child(tagline)
	box.add_child(UiKit.spacer(22))
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
	var footer := UiKit.label(footer_text, FOOTER_SIZE, Palette.PAPER_DIM)
	footer.name = "Footer"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
	footer.grow_horizontal = GROW_DIRECTION_BEGIN
	footer.grow_vertical = GROW_DIRECTION_BEGIN
	footer.position -= Vector2(FOOTER_MARGIN, FOOTER_MARGIN)
	add_child(footer)
	var credit := UiKit.label("Lilita One and Rubik, both OFL", FOOTER_SIZE, Palette.PAPER_DIM)
	credit.name = "Credit"
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	credit.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT)
	credit.grow_vertical = GROW_DIRECTION_BEGIN
	credit.position += Vector2(FOOTER_MARGIN, -FOOTER_MARGIN)
	add_child(credit)


func first_focus() -> Control:
	return _new_run


## The ball on the wordmark bobs while the menu is up.
func _process(delta: float) -> void:
	if _ball == null:
		return
	_time += delta
	_ball.position = _ball_rest + Vector2(0.0, sin(_time * BOB_RATE * TAU * 0.5) * BOB)


## "PONPONG" with a ball sitting where the full stop would go.
func _wordmark() -> Control:
	var row := UiKit.hbox(6)
	row.name = "Wordmark"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var word := UiKit.title("PONPONG", TITLE_SIZE)
	word.name = "Title"
	row.add_child(word)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(BALL_SIZE, BALL_SIZE)
	holder.size_flags_vertical = SIZE_SHRINK_END
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	_ball = UiKit.icon(UiKit.ICON_BALL, BALL_SIZE, Palette.ORANGE)
	_ball.name = "Ball"
	_ball_rest = Vector2(0.0, -22.0)
	_ball.position = _ball_rest
	holder.add_child(_ball)
	var shadow := UiKit.icon(UiKit.ICON_BALL, BALL_SIZE, Palette.INK)
	shadow.name = "BallShadow"
	shadow.position = _ball_rest + Vector2(5.0, 5.0)
	holder.add_child(shadow)
	holder.move_child(shadow, 0)
	row.add_child(holder)
	return row


func _menu_button(box: VBoxContainer, text: String, action: String) -> Button:
	var b := UiKit.button(text)
	b.size_flags_horizontal = SIZE_SHRINK_CENTER
	_bind(b, action)
	box.add_child(b)
	return b
