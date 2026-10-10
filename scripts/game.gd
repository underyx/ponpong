## The match presenter. Owns a MatchState, feeds it actions (from the UI for
## player 0, from AIController for player 1) and plays back the events it
## returns as tweens, labels and callouts. It never decides a rally outcome.
##
## One instance lives in main.tscn for the whole session: the Director calls
## start(config) for every match and set_idle(true) between runs, when the
## 3D table is just the menus' backdrop. Every await is followed by a
## generation check so a match that was abandoned or replaced stops
## presenting. Run on its own (F6 on match.tscn) it starts a quick match
## against the opener and rematches when it ends.
##
## Every feel moment (a swing, a landing, a point, a stamina change) goes out
## as the `fx` signal; the sound and the particle nodes subscribe to it and
## this script never calls them. The camera rig is reached only through
## has_method(), so the scene runs with a plain Camera3D too.
##
## Player 0 is always drawn at the bottom. For online play, swap AIController
## for a controller that receives the other peer's actions, and send player 0's
## actions out from _submit().
class_name MatchScene
extends Node3D

## Fired after the YOU WIN / YOU LOSE callout has shown for MATCH_OVER_HOLD.
signal match_finished(winner: int, score: Array, longest_rally: int, stats: Array)
## A feel moment. Names and data, in match order:
##   match_start  {opponent: String, boss: bool}
##   point_start  {server: int, score: Array, stamina: Array}
##   card_select  {index: int}          card_deselect {}
##   zone_hover   {zone: Zone}          zone_commit   {zone: Zone}
##   swing        {player, power, color, tired}            at paddle contact
##   landed       {player, outcome, kind, zone, pos, color, tired}
##                                      after the flight, before the callout
##   point        {winner, score, points_to_win, rally_length}
##   rally        {length}              at RALLY_MILESTONES
##   stamina      {player, value, delta}   whenever a shown value changes
##   match_over   {won: bool, score: Array}
signal fx(name: String, data: Dictionary)

## HAND: a card is being picked (focus walks the hand). AIM: a card is chosen
## and the zone cursor is live. NONE: the local player cannot act.
enum InputMode { NONE, HAND, AIM }

const PADDLE_X := 1.6
const PADDLE_Y := 1.0
const AI_THINK_TIME := 0.55
const POINT_HOLD_TIME := 1.1
## How long the VS banner holds before the first point.
const VS_BANNER_TIME := 1.6
## How long YOU WIN / YOU LOSE shows before match_finished fires.
const MATCH_OVER_HOLD := 1.2
const LOCAL := 0
const REMOTE := 1
## The HUD keeps the middle of the screen for the table: the score plate
## sits top centre, the situation (stage, hearts, the incoming ball and the
## hint) in a column on the left, the opponent and the commentary in one on
## the right, the hand along the bottom.
const SCORE_FONT_SIZE := 38
const HUD_EDGE := Vector2(22, 18)
## Width of the two side columns' plates.
const SIDE_COLUMN_WIDTH := 300
## Where the zone cursor starts: the short middle of their half.
const CURSOR_START := Vector2i(0, 2)
const MY_PIP_COLOR := Palette.ORANGE
const THEIR_PIP_COLOR := Palette.BLUE_LIGHT
const HINT_KEYBOARD := "1-4 card  ·  arrows aim\nEnter play  ·  Esc pause"
const HINT_GAMEPAD := "A pick  ·  d-pad aim\nA play  ·  B back  ·  Start pause"
const RALLY_MILESTONES := [4, 7, 10, 15]
## Opponent names up to this long go whole into the score line, longer ones
## as their first word.
const SHORT_NAME_MAX := 11
## Where the ball rests while the table is a backdrop.
const IDLE_BALL_POSITION := Vector3(-1.1, ZoneLayout.TOP_Y + 0.035, 0.15)
## A callout holds this long, then fades out over CALLOUT_FADE.
const CALLOUT_HOLD := 0.9
const CALLOUT_FADE := 0.25
const CALLOUT_GOOD := Palette.YELLOW
const CALLOUT_BAD := Palette.PINK
## Shots at least this powerful freeze time for a beat at contact...
const HIT_STOP_POWER := 0.8
## ... and this powerful punch the camera, by -2 - 4 * power degrees of fov.
const PUNCH_POWER := 0.6
## The VS banner slides in from this far right (a fraction of the screen)
## and out to the left, with a skewed backplate.
const BANNER_SLIDE_FROM := 0.6
const BANNER_SLIDE_TO := 0.25
const BANNER_SLIDE_IN := 0.3
const BANNER_SLIDE_OUT := 0.25
const BANNER_SKEW := 0.12
## Idle life: the paddles breathe, and the opponent's twitches while the AI
## thinks under a "..." label.
const PADDLE_BOB := 0.01
const THINK_JITTER := 0.02
## Where the "..." floats relative to the opponent's paddle: a little above it
## and towards the camera's right, clear of the HUD block the far paddle sits
## under and of the ball waiting at the blade.
const THINK_OFFSET := Vector3(-0.3, 0.08, 0.26)
## Where the camera looks: a little toward the player's end, so the table
## sits high enough in the frame for the hand to clear its near edge.
const LOOK_AT := Vector3(-0.70, ZoneLayout.TOP_Y, 0.0)

@onready var ball: BallFlight = $World/Ball
@onready var grid: ZoneGrid = $World/ZoneGrid
@onready var paddles: Array[Node3D] = [$World/PlayerPaddle, $World/OpponentPaddle]
@onready var camera: Camera3D = $World/Camera3D
@onready var callout: Label3D = $World/Callout
@onready var hud_root: Control = $UI/Root
@onready var hand_ui: HandUI = %Hand

