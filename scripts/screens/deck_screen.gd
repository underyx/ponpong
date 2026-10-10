## The deck as a scrolling grid of CardViews, one per card id with an "xN"
## badge, sorted by cost then title. In view mode it is read-only with a Back
## button; in remove mode (a regroup after a lost match, or a trim instead of a
## reward) the cards toggle and "Remove selected" takes one out of the deck.
##
## args: {"deck": [ids], "mode": "view"|"remove", "reason": "regroup"|"trim"|"",
##        "return": "pause"|"reward"|"", "deck_min": int}
## actions: back, remove {index} (into the ungrouped deck, the first copy of
## that id), skip. ui_cancel presses back in view mode only.
class_name DeckScreen
extends UiScreen

const COLUMNS := 5
const GRID_SEPARATION := 14
## Rows shown at once; a longer deck scrolls.
const VISIBLE_ROWS := 3
## Room kept beside the grid for the vertical scrollbar.
const SCROLLBAR_WIDTH := 16
## Space around the grid inside the scroll area, for the cards' focus rings.
const GRID_PADDING := 6
const HEADERS := {
	"regroup": "Regroup: remove one card before the rematch",
	"trim": "Trim: remove one card, or keep them all",
}
const REMOVE_SIZE := Vector2(230, 48)

var mode := "view"
var deck: Array[String] = []
var deck_min := RunState.DECK_MIN
## One CardView per distinct id, in grid order.
var views: Array[CardView] = []
## Id of the card marked for removal, "" for none.
var selected_id := ""
var header: Label
var curve_label: Label
var scroll: ScrollContainer
var grid: GridContainer
var remove_button: Button
var keep_button: Button
var back_button: Button


func setup(p_args: Dictionary) -> void:
	super(p_args)
	mode = String(args.get("mode", "view"))
	deck.assign(args.get("deck", []))
	deck_min = int(args.get("deck_min", RunState.DECK_MIN))
	back_action = "back" if mode == "view" else ""
	add_child(UiKit.dim(0.55))
	var box := UiKit.vbox(10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	header = UiKit.title(_header_text(), 40)
	box.add_child(header)
	curve_label = UiKit.label(cost_curve(deck), 18, UiKit.MUTED)
	box.add_child(curve_label)
	if mode == "remove" and deck.size() <= deck_min:
		box.add_child(UiKit.label("Your deck is at its minimum of %d cards: nothing can be removed." % deck_min,
			16, UiKit.DANGER))
	grid = GridContainer.new()
	grid.name = "Grid"
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", GRID_SEPARATION)
	grid.add_theme_constant_override("v_separation", GRID_SEPARATION)
	var entries := group(deck)
	for entry in entries:
		grid.add_child(_make_view(entry))
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = grid_size(entries.size())
	scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	# Padding inside the scroll area, so the focus ring drawn outside a card
	# on the edge of the grid is not clipped.
	var pad := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, GRID_PADDING)
	pad.add_child(grid)
	scroll.add_child(pad)
	box.add_child(scroll)
	box.add_child(_buttons())
	add_child(UiKit.center(box))


## In view mode the first card; in remove mode too, so the gamepad lands on
## the thing to choose rather than on a disabled button.
func first_focus() -> Control:
	if not views.is_empty():
		return views[0]
	return super()


## The scroll area for `distinct` cards: the grid's width plus the scrollbar,
## and as many rows as it has up to VISIBLE_ROWS, so the buttons sit right
## under a short deck and a long one scrolls.
static func grid_size(distinct: int) -> Vector2:
	var rows: int = mini(VISIBLE_ROWS, maxi(1, ceili(float(distinct) / COLUMNS)))
	return Vector2(
		COLUMNS * CardView.SIZE.x + (COLUMNS - 1) * GRID_SEPARATION + 2 * GRID_PADDING + SCROLLBAR_WIDTH,
		rows * CardView.SIZE.y + (rows - 1) * GRID_SEPARATION + 2 * GRID_PADDING)


## {id, card, count, index} per distinct id, sorted by cost then title;
## `index` is the first copy's position in `ids`.
static func group(ids: Array) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var by_id: Dictionary = {}
	for i in ids.size():
		var id := String(ids[i])
		if by_id.has(id):
			by_id[id]["count"] += 1
			continue
		var card := CardLibrary.by_id(id)
		if card == null:
			continue
		var entry := {"id": id, "card": card, "count": 1, "index": i}
		by_id[id] = entry
		entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca: Card = a["card"]
		var cb: Card = b["card"]
		if ca.cost != cb.cost:
			return ca.cost < cb.cost
		return ca.title < cb.title)
	return entries


## "0-cost x4 · 1-cost x6 · 2-cost x3 · 3-cost x2"
static func cost_curve(ids: Array) -> String:
	var counts := [0, 0, 0, 0]
	for id in ids:
		var card := CardLibrary.by_id(String(id))
		if card != null and card.cost >= 0 and card.cost < counts.size():
			counts[card.cost] += 1
	var parts: Array[String] = []
	for cost in counts.size():
		parts.append("%d-cost x%d" % [cost, counts[cost]])
	return " · ".join(parts)


func _header_text() -> String:
	if mode == "remove":
		return String(HEADERS.get(String(args.get("reason", "")), "Remove one card, or keep them all"))
	return "Your deck (%d)" % deck.size()


func _make_view(entry: Dictionary) -> CardView:
	var view := CardView.new()
	view.name = "Card_" + String(entry["id"])
	view.set_card(entry["card"], BallType.NONE, -1, int(entry["count"]))
	if mode == "remove":
		view.toggle_mode = true
		view.pressed.connect(_on_card_pressed.bind(String(entry["id"])))
	views.append(view)
	return view


func _buttons() -> HBoxContainer:
	var row := UiKit.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if mode == "remove":
		remove_button = UiKit.button("Remove selected", 20, REMOVE_SIZE)
		remove_button.pressed.connect(_on_remove_pressed)
		row.add_child(remove_button)
		keep_button = UiKit.button("Keep all", 20, REMOVE_SIZE)
		_bind(keep_button, "skip")
		row.add_child(keep_button)
		_refresh_remove_button()
	else:
		back_button = UiKit.button("Back", 20, REMOVE_SIZE)
		_bind(back_button, "back")
		row.add_child(back_button)
	return row


## Marks one card for removal; pressing the marked card again unmarks it.
func _on_card_pressed(id: String) -> void:
	selected_id = "" if selected_id == id else id
	for view in views:
		view.set_selected(view.card.id == selected_id)
	_refresh_remove_button()


func _refresh_remove_button() -> void:
	remove_button.disabled = selected_id == "" or deck.size() <= deck_min


func _on_remove_pressed() -> void:
	var index := deck.find(selected_id)
	if index < 0 or deck.size() <= deck_min:
		return
	press("remove", {"index": index})
