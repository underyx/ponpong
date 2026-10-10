## One card face: a Button wearing the card's rarity as its frame, with a
## title band, the card's art window, and a paper text box of numbers and
## matchups. The hand, the Reward screen and the Deck screen all build their
## cards from this, so a card looks the same everywhere. The face is built
## in _init, so a CardView is complete before it enters the tree.
##
## Two modes, chosen by `stamina` in set_card(): in a match (stamina >= 0) the
## matchup line reads against the incoming ball and over-budget cards are
## drawn tired; in a deck or reward view (stamina -1) it lists every strong
## and weak matchup instead and an "xN" badge shows how many copies there are.
##
## Motion: a card deals in from below or flips in, lifts under the mouse or
## the focus, tilts when selected, pulses its TIRED line, shakes when an
## unaffordable card is picked, and flies out when played. Every animated
## quantity is its own channel laid over `rest_position`, the spot the
## container gave the card, so the lift, the deal-in and a shake never fight
## each other or the layout. Nothing here plays a sound.
class_name CardView
extends Button

const SIZE := Vector2(150, 210)
## The art window inside the frame, at half the SVG's authored size.
const ART_SIZE := Vector2(130, 65)
const TEXT_COLOR := Palette.INK
const STRONG_COLOR := Color("1a9476")
const WEAK_COLOR := Color("d84063")
const TIRED_COLOR := Palette.PINK
## Over-budget cards are still playable, just washed out.
const TIRED_MODULATE := Color(0.62, 0.6, 0.66)
const TITLE_SIZE := 15
const BODY_SIZE := 11
const SMALL_SIZE := 10
## The frame band between the ink edge and the inner parts.
const FRAME := 6.0
const CORNER := 10
## The cost badge hangs off the top left corner by this much.
const BADGE_SIZE := 28.0
const BADGE_OVERHANG := 7.0
## How far outside the card the focus ring is drawn.
const FOCUS_RING_GAP := 4.0
## The POW and CTL meters: this many segments each.
const METER_SEGMENTS := 5

## Deal-in: the card rises this far while fading in, one after another.
const DEAL_DROP := 140.0
const DEAL_TIME := 0.18
const DEAL_STAGGER := 0.05
## Flip-in (rewards): the card opens from a line to full width.
const FLIP_TIME := 0.18
const FLIP_STAGGER := 0.12
## Under the mouse or the focus the card grows a little and lifts.
const RAISE_TIME := 0.08
const RAISE_LIFT := -18.0
const RAISE_ZOOM := 1.04
## The card about to be played grows more and tilts.
const SELECTED_ZOOM := 1.06
const SELECTED_TILT_DEG := -2.0
## The reward card that was taken.
const PICK_ZOOM := 1.1
const PICK_LIFT := -24.0
const FADE_TIME := 0.15
const PLAY_OUT_TIME := 0.15
## An unaffordable pick shakes the card sideways this far, this many times.
const SHAKE_PX := 4.0
const SHAKE_TIMES := 3
const SHAKE_STEP := 0.03
## The TIRED line breathes between these over a PULSE_PERIOD loop.
const PULSE_LOW := 0.6
const PULSE_PERIOD := 0.8

var card: Card
## How many copies this face stands for (deck views group identical cards).
var copies := 1
var tired := false
var selected := false
## Under the mouse or holding focus: drawn lifted.
var raised := false
## Where the container put the card; every motion is an offset from here.
var rest_position := Vector2.ZERO

var _frame_color: Color = Palette.RARITY[0]
var _face: VBoxContainer
var _title: Label
var _art: TextureRect
var _art_frame: PanelContainer
var _pow_meter: HBoxContainer
var _ctl_meter: HBoxContainer
var _pow_value: Label
var _ctl_value: Label
var _sends_icon: TextureRect
var _sends: Label
var _matchup: Label
var _keyword_icon: TextureRect
var _keyword: Label
var _keyword_row: HBoxContainer
var _likes: Label
var _tired_line: Label
var _cost_badge: Label
var _rarity_badge: TextureRect
var _count_badge: Label

