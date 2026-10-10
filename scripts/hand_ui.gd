## Renders the hand as a row of card buttons and reports which one was picked.
class_name HandUI
extends HBoxContainer

signal card_chosen(index: int)

const CARD_SIZE := Vector2(176, 132)
const TEXT_COLOR := Color(0.08, 0.07, 0.12)
## Over-budget cards are still playable, just washed out.
const TIRED_GREY := Color(0.58, 0.58, 0.60)
const TIRED_MODULATE := Color(0.72, 0.72, 0.72)


## `stamina` is what the player has right now; cards that cost more are drawn
## tired. Pass -1 when there is no stamina to compare against (deck views).
func show_hand(cards: Array[Card], incoming: int, stamina: int = -1) -> void:
	clear()
	for i in cards.size():
		add_child(_make_button(cards[i], i, incoming, stamina))


func clear() -> void:
	for child in get_children():
		child.queue_free()


func set_enabled(enabled: bool) -> void:
	for child in get_children():
		if child is Button:
			child.disabled = not enabled


static func is_tired(card: Card, stamina: int) -> bool:
	return stamina >= 0 and card.cost > stamina


## "●●●" for cost 3, "○" for a free card.
static func cost_dots(cost: int) -> String:
	return "●".repeat(cost) if cost > 0 else "○"


func _make_button(card: Card, index: int, incoming: int, stamina: int) -> Button:
	var tired := is_tired(card, stamina)
	var color := card.color.lerp(TIRED_GREY, 0.7) if tired else card.color
	var button := Button.new()
	button.toggle_mode = true
	button.custom_minimum_size = CARD_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.text = _card_text(card, incoming, stamina)
	button.tooltip_text = card.flavor
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	button.add_theme_color_override("font_pressed_color", TEXT_COLOR)
	button.add_theme_color_override("font_disabled_color", Color(TEXT_COLOR, 0.5))
	button.add_theme_stylebox_override("normal", _style(color, false))
	button.add_theme_stylebox_override("hover", _style(color.lightened(0.15), true))
	button.add_theme_stylebox_override("pressed", _style(color.darkened(0.15), true))
	button.add_theme_stylebox_override("disabled", _style(color.darkened(0.35), false))
	if tired:
		button.modulate = TIRED_MODULATE
	button.pressed.connect(func() -> void:
		set_selected(index)
		card_chosen.emit(index))
	return button


func set_selected(index: int) -> void:
	var i := 0
	for child in get_children():
		if child is Button:
			child.set_pressed_no_signal(i == index)
		i += 1


func _card_text(card: Card, incoming: int, stamina: int) -> String:
	var lines: Array[String] = [card.title]
	lines.append(cost_dots(card.cost) + ("   TIRED" if is_tired(card, stamina) else ""))
	lines.append("power %d  control %d" % [roundi(card.power * 10.0), roundi(card.control * 10.0)])
	lines.append("sends: %s" % BallType.label(card.produces))
	if card.is_strong_vs(incoming):
		lines.append("STRONG vs %s" % BallType.label(incoming))
	elif card.is_weak_vs(incoming):
		lines.append("weak vs %s" % BallType.label(incoming))
	else:
		lines.append(" ")
	lines.append(card.keyword_text() if card.keyword != "" else " ")
	return "\n".join(lines)


func _style(color: Color, raised: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(10)
	style.set_border_width_all(3)
	style.border_color = Color(0.09, 0.07, 0.14)
	style.set_content_margin_all(10.0)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 8 if raised else 4
	style.shadow_offset = Vector2(0, 4)
	return style