## Code-built HUD, see _build_hud(). The labels the tests and VisualFx read
## are also exposed as %ScoreLabel, %IncomingLabel, %HintLabel, %LogLabel,
## %MyPips, %TheirPips and %RallyLabel.
var score_label: Label
var incoming_label: Label
var hint_label: Label
var log_label: Label
var stamina_row: HBoxContainer
var hearts_row: HBoxContainer
var stage_label: Label
var opponent_label: Label
var their_name_label: Label
var to_win_label: Label
var boss_label: Control
var versus_banner: Control
var rally_label: Label
var controls_hint: Label
## The left column's plate with the incoming ball and the hint, shown only
## while there is something to say; the right column's commentary likewise.
var situation_plate: PanelContainer
var log_plate: PanelContainer

var layout := ZoneLayout.new()
var state: MatchState
## Personality of the computer seat; empty means AIController.DEFAULTS.
var ai_params: Dictionary = {}
var opponent_name := "Them"
## The opponent's library id, for the emblem; "" shows none.
var opponent_id := ""
## What the score plate calls them: "YOU  3  -  2  JAX DUNN".
var short_name := "THEM"
var points_to_win := MatchState.DEFAULT_POINTS_TO_WIN

## True while the local player may act.
var input_open := false
var selected_index := -1
var hover_zone: Zone = null
var input_mode := InputMode.NONE
## Keyboard and gamepad aim as (row, col) on their half. Mouse hover writes
## it too, so hover_zone is always the cursor's zone while aiming.
var cursor := CURSOR_START
var idle := false
var gamepad := false

var _queue: Array[Dictionary] = []
var _pumping := false
## Stamina as last shown: follows events, not the state, so the HUD does not
## run ahead of the ball.
var _shown_stamina: Array = [MatchState.STAMINA_MAX, MatchState.STAMINA_MAX]
## Bumped by start() and set_idle(true). Every await re-checks it.
var _generation := 0
var _my_pips: HBoxContainer
var _their_pips: HBoxContainer
var _banner_labels: Dictionary = {}
var _banner_emblem: TextureRect
var _emblem: TextureRect
var _banner_tween: Tween
var _callout_tween: Tween
var _blade_material: ShaderMaterial
var _paddle_rest: Array[Vector3] = []
var _base_fov := 44.0
var _standalone := false
## Seconds since _ready, for the idle motion.
var _time := 0.0
## True while the AI is taking its think time.
var _thinking := false
var _think_label: Label3D


func _ready() -> void:
	# Idempotent, so under the Director this is a no-op; standalone it is
	# what gives the hand its 1-4, Q/E and Backspace keys.
	InputSetup.register()
	camera.look_at(LOOK_AT)
	_base_fov = camera.fov
	grid.build(layout)
	for p in paddles:
		_paddle_rest.append(p.rotation)
	_build_hud()
	_build_think_label()
	hand_ui.card_chosen.connect(_on_card_chosen)
	callout.visible = false
	_standalone = get_parent() == get_tree().root or get_tree().current_scene == self
	if _standalone:
		match_finished.connect(func(_winner: int, _score: Array, _rally: int, _stats: Array) -> void:
			_start_standalone.call_deferred())
		_start_standalone()


## Idle life: the paddles breathe, the opponent's twitches while the AI
## thinks, and the "..." label floats above it. Pausable with the match.
func _process(delta: float) -> void:
	_time += delta
	for p in 2:
		paddles[p].position.y = PADDLE_Y + sin(_time * 2.0 + p * 2.1) * PADDLE_BOB
	if _thinking:
		paddles[REMOTE].rotation.z = _paddle_rest[REMOTE].z + sin(_time * 40.0) * THINK_JITTER
		_think_label.position = paddles[REMOTE].position + THINK_OFFSET
	situation_plate.visible = incoming_label.text != "" or hint_label.text != ""
	log_plate.visible = log_label.text != ""


# --- public API for the Director ------------------------------------------------

## Begins a match. config: {"seed", "decks": [Array[Card], Array[Card]],
## "points_to_win", "ai", "opponent_id", "opponent_name", "blurb",
## "paddle_color", "boss", "hearts", "stage", "stages"}. Any match in
## progress stops at once.
func start(config: Dictionary) -> void:
	_generation += 1
	var gen := _generation
	idle = false
	_reset_presentation()
	state = MatchState.new(int(config["seed"]), config["decks"], layout,
		int(config.get("points_to_win", MatchState.DEFAULT_POINTS_TO_WIN)))
	points_to_win = state.points_to_win
	ai_params = config.get("ai", {})
	opponent_name = String(config.get("opponent_name", "Them"))
	opponent_id = String(config.get("opponent_id", ""))
	short_name = short_name_of(opponent_name)
	var boss := bool(config.get("boss", false))
	_set_paddle_color(config.get("paddle_color", null))
	opponent_label.text = opponent_name
	their_name_label.text = short_name
	to_win_label.text = "first to %d" % points_to_win
	boss_label.visible = boss
	_emblem.texture = UiKit.emblem_texture(opponent_id)
	_emblem.visible = _emblem.texture != null
	stage_label.text = "STAGE %d of %d" % [int(config.get("stage", 0)) + 1, int(config.get("stages", RunState.STAGES))]
	UiKit.set_pips(hearts_row, int(config.get("hearts", RunState.HEARTS)))
	hud_root.visible = true
	_shown_stamina = [MatchState.STAMINA_MAX, MatchState.STAMINA_MAX]
	_refresh_score([0, 0])
	_log("%s. First to %d." % [opponent_name, points_to_win])
	_set_orbit(false)
	fx.emit("match_start", {"opponent": opponent_name, "boss": boss})
	await _show_versus(config, boss)
	if gen != _generation:
		return
	_enqueue(state.start_point())


