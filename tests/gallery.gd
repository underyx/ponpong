## Renders every generated asset to one PNG: the app icon, the HUD icons
## (white, so they are shown over ink and over paper), the 25 card windows,
## the 9 opponent emblems and, once CardView exists, one card face per card.
## A quick way to look at tools/build_art.py's output without the editor.
## Needs a display, virtual or real:
##   LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --path . --rendering-driver opengl3 -s tests/gallery.gd -- /out/dir
extends SceneTree

const SETTLE := 4
const CELL := Vector2(136, 68)
const EMBLEM := 96
const ICON := 48
const COLUMNS := 8

var frames := 0
var out_dir := OS.get_user_data_dir().path_join("shots")
var pages: Array[Control] = []
var names: Array[String] = []
var page := 0
var next_at := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_add_page("gallery_icons.png", _icons_page())
	_add_page("gallery_cards.png", _cards_page())
	_add_page("gallery_emblems.png", _emblems_page())
	if ClassDB.class_exists("CardView") or ResourceLoader.exists("res://scripts/ui/card_view.gd"):
		_add_page("gallery_faces.png", _faces_page())


func _process(_delta: float) -> bool:
	frames += 1
	if frames < next_at:
		return false
	if page > 0:
		_save(names[page - 1])
	if page >= pages.size():
		quit(0)
		return true
	for p in pages:
		p.visible = false
	pages[page].visible = true
	page += 1
	next_at = frames + SETTLE
	return false


func _add_page(file_name: String, control: Control) -> void:
	control.visible = false
	root.add_child(control)
	pages.append(control)
	names.append(file_name)


func _paper() -> Control:
	var bg := ColorRect.new()
	bg.color = Palette.PAPER
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return bg


func _icons_page() -> Control:
	var bg := _paper()
	var ink := ColorRect.new()
	ink.color = Palette.INK
	ink.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ink.anchor_bottom = 0.5
	bg.add_child(ink)
	var files := _list("res://assets/icons")
	for row in 2:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		h.position = Vector2(24, 40 + row * 360)
		bg.add_child(h)
		for f in files:
			var t := TextureRect.new()
			t.texture = load("res://assets/icons/" + f)
			t.custom_minimum_size = Vector2(ICON, ICON)
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			t.modulate = Palette.PAPER if row == 0 else Palette.INK
			h.add_child(t)
	var icon := TextureRect.new()
	icon.texture = load("res://icon.svg")
	icon.position = Vector2(24, 140)
	icon.custom_minimum_size = Vector2(128, 128)
	bg.add_child(icon)
	var big := TextureRect.new()
	big.texture = load("res://icon.svg")
	big.position = Vector2(180, 110)
	big.custom_minimum_size = Vector2(192, 192)
	big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.add_child(big)
	var label := Label.new()
	label.text = "Lilita One display  /  Rubik body 300 to 900: Pick a card, then aim at a zone on their half."
	label.add_theme_font_override("font", Palette.display)
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", Palette.PAPER)
	label.position = Vector2(24, 280)
	bg.add_child(label)
	var body := Label.new()
	body.text = "Rubik: Every card costs 0 to 3 stamina. Both players start a match at 6, get 1 back at the start of every point. 0123456789 POW CTL"
	body.add_theme_font_size_override("font_size", 20)
	body.add_theme_color_override("font_color", Palette.INK)
	body.position = Vector2(24, 460)
	bg.add_child(body)
	var bold := Label.new()
	bold.text = "Rubik Bold: STRONG vs High   weak vs Fast   Rest: +2 stamina.   x3   likes deep   TIRED"
	bold.add_theme_font_override("font", Palette.body_bold)
	bold.add_theme_font_size_override("font_size", 20)
	bold.add_theme_color_override("font_color", Palette.INK)
	bold.position = Vector2(24, 500)
	bg.add_child(bold)
	return bg


func _cards_page() -> Control:
	var bg := _paper()
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.position = Vector2(24, 24)
	bg.add_child(grid)
	for id in CardLibrary.ALL_IDS:
		var t := TextureRect.new()
		t.texture = load("res://assets/cards/%s.svg" % id)
		t.custom_minimum_size = CELL
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		grid.add_child(t)
	return bg


func _emblems_page() -> Control:
	var bg := _paper()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	h.position = Vector2(24, 24)
	bg.add_child(h)
	for id in OpponentLibrary.all_ids():
		var t := TextureRect.new()
		t.texture = load("res://assets/opponents/%s.svg" % id)
		t.custom_minimum_size = Vector2(EMBLEM, EMBLEM)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		h.add_child(t)
	var small := HBoxContainer.new()
	small.add_theme_constant_override("separation", 20)
	small.position = Vector2(24, 160)
	bg.add_child(small)
	for id in OpponentLibrary.all_ids():
		var t := TextureRect.new()
		t.texture = load("res://assets/opponents/%s.svg" % id)
		t.custom_minimum_size = Vector2(40, 40)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		small.add_child(t)
	return bg


func _faces_page() -> Control:
	var bg := _paper()
	var dark := ColorRect.new()
	dark.color = Palette.INK
	dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dark.anchor_right = 0.5
	bg.add_child(dark)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.position = Vector2(16, 16)
	bg.add_child(grid)
	var i := 0
	for id in CardLibrary.ALL_IDS:
		var view := CardView.new()
		var card := CardLibrary.by_id(id)
		# A mix of modes: hand mode with every matchup, tired, and deck mode.
		match i % 5:
			0: view.set_card(card, BallType.HIGH, 6)
			1: view.set_card(card, BallType.FAST, 1)
			2: view.set_card(card, BallType.SPIN, 0)
			3: view.set_card(card)
			4: view.set_card(card, BallType.NONE, -1, 3)
		if i == 7:
			view.set_selected(true)
		grid.add_child(view)
		i += 1
	return bg


func _list(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir_path):
		if f.ends_with(".svg"):
			out.append(f)
	out.sort()
	return out


func _save(file_name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join(file_name)
	var err := img.save_png(path)
	print("saved %s err=%d" % [path, err])
