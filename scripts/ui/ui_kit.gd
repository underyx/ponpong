## The static builders every code-built screen and widget is made of, so the
## menus, the cards and the HUD share one printed look: paper plates with an
## ink frame and a violet drop for the screens, ink plates with a paper frame
## for the match HUD, Lilita One for anything that shouts and Rubik for the
## rest. The colours come from Palette; the native widgets (buttons, sliders,
## scrollbars, tooltips) take theirs from theme/ponpong.tres, the project
## theme, and the builders here only add what a place needs on top. Nothing
## here is a node of its own: each builder returns a fresh Control for the
## caller to place, and the only state is what the caller keeps.
class_name UiKit
extends RefCounted

## The names the first kit used, kept so callers read the same.
const TEXT := Palette.PAPER
const MUTED := Palette.PAPER_DIM
const GOLD := Palette.YELLOW
const DANGER := Palette.PINK
const OUTLINE := Palette.INK
const RARITY_BORDER := Palette.RARITY
const BUTTON_SIZE := Vector2(280, 56)
## Width of the ring a focused control wears, so a gamepad always has a
## visible position on screen.
const FOCUS_WIDTH := 3
const BUTTON_CORNER := 12
const PANEL_CORNER := 18
const PLATE_CORNER := 12
## Alpha of an empty pip.
const PIP_EMPTY_ALPHA := 0.3
const PIP_SEPARATION := 4
## The outline a label wears over the 3D scene, per 8px of font size.
const OUTLINE_PER_8PX := 1.0
## The orange second impression under a title, per 16px of font size.
const SHADOW_PER_16PX := 1.0

const ICON_BALL := preload("res://assets/icons/ball.svg")
const ICON_HEART := preload("res://assets/icons/heart.svg")
const ICON_BOLT := preload("res://assets/icons/bolt.svg")
const ICON_PADDLE := preload("res://assets/icons/paddle.svg")
const ICON_CURSOR := preload("res://assets/icons/cursor.svg")
## By BallType value: the glyph of each ball, serve included.
const ICON_TYPE := {
	0: preload("res://assets/icons/type_serve.svg"),
	1: preload("res://assets/icons/type_flat.svg"),
	2: preload("res://assets/icons/type_high.svg"),
	3: preload("res://assets/icons/type_spin.svg"),
	4: preload("res://assets/icons/type_fast.svg"),
}
## By keyword.
const ICON_KEYWORD := {
	"rest": preload("res://assets/icons/kw_rest.svg"),
	"sap": preload("res://assets/icons/kw_sap.svg"),
	"exhaust": preload("res://assets/icons/kw_exhaust.svg"),
	"steady": preload("res://assets/icons/kw_steady.svg"),
	"reach": preload("res://assets/icons/kw_reach.svg"),
	"heavy": preload("res://assets/icons/kw_heavy.svg"),
}
## By Card.Rarity.
const ICON_RARITY := {
	0: preload("res://assets/icons/rarity_common.svg"),
	1: preload("res://assets/icons/rarity_uncommon.svg"),
	2: preload("res://assets/icons/rarity_rare.svg"),
}


# --- text ----------------------------------------------------------------------

## A big display heading over the 3D scene: paper with an ink outline and an
## orange second impression a little off to the side, like a riso print.
static func title(text: String, size := 72, color := Palette.PAPER) -> Label:
	var l := _label(text, Palette.display, size, color)
	l.add_theme_color_override("font_outline_color", Palette.INK)
	l.add_theme_constant_override("outline_size", _outline_for(size))
	_shadow(l, Palette.ORANGE, _shadow_for(size))
	return l


## A display heading printed on a paper plate: ink with the orange impression.
static func heading(text: String, size := 44, color := Palette.INK) -> Label:
	var l := _label(text, Palette.display, size, color)
	_shadow(l, Palette.ORANGE, _shadow_for(size))
	return l


## Display type with no decoration: HUD numbers, chips, card titles.
static func display(text: String, size := 20, color := Palette.PAPER) -> Label:
	return _label(text, Palette.display, size, color)


## Body text over the 3D scene: paper with a thin ink outline.
static func label(text: String, size := 18, color := Palette.PAPER) -> Label:
	var l := _label(text, Palette.body_medium, size, color)
	l.add_theme_color_override("font_outline_color", Palette.INK)
	l.add_theme_constant_override("outline_size", _outline_for(size))
	return l


