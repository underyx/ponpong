## Shown when a match ends: the result, the score, both players' numbers and
## what the run does next (a reward, a lost heart, or the end of the run).
class_name MatchEndScreen
extends UiScreen

const TITLE_SIZE := 64
const SCORE_SIZE := 40
const STAT_SIZE := 20
const HEART_SIZE := 18

var _continue: Button


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
	elif run_over:
		box.add_child(UiKit.label("Run over", STAT_SIZE, UiKit.DANGER))
	else:
		box.add_child(UiKit.label("Heart lost", STAT_SIZE, UiKit.DANGER))
		var pips := UiKit.pips(RunState.HEARTS, hearts, UiKit.DANGER, HEART_SIZE)
		pips.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_child(pips)
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
