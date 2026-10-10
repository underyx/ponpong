## The whole rules side of a match, with no nodes in it.
##
## Two players, each with a deck, a hand and a lane. Everything random comes
## from one seeded RandomNumberGenerator, so two copies of this class fed the
## same seed and the same actions produce the same match. That is the contract
## online play will lean on: peers exchange actions (small dictionaries), each
## runs apply() locally, and the presenter only ever plays back the events
## apply() returns. Nothing in here may touch the scene tree or global RNG.
class_name MatchState
extends RefCounted

enum Phase { RALLY, POINT_OVER, MATCH_OVER }
enum Outcome { FAULT = RallyResolver.Outcome.FAULT, WINNER = RallyResolver.Outcome.WINNER, RETURNED = RallyResolver.Outcome.RETURNED }

const HAND_SIZE := 4
const POINTS_TO_WIN := 7
const SERVE_SWITCH_EVERY := 2
const HOME_COL := 2


class PlayerState:
	var deck: Array[Card] = []
	var hand: Array[Card] = []
	var discard: Array[Card] = []
	var score := 0
	var col := HOME_COL

	func draw_to(count: int, rng: RandomNumberGenerator) -> void:
		while hand.size() < count:
			if deck.is_empty():
				if discard.is_empty():
					return
				deck = discard.duplicate()
				discard.clear()
				MatchState.shuffle(deck, rng)
			hand.append(deck.pop_back())

	func to_dict() -> Dictionary:
		return {
			"deck": CardLibrary.ids_of(deck),
			"hand": CardLibrary.ids_of(hand),
			"discard": CardLibrary.ids_of(discard),
			"score": score,
			"col": col,
		}

	static func from_dict(d: Dictionary) -> PlayerState:
		var p := PlayerState.new()
		p.deck = CardLibrary.from_ids(d["deck"])
		p.hand = CardLibrary.from_ids(d["hand"])
		p.discard = CardLibrary.from_ids(d["discard"])
		p.score = int(d["score"])
		p.col = int(d["col"])
		return p


var layout: ZoneLayout
var rng := RandomNumberGenerator.new()
var seed_value: int
var players: Array[PlayerState] = []
var points_played := 0
var rally_length := 0
## Index of the player who hits next.
var turn := 0
var incoming_type: int = BallType.NONE
var incoming_zone: Zone = null
## Starts between points: call start_point() to begin the first one.
var phase: Phase = Phase.POINT_OVER


func _init(p_seed: int, decks: Array, p_layout: ZoneLayout) -> void:
	layout = p_layout
	seed_value = p_seed
	rng.seed = p_seed
	for i in 2:
		var p := PlayerState.new()
		p.deck = (decks[i] as Array[Card]).duplicate()
		shuffle(p.deck, rng)
		players.append(p)


## Fisher-Yates on our own RNG. Array.shuffle() uses the global one, which
## would break determinism between peers.
static func shuffle(cards: Array, p_rng: RandomNumberGenerator) -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j := p_rng.randi_range(0, i)
		var tmp = cards[i]
		cards[i] = cards[j]
		cards[j] = tmp


static func side_of(player: int) -> int:
	return -1 if player == 0 else 1


static func opponent_of(player: int) -> int:
	return 1 - player


func server() -> int:
	@warning_ignore("integer_division")
	var pair: int = points_played / SERVE_SWITCH_EVERY
	return pair % 2


func player_on(side: int) -> PlayerState:
	return players[0] if side < 0 else players[1]


## Begin a point. Returns the events the presenter should play back.
func start_point() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	rally_length = 0
	for p in players:
		p.col = HOME_COL
		p.draw_to(HAND_SIZE, rng)
	turn = server()
	incoming_type = BallType.NONE
	incoming_zone = null
	phase = Phase.RALLY
	events.append({"type": "point_start", "server": turn})
	events.append(_turn_event())
	return events


func _turn_event() -> Dictionary:
	return {
		"type": "turn",
		"player": turn,
		"incoming_type": incoming_type,
		"incoming_zone": incoming_zone,
	}