## Body text printed on a paper plate: ink, no outline.
static func text(text: String, size := 17, color := Palette.INK) -> Label:
	return _label(text, Palette.body, size, color)


## Emphasised body text on a paper plate.
static func strong(text: String, size := 17, color := Palette.INK) -> Label:
	return _label(text, Palette.body_bold, size, color)


## Small, quiet text: footers, captions, the second line.
static func caption(text: String, size := 13, color := Palette.INK_DIM) -> Label:
	return _label(text, Palette.body_medium, size, color)


static func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func _shadow(l: Label, color: Color, offset: int) -> void:
	l.add_theme_color_override("font_shadow_color", color)
	l.add_theme_constant_override("shadow_offset_x", offset)
	l.add_theme_constant_override("shadow_offset_y", offset)
	l.add_theme_constant_override("shadow_outline_size", l.get_theme_constant("outline_size"))


static func _outline_for(size: int) -> int:
	return maxi(2, roundi(size / 8.0 * OUTLINE_PER_8PX))


static func _shadow_for(size: int) -> int:
	return maxi(2, roundi(size / 16.0 * SHADOW_PER_16PX))


# --- buttons ---------------------------------------------------------------------

## A menu button in the theme's print style: paper face, ink frame, a hard
## ink drop that the press flattens. It takes keyboard and gamepad focus and
## shows it with an orange ring. Callers connect `pressed` (UiScreen._bind).
static func button(text: String, size := 22, min_size := BUTTON_SIZE) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", size)
	return b


## A button for the choice that costs something: pink face, paper text.
static func danger_button(text: String, size := 22, min_size := BUTTON_SIZE) -> Button:
	var b := button(text, size, min_size)
	b.add_theme_stylebox_override("normal", button_style(Palette.PINK, Palette.INK))
	b.add_theme_stylebox_override("hover", button_style(Palette.PINK.lightened(0.15), Palette.INK))
	b.add_theme_color_override("font_color", Palette.PAPER)
	b.add_theme_color_override("font_hover_color", Palette.PAPER)
	b.add_theme_color_override("font_focus_color", Palette.PAPER)
	return b


