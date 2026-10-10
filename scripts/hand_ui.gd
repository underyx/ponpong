## Renders the hand as a row of card buttons and reports which one was picked.
class_name HandUI
extends HBoxContainer

signal card_chosen(index: int)

const CARD_SIZE := Vector2(176, 132)


func show_hand(cards: Array[Card], incoming: int) -> void:
	clear()
	for i in cards.size():
		add_child(_make_button(cards[i], i, incoming))


func clear() -> void:
	for child in get_children():
		child.queue_free()


func set_enabled(enabled: bool) -> void:
	for child in get_children():
		if child is Button:
			child.disabled = not enabled


func _make_button(card: Card, index: int, incoming: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = CARD_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.text = _card_text(card, incoming)
	button.tooltip_text = card.flavor
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color(0.08, 0.07, 0.12))
	button.add_theme_color_override("font_hover_color", Color(0.08, 0.07, 0.12))
	button.add_theme_color_override("font_pressed_color", Color(0.08, 0.07, 0.12))
	button.add_theme_color_override("font_disabled_color", Color(0.08, 0.07, 0.12, 0.5))
	button.add_theme_stylebox_override("normal", _style(card.color, false))
	button.add_theme_stylebox_override("hover", _style(card.color.lightened(0.15), true))
	button.add_theme_stylebox_override("pressed", _style(card.color.darkened(0.15), true))
	button.add_theme_stylebox_override("disabled", _style(card.color.darkened(0.35), false))
	button.pressed.connect(func() -> void: card_chosen.emit(index))
	return button


func _card_text(card: Card, incoming: int) -> String:
	var lines: Array[String] = [card.title]
	lines.append("power %d  control %d" % [roundi(card.power * 10.0), roundi(card.control * 10.0)])
	lines.append("sends: %s" % BallType.label(card.produces))
	if card.is_strong_vs(incoming):
		lines.append("STRONG vs %s" % BallType.label(incoming))
	elif card.is_weak_vs(incoming):
		lines.append("weak vs %s" % BallType.label(incoming))
	else:
		lines.append(" ")
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
