## Shown when a match ends: the result, the score, both players' numbers in
## a two-column table and what the run does next (a reward, a lost heart,
## or the end of the run). On a loss the heart that was just lost is still
## lit when the screen opens, then shakes, sounds and greys out.
class_name MatchEndScreen
extends UiScreen

const TITLE_SIZE := 64
const SCORE_SIZE := 48
const STAT_SIZE := 18
const HEART_SIZE := 26
## The lost heart holds this long before it shakes and goes out.
const HEART_DELAY := 0.4
const HEART_SHAKE_PX := 3.0
const HEART_SHAKES := 3
const HEART_SHAKE_STEP := 0.04
## Trauma handed to the match camera under the panel when the heart goes.
const HEART_CAMERA_SHAKE := 0.6
const STATS := [["Winners", "winners"], ["Faults", "faults"], ["Tired plays", "tired_plays"]]

var _continue: Button
var _hearts: HBoxContainer
## Hearts left after this match, when it was lost.
var _hearts_left := 0
var _heart_tween: Tween


## args: {"won": bool, "score": [a, b], "hearts": int, "stats": [p0, p1],
##        "longest_rally": int, "run_over": bool}
func setup(p_args: Dictionary) -> void:
	super(p_args)
	back_action = ""
	add_child(UiKit.dim(0.5))
	var won := bool(args.get("won", false))
	var score: Array = args.get("score", [0, 0])
	var stats: Array = args.get("stats", [{}, {}])
	var run_over := bool(args.get("run_over", false))
	var hearts := int(args.get("hearts", 0))

	var box := UiKit.vbox(6)
	box.add_child(UiKit.heading("YOU WIN" if won else "YOU LOSE", TITLE_SIZE, Palette.TEAL if won else Palette.PINK))
	box.add_child(UiKit.rule())
	box.add_child(UiKit.heading("%d  –  %d" % [int(score[0]), int(score[1])], SCORE_SIZE))
	box.add_child(UiKit.spacer(4))
	box.add_child(_stats_table(stats, int(args.get("longest_rally", 0))))
	box.add_child(UiKit.spacer(4))
	if won:
		box.add_child(UiKit.chip("You are the champion" if run_over else "Next: reward", UiKit.ICON_BALL,
			Palette.TEAL, Palette.PAPER, 14))
	else:
		box.add_child(UiKit.chip("Run over" if run_over else "Heart lost", UiKit.ICON_HEART, Palette.PINK, Palette.PAPER, 14))
		# One more heart lit than the run has left: the one about to go.
		_hearts_left = clampi(hearts, 0, RunState.HEARTS - 1)
		_hearts = UiKit.hearts(RunState.HEARTS, _hearts_left + 1, HEART_SIZE)
		_hearts.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_child(_hearts)
	for chip in box.get_children():
		if chip is PanelContainer:
			chip.size_flags_horizontal = SIZE_SHRINK_CENTER
	box.add_child(UiKit.spacer(8))
	_continue = UiKit.button("Continue")
	_continue.size_flags_horizontal = SIZE_SHRINK_CENTER
	_bind(_continue, "continue")
	box.add_child(_continue)
	var panel := UiKit.panel()
	panel.add_child(box)
	add_child(UiKit.center(panel))


func first_focus() -> Control:
	return _continue


## The screen is built in setup(); entering the tree only starts the motion.
func _ready() -> void:
	if _hearts != null:
		_lose_heart()


func _exit_tree() -> void:
	if _heart_tween != null and _heart_tween.is_valid():
		_heart_tween.kill()


## The lost heart rattles and goes grey after HEART_DELAY. The heart is a
## container child; by the time the delay is over it has been placed, and
## relative steps that add up to zero leave it where it was.
func _lose_heart() -> void:
	var heart := _hearts.get_child(_hearts_left) as Control
	if heart == null:
		return
	_heart_tween = create_tween()
	_heart_tween.tween_interval(HEART_DELAY)
	_heart_tween.tween_callback(_on_heart_breaks)
	for i in HEART_SHAKES:
		_heart_tween.tween_property(heart, "position:x", HEART_SHAKE_PX, HEART_SHAKE_STEP).as_relative()
		_heart_tween.tween_property(heart, "position:x", -2.0 * HEART_SHAKE_PX, HEART_SHAKE_STEP * 2.0).as_relative()
		_heart_tween.tween_property(heart, "position:x", HEART_SHAKE_PX, HEART_SHAKE_STEP).as_relative()
	_heart_tween.tween_callback(func() -> void:
		if is_instance_valid(_hearts):
			UiKit.set_pips(_hearts, _hearts_left))


## The moment the heart goes: the sound, and a thump through the match
## camera, which is still the viewport's camera under the dimmed panel. A
## camera without a rig (or no camera at all, in the headless tests) is
## left alone.
func _on_heart_breaks() -> void:
	Sfx.play("heart_lost", 0.02)
	if not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.has_method("shake"):
		camera.call("shake", HEART_CAMERA_SHAKE)


## A three-column table: the stat, yours, theirs; the longest rally under it.
static func _stats_table(stats: Array, longest_rally: int) -> Control:
	var inset := UiKit.inset(Vector2(18, 8))
	inset.name = "Stats"
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 2)
	grid.add_child(UiKit.caption("", STAT_SIZE))
	grid.add_child(_cell("you", Palette.body_bold, Palette.YELLOW.darkened(0.25)))
	grid.add_child(_cell("them", Palette.body_bold, Palette.BLUE))
	for row in STATS:
		var mine := int((stats[0] as Dictionary).get(row[1], 0)) if stats.size() > 0 else 0
		var theirs := int((stats[1] as Dictionary).get(row[1], 0)) if stats.size() > 1 else 0
		var name_cell := _cell(row[0], Palette.body_medium, Palette.INK_DIM)
		name_cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(name_cell)
		grid.add_child(_cell(str(mine), Palette.body_bold, Palette.INK))
		grid.add_child(_cell(str(theirs), Palette.body_bold, Palette.INK))
	var rally := _cell("Longest rally", Palette.body_medium, Palette.INK_DIM)
	rally.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	grid.add_child(rally)
	var rally_value := _cell(str(longest_rally), Palette.body_bold, Palette.INK)
	grid.add_child(rally_value)
	grid.add_child(UiKit.caption("", STAT_SIZE))
	inset.add_child(grid)
	return inset


static func _cell(text: String, font: Font, color: Color) -> Label:
	var l := UiKit.text(text, STAT_SIZE, color)
	l.add_theme_font_override("font", font)
	l.custom_minimum_size = Vector2(60, 0)
	return l