## The face of a button in one state, in the print style.
static func button_style(bg: Color, border: Color, drop := 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(3)
	s.set_corner_radius_all(BUTTON_CORNER)
	s.content_margin_left = 20.0
	s.content_margin_right = 20.0
	s.content_margin_top = 8.0
	s.content_margin_bottom = 8.0 + drop
	if drop > 0:
		s.shadow_color = border
		s.shadow_size = 1
		s.shadow_offset = Vector2(0, drop)
	return s


## A hollow orange ring drawn outside whatever the control shows, for the
## `focus` StyleBox of buttons and cards.
static func focus_style(corner := BUTTON_CORNER, gap := 4.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = Palette.ORANGE
	s.set_border_width_all(FOCUS_WIDTH)
	s.set_corner_radius_all(corner + int(gap))
	s.set_expand_margin_all(gap)
	return s


# --- containers -------------------------------------------------------------------

## A paper plate with an ink frame and a violet drop: the theme's panel.
## Put a vbox inside.
static func panel(min_size := Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	return p


## The paper plate's style, for callers that want to change one thing (the
## VS banner's skew).
static func panel_style(bg := Palette.PAPER, margin := 24.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = Palette.INK
	s.set_border_width_all(3)
	s.set_corner_radius_all(PANEL_CORNER)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(Palette.VIOLET, 0.75)
	s.shadow_size = 1
	s.shadow_offset = Vector2(8, 8)
	return s


## An ink plate with a paper frame: what the match HUD sits on, and what
## an inset box on a paper plate looks like.
static func plate(margin := Vector2(14, 8), alpha := 0.9) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", plate_style(margin, alpha))
	return p


static func plate_style(margin := Vector2(14, 8), alpha := 0.9, bg := Palette.INK, frame := Palette.PAPER) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(bg, alpha)
	s.border_color = frame
	s.set_border_width_all(2)
	s.set_corner_radius_all(PLATE_CORNER)
	s.content_margin_left = margin.x
	s.content_margin_right = margin.x
	s.content_margin_top = margin.y
	s.content_margin_bottom = margin.y
	return s


## A paler box inset on a paper plate: a card's text box, a scouting report.
static func inset(margin := Vector2(14, 10)) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Palette.PAPER_BRIGHT
	s.border_color = Color(Palette.INK, 0.35)
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	s.content_margin_left = margin.x
	s.content_margin_right = margin.x
	s.content_margin_top = margin.y
	s.content_margin_bottom = margin.y
	p.add_theme_stylebox_override("panel", s)
	return p


## A short horizontal rule in orange, the print's second colour.
static func rule(width := 120, color := Palette.ORANGE) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 4)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(width, 4)
	r.size = Vector2(width, 4)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_CENTER_TOP)
	r.position = Vector2(-width * 0.5, 0.0)
	c.add_child(r)
	return c


## A full-screen ink veil that also stops clicks reaching what is under it.
static func dim(alpha := 0.55) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(Palette.INK, alpha)
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


static func spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Puts `child` in the middle of the screen.
static func center(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(child)
	return c


# --- icons and chips ---------------------------------------------------------------

## One of the white SVG glyphs, drawn `size` wide in `color`.
static func icon(texture: Texture2D, size := 20, color := Palette.INK) -> TextureRect:
	var t := TextureRect.new()
	t.texture = texture
	t.custom_minimum_size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


## An opponent's emblem, by id, or an empty rect for an unknown one.
static func emblem(opponent_id: String, size := 48) -> TextureRect:
	var t := icon(emblem_texture(opponent_id), size, Color.WHITE)
	t.name = "Emblem"
	return t


## The emblem drawn for an opponent id, or null when there is none.
static func emblem_texture(opponent_id: String) -> Texture2D:
	var path := "res://assets/opponents/%s.svg" % opponent_id
	return load(path) if (opponent_id != "" and ResourceLoader.exists(path)) else null


## A small pill with an optional glyph and a word: a ball type, a stage, a
## BOSS tag.
static func chip(text: String, texture: Texture2D = null, bg := Palette.INK, fg := Palette.PAPER, size := 13) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(10)
	s.content_margin_left = 8.0
	s.content_margin_right = 9.0
	s.content_margin_top = 2.0
	s.content_margin_bottom = 2.0
	p.add_theme_stylebox_override("panel", s)
	var row := hbox(5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if texture != null:
		row.add_child(icon(texture, size + 3, fg))
	var l := _label(text, Palette.body_bold, size, fg)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	p.add_child(row)
	return p


# --- pips ----------------------------------------------------------------------------

## A row of `count` stamina cells with the first `filled` lit in `color` and
## the rest dimmed. Update it with set_pips(). VisualFx pops the cells, so
## each one is a Panel.
static func pips(count: int, filled: int, color := Palette.YELLOW, size := 14) -> HBoxContainer:
	var row := hbox(PIP_SEPARATION)
	row.set_meta("pip_color", color)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in count:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(size, size * 0.8)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(3)
		s.bg_color = _pip_color(color, i < filled)
		pip.add_theme_stylebox_override("panel", s)
		row.add_child(pip)
	return row


## A row of hearts, the first `filled` lit in pink and the rest gone grey.
## Update it with set_pips().
static func hearts(count: int, filled: int, size := 18) -> HBoxContainer:
	return _glyph_row(ICON_HEART, count, filled, Palette.PINK, size, 2)


## A row of stamina bolts, the first `filled` lit in `color`. Update it with
## set_pips(); VisualFx pops and flashes the glyphs.
static func bolts(count: int, filled: int, color := Palette.ORANGE, size := 16) -> HBoxContainer:
	return _glyph_row(ICON_BOLT, count, filled, color, size, 1)


static func _glyph_row(texture: Texture2D, count: int, filled: int, color: Color, size: int, sep: int) -> HBoxContainer:
	var row := hbox(sep)
	row.set_meta("pip_color", color)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in count:
		var glyph := icon(texture, size, _pip_color(color, i < filled))
		glyph.pivot_offset = Vector2(size, size) * 0.5
		row.add_child(glyph)
	return row


## Lights the first `filled` pips of a row made by pips() or hearts().
static func set_pips(row: HBoxContainer, filled: int) -> void:
	var color: Color = row.get_meta("pip_color", Palette.YELLOW)
	var i := 0
	for child in row.get_children():
		if child is Panel:
			var s := (child as Panel).get_theme_stylebox("panel") as StyleBoxFlat
			if s != null:
				s.bg_color = _pip_color(color, i < filled)
			i += 1
		elif child is TextureRect:
			(child as TextureRect).modulate = _pip_color(color, i < filled)
			i += 1


static func _pip_color(color: Color, lit: bool) -> Color:
	return color if lit else Color(Palette.PAPER_DIM, PIP_EMPTY_ALPHA)
