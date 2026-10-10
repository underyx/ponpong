## The end of a run, won or lost: the headline, where it ended, the run's
## numbers and the seed, with a fresh run, the same seed again, or the menu.
## A won run rains confetti over the panel.
class_name RunEndScreen
extends UiScreen

const TITLE_SIZE := 72
const SUB_SIZE := 24
const STAT_SIZE := 20
const SEED_SIZE := 18
## Confetti: this many flakes alive at once, each falling for this long.
const CONFETTI_AMOUNT := 80
const CONFETTI_LIFETIME := 2.5
## Each flake is a 4x4 white square drawn at this scale, in these colours.
const CONFETTI_TEXTURE_SIZE := 4
const CONFETTI_SCALE_MIN := 1.5
const CONFETTI_SCALE_MAX := 3.0
const CONFETTI_COLORS := [UiKit.GOLD, UiKit.DANGER, Color(0.45, 0.70, 0.95), Color(0.60, 0.85, 0.60),
	Color(0.85, 0.65, 0.95), UiKit.TEXT]
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
	add_child(UiKit.dim(0.70))
	var won := bool(args.get("won", false))
	var stats: Dictionary = args.get("stats", {})
	var box := UiKit.vbox(8)
	var heading := UiKit.title("CHAMPION" if won else "RUN OVER", TITLE_SIZE)
	heading.add_theme_color_override("font_color", UiKit.GOLD if won else UiKit.DANGER)
	box.add_child(heading)
	if not won:
		box.add_child(UiKit.label("at stage %d vs %s" % [int(args.get("stage", 0)) + 1, String(args.get("opponent_name", "?"))],
			SUB_SIZE))
	box.add_child(_spacer(6))
	box.add_child(_stat("Opponents beaten   %d / %d" % [int(stats.get("matches_won", 0)), RunState.STAGES]))
	box.add_child(_stat("Points   %d won  ·  %d lost" % [int(stats.get("points_won", 0)), int(stats.get("points_lost", 0))]))
	box.add_child(_stat("Longest rally   %d" % int(stats.get("longest_rally", 0))))
	box.add_child(_stat("Cards   %d added  ·  %d removed  ·  %d in the deck" % [
		int(stats.get("cards_added", 0)), int(stats.get("cards_removed", 0)), int(args.get("deck_size", 0))]))
	box.add_child(_stat("Tired plays   %d" % int(stats.get("tired_plays", 0))))
	box.add_child(_spacer(4))
	box.add_child(UiKit.label("Seed %d" % int(args.get("seed", 0)), SEED_SIZE, UiKit.GOLD))
	box.add_child(_spacer(6))
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
	var b := UiKit.button(text, 20, Vector2(220, 48))
	_bind(b, action)
	row.add_child(b)
	return b


static func _stat(text: String) -> Label:
	return UiKit.label(text, STAT_SIZE, UiKit.MUTED)


static func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = MOUSE_FILTER_IGNORE
	return c