## The motion channels; see _apply_transform().
var _zoom := 1.0
var _flip := 1.0
var _raise_y := 0.0
var _deal_y := 0.0
var _shake_x := 0.0
var _tilt_deg := 0.0
var _motion: Tween
var _entry: Tween
var _pulse: Tween
var _shake: Tween
var _fade: Tween
## An entry asked for before the card was in the tree: "deal" or "flip".
var _pending_entry := ""
var _pending_delay := 0.0
var _sorted_parent: Container


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = SIZE * 0.5
	focus_mode = Control.FOCUS_ALL
	text = ""
	clip_contents = false
	_build_face()
	_apply_style()
	resized.connect(_on_resized)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus_changed.bind(true))
	focus_exited.connect(_on_focus_changed.bind(false))


func _enter_tree() -> void:
	rest_position = position
	var parent := get_parent()
	if parent is Container:
		_sorted_parent = parent
		_sorted_parent.sort_children.connect(_on_parent_sorted)
	if _pending_entry != "":
		_start_entry(_pending_entry, _pending_delay)
		_pending_entry = ""
	_refresh_pulse()


func _exit_tree() -> void:
	if _sorted_parent != null and is_instance_valid(_sorted_parent):
		_sorted_parent.sort_children.disconnect(_on_parent_sorted)
	_sorted_parent = null
	stop_motion()


## Fills the face for `p_card`. `incoming` is the ball type the card would
## answer and `stamina` what the player has: pass stamina -1 (the default) for
## a deck or reward view, where there is no ball to read and nothing to be
## tired against. `count` > 1 shows an "xN" badge.
func set_card(p_card: Card, incoming: int = BallType.NONE, stamina: int = -1, count: int = 1) -> void:
	card = p_card
	copies = count
	var in_match := stamina >= 0
	_title.text = card.title
	tooltip_text = "%s\n%s · cost %d · %s" % [card.flavor, String(Palette.RARITY_NAMES.get(card.rarity, "")),
		card.cost, cost_dots(card.cost)]
	_art.texture = art_for(card.id)
	_art_frame.visible = _art.texture != null
	_cost_badge.text = str(card.cost)
	_cost_badge.add_theme_color_override("font_color", Palette.YELLOW if card.cost > 0 else Palette.TEAL)
	_rarity_badge.texture = UiKit.ICON_RARITY.get(card.rarity, UiKit.ICON_RARITY[0])
	_rarity_badge.modulate = Palette.RARITY.get(card.rarity, Palette.PAPER) if card.rarity > 0 else Palette.PAPER_DIM
	_count_badge.text = "x%d" % copies
	_count_badge.visible = copies > 1
	_fill_meter(_pow_meter, card.power, Palette.ORANGE)
	_fill_meter(_ctl_meter, card.control, Palette.TEAL)
	_pow_value.text = str(roundi(card.power * 10.0))
	_ctl_value.text = str(roundi(card.control * 10.0))
	_sends_icon.texture = UiKit.ICON_TYPE.get(card.produces, UiKit.ICON_TYPE[1])
	_sends.text = "sends %s" % BallType.label(card.produces)
	if in_match:
		if card.is_strong_vs(incoming):
			_matchup.text = "STRONG vs %s" % BallType.label(incoming)
			_matchup.add_theme_color_override("font_color", STRONG_COLOR)
		elif card.is_weak_vs(incoming):
			_matchup.text = "weak vs %s" % BallType.label(incoming)
			_matchup.add_theme_color_override("font_color", WEAK_COLOR)
		else:
			_matchup.text = "no matchup"
			_matchup.add_theme_color_override("font_color", Palette.INK_DIM)
	else:
		_matchup.text = matchup_summary(card)
		_matchup.add_theme_color_override("font_color", TEXT_COLOR)
	_keyword.text = card.keyword_text()
	_keyword_row.visible = card.keyword != ""
	_keyword_icon.texture = UiKit.ICON_KEYWORD.get(card.keyword, null)
	_keyword_icon.visible = _keyword_icon.texture != null
	_likes.text = ""
	if card.prefers_row == 1:
		_likes.text = "likes deep"
	elif card.prefers_row == 0:
		_likes.text = "likes short"
	_frame_color = Palette.RARITY.get(card.rarity, Palette.RARITY[0])
	set_tired(is_tired(card, stamina))
	_apply_style()


