## The turn loop. One point = a sequence of card plays until someone misses.
## Play is 2D: pick a card, then aim it at one of the 2x5 zones on their half.
extends Node3D

enum Phase { PLAYER_TURN, ANIMATING, POINT_OVER, MATCH_OVER }

const HAND_SIZE := 4
const POINTS_TO_WIN := 7
const SERVE_SWITCH_EVERY := 2
const PADDLE_X := 1.6
const PADDLE_Y := 1.0

@onready var ball: BallFlight = $World/Ball
@onready var grid: ZoneGrid = $World/ZoneGrid
@onready var player_paddle: Node3D = $World/PlayerPaddle
@onready var opponent_paddle: Node3D = $World/OpponentPaddle
@onready var camera: Camera3D = $World/Camera3D
@onready var callout: Label3D = $World/Callout
@onready var score_label: Label = %ScoreLabel
@onready var incoming_label: Label = %IncomingLabel
@onready var hint_label: Label = %HintLabel
@onready var log_label: Label = %LogLabel
@onready var hand_ui: HandUI = %Hand
@onready var restart_button: Button = %RestartButton

var rng := RandomNumberGenerator.new()
var deck: Array[Card] = []
var hand: Array[Card] = []
var discard: Array[Card] = []

var player_score := 0
var opponent_score := 0
var points_played := 0
var rally_length := 0
var phase: Phase = Phase.MATCH_OVER

var incoming: int = BallType.NONE
var incoming_zone: Zone = null
var player_col := 2
var opponent_col := 2
var selected_index := -1
var hover_zone: Zone = null
var target_zone: Zone = null


func _ready() -> void:
	rng.randomize()
	camera.look_at(Vector3(-0.45, 0.76, 0.0))
	hand_ui.card_chosen.connect(_on_card_chosen)
	restart_button.pressed.connect(start_match)
	callout.visible = false
	start_match()


func start_match() -> void:
	player_score = 0
	opponent_score = 0
	points_played = 0
	deck = CardLibrary.starter_deck()
	deck.shuffle()
	hand.clear()
	discard.clear()
	restart_button.visible = false
	_log("New match. First to %d." % POINTS_TO_WIN)
	_refresh_score()
	_start_point()


func _player_serves() -> bool:
	@warning_ignore("integer_division")
	var pair: int = points_played / SERVE_SWITCH_EVERY
	return pair % 2 == 0


func _start_point() -> void:
	rally_length = 0
	_draw_to(HAND_SIZE)
	grid.clear_states(-1)
	grid.clear_states(1)
	_move_player_to(2, true)
	_move_opponent_to(2, true)
	if _player_serves():
		incoming = BallType.NONE
		incoming_zone = null
		ball.global_position = _player_hit_point() + Vector3(0.1, 0.0, 0.0)
		_log("Your serve.")
		_begin_player_turn()
	else:
		_opponent_serves()


func _opponent_serves() -> void:
	phase = Phase.ANIMATING
	hand_ui.set_enabled(false)
	_log("Opponent serves...")
	ball.global_position = _opponent_hit_point() + Vector3(-0.1, 0.0, 0.0)
	await get_tree().create_timer(0.5).timeout
	await _opponent_hits(OpponentAI.serve(rng), 0.9)
	_begin_player_turn()


## The opponent sends a ball of `type` to a zone on your side; you shuffle over.
func _opponent_hits(type: int, speed: float) -> void:
	incoming = type
	incoming_zone = OpponentAI.aim(grid, type, player_col, rng)
	grid.clear_states(-1)
	grid.set_state(incoming_zone, Zone.State.INCOMING)
	_swing(opponent_paddle, -1.0)
	_move_player_to(incoming_zone.col, false)
	var arc := 0.9 if type == BallType.HIGH else 0.3
	var spd := 1.5 if type == BallType.FAST else 1.0
	await ball.shot(grid.landing_point(incoming_zone), _player_hit_point(), arc, spd * speed)


