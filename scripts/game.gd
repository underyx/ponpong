## The presenter. Owns a MatchState, feeds it actions (from the UI for player
## 0, from AIController for player 1) and plays back the events it returns as
## tweens, labels and callouts. It never decides a rally outcome itself.
##
## Player 0 is always drawn at the bottom. For online play, swap AIController
## for a controller that receives the other peer's actions, and send player 0's
## actions out from _submit().
extends Node3D

const PADDLE_X := 1.6
const PADDLE_Y := 1.0
const AI_THINK_TIME := 0.55
const POINT_HOLD_TIME := 1.1
const LOCAL := 0
const REMOTE := 1
## The stamina row squeezes in under the score; these keep the top block from
## growing down onto the far end of the table.
const HUD_TOP_MARGIN := 8
const HUD_SEPARATION := 4
const SCORE_FONT_SIZE := 32
const STAMINA_FONT_SIZE := 16

@onready var ball: BallFlight = $World/Ball
@onready var grid: ZoneGrid = $World/ZoneGrid
@onready var paddles: Array[Node3D] = [$World/PlayerPaddle, $World/OpponentPaddle]
@onready var camera: Camera3D = $World/Camera3D
@onready var callout: Label3D = $World/Callout
@onready var score_label: Label = %ScoreLabel
@onready var incoming_label: Label = %IncomingLabel
@onready var hint_label: Label = %HintLabel
@onready var log_label: Label = %LogLabel
@onready var hand_ui: HandUI = %Hand
@onready var restart_button: Button = %RestartButton

## Code-built row right under the score: "stamina  you 4/6  ·  them 6/6".
var stamina_label: Label

var layout := ZoneLayout.new()
var state: MatchState
## Personality of the computer seat; empty means AIController.DEFAULTS.
var ai_params: Dictionary = {}

## True while the local player may act.
var input_open := false
var selected_index := -1
var hover_zone: Zone = null

var _queue: Array[Dictionary] = []
var _pumping := false
## Stamina as last shown: follows events, not the state, so the HUD does not
## run ahead of the ball.
var _shown_stamina: Array = [MatchState.STAMINA_MAX, MatchState.STAMINA_MAX]


func _ready() -> void:
	camera.look_at(Vector3(-0.45, 0.76, 0.0))
	grid.build(layout)
	_build_stamina_label()
	hand_ui.card_chosen.connect(_on_card_chosen)
	restart_button.pressed.connect(start_match)
	callout.visible = false
	start_match()


## Adds the stamina row under the score and tightens the HUD so the hint line
## stays above the table.
func _build_stamina_label() -> void:
	stamina_label = Label.new()
	stamina_label.name = "StaminaLabel"
	stamina_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamina_label.add_theme_font_size_override("font_size", STAMINA_FONT_SIZE)
	stamina_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))
	stamina_label.add_theme_color_override("font_outline_color", Color(0.09, 0.07, 0.14))
	stamina_label.add_theme_constant_override("outline_size", 5)
	var vbox: Control = score_label.get_parent()
	vbox.add_child(stamina_label)
	vbox.move_child(stamina_label, score_label.get_index() + 1)
	vbox.add_theme_constant_override("separation", HUD_SEPARATION)
	vbox.get_parent().add_theme_constant_override("margin_top", HUD_TOP_MARGIN)
	score_label.add_theme_font_size_override("font_size", SCORE_FONT_SIZE)


func start_match() -> void:
	# Online, the seed is agreed once at match start and both peers use it.
	state = MatchState.new(randi(), [CardLibrary.starter_deck(), CardLibrary.starter_deck()], layout,
		MatchState.DEFAULT_POINTS_TO_WIN)
	_shown_stamina = [MatchState.STAMINA_MAX, MatchState.STAMINA_MAX]
	restart_button.visible = false
	callout.visible = false
	_log("New match. First to %d." % state.points_to_win)
	_refresh_score([state.players[0].score, state.players[1].score])
	_enqueue(state.start_point())


# --- event playback ---------------------------------------------------------

func _enqueue(events: Array[Dictionary]) -> void:
	_queue.append_array(events)
	if not _pumping:
		_pump()


func _pump() -> void:
	_pumping = true
	while not _queue.is_empty():
		var e: Dictionary = _queue.pop_front()
		await _present(e)
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
			_present_match_over(int(e["winner"]))


func _present_point_start(e: Dictionary) -> void:
	var server := int(e["server"])
	grid.clear_all()
	for p in 2:
		_slide_paddle(p, state.players[p].col, true)
	ball.stop()
	ball.global_position = _hit_point(server) - Vector3(MatchState.side_of(server) * 0.1, 0.0, 0.0)
	_set_stamina(e["stamina"])
	_log("Your serve." if server == LOCAL else "Their serve.")