## Washes the card out and shows the pink TIRED line, which breathes while
## the card is in the tree: the player can still play it, the shot just
## lands worse.
func set_tired(p_tired: bool) -> void:
	tired = p_tired
	modulate = TIRED_MODULATE if tired else Color.WHITE
	_tired_line.visible = tired
	_refresh_pulse()


## The pressed look with an orange frame and a tilt: the card the player is
## about to play, or the one marked for removal.
func set_selected(on: bool) -> void:
	selected = on
	if toggle_mode:
		set_pressed_no_signal(on)
	_apply_style()
	_refresh_motion()


## Lifted, as under the mouse. Hover and focus set this by themselves.
func set_raised(on: bool) -> void:
	if raised == on:
		return
	raised = on
	_refresh_motion()


static func is_tired(p_card: Card, stamina: int) -> bool:
	return stamina >= 0 and p_card.cost > stamina


## "●●●" for cost 3, "○" for a free card: the cost in the tooltip.
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


## The card's art window from assets/cards, or null when it has none.
static func art_for(card_id: String) -> Texture2D:
	var path := "res://assets/cards/%s.svg" % card_id
	return load(path) if ResourceLoader.exists(path) else null


# --- motion ------------------------------------------------------------------

## Starts DEAL_DROP below its spot and invisible, then rises and fades in
## after `delay` seconds. Safe before the card is in the tree: it starts on
## entering.
func deal_in(delay := 0.0) -> void:
	_deal_y = DEAL_DROP
	modulate.a = 0.0
	_apply_transform()
	_queue_entry("deal", delay)


## Starts as a vertical line and opens to full width after `delay` seconds.
func flip_in(delay := 0.0) -> void:
	_flip = 0.0
	_apply_transform()
	_queue_entry("flip", delay)


## The reward card that was taken: bigger and higher than a hover.
func lift_pick() -> void:
	_tween_motion(PICK_ZOOM, PICK_LIFT, 0.0)


## Fades the whole card to `alpha` (the reward cards that were not taken).
func fade_to(alpha: float) -> void:
	_kill(_fade)
	if not is_inside_tree():
		modulate.a = alpha
		return
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", alpha, FADE_TIME)


