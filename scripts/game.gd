## The turn loop. One point = a sequence of card plays until someone misses.
extends Node3D

enum Phase { PLAYER_TURN, ANIMATING, POINT_OVER, MATCH_OVER }

const HAND_SIZE := 4
const POINTS_TO_WIN := 7
const SERVE_SWITCH_EVERY := 2

@onready var ball: BallFlight = $World/Ball
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
var incoming: int = BallType.NONE
var phase: Phase = Phase.MATCH_OVER

# Fixed spots on the table, in world space. Table is 2.74 long along X.
const PLAYER_HIT := Vector3(-1.55, 1.0, -0.05)
const OPPONENT_HIT := Vector3(1.55, 1.0, 0.05)
const NET_TOP := Vector3(0.0, 0.92, 0.0)


func _ready() -> void:
	rng.randomize()
	camera.look_at(Vector3(0.0, 0.75, 0.0))
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
	if _player_serves():
		incoming = BallType.NONE
		ball.global_position = PLAYER_HIT + Vector3(0.1, 0.0, 0.0)
		_log("Your serve.")
		_begin_player_turn()
	else:
		_opponent_serves()


func _opponent_serves() -> void:
	phase = Phase.ANIMATING
	hand_ui.set_enabled(false)
	_log("Opponent serves...")
	ball.global_position = OPPONENT_HIT + Vector3(-0.1, 0.0, 0.0)
	await get_tree().create_timer(0.5).timeout
	incoming = OpponentAI.serve(rng)
	_swing(opponent_paddle, -1.0)
	await ball.shot(_bounce_point(-1.0, 0.5), PLAYER_HIT, 0.4, 0.9)
	_begin_player_turn()


func _begin_player_turn() -> void:
	phase = Phase.PLAYER_TURN
	incoming_label.text = "Incoming: %s" % BallType.label(incoming)
	hint_label.text = BallType.hint(incoming)
	hand_ui.show_hand(hand, incoming)
	hand_ui.set_enabled(true)


func _on_card_chosen(index: int) -> void:
	if phase != Phase.PLAYER_TURN or index >= hand.size():
		return
	phase = Phase.ANIMATING
	hand_ui.set_enabled(false)
	var card: Card = hand[index]
	hand.remove_at(index)
	discard.append(card)
	await _play_card(card)


func _play_card(card: Card) -> void:
	rally_length += 1
	var result := RallyResolver.resolve(card, incoming, rng)
	var outcome: int = result["outcome"]
	_swing(player_paddle, 1.0)
	if card.power > 0.8:
		_camera_punch()

	match outcome:
		RallyResolver.Outcome.FAULT:
			_log("%s... into the net." % card.title)
			await ball.into_net(NET_TOP, card.speed)
			_show_callout("FAULT", Color(0.95, 0.4, 0.4))
			await _end_point(false)
		RallyResolver.Outcome.WINNER:
			_log("%s! Clean winner." % card.title)
			var past := OPPONENT_HIT + Vector3(0.9, -0.5, rng.randf_range(-0.6, 0.6))
			await ball.shot(_bounce_point(1.0, 0.75), past, card.arc_height, card.speed)
			_show_callout("WINNER", Color(1.0, 0.85, 0.3))
			await _end_point(true)
		_:
			await ball.shot(_bounce_point(1.0, 0.55), OPPONENT_HIT, card.arc_height, card.speed)
			incoming = OpponentAI.reply_to(card.produces, rng)
			_log("%s returned. They answer with a %s ball." % [card.title, BallType.label(incoming).to_lower()])
			_swing(opponent_paddle, -1.0)
			var reply_arc := 0.9 if incoming == BallType.HIGH else 0.3
			var reply_speed := 1.5 if incoming == BallType.FAST else 1.0
			await ball.shot(_bounce_point(-1.0, 0.55), PLAYER_HIT, reply_arc, reply_speed)
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

	# Played cards go back into the deck only when it runs dry; the hand carries over.
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


## Where the ball bounces on the receiving half. `dir` is +1 toward the opponent.
func _bounce_point(dir: float, depth: float) -> Vector3:
	return Vector3(dir * lerpf(0.2, 1.3, depth), 0.78, rng.randf_range(-0.35, 0.35))


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
