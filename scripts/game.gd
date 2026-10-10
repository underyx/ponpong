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
## Player 0 is always drawn at the bottom. For online play, swap AIController
## for a controller that receives the other peer's actions, and send player 0's
## actions out from _submit().
class_name MatchScene
extends Node3D

## Fired after the YOU WIN / YOU LOSE callout has shown for MATCH_OVER_HOLD.
signal match_finished(winner: int, score: Array, longest_rally: int, stats: Array)

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
## The stamina pips squeeze in under the score; these keep the top block
## from growing down onto the far end of the table.
const HUD_TOP_MARGIN := 8
const HUD_SEPARATION := 4
const SCORE_FONT_SIZE := 32
const HUD_EDGE := Vector2(24, 20)
## Where the zone cursor starts: the short middle of their half.
const CURSOR_START := Vector2i(0, 2)
const THEIR_PIP_COLOR := Color(0.55, 0.80, 1.0)
const HINT_KEYBOARD := "1-4 card  ·  arrows aim\nEnter play  ·  Esc pause"
const HINT_GAMEPAD := "A pick  ·  d-pad aim\nA play  ·  B back  ·  Start pause"
const RALLY_MILESTONES := [4, 7, 10, 15]
## Opponent names up to this long go whole into the score line, longer ones
## as their first word.
const SHORT_NAME_MAX := 11
## Where the ball rests while the table is a backdrop.
const IDLE_BALL_POSITION := Vector3(-1.1, ZoneLayout.TOP_Y + 0.035, 0.15)

@onready var ball: BallFlight = $World/Ball
@onready var grid: ZoneGrid = $World/ZoneGrid
@onready var paddles: Array[Node3D] = [$World/PlayerPaddle, $World/OpponentPaddle]
@onready var camera: Camera3D = $World/Camera3D
@onready var callout: Label3D = $World/Callout
@onready var hud_root: Control = $UI/Root
@onready var score_label: Label = %ScoreLabel
@onready var incoming_label: Label = %IncomingLabel
@onready var hint_label: Label = %HintLabel
@onready var log_label: Label = %LogLabel
@onready var hand_ui: HandUI = %Hand

## Code-built HUD, see _build_hud().
var stamina_row: HBoxContainer
var hearts_row: HBoxContainer
var stage_label: Label
var opponent_label: Label
var boss_label: Label
var versus_banner: Control
var rally_label: Label
var controls_hint: Label

var layout := ZoneLayout.new()
var state: MatchState
## Personality of the computer seat; empty means AIController.DEFAULTS.
var ai_params: Dictionary = {}
var opponent_name := "Them"
## What the score line calls them: "YOU 3  -  2 JAX DUNN".
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
var _banner_tween: Tween
var _blade_material: ShaderMaterial
var _paddle_rest: Array[Vector3] = []
var _standalone := false


func _ready() -> void:
	# Idempotent, so under the Director this is a no-op; standalone it is
	# what gives the hand its 1-4, Q/E and Backspace keys.
	InputSetup.register()
	camera.look_at(Vector3(-0.45, 0.76, 0.0))
	grid.build(layout)
	for p in paddles:
		_paddle_rest.append(p.rotation)
	_build_hud()
	hand_ui.card_chosen.connect(_on_card_chosen)
	callout.visible = false
	_standalone = get_parent() == get_tree().root or get_tree().current_scene == self
	if _standalone:
		match_finished.connect(func(_winner: int, _score: Array, _rally: int, _stats: Array) -> void:
			_start_standalone.call_deferred())
		_start_standalone()


# --- public API for the Director ------------------------------------------------

## Begins a match. config: {"seed", "decks": [Array[Card], Array[Card]],
## "points_to_win", "ai", "opponent_name", "blurb", "paddle_color", "boss",
## "hearts", "stage", "stages"}. Any match in progress stops at once.
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
	short_name = short_name_of(opponent_name)
	var boss := bool(config.get("boss", false))
	_set_paddle_color(config.get("paddle_color", null))
	opponent_label.text = opponent_name
	boss_label.visible = boss
	stage_label.text = "STAGE %d of %d" % [int(config.get("stage", 0)) + 1, int(config.get("stages", RunState.STAGES))]
	UiKit.set_pips(hearts_row, int(config.get("hearts", RunState.HEARTS)))
	hud_root.visible = true
	_shown_stamina = [MatchState.STAMINA_MAX, MatchState.STAMINA_MAX]
	_refresh_score([0, 0])
	_log("%s. First to %d." % [opponent_name, points_to_win])
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
	hud_root.visible = not p_idle


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
	callout.visible = false
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
	for p in 2:
		paddles[p].rotation = _paddle_rest[p]
		_slide_paddle(p, MatchState.HOME_COL, true)


# --- HUD ------------------------------------------------------------------------