## Idle: the HUD hides and the table is a backdrop. Any match stops at once.
func set_idle(p_idle: bool) -> void:
	idle = p_idle
	if p_idle:
		_generation += 1
		_reset_presentation()
		ball.global_position = IDLE_BALL_POSITION
		_set_orbit(true)
	hud_root.visible = not p_idle


## The camera rig (M3) orbits the table while the menus are up. A plain
## Camera3D has no orbit and is left alone.
func _set_orbit(on: bool) -> void:
	if camera.has_method("orbit"):
		camera.call("orbit", on)


## Shows or hides the match HUD. The Director hides it under every screen
## but Pause, so the score, the hint and the hand do not show through the
## reward, deck and run end panels of a match that is already over.
func set_hud_visible(on: bool) -> void:
	hud_root.visible = on and not idle


## After a pause: focus goes back to the hand while a card is being picked.
## While aiming nothing holds focus on purpose, so the arrows reach the cursor.
func refocus() -> void:
	if input_open and input_mode == InputMode.HAND:
		hand_ui.focus_index(maxi(selected_index, 0))


## Switches the controls hint between keyboard and gamepad wording.
func set_gamepad(on: bool) -> void:
	gamepad = on
	controls_hint.text = HINT_GAMEPAD if on else HINT_KEYBOARD


## "Mara \"Chopper\" Vale" -> "MARA VALE", "Ilse Varga, Champion" -> "ILSE VARGA",
## "Dot & Dash" -> "DOT & DASH"; anything still longer than SHORT_NAME_MAX
## becomes its first word.
static func short_name_of(full_name: String) -> String:
	var s := full_name.get_slice(",", 0)
	var quote := s.find("\"")
	while quote >= 0:
		var close := s.find("\"", quote + 1)
		if close < 0:
			break
		s = s.substr(0, quote) + s.substr(close + 1)
		quote = s.find("\"")
	s = " ".join(s.split(" ", false)).to_upper()
	if s.length() > SHORT_NAME_MAX:
		s = s.get_slice(" ", 0)
	return s


func _start_standalone() -> void:
	var pim := OpponentLibrary.profile(OpponentLibrary.OPENER)
	# Presenter side: a quick match may draw its own seed.
	start({
		"seed": randi(),
		"decks": [CardLibrary.starter_deck(), CardLibrary.from_ids(OpponentLibrary.deck_ids(OpponentLibrary.OPENER))],
		"points_to_win": MatchState.DEFAULT_POINTS_TO_WIN,
		"ai": pim["ai"],
		"opponent_id": OpponentLibrary.OPENER,
		"opponent_name": pim["name"],
		"blurb": pim["blurb"],
		"paddle_color": pim["paddle_color"],
		"boss": false,
		"hearts": RunState.HEARTS,
		"stage": 0,
		"stages": RunState.STAGES,
	})


## Stops whatever the previous match was doing and clears the HUD.
func _reset_presentation() -> void:
	ball.stop()
	_hide_callout()
	_queue.clear()
	_pumping = false
	input_open = false
	input_mode = InputMode.NONE
	selected_index = -1
	hover_zone = null
	cursor = CURSOR_START
	grid.clear_all()
	hand_ui.clear()
	incoming_label.text = ""
	hint_label.text = ""
	rally_label.visible = false
	_hide_banner()
	_set_thinking(false)
	for p in 2:
		paddles[p].rotation = _paddle_rest[p]
		_slide_paddle(p, MatchState.HOME_COL, true)


# --- HUD ------------------------------------------------------------------------

