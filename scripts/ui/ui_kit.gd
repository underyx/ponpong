## The palette and the static builders every code-built screen and widget is
## made of, so menus, cards and HUD rows share one look. Nothing here is a
## node of its own: each builder returns a fresh Control for the caller to
## place, and the only state is what the caller keeps.
class_name UiKit
extends RefCounted

const PANEL := Color(0.09, 0.07, 0.14, 0.88)
const TEXT := Color(0.98, 0.96, 0.90)
const MUTED := Color(0.72, 0.70, 0.80)
const GOLD := Color(1.0, 0.85, 0.45)
const DANGER := Color(0.95, 0.40, 0.40)
const OUTLINE := Color(0.09, 0.07, 0.14)
## Card border by Card.Rarity: common blends into the outline, uncommon is
## silver, rare is gold.
const RARITY_BORDER := {0: Color(0.09, 0.07, 0.14), 1: Color(0.75, 0.78, 0.85), 2: Color(1.0, 0.82, 0.35)}
const BUTTON_SIZE := Vector2(260, 52)
## Button face at rest; hover lightens it, pressed darkens it.
const BUTTON_BG := Color(0.20, 0.17, 0.30)
const BUTTON_BORDER := Color(0.38, 0.33, 0.52)
## The ring a focused button or card wears, so a gamepad always has a
## visible position on screen.
const FOCUS_WIDTH := 3
const BUTTON_CORNER := 10
const PANEL_CORNER := 16
const PANEL_MARGIN := 28
const TITLE_OUTLINE := 10
const LABEL_OUTLINE := 5
## Alpha of an empty pip.
const PIP_EMPTY_ALPHA := 0.35
const PIP_SEPARATION := 4


# --- text ----------------------------------------------------------------------

## A big centred heading with a thick outline, readable over the 3D table.
static func title(text: String, size := 72) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TEXT)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", TITLE_OUTLINE)
	return l


## Body text with a thin outline.
static func label(text: String, size := 20, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", LABEL_OUTLINE)
	return l


# --- buttons ---------------------------------------------------------------------

## A menu button that takes keyboard and gamepad focus and shows it with a
## gold ring. Callers connect `pressed` (UiScreen._bind does).
static func button(text: String, size := 22, min_size := BUTTON_SIZE) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_focus_color", TEXT)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_hover_pressed_color", GOLD)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", Color(MUTED, 0.5))
	b.add_theme_color_override("font_outline_color", OUTLINE)
	b.add_theme_constant_override("outline_size", 4)
	b.add_theme_stylebox_override("normal", button_style(BUTTON_BG, BUTTON_BORDER))
	b.add_theme_stylebox_override("hover", button_style(BUTTON_BG.lightened(0.12), GOLD.darkened(0.2)))
	b.add_theme_stylebox_override("pressed", button_style(BUTTON_BG.darkened(0.25), GOLD))
	b.add_theme_stylebox_override("hover_pressed", button_style(BUTTON_BG.darkened(0.1), GOLD))
	b.add_theme_stylebox_override("disabled", button_style(Color(BUTTON_BG, 0.45), Color(BUTTON_BORDER, 0.45)))
	b.add_theme_stylebox_override("focus", focus_style(BUTTON_CORNER))
	return b


## The face of a menu button in one state.
static func button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(BUTTON_CORNER)
	s.content_margin_left = 18.0
	s.content_margin_right = 18.0
	s.content_margin_top = 8.0
	s.content_margin_bottom = 8.0
	return s


## A hollow gold ring drawn over whatever the control shows, for the `focus`
## StyleBox of buttons and cards.
static func focus_style(corner := BUTTON_CORNER) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = GOLD
	s.set_border_width_all(FOCUS_WIDTH)
	s.set_corner_radius_all(corner)
	return s


## A card face: the colour of the card with a shadow that lifts when raised.
## The border carries the rarity (RARITY_BORDER) or the selection colour.
static func card_style(color: Color, border: Color, raised: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(BUTTON_CORNER)
	s.set_border_width_all(3)
	s.border_color = border
	s.set_content_margin_all(10.0)
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	s.shadow_size = 8 if raised else 4
	s.shadow_offset = Vector2(0, 4)
	return s


# --- containers -------------------------------------------------------------------

## A dark rounded box with generous padding; put a vbox inside.
static func panel(min_size := Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL
	s.set_corner_radius_all(PANEL_CORNER)
	s.set_content_margin_all(PANEL_MARGIN)
	p.add_theme_stylebox_override("panel", s)
	return p


## A full-screen black veil that also stops clicks reaching what is under it.
static func dim(alpha := 0.55) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.0, 0.0, 0.0, alpha)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


## Puts `child` in the middle of the screen.
static func center(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(child)
	return c


# --- pips ----------------------------------------------------------------------------

## A row of `count` round pips with the first `filled` lit in `color` and the
## rest dimmed: stamina, hearts. Update it with set_pips().
static func pips(count: int, filled: int, color := GOLD, size := 14) -> HBoxContainer:
	var row := hbox(PIP_SEPARATION)
	row.set_meta("pip_color", color)
	for i in count:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(size, size)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var s := StyleBoxFlat.new()
		@warning_ignore("integer_division")
		s.set_corner_radius_all(size / 2)
		s.bg_color = _pip_color(color, i < filled)
		pip.add_theme_stylebox_override("panel", s)
		row.add_child(pip)
	return row


## Lights the first `filled` pips of a row made by pips().
static func set_pips(row: HBoxContainer, filled: int) -> void:
	var color: Color = row.get_meta("pip_color", GOLD)
	var i := 0
	for child in row.get_children():
		if child is Panel:
			var s := (child as Panel).get_theme_stylebox("panel") as StyleBoxFlat
			if s != null:
				s.bg_color = _pip_color(color, i < filled)
			i += 1


static func _pip_color(color: Color, lit: bool) -> Color:
	return color if lit else Color(MUTED, PIP_EMPTY_ALPHA)
