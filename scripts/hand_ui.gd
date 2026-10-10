## Renders the hand as a row of CardViews and reports which one was picked.
## Every card takes keyboard and gamepad focus: left and right walk the strip,
## up and down stay put, and Enter, Space or the A button on a focused card
## picks it, exactly like a click.
class_name HandUI
extends HBoxContainer

signal card_chosen(index: int)

const CARD_SIZE := CardView.SIZE


## `stamina` is what the player has right now; cards that cost more are drawn
## tired. Pass -1 when there is no stamina to compare against (deck views).
func show_hand(cards: Array[Card], incoming: int, stamina: int = -1) -> void:
	clear()
	for i in cards.size():
		add_child(_make_view(cards[i], i, incoming, stamina))
	_link_focus()


## Drops the cards at once rather than at the end of the frame, so a hand
## dealt in the same call starts from an empty strip.
func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


func set_enabled(enabled: bool) -> void:
	for view in views():
		view.disabled = not enabled


## Puts keyboard and gamepad focus on the first card, if there is one.
func focus_first() -> void:
	focus_index(0)


## Puts focus on card `index`; out of range does nothing.
func focus_index(index: int) -> void:
	var cards := views()
	if index >= 0 and index < cards.size():
		cards[index].grab_focus()


## Marks card `index` as the one about to be played; -1 clears the mark.
func set_selected(index: int) -> void:
	var cards := views()
	for i in cards.size():
		cards[i].set_selected(i == index)


## The cards on the strip, left to right.
func views() -> Array[CardView]:
	var out: Array[CardView] = []
	for child in get_children():
		if child is CardView:
			out.append(child)
	return out


func _make_view(card: Card, index: int, incoming: int, stamina: int) -> CardView:
	var view := CardView.new()
	view.name = "Card%d" % (index + 1)
	view.toggle_mode = true
	view.set_card(card, incoming, stamina)
	view.pressed.connect(func() -> void:
		set_selected(index)
		card_chosen.emit(index))
	return view


## Left and right walk the strip and wrap at the ends; up and down point at
## the card itself, so the arrows and the d-pad never leave the hand.
func _link_focus() -> void:
	var cards := views()
	var n := cards.size()
	for i in n:
		var view := cards[i]
		var me := view.get_path_to(view)
		view.focus_neighbor_top = me
		view.focus_neighbor_bottom = me
		view.focus_neighbor_left = view.get_path_to(cards[(i - 1 + n) % n])
		view.focus_neighbor_right = view.get_path_to(cards[(i + 1) % n])
		view.focus_previous = view.focus_neighbor_left
		view.focus_next = view.focus_neighbor_right
