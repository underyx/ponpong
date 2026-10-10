## The end of a run, won or lost: the headline, where it ended, the run's
## numbers and the seed, with a fresh run, the same seed again, or the menu.
## A won run rains confetti over the panel.
class_name RunEndScreen
extends UiScreen

const TITLE_SIZE := 80
const SUB_SIZE := 22
const STAT_SIZE := 18
const SEED_SIZE := 16
## Confetti: this many flakes alive at once, each falling for this long.
const CONFETTI_AMOUNT := 90
const CONFETTI_LIFETIME := 2.5
## Each flake is a 4x4 white square drawn at this scale, in these colours.
const CONFETTI_TEXTURE_SIZE := 4
const CONFETTI_SCALE_MIN := 1.5
const CONFETTI_SCALE_MAX := 3.0
const CONFETTI_COLORS := [Palette.YELLOW, Palette.PINK, Palette.BLUE_LIGHT, Palette.TEAL, Palette.ORANGE, Palette.PAPER]
const CONFETTI_GRAVITY := Vector2(0.0, 240.0)
const CONFETTI_SPEED_MIN := 40.0
const CONFETTI_SPEED_MAX := 140.0
const CONFETTI_SPIN := 240.0

var _new_run: Button


## args: {"won": bool, "stage": int, "opponent_name": String, "stats": Dictionary,
##        "seed": int, "deck_size": int}
func setup(p_args: Dictionary) -> void:
	super(p_args)
	back_action = ""
	add_child(UiKit.dim(0.65))
	var won := bool(args.get("won", false))
	var stats: Dictionary = args.get("stats", {})
	var box := UiKit.vbox(6)
	box.add_child(UiKit.heading("CHAMPION" if won else "RUN OVER", TITLE_SIZE, Palette.TEAL if won else Palette.PINK))
	box.add_child(UiKit.rule())
	if won:
		box.add_child(UiKit.text("Six opponents, one deck, no hearts spared", SUB_SIZE))
	else:
		box.add_child(UiKit.text("at stage %d vs %s" % [int(args.get("stage", 0)) + 1, String(args.get("opponent_name", "?"))],
			SUB_SIZE))
	box.add_child(UiKit.spacer(4))
	var inset := UiKit.inset(Vector2(18, 8))
	inset.name = "Stats"
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 2)
	_row(grid, "Opponents beaten", "%d / %d" % [int(stats.get("matches_won", 0)), RunState.STAGES])
	_row(grid, "Points", "%d won  ·  %d lost" % [int(stats.get("points_won", 0)), int(stats.get("points_lost", 0))])
	_row(grid, "Longest rally", str(int(stats.get("longest_rally", 0))))
	_row(grid, "Cards", "%d added  ·  %d removed  ·  %d in the deck" % [
		int(stats.get("cards_added", 0)), int(stats.get("cards_removed", 0)), int(args.get("deck_size", 0))])
	_row(grid, "Tired plays", str(int(stats.get("tired_plays", 0))))
	inset.add_child(grid)
	box.add_child(inset)
	box.add_child(UiKit.spacer(2))
	var seed_chip := UiKit.chip("Seed %d" % int(args.get("seed", 0)), null, Palette.INK, Palette.YELLOW, SEED_SIZE)
	seed_chip.size_flags_horizontal = SIZE_SHRINK_CENTER
	box.add_child(seed_chip)
	box.add_child(UiKit.spacer(8))
	var row := UiKit.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_new_run = _menu_button(row, "New Run", "new_run")
	_menu_button(row, "Retry this seed", "retry")
	_menu_button(row, "Main Menu", "menu")
	box.add_child(row)
	var panel := UiKit.panel()
	panel.add_child(box)
	add_child(UiKit.center(panel))
	if won:
		add_child(_confetti())


func first_focus() -> Control:
	return _new_run


## A rain of coloured squares from the top edge, across the design width.
## The texture is made here from an Image, so there is no asset to load.
static func _confetti() -> CPUParticles2D:
	var img := Image.create_empty(CONFETTI_TEXTURE_SIZE, CONFETTI_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var width := float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280))
	var p := CPUParticles2D.new()
	p.name = "Confetti"
	p.texture = ImageTexture.create_from_image(img)
	p.amount = CONFETTI_AMOUNT
	p.lifetime = CONFETTI_LIFETIME
	p.position = Vector2(width * 0.5, -2.0 * CONFETTI_TEXTURE_SIZE * CONFETTI_SCALE_MAX)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(width * 0.5, 2.0)
	p.direction = Vector2(0.0, 1.0)
	p.spread = 30.0
	p.gravity = CONFETTI_GRAVITY
	p.initial_velocity_min = CONFETTI_SPEED_MIN
	p.initial_velocity_max = CONFETTI_SPEED_MAX
	p.angular_velocity_min = -CONFETTI_SPIN
	p.angular_velocity_max = CONFETTI_SPIN
	p.scale_amount_min = CONFETTI_SCALE_MIN
	p.scale_amount_max = CONFETTI_SCALE_MAX
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in CONFETTI_COLORS.size():
		offsets.append(float(i) / float(CONFETTI_COLORS.size() - 1))
		colors.append(CONFETTI_COLORS[i])
	var ramp := Gradient.new()
	ramp.offsets = offsets
	ramp.colors = colors
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	p.color_initial_ramp = ramp
	p.emitting = true
	return p


func _menu_button(row: BoxContainer, text: String, action: String) -> Button:
	var b := UiKit.button(text, 20, Vector2(220, 52))
	_bind(b, action)
	row.add_child(b)
	return b


static func _row(grid: GridContainer, name_text: String, value: String) -> void:
	var n := UiKit.text(name_text, STAT_SIZE, Palette.INK_DIM)
	n.add_theme_font_override("font", Palette.body_medium)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(n)
	var v := UiKit.strong(value, STAT_SIZE)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	grid.add_child(v)