func _begin_player_turn() -> void:
	phase = Phase.PLAYER_TURN
	selected_index = -1
	target_zone = null
	grid.clear_states(1)
	grid.set_covered(1, [opponent_col - 1, opponent_col, opponent_col + 1])
	var where := "" if incoming_zone == null else " to your %s" % incoming_zone.label()
	incoming_label.text = "Incoming: %s%s" % [BallType.label(incoming), where]
	hint_label.text = BallType.hint(incoming) + "  Pick a card, then click a zone on their half."
	hand_ui.show_hand(hand, incoming)
	hand_ui.set_enabled(true)


func _on_card_chosen(index: int) -> void:
	if phase != Phase.PLAYER_TURN or index >= hand.size():
		return
	selected_index = index
	hand_ui.set_selected(index)
	_update_hover_hint()


func _unhandled_input(event: InputEvent) -> void:
	if phase != Phase.PLAYER_TURN:
		return
	if event is InputEventMouseMotion:
		_set_hover(_zone_under_mouse(event.position))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var z := _zone_under_mouse(event.position)
		if z != null and z.side > 0:
			choose_zone(z)


func _zone_under_mouse(screen_pos: Vector2) -> Zone:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var hit = Plane(Vector3.UP, ZoneGrid.TOP_Y).intersects_ray(from, dir)
	if hit == null:
		return null
	var z := grid.zone_at(hit)
	return z if (z != null and z.side > 0) else null


func _set_hover(z: Zone) -> void:
	if z == hover_zone:
		return
	if hover_zone != null and hover_zone.state == Zone.State.HOVER:
		grid.set_state(hover_zone, Zone.State.IDLE)
	hover_zone = z
	if hover_zone != null and hover_zone.state == Zone.State.IDLE:
		grid.set_state(hover_zone, Zone.State.HOVER)
	_update_hover_hint()


func _update_hover_hint() -> void:
	if selected_index < 0:
		hint_label.text = BallType.hint(incoming) + "  Pick a card first."
		return
	var card: Card = hand[selected_index]
	if hover_zone == null:
		hint_label.text = "%s selected. Dotted zones are easier to miss, darker ones are where they stand." % card.title
		return
	var odds := RallyResolver.odds(_build_shot(card, hover_zone))
	hint_label.text = "%s to the %s: lands %d%%, wins %d%% if it does." % [
		card.title, hover_zone.label(), roundi(odds["land"] * 100.0), roundi(odds["win"] * 100.0)]


func _build_shot(card: Card, zone: Zone) -> RallyResolver.Shot:
	var shot := RallyResolver.Shot.new()
	shot.card = card
	shot.incoming_type = incoming
	shot.incoming_risk = 0.0 if incoming_zone == null else incoming_zone.risk
	shot.target = zone
	shot.opponent_col = opponent_col
	return shot


## Commit the selected card at `zone`. Also what the headless test calls.
func choose_zone(zone: Zone) -> void:
	if phase != Phase.PLAYER_TURN or selected_index < 0 or zone.side <= 0:
		return
	phase = Phase.ANIMATING
	hand_ui.set_enabled(false)
	var card: Card = hand[selected_index]
	hand.remove_at(selected_index)
	discard.append(card)
	selected_index = -1
	target_zone = zone
	_set_hover(null)
	grid.set_state(zone, Zone.State.TARGET)
	await _play_card(card, zone)


