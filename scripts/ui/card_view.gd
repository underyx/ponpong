## One card face: a Button wearing the card's colour and rarity border with a
## stack of labels on top. The hand, the Reward screen and the Deck screen all
## build their cards from this, so a card looks the same everywhere. The face
## is built in _init, so a CardView is complete before it enters the tree.
##
## Two modes, chosen by `stamina` in set_card(): in a match (stamina >= 0) the
## matchup line reads against the incoming ball and over-budget cards are
## drawn tired; in a deck or reward view (stamina -1) it lists every strong
## and weak matchup instead and an "xN" badge shows how many copies there are.
class_name CardView
extends Button

const SIZE := Vector2(176, 132)
## Dark text on the pastel card colours.
const TEXT_COLOR := Color(0.08, 0.07, 0.12)
const STRONG_COLOR := Color(0.05, 0.42, 0.12)
const WEAK_COLOR := Color(0.72, 0.10, 0.10)
const TIRED_COLOR := Color(0.82, 0.06, 0.06)
## Over-budget cards are still playable, just washed out.
const TIRED_MODULATE := Color(0.6, 0.6, 0.6)
const BADGE_BG := Color(0.09, 0.07, 0.14, 0.85)
const TITLE_SIZE := 14
const BODY_SIZE := 12
const SMALL_SIZE := 11
## Space between the card border and the stack of labels.
const FACE_MARGIN := Vector2(6, 5)
const BADGE_CORNER := 9
## How far outside the card the focus ring is drawn.
const FOCUS_RING_GAP := 4.0

var card: Card
## How many copies this face stands for (deck views group identical cards).
var copies := 1
var tired := false
var selected := false

var _face_color := Color(0.9, 0.9, 0.9)
var _rarity_border := UiKit.OUTLINE
var _face: VBoxContainer
var _title: Label
var _stats: Label
var _matchup: Label
var _keyword: Label
var _likes: Label
var _tired_line: Label
var _cost_badge: Label
var _count_badge: Label


func _init() -> void:
	custom_minimum_size = SIZE
	focus_mode = Control.FOCUS_ALL
	text = ""
	_build_face()
	_apply_style()


## Fills the face for `p_card`. `incoming` is the ball type the card would
## answer and `stamina` what the player has: pass stamina -1 (the default) for
## a deck or reward view, where there is no ball to read and nothing to be
## tired against. `count` > 1 shows an "xN" badge.
func set_card(p_card: Card, incoming: int = BallType.NONE, stamina: int = -1, count: int = 1) -> void:
	card = p_card
	copies = count
	var in_match := stamina >= 0
	_title.text = card.title
	tooltip_text = card.flavor
	_cost_badge.text = cost_dots(card.cost)
	_count_badge.text = "x%d" % copies
	_count_badge.visible = copies > 1
	_stats.text = "POW %d  CTL %d  sends %s" % [
		roundi(card.power * 10.0), roundi(card.control * 10.0), BallType.label(card.produces)]
	if in_match:
		if card.is_strong_vs(incoming):
			_matchup.text = "STRONG vs %s" % BallType.label(incoming)
			_matchup.add_theme_color_override("font_color", STRONG_COLOR)
		elif card.is_weak_vs(incoming):
			_matchup.text = "weak vs %s" % BallType.label(incoming)
			_matchup.add_theme_color_override("font_color", WEAK_COLOR)
		else:
			_matchup.text = ""
	else:
		_matchup.text = matchup_summary(card)
		_matchup.add_theme_color_override("font_color", TEXT_COLOR)
	_keyword.text = card.keyword_text()
	_likes.text = ""
	if card.prefers_row == 1:
		_likes.text = "likes deep"
	elif card.prefers_row == 0:
		_likes.text = "likes short"
	_face_color = card.color
	_rarity_border = UiKit.RARITY_BORDER.get(card.rarity, UiKit.OUTLINE)
	set_tired(is_tired(card, stamina))
	_apply_style()


## Washes the card out and shows the red TIRED line: the player can still play
## it, the shot just lands worse.
func set_tired(p_tired: bool) -> void:
	tired = p_tired
	modulate = TIRED_MODULATE if tired else Color.WHITE
	_tired_line.visible = tired