## Adds everything the scene file does not carry: stamina pips under the
## score, stage and hearts top-left, the opponent top-right, the controls hint
## bottom-right, the rally label and the VS banner.
func _build_hud() -> void:
	var vbox: Control = score_label.get_parent()
	vbox.add_theme_constant_override("separation", HUD_SEPARATION)
	vbox.get_parent().add_theme_constant_override("margin_top", int(HUD_TOP_MARGIN))
	score_label.add_theme_font_size_override("font_size", SCORE_FONT_SIZE)

	stamina_row = UiKit.hbox(28)
	stamina_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_my_pips = UiKit.pips(MatchState.STAMINA_MAX, MatchState.STAMINA_MAX, UiKit.GOLD, 14)
	_their_pips = UiKit.pips(MatchState.STAMINA_MAX, MatchState.STAMINA_MAX, THEIR_PIP_COLOR, 14)
	stamina_row.add_child(_pip_group("you", _my_pips, false))
	stamina_row.add_child(_pip_group("them", _their_pips, true))
	vbox.add_child(stamina_row)
	vbox.move_child(stamina_row, score_label.get_index() + 1)
	_expose(stamina_row, "StaminaRow")

	var corner := UiKit.vbox(4)
	stage_label = UiKit.label("STAGE 1 of 6", 16, UiKit.MUTED)
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	corner.add_child(stage_label)
	hearts_row = UiKit.pips(RunState.HEARTS, RunState.HEARTS, UiKit.DANGER, 16)
	hearts_row.add_child(UiKit.label("hearts", 14, UiKit.MUTED))
	corner.add_child(hearts_row)
	corner.position = HUD_EDGE
	hud_root.add_child(corner)
	_expose(corner, "HeartsRow")

	var who := UiKit.vbox(0)
	who.name = "OpponentBox"
	opponent_label = UiKit.label("Them", 22)
	opponent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	who.add_child(opponent_label)
	boss_label = UiKit.label("BOSS", 16, UiKit.DANGER)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	boss_label.visible = false
	who.add_child(boss_label)
	_pin_right(who, true)
	hud_root.add_child(who)
	_expose(opponent_label, "OpponentLabel")

	controls_hint = UiKit.label(HINT_KEYBOARD, 14, UiKit.MUTED)
	controls_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pin_right(controls_hint, false)
	hud_root.add_child(controls_hint)
	_expose(controls_hint, "ControlsHint")

	rally_label = UiKit.label("", 28, UiKit.GOLD)
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
	for node in [stamina_row, corner, who, versus_banner]:
		_let_mouse_through(node)


## Gives a code-built HUD node a scene-unique name, so %Name reaches it from
## anywhere in the scene exactly like the nodes the scene file carries. The
## node must already be in the tree: the owner has to be an ancestor.
func _expose(node: Node, unique_name: String) -> void:
	node.name = unique_name
	node.owner = self
	node.unique_name_in_owner = true


func _pip_group(caption: String, pips: HBoxContainer, label_last: bool) -> HBoxContainer:
	var group := UiKit.hbox(8)
	var caption_label := UiKit.label(caption, 14, UiKit.MUTED)
	if not label_last:
		group.add_child(caption_label)
	group.add_child(pips)
	if label_last:
		group.add_child(caption_label)
	return group


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


## "STAGE 3 of 6 / JAX DUNN / blurb / first to 7", centred, hidden until start().
func _build_banner() -> Control:
	var box := UiKit.vbox(6)
	_banner_labels["stage"] = UiKit.label("STAGE 1 of 6", 20, UiKit.MUTED)
	_banner_labels["name"] = UiKit.title("THEM", 56)
	_banner_labels["blurb"] = UiKit.label("", 20)
	_banner_labels["boss"] = UiKit.label("BOSS", 22, UiKit.DANGER)
	_banner_labels["to"] = UiKit.label("first to 7", 22, UiKit.GOLD)
	for key in ["stage", "name", "boss", "blurb", "to"]:
		box.add_child(_banner_labels[key])
	var panel := UiKit.panel()
	panel.add_child(box)
	var center := UiKit.center(panel)
	center.name = "VersusBanner"
	center.visible = false
	return center


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
	versus_banner.visible = true
	versus_banner.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(versus_banner, "modulate:a", 1.0, 0.2)
	_banner_tween.tween_interval(VS_BANNER_TIME - 0.45)
	_banner_tween.tween_property(versus_banner, "modulate:a", 0.0, 0.25)
	await _banner_tween.finished
	versus_banner.visible = false


func _hide_banner() -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	versus_banner.visible = false


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
	_set_stamina(e["stamina"])
	var score: Array = e["score"]
	rally_label.visible = int(score[0]) == points_to_win - 1 or int(score[1]) == points_to_win - 1
	rally_label.text = "MATCH POINT"
	_log("Your serve." if server == LOCAL else "Their serve.")