func _play_card(card: Card, zone: Zone) -> void:
	rally_length += 1
	var shot := _build_shot(card, zone)
	var result := RallyResolver.resolve(shot, rng)
	var outcome: int = result["outcome"]
	_swing(player_paddle, 1.0)
	if card.power > 0.8:
		_camera_punch()
	var landing := grid.landing_point(zone)

	match outcome:
		RallyResolver.Outcome.FAULT:
			if zone.is_edge_col() or zone.is_deep():
				_log("%s to the %s... just out." % [card.title, zone.label()])
				var out := landing + Vector3(0.35 if zone.is_deep() else 0.0, -0.4, signf(landing.z) * (0.4 if zone.is_edge_col() else 0.0))
				await ball.shot(landing + Vector3(0.0, 0.0, 0.0), out, card.arc_height, card.speed)
			else:
				_log("%s... into the net." % card.title)
				await ball.into_net(Vector3(0.0, 0.92, landing.z * 0.5), card.speed)
			_show_callout("FAULT", Color(0.95, 0.4, 0.4))
			await _end_point(false)
		RallyResolver.Outcome.WINNER:
			_log("%s to the %s! Clean winner." % [card.title, zone.label()])
			_move_opponent_to(clampi(zone.col + signi(opponent_col - zone.col), 0, 4), false)
			var past := landing + Vector3(1.1, -0.45, signf(landing.z) * 0.3)
			await ball.shot(landing, past, card.arc_height, card.speed)
			_show_callout("WINNER", Color(1.0, 0.85, 0.3))
			await _end_point(true)
		_:
			_move_opponent_to(zone.col, false)
			await ball.shot(landing, _opponent_hit_point(), card.arc_height, card.speed)
			var reply := OpponentAI.reply_to(card.produces, rng)
			_log("%s returned. They answer with a %s ball." % [card.title, BallType.label(reply).to_lower()])
			await _opponent_hits(reply, 1.0)
			opponent_col = OpponentAI.reposition(opponent_col, rng)
			_move_opponent_to(opponent_col, false)
			_draw_to(HAND_SIZE)
			_begin_player_turn()


func _end_point(player_won: bool) -> void:
	phase = Phase.POINT_OVER
	points_played += 1
	if player_won:
		player_score += 1
	else:
		opponent_score += 1
	_refresh_score()
	await get_tree().create_timer(1.1).timeout
	callout.visible = false

	if player_score >= POINTS_TO_WIN or opponent_score >= POINTS_TO_WIN:
		phase = Phase.MATCH_OVER
		var won := player_score > opponent_score
		_log("Match over. You %s %d to %d." % ["win" if won else "lose", player_score, opponent_score])
		_show_callout("YOU WIN" if won else "YOU LOSE", Color(1.0, 0.85, 0.3) if won else Color(0.7, 0.7, 0.9))
		hand_ui.clear()
		incoming_label.text = ""
		hint_label.text = ""
		restart_button.visible = true
		return

	_start_point()


func _draw_to(count: int) -> void:
	while hand.size() < count:
		if deck.is_empty():
			if discard.is_empty():
				return
			deck = discard.duplicate()
			discard.clear()
			deck.shuffle()
		hand.append(deck.pop_back())


func _lane_z(col: int) -> float:
	return grid.zone(1, 0, col).center().z


func _player_hit_point() -> Vector3:
	return Vector3(-PADDLE_X + 0.15, PADDLE_Y, _lane_z(player_col))


func _opponent_hit_point() -> Vector3:
	return Vector3(PADDLE_X - 0.15, PADDLE_Y, _lane_z(opponent_col))


func _move_player_to(col: int, instant: bool) -> void:
	player_col = col
	_slide(player_paddle, Vector3(-PADDLE_X, PADDLE_Y, _lane_z(col)), instant)


func _move_opponent_to(col: int, instant: bool) -> void:
	opponent_col = col
	_slide(opponent_paddle, Vector3(PADDLE_X, PADDLE_Y, _lane_z(col)), instant)


func _slide(paddle: Node3D, to: Vector3, instant: bool) -> void:
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


func _show_callout(text: String, color: Color) -> void:
	callout.text = text
	callout.modulate = color
	callout.visible = true
	callout.scale = Vector3.ONE * 0.4
	var t := create_tween()
	t.tween_property(callout, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _refresh_score() -> void:
	score_label.text = "YOU %d   -   %d THEM" % [player_score, opponent_score]


func _log(text: String) -> void:
	log_label.text = text