## Builds the HUD around the hand the scene file carries. Top centre, the
## score plate: YOU, the score, their name, and the stamina bolts under
## each. Top left, the stage and hearts, then the situation plate with the
## incoming ball and the hint. Top right, the opponent's nameplate with
## their emblem, then the commentary. Bottom right, the controls hint. And
## over the table's left edge, the rally label; over everything, the VS
## banner.
func _build_hud() -> void:
	# --- top centre: the score ---
	var score_box := UiKit.vbox(0)
	score_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var score_row := UiKit.hbox(16)
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var you_label := UiKit.display("YOU", 18, MY_PIP_COLOR)
	you_label.size_flags_vertical = Control.SIZE_SHRINK_END
	score_row.add_child(you_label)
	score_label = UiKit.display("0  -  0", SCORE_FONT_SIZE, Palette.PAPER)
	score_label.custom_minimum_size = Vector2(120, 0)
	score_row.add_child(score_label)
	their_name_label = UiKit.display("THEM", 18, THEIR_PIP_COLOR)
	their_name_label.size_flags_vertical = Control.SIZE_SHRINK_END
	score_row.add_child(their_name_label)
	score_box.add_child(score_row)
	stamina_row = UiKit.hbox(22)
	stamina_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_my_pips = UiKit.bolts(MatchState.STAMINA_MAX, MatchState.STAMINA_MAX, MY_PIP_COLOR, 16)
	_their_pips = UiKit.bolts(MatchState.STAMINA_MAX, MatchState.STAMINA_MAX, THEIR_PIP_COLOR, 16)
	stamina_row.add_child(_my_pips)
	stamina_row.add_child(UiKit.icon(UiKit.ICON_BALL, 9, Palette.PAPER_DIM))
	stamina_row.add_child(_their_pips)
	score_box.add_child(stamina_row)
	var score_plate := UiKit.plate(Vector2(24, 6))
	score_plate.add_child(score_box)
	_pin_top_center(score_plate)
	hud_root.add_child(score_plate)
	_expose(score_plate, "ScorePlate")
	_expose(score_label, "ScoreLabel")
	_expose(stamina_row, "StaminaRow")
	_expose(_my_pips, "MyPips")
	_expose(_their_pips, "TheirPips")

	# --- top left: the stage, the hearts, the situation ---
	var left := UiKit.vbox(8)
	left.name = "LeftColumn"
	left.position = HUD_EDGE
	var stage_plate := UiKit.plate(Vector2(12, 4))
	stage_plate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var stage_row := UiKit.hbox(10)
	stage_label = UiKit.display("STAGE 1 of 6", 17, Palette.PAPER)
	stage_row.add_child(stage_label)
	hearts_row = UiKit.hearts(RunState.HEARTS, RunState.HEARTS, 18)
	stage_row.add_child(hearts_row)
	stage_plate.add_child(stage_row)
	left.add_child(stage_plate)
	situation_plate = UiKit.plate(Vector2(14, 10))
	situation_plate.custom_minimum_size = Vector2(SIDE_COLUMN_WIDTH, 0)
	var situation := UiKit.vbox(2)
	situation.add_child(_column_caption("INCOMING"))
	incoming_label = UiKit.display("", 22, Palette.PAPER)
	_column_text(incoming_label)
	situation.add_child(incoming_label)
	hint_label = UiKit.text("", 14, Palette.PAPER)
	_column_text(hint_label)
	situation.add_child(hint_label)
	situation_plate.add_child(situation)
	left.add_child(situation_plate)
	hud_root.add_child(left)
	_expose(hearts_row, "HeartsRow")
	_expose(situation_plate, "SituationPlate")
	_expose(incoming_label, "IncomingLabel")
	_expose(hint_label, "HintLabel")

	# --- top right: the opponent, the commentary ---
	var right := UiKit.vbox(8)
	right.name = "RightColumn"
	var who_plate := UiKit.plate(Vector2(14, 6))
	var who_row := UiKit.hbox(12)
	var who := UiKit.vbox(0)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opponent_label = UiKit.display("Them", 22, Palette.PAPER)
	opponent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	who.add_child(opponent_label)
	var tags := UiKit.hbox(8)
	tags.alignment = BoxContainer.ALIGNMENT_END
	boss_label = UiKit.chip("BOSS", null, Palette.PINK, Palette.PAPER, 11)
	boss_label.name = "BossTag"
	boss_label.visible = false
	tags.add_child(boss_label)
	to_win_label = UiKit.caption("first to 7", 12, Palette.PAPER_DIM)
	to_win_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tags.add_child(to_win_label)
	who.add_child(tags)
	who_row.add_child(who)
	_emblem = UiKit.emblem("", 46)
	_emblem.visible = false
	who_row.add_child(_emblem)
	who_plate.add_child(who_row)
	right.add_child(who_plate)
	log_plate = UiKit.plate(Vector2(14, 8), 0.8)
	log_plate.custom_minimum_size = Vector2(SIDE_COLUMN_WIDTH, 0)
	log_label = UiKit.text("", 14, Palette.PAPER)
	_column_text(log_label)
	log_plate.add_child(log_label)
	right.add_child(log_plate)
	_pin_right(right, true)
	hud_root.add_child(right)
	_expose(opponent_label, "OpponentLabel")
	_expose(log_label, "LogLabel")

	# --- bottom right: the controls ---
	controls_hint = UiKit.label(HINT_KEYBOARD, 13, Palette.PAPER_DIM)
	controls_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pin_right(controls_hint, false)
	hud_root.add_child(controls_hint)
	_expose(controls_hint, "ControlsHint")

	# --- the rally label, over the table's left edge ---
	rally_label = UiKit.title("", 30, Palette.YELLOW)
	rally_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rally_label.anchor_top = 0.5
	rally_label.anchor_bottom = 0.5
	rally_label.offset_left = HUD_EDGE.x
	rally_label.offset_right = HUD_EDGE.x + 300.0
	rally_label.offset_top = -70.0
	rally_label.offset_bottom = -30.0
	rally_label.visible = false
	hud_root.add_child(rally_label)
	_expose(rally_label, "RallyLabel")

	versus_banner = _build_banner()
	hud_root.add_child(versus_banner)
	_expose(versus_banner, "VersusBanner")
	for node in [score_plate, left, right, controls_hint, rally_label, versus_banner]:
		_let_mouse_through(node)


## The small orange heading of a side column plate.
static func _column_caption(text: String) -> Label:
	var l := UiKit.caption(text, 11, Palette.ORANGE)
	l.add_theme_font_override("font", Palette.body_bold)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


## Side column text runs left and wraps inside the plate.
static func _column_text(l: Label) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Gives a code-built HUD node a scene-unique name, so %Name reaches it from
## anywhere in the scene exactly like the nodes the scene file carries. The
## node must already be in the tree: the owner has to be an ancestor.
func _expose(node: Node, unique_name: String) -> void:
	node.name = unique_name
	node.owner = self
	node.unique_name_in_owner = true


## Anchors a control to the top edge, centred, growing both ways.
func _pin_top_center(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_CENTER_TOP)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_END
	c.offset_left = 0.0
	c.offset_right = 0.0
	c.offset_top = HUD_EDGE.y
	c.offset_bottom = HUD_EDGE.y


## Anchors a control to the right edge, at the top or the bottom, growing
## left so its text keeps the margin.
func _pin_right(c: Control, top: bool) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_RIGHT if top else Control.PRESET_BOTTOM_RIGHT)
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	c.grow_vertical = Control.GROW_DIRECTION_END if top else Control.GROW_DIRECTION_BEGIN
	c.offset_left = -HUD_EDGE.x
	c.offset_right = -HUD_EDGE.x
	if top:
		c.offset_top = HUD_EDGE.y
		c.offset_bottom = HUD_EDGE.y
	else:
		c.offset_top = -HUD_EDGE.y * 0.6
		c.offset_bottom = -HUD_EDGE.y * 0.6