func _remote_turn() -> void:
	await get_tree().create_timer(AI_THINK_TIME, false).timeout
	var action := AIController.choose(state, REMOTE, ai_params)
	_enqueue(state.apply(action))


func _present_shot(e: Dictionary) -> void:
	var shooter := int(e["player"])
	var receiver := MatchState.opponent_of(shooter)
	var side := MatchState.side_of(shooter)
	var card: Card = e["card"]
	var zone: Zone = e["target"]
	var outcome := int(e["outcome"])
	var landing := grid.landing_point(zone)
	var who := "You" if shooter == LOCAL else "They"
	var shot_name := card.title + (" (tired)" if bool(e["tired"]) else "")

	grid.set_state(zone, ZoneGrid.State.TARGET if shooter == LOCAL else ZoneGrid.State.INCOMING)
	_swing(paddles[shooter], -float(side))
	_set_stamina(e["stamina"])
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
			_show_callout("FAULT" if shooter == LOCAL else "THEY MISSED", shooter != LOCAL)
		RallyResolver.Outcome.WINNER:
			_log("%s: %s to the %s. Clean winner." % [who, shot_name, zone.label()])
			var past := landing + Vector3(side * 1.1, -0.45, signf(landing.z) * 0.3)
			await ball.shot(landing, past, card.arc_height, card.speed)
			_show_callout("WINNER" if shooter == LOCAL else "THEIR POINT", shooter == LOCAL)
		_:
			_log("%s: %s to the %s." % [who, shot_name, zone.label()])
			_slide_paddle(receiver, zone.col, false)
			await ball.shot(landing, _hit_point(receiver), card.arc_height, card.speed)


func _present_point(e: Dictionary) -> void:
	input_open = false
	_refresh_score(e["score"])
	await get_tree().create_timer(POINT_HOLD_TIME, false).timeout
	callout.visible = false
	if state.phase != MatchState.Phase.MATCH_OVER:
		_enqueue(state.start_point())


func _present_match_over(winner: int) -> void:
	var won := winner == LOCAL
	_log("Match over. You %s %d to %d." % ["win" if won else "lose", state.players[0].score, state.players[1].score])
	_show_callout("YOU WIN" if won else "YOU LOSE", won)
	hand_ui.clear()
	incoming_label.text = ""
	hint_label.text = ""
	restart_button.visible = true


# --- local input ------------------------------------------------------------

func _open_input() -> void:
	input_open = true
	selected_index = -1
	grid.clear_states(1)
	var their_col := state.players[REMOTE].col
	grid.set_covered(1, [their_col - 1, their_col, their_col + 1])
	var where := "" if state.incoming_zone == null else " to your %s" % state.incoming_zone.label()
	var heavy := ", and it is heavy" if state.incoming_heavy else ""
	incoming_label.text = "Incoming: %s%s%s" % [BallType.label(state.incoming_type), where, heavy]
	hint_label.text = BallType.hint(state.incoming_type) + "  Pick a card, then click a zone on their half."
	hand_ui.show_hand(state.players[LOCAL].hand, state.incoming_type, state.players[LOCAL].stamina)
	hand_ui.set_enabled(true)


func _on_card_chosen(index: int) -> void:
	if not input_open or index >= state.players[LOCAL].hand.size():
		return
	selected_index = index
	hand_ui.set_selected(index)
	_update_hover_hint()


func _unhandled_input(event: InputEvent) -> void:
	if not input_open:
		return
	if event is InputEventMouseMotion:
		_set_hover(_zone_under_mouse(event.position))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var z := _zone_under_mouse(event.position)
		if z != null:
			choose_zone(z)


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
	if not input_open or selected_index < 0 or zone.side <= 0:
		return
	var action := {"type": "shot", "player": LOCAL, "card": selected_index, "row": zone.row, "col": zone.col}
	_submit(action)


## The one place a local action leaves the UI. Online, this is also where it
## gets sent to the other peer before being applied here.
func _submit(action: Dictionary) -> void:
	input_open = false
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
	score_label.text = "YOU %d   -   %d THEM" % [score[0], score[1]]
	_refresh_stamina()


func _refresh_stamina() -> void:
	stamina_label.text = "stamina   you %d/%d   ·   them %d/%d" % [
		_shown_stamina[0], MatchState.STAMINA_MAX, _shown_stamina[1], MatchState.STAMINA_MAX]


func _log(text: String) -> void:
	log_label.text = text
