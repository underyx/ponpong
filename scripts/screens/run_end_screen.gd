## The end of a run, won or lost: the headline, where it ended, the run's
## numbers and the seed, with a fresh run, the same seed again, or the menu.
class_name RunEndScreen
extends UiScreen

const TITLE_SIZE := 72
const SUB_SIZE := 24
const STAT_SIZE := 20
const SEED_SIZE := 18

var _new_run: Button


## args: {"won": bool, "stage": int, "opponent_name": String, "stats": Dictionary,
##        "seed": int, "deck_size": int}
func setup(p_args: Dictionary) -> void:
	super(p_args)
	back_action = ""
	add_child(UiKit.dim(0.70))
	var won := bool(args.get("won", false))
	var stats: Dictionary = args.get("stats", {})
	var box := UiKit.vbox(8)
	var heading := UiKit.title("CHAMPION" if won else "RUN OVER", TITLE_SIZE)
	heading.add_theme_color_override("font_color", UiKit.GOLD if won else UiKit.DANGER)
	box.add_child(heading)
	if not won:
		box.add_child(UiKit.label("at stage %d vs %s" % [int(args.get("stage", 0)) + 1, String(args.get("opponent_name", "?"))],
			SUB_SIZE))
	box.add_child(_spacer(6))
	box.add_child(_stat("Opponents beaten   %d / %d" % [int(stats.get("matches_won", 0)), RunState.STAGES]))
	box.add_child(_stat("Points   %d won  ·  %d lost" % [int(stats.get("points_won", 0)), int(stats.get("points_lost", 0))]))
	box.add_child(_stat("Longest rally   %d" % int(stats.get("longest_rally", 0))))
	box.add_child(_stat("Cards   %d added  ·  %d removed  ·  %d in the deck" % [
		int(stats.get("cards_added", 0)), int(stats.get("cards_removed", 0)), int(args.get("deck_size", 0))]))
	box.add_child(_stat("Tired plays   %d" % int(stats.get("tired_plays", 0))))
	box.add_child(_spacer(4))
	box.add_child(UiKit.label("Seed %d" % int(args.get("seed", 0)), SEED_SIZE, UiKit.GOLD))
	box.add_child(_spacer(6))
	var row := UiKit.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_new_run = _menu_button(row, "New Run", "new_run")
	_menu_button(row, "Retry this seed", "retry")
	_menu_button(row, "Main Menu", "menu")
	box.add_child(row)
	var panel := UiKit.panel()
	panel.add_child(box)
	add_child(UiKit.center(panel))


func first_focus() -> Control:
	return _new_run


func _menu_button(row: BoxContainer, text: String, action: String) -> Button:
	var b := UiKit.button(text, 20, Vector2(220, 48))
	_bind(b, action)
	row.add_child(b)
	return b


static func _stat(text: String) -> Label:
	return UiKit.label(text, STAT_SIZE, UiKit.MUTED)


static func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = MOUSE_FILTER_IGNORE
	return c