## The pressed look with a gold border: the card the player is about to play,
## or the one marked for removal.
func set_selected(on: bool) -> void:
	selected = on
	if toggle_mode:
		set_pressed_no_signal(on)
	_apply_style()


static func is_tired(p_card: Card, stamina: int) -> bool:
	return stamina >= 0 and p_card.cost > stamina


## "●●●" for cost 3, "○" for a free card.
static func cost_dots(cost: int) -> String:
	return "●".repeat(cost) if cost > 0 else "○"


## "+Flat +High   -Fast": every matchup at once, for views with no incoming ball.
static func matchup_summary(p_card: Card) -> String:
	var strong: Array[String] = []
	for type in p_card.strong_vs:
		strong.append("+" + BallType.label(type))
	var weak: Array[String] = []
	for type in p_card.weak_vs:
		weak.append("-" + BallType.label(type))
	var parts: Array[String] = []
	if not strong.is_empty():
		parts.append(" ".join(strong))
	if not weak.is_empty():
		parts.append(" ".join(weak))
	return "   ".join(parts)


func _build_face() -> void:
	_face = VBoxContainer.new()
	_face.name = "Face"
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.add_theme_constant_override("separation", 0)
	_face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_face.offset_left = FACE_MARGIN.x
	_face.offset_top = FACE_MARGIN.y
	_face.offset_right = -FACE_MARGIN.x
	_face.offset_bottom = -FACE_MARGIN.y
	add_child(_face)
	_title = _line("Title", TITLE_SIZE)
	_stats = _line("Stats", BODY_SIZE)
	_matchup = _line("Matchup", BODY_SIZE)
	_keyword = _line("Keyword", SMALL_SIZE)
	_keyword.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_likes = _line("Likes", SMALL_SIZE)
	_tired_line = _line("Tired", BODY_SIZE, TIRED_COLOR)
	_tired_line.text = "TIRED"
	_tired_line.visible = false
	_cost_badge = _badge("Cost", UiKit.GOLD)
	_cost_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_cost_badge.position = FACE_MARGIN
	_count_badge = _badge("Count", UiKit.TEXT)
	_count_badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_count_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_count_badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_count_badge.offset_right = -FACE_MARGIN.x
	_count_badge.offset_bottom = -FACE_MARGIN.y
	_count_badge.visible = false


func _line(p_name: String, size: int, color := TEXT_COLOR) -> Label:
	var l := Label.new()
	l.name = p_name
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	_face.add_child(l)
	return l


## A small dark pill with light text, laid over a corner of the card.
func _badge(p_name: String, color: Color) -> Label:
	var l := Label.new()
	l.name = p_name
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", SMALL_SIZE)
	l.add_theme_color_override("font_color", color)
	var s := StyleBoxFlat.new()
	s.bg_color = BADGE_BG
	s.set_corner_radius_all(BADGE_CORNER)
	s.content_margin_left = 6.0
	s.content_margin_right = 6.0
	s.content_margin_top = 1.0
	s.content_margin_bottom = 1.0
	l.add_theme_stylebox_override("normal", s)
	add_child(l)
	return l


func _apply_style() -> void:
	var border := UiKit.GOLD if selected else _rarity_border
	var c := _face_color
	add_theme_stylebox_override("normal", UiKit.card_style(c, border, selected))
	add_theme_stylebox_override("hover", UiKit.card_style(c.lightened(0.15), border, true))
	add_theme_stylebox_override("pressed", UiKit.card_style(c.darkened(0.15), border, true))
	add_theme_stylebox_override("hover_pressed", UiKit.card_style(c.darkened(0.08), border, true))
	add_theme_stylebox_override("disabled", UiKit.card_style(c.darkened(0.35), border, false))
	# The ring sits outside the card, so it still shows on a rare card whose
	# border is already gold, and on a selected one.
	var focus := UiKit.focus_style()
	focus.set_expand_margin_all(FOCUS_RING_GAP)
	add_theme_stylebox_override("focus", focus)