## The card was played: it shrinks away and frees itself.
func play_out() -> void:
	_kill(_motion)
	_kill(_entry)
	_kill(_shake)
	_kill(_fade)
	disabled = true
	if not is_inside_tree():
		queue_free()
		return
	_fade = create_tween().set_parallel(true)
	_fade.tween_method(_set_zoom, _zoom, 0.0, PLAY_OUT_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_fade.tween_property(self, "modulate:a", 0.0, PLAY_OUT_TIME)
	_fade.chain().tween_callback(func() -> void:
		if is_instance_valid(self):
			queue_free())


## A quick sideways rattle: the card was picked but cannot be afforded.
func shake() -> void:
	_kill(_shake)
	if not is_inside_tree():
		return
	_shake = create_tween()
	for i in SHAKE_TIMES:
		_shake.tween_method(_set_shake_x, 0.0, SHAKE_PX, SHAKE_STEP)
		_shake.tween_method(_set_shake_x, SHAKE_PX, -SHAKE_PX, SHAKE_STEP * 2.0)
		_shake.tween_method(_set_shake_x, -SHAKE_PX, 0.0, SHAKE_STEP)


## Kills every tween and puts the card back at rest, at full size and
## opacity. The hand calls this before dropping its cards.
func stop_motion() -> void:
	_kill(_motion)
	_kill(_entry)
	_kill(_pulse)
	_kill(_shake)
	_kill(_fade)
	_pending_entry = ""
	_zoom = 1.0
	_flip = 1.0
	_raise_y = 0.0
	_deal_y = 0.0
	_shake_x = 0.0
	_tilt_deg = 0.0
	modulate.a = 1.0
	_tired_line.modulate = Color.WHITE
	_apply_transform()


func _queue_entry(kind: String, delay: float) -> void:
	if is_inside_tree():
		_start_entry(kind, delay)
	else:
		_pending_entry = kind
		_pending_delay = delay


func _start_entry(kind: String, delay: float) -> void:
	_kill(_entry)
	_entry = create_tween().set_parallel(true)
	if kind == "deal":
		_entry.tween_method(_set_deal_y, DEAL_DROP, 0.0, DEAL_TIME).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_entry.tween_property(self, "modulate:a", 1.0, DEAL_TIME).set_delay(delay)
	else:
		_entry.tween_method(_set_flip, 0.0, 1.0, FLIP_TIME).set_delay(delay) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Eases zoom, lift and tilt to what `selected` and `raised` call for.
func _refresh_motion() -> void:
	if selected:
		_tween_motion(SELECTED_ZOOM, RAISE_LIFT, SELECTED_TILT_DEG)
	elif raised:
		_tween_motion(RAISE_ZOOM, RAISE_LIFT, 0.0)
	else:
		_tween_motion(1.0, 0.0, 0.0)


func _tween_motion(zoom: float, raise_y: float, tilt_deg: float) -> void:
	_kill(_motion)
	if not is_inside_tree():
		_set_zoom(zoom)
		_set_raise_y(raise_y)
		_set_tilt(tilt_deg)
		return
	_motion = create_tween().set_parallel(true)
	_motion.tween_method(_set_zoom, _zoom, zoom, RAISE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_motion.tween_method(_set_raise_y, _raise_y, raise_y, RAISE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_motion.tween_method(_set_tilt, _tilt_deg, tilt_deg, RAISE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## The TIRED line breathes while the card is tired and in the tree.
func _refresh_pulse() -> void:
	_kill(_pulse)
	_tired_line.modulate = Color.WHITE
	if not (tired and is_inside_tree()):
		return
	_pulse = create_tween().set_loops()
	var low := Color(PULSE_LOW, PULSE_LOW, PULSE_LOW)
	_pulse.tween_property(_tired_line, "modulate", low, PULSE_PERIOD * 0.5).set_trans(Tween.TRANS_SINE)
	_pulse.tween_property(_tired_line, "modulate", Color.WHITE, PULSE_PERIOD * 0.5).set_trans(Tween.TRANS_SINE)


func _set_zoom(v: float) -> void:
	_zoom = v
	_apply_transform()


func _set_flip(v: float) -> void:
	_flip = v
	_apply_transform()


func _set_raise_y(v: float) -> void:
	_raise_y = v
	_apply_transform()


func _set_deal_y(v: float) -> void:
	_deal_y = v
	_apply_transform()


func _set_shake_x(v: float) -> void:
	_shake_x = v
	_apply_transform()


func _set_tilt(v: float) -> void:
	_tilt_deg = v
	_apply_transform()


## Lays every channel over the rest position in one go.
func _apply_transform() -> void:
	scale = Vector2(_zoom * _flip, _zoom)
	rotation = deg_to_rad(_tilt_deg)
	position = rest_position + Vector2(_shake_x, _deal_y + _raise_y)


## The container has just placed the card: that is the new rest position,
## and the motion goes back on top of it.
func _on_parent_sorted() -> void:
	rest_position = position
	_apply_transform()


func _on_resized() -> void:
	pivot_offset = size * 0.5


func _on_mouse_entered() -> void:
	if not disabled:
		set_raised(true)


func _on_mouse_exited() -> void:
	if not has_focus():
		set_raised(false)


func _on_focus_changed(on: bool) -> void:
	set_raised(on or (is_inside_tree() and get_viewport().gui_get_hovered_control() == self))


static func _kill(t: Tween) -> void:
	if t != null and t.is_valid():
		t.kill()


# --- face ----------------------------------------------------------------------

func _build_face() -> void:
	_face = VBoxContainer.new()
	_face.name = "Face"
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.add_theme_constant_override("separation", 4)
	_face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_face.offset_left = FRAME
	_face.offset_top = FRAME
	_face.offset_right = -FRAME
	_face.offset_bottom = -FRAME
	add_child(_face)

	# The title band: ink, with room on the left for the cost badge.
	var band := PanelContainer.new()
	band.name = "TitleBand"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var band_style := StyleBoxFlat.new()
	band_style.bg_color = Palette.INK
	band_style.set_corner_radius_all(6)
	band_style.content_margin_left = BADGE_SIZE - BADGE_OVERHANG + 2.0
	band_style.content_margin_right = 18.0
	band_style.content_margin_top = 2.0
	band_style.content_margin_bottom = 3.0
	band.add_theme_stylebox_override("panel", band_style)
	_title = UiKit.display("Title", TITLE_SIZE, Palette.PAPER)
	_title.name = "Title"
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	band.add_child(_title)
	_face.add_child(band)

	# The art window, framed in ink.
	_art_frame = PanelContainer.new()
	_art_frame.name = "ArtFrame"
	_art_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art_style := StyleBoxFlat.new()
	art_style.bg_color = Palette.INK
	art_style.set_border_width_all(2)
	art_style.border_color = Palette.INK
	art_style.set_corner_radius_all(4)
	art_style.set_content_margin_all(0.0)
	_art_frame.add_theme_stylebox_override("panel", art_style)
	_art = TextureRect.new()
	_art.name = "Art"
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.custom_minimum_size = ART_SIZE
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art_frame.add_child(_art)
	_face.add_child(_art_frame)

	# The text box: a paler paper inset with the numbers and the words.
	var box := UiKit.inset(Vector2(6, 4))
	box.name = "TextBox"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lines := VBoxContainer.new()
	lines.name = "Lines"
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation", 1)
	box.add_child(lines)
	_face.add_child(box)

	var meters := UiKit.hbox(6)
	meters.name = "Meters"
	meters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meters.alignment = BoxContainer.ALIGNMENT_CENTER
	var pow_group := _meter("POW")
	_pow_meter = pow_group.get_node("Meter")
	_pow_value = pow_group.get_node("Value")
	meters.add_child(pow_group)
	var ctl_group := _meter("CTL")
	_ctl_meter = ctl_group.get_node("Meter")
	_ctl_value = ctl_group.get_node("Value")
	meters.add_child(ctl_group)
	lines.add_child(meters)

	var sends_row := UiKit.hbox(4)
	sends_row.name = "Sends"
	sends_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sends_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_sends_icon = UiKit.icon(UiKit.ICON_TYPE[1], 14, Palette.INK)
	sends_row.add_child(_sends_icon)
	_sends = _line("SendsLabel", BODY_SIZE, Palette.INK, Palette.body_bold)
	sends_row.add_child(_sends)
	lines.add_child(sends_row)

	_matchup = _line("Matchup", BODY_SIZE, TEXT_COLOR, Palette.body_bold)
	lines.add_child(_matchup)

	_keyword_row = UiKit.hbox(3)
	_keyword_row.name = "KeywordRow"
	_keyword_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keyword_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_keyword_icon = UiKit.icon(null, 13, Palette.VIOLET)
	_keyword_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_keyword_row.add_child(_keyword_icon)
	_keyword = _line("Keyword", SMALL_SIZE, Palette.VIOLET, Palette.body_bold)
	_keyword.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keyword.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keyword_row.add_child(_keyword)
	lines.add_child(_keyword_row)

	var foot := UiKit.hbox(6)
	foot.name = "Foot"
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	_likes = _line("Likes", SMALL_SIZE, Palette.INK_DIM, Palette.body_medium)
	foot.add_child(_likes)
	_tired_line = _line("Tired", BODY_SIZE, TIRED_COLOR, Palette.body_bold)
	_tired_line.text = "TIRED"
	_tired_line.visible = false
	foot.add_child(_tired_line)
	lines.add_child(foot)

	# The badges hang over the frame's corners.
	_cost_badge = _badge("Cost", Palette.YELLOW, Palette.display, 15)
	_cost_badge.custom_minimum_size = Vector2(BADGE_SIZE, BADGE_SIZE)
	_cost_badge.position = Vector2(-BADGE_OVERHANG, -BADGE_OVERHANG) + Vector2(FRAME, FRAME) * 0.5
	_rarity_badge = UiKit.icon(UiKit.ICON_RARITY[0], 16, Palette.PAPER)
	_rarity_badge.name = "Rarity"
	_rarity_badge.position = Vector2(SIZE.x - FRAME - 18.0, FRAME + 5.0)
	add_child(_rarity_badge)
	_count_badge = _badge("Count", Palette.PAPER, Palette.body_bold, SMALL_SIZE + 1)
	_count_badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_count_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_count_badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_count_badge.offset_right = -FRAME * 0.5
	_count_badge.offset_bottom = -FRAME * 0.5
	_count_badge.visible = false


## "POW" plus a five-segment meter plus the number.
func _meter(caption: String) -> HBoxContainer:
	var group := UiKit.hbox(3)
	group.name = caption
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _line("Caption", SMALL_SIZE, Palette.INK_DIM, Palette.body_bold)
	l.text = caption
	group.add_child(l)
	var meter := UiKit.hbox(1)
	meter.name = "Meter"
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in METER_SEGMENTS:
		var seg := Panel.new()
		seg.custom_minimum_size = Vector2(7, 8)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(2)
		s.bg_color = Color(Palette.INK, 0.15)
		seg.add_theme_stylebox_override("panel", s)
		meter.add_child(seg)
	group.add_child(meter)
	var v := _line("Value", SMALL_SIZE, Palette.INK, Palette.body_bold)
	v.text = "0"
	group.add_child(v)
	return group


static func _fill_meter(meter: HBoxContainer, value: float, color: Color) -> void:
	var lit := roundi(clampf(value, 0.0, 1.0) * METER_SEGMENTS)
	var i := 0
	for seg in meter.get_children():
		var s := (seg as Panel).get_theme_stylebox("panel") as StyleBoxFlat
		if s != null:
			s.bg_color = color if i < lit else Color(Palette.INK, 0.15)
		i += 1


func _line(p_name: String, size: int, color: Color, font: Font) -> Label:
	var l := Label.new()
	l.name = p_name
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A round ink badge with a paper rim and text in `color`, laid over a
## corner of the card.
func _badge(p_name: String, color: Color, font: Font, size: int) -> Label:
	var l := Label.new()
	l.name = p_name
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	var s := StyleBoxFlat.new()
	s.bg_color = Palette.INK
	s.border_color = Palette.PAPER
	s.set_border_width_all(2)
	s.set_corner_radius_all(int(BADGE_SIZE * 0.5))
	s.content_margin_left = 7.0
	s.content_margin_right = 7.0
	s.content_margin_top = 1.0
	s.content_margin_bottom = 1.0
	l.add_theme_stylebox_override("normal", s)
	add_child(l)
	return l


## The frame in one state: the rarity colour at rest, orange when selected.
static func frame_style(color: Color, border: Color, raised: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(CORNER)
	s.set_border_width_all(2)
	s.border_color = border
	s.set_content_margin_all(0.0)
	s.shadow_color = Color(Palette.INK, 0.45)
	s.shadow_size = 2
	s.shadow_offset = Vector2(0, 8 if raised else 4)
	return s


func _apply_style() -> void:
	var border := Palette.ORANGE if selected else Palette.INK
	var c := _frame_color
	add_theme_stylebox_override("normal", frame_style(c, border, selected))
	add_theme_stylebox_override("hover", frame_style(c.lightened(0.12), border, true))
	add_theme_stylebox_override("pressed", frame_style(c.darkened(0.12), border, true))
	add_theme_stylebox_override("hover_pressed", frame_style(c.darkened(0.06), border, true))
	add_theme_stylebox_override("disabled", frame_style(c.darkened(0.3), border, false))
	# The ring sits outside the card, so it still shows on a gold rare card
	# and on a selected one.
	add_theme_stylebox_override("focus", UiKit.focus_style(CORNER, FOCUS_RING_GAP))