## Zones `player` may aim at: the whole of the other half.
func legal_targets(player: int) -> Array[Zone]:
	return layout.zones_on(side_of(opponent_of(player)))


func build_shot(player: int, card: Card, zone: Zone) -> RallyResolver.Shot:
	var shot := RallyResolver.Shot.new()
	shot.card = card
	shot.incoming_type = incoming_type
	shot.incoming_risk = 0.0 if incoming_zone == null else incoming_zone.risk
	shot.target = zone
	shot.opponent_col = players[opponent_of(player)].col
	return shot


func odds(player: int, card_index: int, zone: Zone) -> Dictionary:
	return RallyResolver.odds(build_shot(player, players[player].hand[card_index], zone))


## An action is a plain dictionary so it can be sent as-is:
##   {"type": "shot", "player": 0, "card": 2, "row": 1, "col": 3}
## `card` is an index into that player's hand; `row`/`col` pick a zone on the
## other half. Returns the events that happened, in order.
func apply(action: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if phase != Phase.RALLY:
		push_warning("MatchState.apply: no rally in progress")
		return events
	var player := int(action["player"])
	if player != turn:
		push_warning("MatchState.apply: it is player %d's turn, not %d" % [turn, player])
		return events
	var me := players[player]
	var card_index := int(action["card"])
	if card_index < 0 or card_index >= me.hand.size():
		push_warning("MatchState.apply: bad card index %d" % card_index)
		return events
	var zone := layout.find(side_of(opponent_of(player)), int(action["row"]), int(action["col"]))
	if zone == null:
		push_warning("MatchState.apply: bad target zone")
		return events

	var card: Card = me.hand[card_index]
	me.hand.remove_at(card_index)
	me.discard.append(card)
	var shot := build_shot(player, card, zone)
	var result := RallyResolver.resolve(shot, rng)
	var outcome: int = result["outcome"]
	rally_length += 1
	events.append({
		"type": "shot",
		"player": player,
		"card": card,
		"target": zone,
		"outcome": outcome,
		"incoming_type": incoming_type,
		"quality": result["quality"],
	})

	match outcome:
		RallyResolver.Outcome.FAULT:
			events.append_array(_end_point(opponent_of(player)))
		RallyResolver.Outcome.WINNER:
			events.append_array(_end_point(player))
		_:
			var them := players[opponent_of(player)]
			them.col = zone.col
			incoming_type = card.produces
			incoming_zone = zone
			turn = opponent_of(player)
			me.draw_to(HAND_SIZE, rng)
			events.append(_turn_event())
	return events


func _end_point(winner: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	players[winner].score += 1
	points_played += 1
	phase = Phase.POINT_OVER
	events.append({
		"type": "point",
		"winner": winner,
		"score": [players[0].score, players[1].score],
	})
	if players[winner].score >= POINTS_TO_WIN:
		phase = Phase.MATCH_OVER
		events.append({"type": "match_over", "winner": winner})
	return events


## Snapshot for reconnects, replays or spectators. Cards travel as ids.
func to_dict() -> Dictionary:
	return {
		"seed": seed_value,
		"rng_state": rng.state,
		"players": [players[0].to_dict(), players[1].to_dict()],
		"points_played": points_played,
		"rally_length": rally_length,
		"turn": turn,
		"incoming_type": incoming_type,
		"incoming_zone": null if incoming_zone == null else incoming_zone.to_dict(),
		"phase": phase,
	}


static func from_dict(d: Dictionary, p_layout: ZoneLayout) -> MatchState:
	var empty: Array[Card] = []
	var s := MatchState.new(int(d["seed"]), [empty, empty], p_layout)
	s.rng.state = int(d["rng_state"])
	s.players = [PlayerState.from_dict(d["players"][0]), PlayerState.from_dict(d["players"][1])]
	s.points_played = int(d["points_played"])
	s.rally_length = int(d["rally_length"])
	s.turn = int(d["turn"])
	s.incoming_type = int(d["incoming_type"])
	s.incoming_zone = null if d["incoming_zone"] == null else p_layout.from_dict(d["incoming_zone"])
	s.phase = int(d["phase"]) as Phase
	return s
