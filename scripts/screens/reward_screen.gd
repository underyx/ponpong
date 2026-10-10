## After a won match: pick one of three cards, skip, or (after some stages)
## remove a card instead. The report underneath scouts the next opponent,
## emblem and all, so the pick is made knowing who it is for.
##
## args: {"offer": [ids], "trim_available": bool, "deck_size": int, "deck_max": int,
##        "hearts": int, "stage": int (0-based, the stage just won), "stages": int,
##        "next": {"id", "name", "blurb", "points_to_win", "deck_summary", "boss"}}
## actions: pick {index}, skip, trim, deck. No back action: a choice is required.
##
## The three cards flip in one after another. Once the Director has taken a
## pick (on_accepted), the chosen card lifts and chimes while the other two
## fade; the Director holds the screen for that beat before the next match.
class_name RewardScreen
extends UiScreen

const HEADER := "VICTORY"
const SUBHEADER := "Pick a card for the road, or skip it"
const FULL_SUBHEADER := "Your deck is full: skip, or make room"
const CARD_SEPARATION := 18
const SKIP_SIZE := Vector2(150, 56)
const ACTION_SIZE := Vector2(230, 48)
## The scouting report never grows past the card row.
const PANEL_WIDTH := 760
const EMBLEM_SIZE := 72
## What the cards that were not taken fade to.
const UNPICKED_ALPHA := 0.3

var views: Array[CardView] = []
var skip_button: Button
var trim_button: Button
var deck_button: Button
var footer: Label


func setup(p_args: Dictionary) -> void:
	super(p_args)
	var offer: Array = args.get("offer", [])
	var deck_size := int(args.get("deck_size", 0))
	var deck_full := deck_size >= int(args.get("deck_max", RunState.DECK_MAX))
	add_child(UiKit.dim(0.5))
	var box := UiKit.vbox(10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var head := UiKit.vbox(0)
	head.add_child(UiKit.title(HEADER, 56))
	head.add_child(UiKit.label(FULL_SUBHEADER if deck_full else SUBHEADER, 18, Palette.PAPER))
	box.add_child(head)

	var row := UiKit.hbox(CARD_SEPARATION)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in offer.size():
		var card := CardLibrary.by_id(String(offer[i]))
		if card == null:
			continue
		var view := CardView.new()
		view.name = "Offer%d" % (i + 1)
		view.set_card(card)
		view.disabled = deck_full
		view.pressed.connect(_on_pick.bind(i))
		view.flip_in(i * CardView.FLIP_STAGGER)
		row.add_child(view)
		views.append(view)
	skip_button = UiKit.button("Skip", 22, SKIP_SIZE)
	skip_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bind(skip_button, "skip")
	row.add_child(skip_button)
	box.add_child(row)

	var actions := UiKit.hbox(14)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	if bool(args.get("trim_available", false)):
		trim_button = UiKit.button("Remove a card instead", 18, ACTION_SIZE)
		_bind(trim_button, "trim")
		actions.add_child(trim_button)
	deck_button = UiKit.button("View deck", 18, ACTION_SIZE)
	_bind(deck_button, "deck")
	actions.add_child(deck_button)
	box.add_child(actions)

	var next: Dictionary = args.get("next", {})
	if not next.is_empty():
		box.add_child(_next_panel(next))

	footer = UiKit.label("Deck: %d cards, hearts %d, stage %d of %d" % [
		deck_size, int(args.get("hearts", 0)), int(args.get("stage", 0)) + 1,
		int(args.get("stages", RunState.STAGES))], 15, Palette.PAPER_DIM)
	box.add_child(footer)
	add_child(UiKit.center(box))


## Card `index` was clicked: the choice leaves; what it looks like waits for
## the Director to accept it, so a click during a fade changes nothing.
func _on_pick(index: int) -> void:
	press("pick", {"index": index})


## The pick went through: the chosen card lifts and chimes, the others fade.
func on_accepted(action: String, data: Dictionary) -> void:
	if action != "pick":
		return
	var index := int(data.get("index", -1))
	Sfx.play("reward_pick")
	for i in views.size():
		if i == index:
			views[i].lift_pick()
		else:
			views[i].fade_to(UNPICKED_ALPHA)


## The scouting report: the emblem, "Next: Jax Dunn (first to 7)", the blurb
## and the deck summary, with a BOSS tag for the last stage.
func _next_panel(next: Dictionary) -> PanelContainer:
	var panel := UiKit.panel()
	panel.name = "NextOpponent"
	panel.add_theme_stylebox_override("panel", UiKit.panel_style(Palette.PAPER, 16.0))
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	var row := UiKit.hbox(16)
	var emblem := UiKit.emblem(String(next.get("id", "")), EMBLEM_SIZE)
	emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(emblem)
	var v := UiKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heading := UiKit.hbox(10)
	heading.alignment = BoxContainer.ALIGNMENT_BEGIN
	var scouting := UiKit.caption("SCOUTING REPORT", 11, Palette.ORANGE)
	scouting.add_theme_font_override("font", Palette.body_bold)
	heading.add_child(scouting)
	if bool(next.get("boss", false)):
		var tag := UiKit.chip("BOSS", null, Palette.PINK, Palette.PAPER, 11)
		tag.name = "BossTag"
		heading.add_child(tag)
	v.add_child(heading)
	var name_line := UiKit.heading("Next: %s (first to %d)" % [
		String(next.get("name", "?")), int(next.get("points_to_win", 0))], 24)
	name_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(name_line)
	var blurb := UiKit.text(String(next.get("blurb", "")), 16)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(blurb)
	var summary := UiKit.caption("Deck: " + String(next.get("deck_summary", "")), 13)
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(summary)
	row.add_child(v)
	panel.add_child(row)
	return panel