func _remote_turn() -> void:
	var gen := _generation
	await get_tree().create_timer(AI_THINK_TIME, false).timeout
	if gen != _generation:
		return
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
	var landing := grid.landing_point(zone)
	var who := "You" if shooter == LOCAL else "They"
	var shot_name := card.title + (" (tired)" if bool(e["tired"]) else "")
	var rally := int(e["rally_length"])

	grid.set_state(zone, ZoneGrid.State.TARGET if shooter == LOCAL else ZoneGrid.State.INCOMING)
	_swing(paddles[shooter], -float(side))
	_set_stamina(e["stamina"])
	if RALLY_MILESTONES.has(rally):
		rally_label.text = "RALLY %d" % rally
		rally_label.visible = true
	if card.power > 0.8:
		_camera_punch()

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
				await ball.into_net(Vector3(0.0, 0.92, landing.z * 0.5), card.speed, side)
			if gen != _generation:
				return
			_show_callout("FAULT" if shooter == LOCAL else "THEY MISSED", shooter != LOCAL)
		RallyResolver.Outcome.WINNER:
			_log("%s: %s to the %s. Clean winner." % [who, shot_name, zone.label()])
			var past := landing + Vector3(side * 1.1, -0.45, signf(landing.z) * 0.3)
			await ball.shot(landing, past, card.arc_height, card.speed)
			if gen != _generation:
				return
			_show_callout("WINNER" if shooter == LOCAL else "THEIR POINT", shooter == LOCAL)
		_:
			_log("%s: %s to the %s." % [who, shot_name, zone.label()])
			_slide_paddle(receiver, zone.col, false)
			await ball.shot(landing, _hit_point(receiver), card.arc_height, card.speed)
			if gen != _generation:
				return


func _present_point(e: Dictionary) -> void:
	var gen := _generation
	input_open = false
	input_mode = InputMode.NONE
	_refresh_score(e["score"])
	await get_tree().create_timer(POINT_HOLD_TIME, false).timeout
	if gen != _generation:
		return
	callout.visible = false
	if state.phase != MatchState.Phase.MATCH_OVER:
		_enqueue(state.start_point())


func _present_match_over(e: Dictionary) -> void:
	var gen := _generation
	var winner := int(e["winner"])
	var won := winner == LOCAL
	_log("Match over. You %s %d to %d." % ["win" if won else "lose", state.players[0].score, state.players[1].score])
	_show_callout("YOU WIN" if won else "YOU LOSE", won)
	hand_ui.clear()
	incoming_label.text = ""
	hint_label.text = ""
	rally_label.visible = false
	input_open = false
	input_mode = InputMode.NONE
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
	var heavy := ", and it is heavy" if state.incoming_heavy else ""
	incoming_label.text = "Incoming: %s%s%s" % [BallType.label(state.incoming_type), where, heavy]
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
	_set_hover(_cursor_zone())
	_update_hover_hint()


## Back from aiming to the hand, with focus on the card that was chosen.
func _unselect_card() -> void:
	var back_to := selected_index
	selected_index = -1
	hand_ui.set_selected(-1)
	input_mode = InputMode.HAND
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
	_submit(action)


## The one place a local action leaves the UI. Online, this is also where it
## gets sent to the other peer before being applied here.
func _submit(action: Dictionary) -> void:
	input_open = false
	input_mode = InputMode.NONE
	selected_index = -1
	hand_ui.set_enabled(false)
	_set_hover(null)
	_enqueue(state.apply(action))


# --- small presentation helpers --------------------------------------------

func _hit_point(player: int) -> Vector3:
	var side := MatchState.side_of(player)
	return Vector3(side * (PADDLE_X - 0.15), PADDLE_Y, layout.lane_z(state.players[player].col))


func _slide_paddle(player: int, col: int, instant: bool) -> void:
	var side := MatchState.side_of(player)
	var to := Vector3(side * PADDLE_X, PADDLE_Y, layout.lane_z(col))
	var paddle := paddles[player]
	if instant:
		paddle.position = to
		return
	var t := create_tween()
	t.tween_property(paddle, "position", to, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _swing(paddle: Node3D, dir: float) -> void:
	var t := create_tween()
	t.tween_property(paddle, "rotation:y", deg_to_rad(-75.0 * dir), 0.08).as_relative()
	t.tween_property(paddle, "rotation:y", deg_to_rad(75.0 * dir), 0.25).as_relative().set_ease(Tween.EASE_OUT)


func _camera_punch() -> void:
	var start_fov := camera.fov
	var t := create_tween()
	t.tween_property(camera, "fov", start_fov - 4.0, 0.06)
	t.tween_property(camera, "fov", start_fov, 0.25).set_ease(Tween.EASE_OUT)


func _show_callout(text: String, good_for_local: bool) -> void:
	callout.text = text
	callout.modulate = Color(1.0, 0.85, 0.3) if good_for_local else Color(0.95, 0.4, 0.4)
	callout.visible = true
	callout.scale = Vector3.ONE * 0.4
	var t := create_tween()
	t.tween_property(callout, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_stamina(values: Array) -> void:
	_shown_stamina = values.duplicate()
	_refresh_stamina()


## The score comes from the point event, never from the state: the state has
## already scored a rally while the ball is still in the air.
func _refresh_score(score: Array) -> void:
	score_label.text = "YOU %d   -   %d %s" % [score[0], score[1], short_name]
	_refresh_stamina()


func _refresh_stamina() -> void:
	UiKit.set_pips(_my_pips, int(_shown_stamina[0]))
	UiKit.set_pips(_their_pips, int(_shown_stamina[1]))


func _log(text: String) -> void:
	log_label.text = text