## The VS banner: the opponent's emblem beside "STAGE 3 of 6 / JAX DUNN /
## BOSS / blurb / first to 7" on a skewed paper plate, centred, hidden
## until start() slides it in.
func _build_banner() -> Control:
	var row := UiKit.hbox(18)
	_banner_emblem = UiKit.emblem("", 84)
	_banner_emblem.visible = false
	row.add_child(_banner_emblem)
	var box := UiKit.vbox(2)
	_banner_labels["stage"] = _column_caption("STAGE 1 of 6")
	_banner_labels["name"] = UiKit.heading("THEM", 46)
	_banner_labels["name"].horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_banner_labels["blurb"] = UiKit.text("", 17)
	_banner_labels["blurb"].horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var tags := UiKit.hbox(10)
	_banner_labels["boss"] = UiKit.chip("BOSS", null, Palette.PINK, Palette.PAPER, 12)
	_banner_labels["to"] = UiKit.strong("first to 7", 16, Palette.ORANGE)
	_banner_labels["to"].size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tags.add_child(_banner_labels["boss"])
	tags.add_child(_banner_labels["to"])
	for key in ["stage", "name", "blurb"]:
		box.add_child(_banner_labels[key])
	box.add_child(tags)
	row.add_child(box)
	var panel := UiKit.panel()
	var plate := UiKit.panel_style(Palette.PAPER, 22.0)
	plate.skew = Vector2(BANNER_SKEW, 0.0)
	panel.add_theme_stylebox_override("panel", plate)
	panel.add_child(row)
	var center := UiKit.center(panel)
	center.name = "VersusBanner"
	center.visible = false
	return center


## The "..." that hovers over the opponent's paddle while the AI thinks.
func _build_think_label() -> void:
	_think_label = Label3D.new()
	_think_label.name = "ThinkLabel"
	_think_label.text = "..."
	_think_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_think_label.no_depth_test = true
	_think_label.pixel_size = 0.004
	_think_label.font = Palette.display
	_think_label.font_size = 128
	_think_label.outline_size = 24
	# The dots of "..." sit on the baseline: anchor the label there.
	_think_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_think_label.modulate = Palette.PAPER
	_think_label.outline_modulate = Palette.INK
	_think_label.visible = false
	$World.add_child(_think_label)


func _set_thinking(on: bool) -> void:
	_thinking = on
	_think_label.visible = on
	if on:
		_think_label.position = paddles[REMOTE].position + THINK_OFFSET
	else:
		paddles[REMOTE].rotation.z = _paddle_rest[REMOTE].z


