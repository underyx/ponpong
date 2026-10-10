## Shown when a match ends: the result, the score, both players' numbers and
## what the run does next (a reward, a lost heart, or the end of the run).
## On a loss the heart that was just lost is still lit when the screen opens,
## then shakes, sounds and greys out.
class_name MatchEndScreen
extends UiScreen

const TITLE_SIZE := 64
const SCORE_SIZE := 40
const STAT_SIZE := 20
const HEART_SIZE := 18
## The lost heart holds this long before it shakes and goes out.
const HEART_DELAY := 0.4
const HEART_SHAKE_PX := 3.0
const HEART_SHAKES := 3
const HEART_SHAKE_STEP := 0.04
## Trauma handed to the match camera under the panel when the heart goes.
const HEART_CAMERA_SHAKE := 0.6

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
	add_child(UiKit.dim(0.55))
	var won := bool(args.get("won", false))
	var score: Array = args.get("score", [0, 0])
	var stats: Array = args.get("stats", [{}, {}])
	var run_over := bool(args.get("run_over", false))
	var hearts := int(args.get("hearts", 0))

	var box := UiKit.vbox(8)
	var heading := UiKit.title("YOU WIN" if won else "YOU LOSE", TITLE_SIZE)
	heading.add_theme_color_override("font_color", UiKit.GOLD if won else UiKit.DANGER)
	box.add_child(heading)
	box.add_child(UiKit.label("%d  -  %d" % [int(score[0]), int(score[1])], SCORE_SIZE))
	box.add_child(_spacer(6))
	box.add_child(_stat_line("Winners", stats, "winners"))
	box.add_child(_stat_line("Faults", stats, "faults"))
	box.add_child(_stat_line("Tired plays", stats, "tired_plays"))
	box.add_child(UiKit.label("Longest rally   %d" % int(args.get("longest_rally", 0)), STAT_SIZE, UiKit.MUTED))
	box.add_child(_spacer(6))
	if won:
		box.add_child(UiKit.label("You are the champion" if run_over else "Next: reward", STAT_SIZE, UiKit.GOLD))
	else:
		box.add_child(UiKit.label("Run over" if run_over else "Heart lost", STAT_SIZE, UiKit.DANGER))
		# One more heart lit than the run has left: the one about to go.
		_hearts_left = clampi(hearts, 0, RunState.HEARTS - 1)
		_hearts = UiKit.pips(RunState.HEARTS, _hearts_left + 1, UiKit.DANGER, HEART_SIZE)
		_hearts.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_child(_hearts)
	box.add_child(_spacer(6))
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


## The lost heart rattles and goes grey after HEART_DELAY. The pip is a
## container child; by the time the delay is over it has been placed, and
## relative steps that add up to zero leave it where it was.
func _lose_heart() -> void:
	var pip := _hearts.get_child(_hearts_left) as Control
	if pip == null:
		return
	_heart_tween = create_tween()
	_heart_tween.tween_interval(HEART_DELAY)
	_heart_tween.tween_callback(_on_heart_breaks)
	for i in HEART_SHAKES:
		_heart_tween.tween_property(pip, "position:x", HEART_SHAKE_PX, HEART_SHAKE_STEP).as_relative()
		_heart_tween.tween_property(pip, "position:x", -2.0 * HEART_SHAKE_PX, HEART_SHAKE_STEP * 2.0).as_relative()
		_heart_tween.tween_property(pip, "position:x", HEART_SHAKE_PX, HEART_SHAKE_STEP).as_relative()
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


## "Winners   you 5  ·  them 3"
static func _stat_line(name_text: String, stats: Array, key: String) -> Label:
	var mine := int((stats[0] as Dictionary).get(key, 0)) if stats.size() > 0 else 0
	var theirs := int((stats[1] as Dictionary).get(key, 0)) if stats.size() > 1 else 0
	return UiKit.label("%s   you %d  ·  them %d" % [name_text, mine, theirs], STAT_SIZE, UiKit.MUTED)


static func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = MOUSE_FILTER_IGNORE
	return c