## HUD containers must not swallow clicks meant for the table.
static func _let_mouse_through(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_let_mouse_through(child)


func _show_versus(config: Dictionary, boss: bool) -> void:
	_banner_labels["stage"].text = "STAGE %d of %d" % [int(config.get("stage", 0)) + 1, int(config.get("stages", RunState.STAGES))]
	_banner_labels["name"].text = opponent_name.to_upper()
	_banner_labels["blurb"].text = String(config.get("blurb", ""))
	_banner_labels["boss"].visible = boss
	_banner_labels["to"].text = "first to %d" % points_to_win
	_banner_emblem.texture = UiKit.emblem_texture(opponent_id)
	_banner_emblem.visible = _banner_emblem.texture != null
	var width := get_viewport().get_visible_rect().size.x
	versus_banner.visible = true
	versus_banner.modulate.a = 0.0
	versus_banner.position = Vector2(width * BANNER_SLIDE_FROM, 0.0)
	_banner_tween = create_tween()
	_banner_tween.tween_property(versus_banner, "position:x", 0.0, BANNER_SLIDE_IN) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.parallel().tween_property(versus_banner, "modulate:a", 1.0, BANNER_SLIDE_IN * 0.6)
	_banner_tween.tween_interval(VS_BANNER_TIME - BANNER_SLIDE_IN - BANNER_SLIDE_OUT)
	_banner_tween.tween_property(versus_banner, "position:x", -width * BANNER_SLIDE_TO, BANNER_SLIDE_OUT) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_banner_tween.parallel().tween_property(versus_banner, "modulate:a", 0.0, BANNER_SLIDE_OUT)
	await _banner_tween.finished
	_hide_banner()


func _hide_banner() -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	versus_banner.visible = false
	versus_banner.position = Vector2.ZERO


## The opponent's blade takes their colour; the material is duplicated once
## so the shared resource on disk stays blue.
func _set_paddle_color(color: Variant) -> void:
	if not (color is Color):
		return
	if _blade_material == null:
		var blade: MeshInstance3D = paddles[REMOTE].get_node("Blade")
		var base := blade.get_surface_override_material(0)
		if base == null or not (base is ShaderMaterial):
			return
		_blade_material = (base as ShaderMaterial).duplicate() as ShaderMaterial
		blade.set_surface_override_material(0, _blade_material)
	_blade_material.set_shader_parameter("albedo", color)
	_blade_material.set_shader_parameter("shadow_tint", (color as Color).darkened(0.55))


# --- event playback ---------------------------------------------------------

func _enqueue(events: Array[Dictionary]) -> void:
	_queue.append_array(events)
	if not _pumping:
		_pump()


func _pump() -> void:
	var gen := _generation
	_pumping = true
	while not _queue.is_empty():
		var e: Dictionary = _queue.pop_front()
		await _present(e)
		if gen != _generation:
			return
	_pumping = false


func _present(e: Dictionary) -> void:
	match String(e["type"]):
		"point_start":
			_present_point_start(e)
		"turn":
			_set_stamina(e["stamina"])
			if int(e["player"]) == LOCAL:
				_open_input()
			else:
				await _remote_turn()
		"shot":
			await _present_shot(e)
		"point":
			await _present_point(e)
		"match_over":
			await _present_match_over(e)


func _present_point_start(e: Dictionary) -> void:
	var server := int(e["server"])
	grid.clear_all()
	for p in 2:
		_slide_paddle(p, state.players[p].col, true)
	ball.stop()
	ball.global_position = _hit_point(server) - Vector3(MatchState.side_of(server) * 0.1, 0.0, 0.0)
	ball.spin_rate = 1.0
	_set_stamina(e["stamina"])
	var score: Array = e["score"]
	rally_label.visible = int(score[0]) == points_to_win - 1 or int(score[1]) == points_to_win - 1
	rally_label.text = "MATCH POINT"
	_log("Your serve." if server == LOCAL else "Their serve.")
	fx.emit("point_start", {"server": server, "score": score.duplicate(), "stamina": (e["stamina"] as Array).duplicate()})


func _remote_turn() -> void:
	var gen := _generation
	_set_thinking(true)
	await get_tree().create_timer(AI_THINK_TIME, false).timeout
	if gen != _generation:
		return
	_set_thinking(false)
	var action := AIController.choose(state, REMOTE, ai_params)
	if action.is_empty():
		# Nothing to play (the AI already warned): the match stalls rather
		# than feeding apply() an empty action for a second warning.
		return
	_enqueue(state.apply(action))


func _present_shot(e: Dictionary) -> void:
	var gen := _generation
	var shooter := int(e["player"])
	var receiver := MatchState.opponent_of(shooter)
	var side := MatchState.side_of(shooter)
	var card: Card = e["card"]
	var zone: Zone = e["target"]
	var outcome := int(e["outcome"])
	var kind := String(e["kind"])
	var tired := bool(e["tired"])
	var landing := grid.landing_point(zone)
	var who := "You" if shooter == LOCAL else "They"
	var shot_name := card.title + (" (tired)" if tired else "")
	var rally := int(e["rally_length"])

	grid.set_state(zone, ZoneGrid.State.TARGET if shooter == LOCAL else ZoneGrid.State.INCOMING)
	_swing(paddles[shooter], -float(side))
	_set_stamina(e["stamina"])
	ball.spin_rate = BallFlight.spin_for(card.produces)
	fx.emit("swing", {"player": shooter, "power": card.power, "color": card.color, "tired": tired})
	if card.power >= HIT_STOP_POWER:
		Feel.hit_stop(get_tree())
	if card.power >= PUNCH_POWER:
		_punch(-2.0 - 4.0 * card.power)
	if RALLY_MILESTONES.has(rally):
		rally_label.text = "RALLY %d" % rally
		rally_label.visible = true
		fx.emit("rally", {"length": rally})

	# Where the ball ends up for the landing effects: the zone, or the net.
	var pos := landing
	match outcome:
		RallyResolver.Outcome.FAULT:
			if zone.is_edge_col() or zone.is_deep():
				_log("%s: %s to the %s... just out." % [who, shot_name, zone.label()])
				var out := landing + Vector3(
					side * (0.35 if zone.is_deep() else 0.0), -0.4,
					signf(landing.z) * (0.4 if zone.is_edge_col() else 0.0))
				await ball.shot(landing, out, card.arc_height, card.speed)
			else:
				_log("%s: %s... into the net." % [who, shot_name])
				pos = Vector3(0.0, 0.92, landing.z * 0.5)
				await ball.into_net(pos, card.speed, side)
		RallyResolver.Outcome.WINNER:
			_log("%s: %s to the %s. Clean winner." % [who, shot_name, zone.label()])
			var past := landing + Vector3(side * 1.1, -0.45, signf(landing.z) * 0.3)
			await ball.shot(landing, past, card.arc_height, card.speed)
		_:
			_log("%s: %s to the %s." % [who, shot_name, zone.label()])
			_slide_paddle(receiver, zone.col, false)
			await ball.shot(landing, _hit_point(receiver), card.arc_height, card.speed)
	if gen != _generation:
		return
	fx.emit("landed", {"player": shooter, "outcome": outcome, "kind": kind, "zone": zone, "pos": pos,
		"color": card.color, "tired": tired})
	if kind == "ace" or kind == "edge" or kind == "winner" or kind == "tired":
		Feel.hit_stop(get_tree())
	var text := callout_text(kind, shooter == LOCAL)
	if text != "":
		# A winner is good news for its shooter, a fault for the other side.
		_show_callout(text, (outcome == RallyResolver.Outcome.WINNER) == (shooter == LOCAL))


## What the callout says for a shot event's `kind`: ACE and EDGE! for either
## side, otherwise who the point went to, and TOO TIRED for a tired fault.
static func callout_text(kind: String, by_local: bool) -> String:
	match kind:
		"ace":
			return "ACE"
		"edge":
			return "EDGE!"
		"winner":
			return "WINNER" if by_local else "THEIR POINT"
		"tired":
			return "TOO TIRED"
		"fault":
			return "FAULT" if by_local else "THEY MISSED"
	return ""


func _present_point(e: Dictionary) -> void:
	var gen := _generation
	input_open = false
	input_mode = InputMode.NONE
	var score: Array = e["score"]
	_refresh_score(score)
	fx.emit("point", {"winner": int(e["winner"]), "score": score.duplicate(),
		"points_to_win": int(e["points_to_win"]), "rally_length": int(e["rally_length"])})
	await get_tree().create_timer(POINT_HOLD_TIME, false).timeout
	if gen != _generation:
		return
	_hide_callout()
	if state.phase != MatchState.Phase.MATCH_OVER:
		_enqueue(state.start_point())


func _present_match_over(e: Dictionary) -> void:
	var gen := _generation
	var winner := int(e["winner"])
	var won := winner == LOCAL
	var score: Array = e["score"]
	_log("Match over. You %s %d to %d." % ["win" if won else "lose", state.players[0].score, state.players[1].score])
	_show_callout("YOU WIN" if won else "YOU LOSE", won, false)
	hand_ui.clear()
	incoming_label.text = ""
	hint_label.text = ""
	rally_label.visible = false
	input_open = false
	input_mode = InputMode.NONE
	fx.emit("match_over", {"won": won, "score": score.duplicate()})
	await get_tree().create_timer(MATCH_OVER_HOLD, false).timeout
	if gen != _generation:
		return
	match_finished.emit(winner, (e["score"] as Array).duplicate(), int(e["longest_rally"]),
		(e["stats"] as Array).duplicate(true))


# --- local input ------------------------------------------------------------

func _open_input() -> void:
	input_open = true
	selected_index = -1
	input_mode = InputMode.HAND
	grid.clear_states(1)
	var their_col := state.players[REMOTE].col
	grid.set_covered(1, [their_col - 1, their_col, their_col + 1])
	var where := "" if state.incoming_zone == null else " to your %s" % state.incoming_zone.label()
	var heavy := ", heavy" if state.incoming_heavy else ""
	incoming_label.text = "%s%s%s" % [BallType.label(state.incoming_type), where, heavy]
	hint_label.text = BallType.hint(state.incoming_type) + "  Pick a card, then aim at a zone on their half."
	hand_ui.show_hand(state.players[LOCAL].hand, state.incoming_type, state.players[LOCAL].stamina)
	hand_ui.set_enabled(true)
	hand_ui.focus_first()


## A card was clicked or accepted in the hand.
func _on_card_chosen(index: int) -> void:
	_select_card(index)


## Chooses card `index` and switches to aiming: focus leaves the hand so the
## arrows and the d-pad drive the zone cursor instead.
func _select_card(index: int) -> void:
	if not input_open or index < 0 or index >= state.players[LOCAL].hand.size():
		return
	selected_index = index
	hand_ui.set_selected(index)
	input_mode = InputMode.AIM
	get_viewport().gui_release_focus()
	fx.emit("card_select", {"index": index})
	_set_hover(_cursor_zone())
	_update_hover_hint()


## Back from aiming to the hand, with focus on the card that was chosen.
func _unselect_card() -> void:
	var back_to := selected_index
	selected_index = -1
	hand_ui.set_selected(-1)
	input_mode = InputMode.HAND
	fx.emit("card_deselect", {})
	_set_hover(null)
	_update_hover_hint()
	hand_ui.focus_index(maxi(back_to, 0))


## Q/E and the shoulder buttons: the previous or next card, from the chosen
## one while aiming or from the focused one while picking.
func _cycle_card(step: int) -> void:
	var n := state.players[LOCAL].hand.size()
	if n == 0:
		return
	var from := selected_index
	if from < 0:
		from = _focused_card_index()
	var to := (from + step + n) % n if from >= 0 else (0 if step > 0 else n - 1)
	_select_card(to)


func _focused_card_index() -> int:
	var owner := get_viewport().gui_get_focus_owner()
	if owner == null or owner.get_parent() != hand_ui:
		return -1
	return owner.get_index()


func _unhandled_input(event: InputEvent) -> void:
	if not input_open:
		return
	if event is InputEventMouseMotion:
		var z := _zone_under_mouse(event.position)
		if z != null:
			cursor = Vector2i(z.row, z.col)
			_set_hover(z)
		elif input_mode == InputMode.HAND:
			_set_hover(null)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var z := _zone_under_mouse(event.position)
		if z != null and input_mode == InputMode.AIM:
			choose_zone(z)
		return
	var card := InputSetup.card_index(event)
	if card >= 0:
		if card < state.players[LOCAL].hand.size():
			_select_card(card)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("card_prev"):
		_cycle_card(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("card_next"):
		_cycle_card(1)
		get_viewport().set_input_as_handled()
		return
	if input_mode == InputMode.HAND:
		# A hand with no focus owner (a click on nothing, say) gets it back
		# on the first navigation press so a gamepad is never stranded.
		if _focused_card_index() < 0 and (event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")
				or event.is_action_pressed("ui_accept")):
			hand_ui.focus_first()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("aim_back"):
		_unselect_card()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept"):
		choose_zone(_cursor_zone())
		get_viewport().set_input_as_handled()
		return
	var step := Vector2i.ZERO
	if event.is_action_pressed("ui_up"):
		step.x = 1
	elif event.is_action_pressed("ui_down"):
		step.x = -1
	elif event.is_action_pressed("ui_left"):
		step.y = -1
	elif event.is_action_pressed("ui_right"):
		step.y = 1
	if step != Vector2i.ZERO:
		_move_cursor(step)
		get_viewport().set_input_as_handled()


## Up is the deep row: their half is at the top of the screen.
func _move_cursor(step: Vector2i) -> void:
	cursor = Vector2i(clampi(cursor.x + step.x, 0, 1), clampi(cursor.y + step.y, 0, 4))
	_set_hover(_cursor_zone())


func _cursor_zone() -> Zone:
	return layout.find(1, cursor.x, cursor.y)


func _zone_under_mouse(screen_pos: Vector2) -> Zone:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var hit = Plane(Vector3.UP, ZoneLayout.TOP_Y).intersects_ray(from, dir)
	if hit == null:
		return null
	var z := layout.at_point(hit)
	return z if (z != null and z.side > 0) else null


func _set_hover(z: Zone) -> void:
	if z == hover_zone:
		return
	if hover_zone != null and grid.state_of(hover_zone) == ZoneGrid.State.HOVER:
		grid.set_state(hover_zone, ZoneGrid.State.IDLE)
	hover_zone = z
	if hover_zone != null and grid.state_of(hover_zone) == ZoneGrid.State.IDLE:
		grid.set_state(hover_zone, ZoneGrid.State.HOVER)
	if hover_zone != null:
		fx.emit("zone_hover", {"zone": hover_zone})
	_update_hover_hint()


func _update_hover_hint() -> void:
	if not input_open:
		# A shot is in flight: the log line says what was played.
		hint_label.text = ""
		return
	if selected_index < 0:
		hint_label.text = BallType.hint(state.incoming_type) + "  Pick a card first."
		return
	var card: Card = state.players[LOCAL].hand[selected_index]
	var tired := " (tired)" if card.cost > state.players[LOCAL].stamina else ""
	if hover_zone == null:
		hint_label.text = "%s selected%s. Dotted zones are easier to miss, darker ones are where they stand." % [card.title, tired]
		return
	var odds := state.odds(LOCAL, selected_index, hover_zone)
	hint_label.text = "%s to the %s: lands %d%%%s, wins %d%% if it does." % [
		card.title, hover_zone.label(), roundi(odds["land"] * 100.0), tired, roundi(odds["win"] * 100.0)]


## Commit the selected card at `zone`. Also what the headless test calls.
func choose_zone(zone: Zone) -> void:
	if not input_open or selected_index < 0 or zone == null or zone.side <= 0:
		return
	var action := {"type": "shot", "player": LOCAL, "card": selected_index, "row": zone.row, "col": zone.col}
	fx.emit("zone_commit", {"zone": zone})
	_submit(action)


## The one place a local action leaves the UI. Online, this is also where it
## gets sent to the other peer before being applied here.
func _submit(action: Dictionary) -> void:
	input_open = false
	input_mode = InputMode.NONE
	selected_index = -1
	hand_ui.set_enabled(false)
	_set_hover(null)
	# The log line narrates the shot in flight; the situation plate has
	# nothing to add until the next ball is on its way.
	hint_label.text = ""
	incoming_label.text = ""
	_enqueue(state.apply(action))


# --- small presentation helpers --------------------------------------------

func _hit_point(player: int) -> Vector3:
	var side := MatchState.side_of(player)
	return Vector3(side * (PADDLE_X - 0.15), PADDLE_Y, layout.lane_z(state.players[player].col))


## Moves a paddle along the table to lane `col`. Only x and z: the height is
## the idle bob's, in _process.
func _slide_paddle(player: int, col: int, instant: bool) -> void:
	var side := MatchState.side_of(player)
	var paddle := paddles[player]
	var x := side * PADDLE_X
	var z := layout.lane_z(col)
	if instant:
		paddle.position.x = x
		paddle.position.z = z
		return
	var t := create_tween().set_parallel(true)
	t.tween_property(paddle, "position:x", x, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(paddle, "position:z", z, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _swing(paddle: Node3D, dir: float) -> void:
	var t := create_tween()
	t.tween_property(paddle, "rotation:y", deg_to_rad(-75.0 * dir), 0.08).as_relative()
	t.tween_property(paddle, "rotation:y", deg_to_rad(75.0 * dir), 0.25).as_relative().set_ease(Tween.EASE_OUT)


## A quick fov kick of `delta_fov` degrees (negative zooms in). The camera rig
## (M3) does it with its own shake and lean; a plain Camera3D gets the tween.
func _punch(delta_fov: float) -> void:
	if camera.has_method("punch"):
		camera.call("punch", delta_fov)
		return
	var t := create_tween()
	t.tween_property(camera, "fov", _base_fov + delta_fov, 0.06)
	t.tween_property(camera, "fov", _base_fov, 0.25).set_ease(Tween.EASE_OUT)


## Pops the 3D callout in; with `auto_fade` it holds CALLOUT_HOLD and fades
## out by itself, otherwise it stays until the next callout or point.
func _show_callout(text: String, good_for_local: bool, auto_fade := true) -> void:
	_hide_callout()
	callout.text = text
	callout.modulate = CALLOUT_GOOD if good_for_local else CALLOUT_BAD
	callout.visible = true
	callout.scale = Vector3.ONE * 0.4
	_callout_tween = create_tween()
	_callout_tween.tween_property(callout, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if auto_fade:
		_callout_tween.tween_interval(CALLOUT_HOLD - 0.18)
		_callout_tween.tween_property(callout, "modulate:a", 0.0, CALLOUT_FADE)
		_callout_tween.tween_callback(_hide_callout)


func _hide_callout() -> void:
	if _callout_tween != null and _callout_tween.is_valid():
		_callout_tween.kill()
	callout.visible = false


## The pips follow the events, and every change goes out as a stamina fx.
func _set_stamina(values: Array) -> void:
	var before := _shown_stamina
	_shown_stamina = values.duplicate()
	_refresh_stamina()
	for p in 2:
		var delta := int(values[p]) - int(before[p])
		if delta != 0:
			fx.emit("stamina", {"player": p, "value": int(values[p]), "delta": delta})


## The score comes from the point event, never from the state: the state has
## already scored a rally while the ball is still in the air.
func _refresh_score(score: Array) -> void:
	score_label.text = "%d  -  %d" % [score[0], score[1]]
	_refresh_stamina()


func _refresh_stamina() -> void:
	UiKit.set_pips(_my_pips, int(_shown_stamina[0]))
	UiKit.set_pips(_their_pips, int(_shown_stamina[1]))


func _log(text: String) -> void:
	log_label.text = text
