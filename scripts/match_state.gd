## The whole rules side of a match, with no nodes in it.
##
## Two players, each with a deck, a hand, a lane and a stamina pool. Everything
## random comes from one seeded RandomNumberGenerator, so two copies of this
## class fed the same seed and the same actions produce the same match. That is
## the contract online play will lean on: peers exchange actions (small
## dictionaries), each runs apply() locally, and the presenter only ever plays
## back the events apply() returns. Nothing in here may touch the scene tree or
## global RNG.
##
## Stamina is soft: a card that costs more than you have can still be played,
## but it empties the pool and the shot is `tired` (a flat quality penalty in
## RallyResolver, so odds() shows it). Both players regain STAMINA_REGEN at
## every point start, capped at STAMINA_MAX, and stamina carries across points.
class_name MatchState
extends RefCounted

enum Phase { RALLY, POINT_OVER, MATCH_OVER }
enum Outcome { FAULT = RallyResolver.Outcome.FAULT, WINNER = RallyResolver.Outcome.WINNER, RETURNED = RallyResolver.Outcome.RETURNED }

const HAND_SIZE := 4
## Used when the constructor is not told otherwise (the quick single match).
const DEFAULT_POINTS_TO_WIN := 7
const SERVE_SWITCH_EVERY := 2
const HOME_COL := 2
const STAMINA_MAX := 6
## Stamina both players get back at every point start.
const STAMINA_REGEN := 1
## Stamina a `rest` card gives back after its cost is paid.
const REST_AMOUNT := 2
## Stamina the opponent loses when a `sap` card lands.
const SAP_AMOUNT := 2
## Extra incoming risk when replying to a `heavy` ball, as if it were a deep edge.
const HEAVY_RISK := 0.25


class PlayerState:
	var deck: Array[Card] = []
	var hand: Array[Card] = []
	var discard: Array[Card] = []
	## Cards with `exhaust` that were played: gone for the rest of the match.
	var exhausted: Array[Card] = []
	var score := 0
	var col := HOME_COL
	var stamina := STAMINA_MAX
	var stats := {"shots": 0, "winners": 0, "faults": 0, "tired_plays": 0}

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
			"exhausted": CardLibrary.ids_of(exhausted),
			"score": score,
			"col": col,
			"stamina": stamina,
			"stats": stats.duplicate(),
		}

	static func from_dict(d: Dictionary) -> PlayerState:
		var p := PlayerState.new()
		p.deck = CardLibrary.from_ids(d["deck"])
		p.hand = CardLibrary.from_ids(d["hand"])
		p.discard = CardLibrary.from_ids(d["discard"])
		p.exhausted = CardLibrary.from_ids(d["exhausted"])
		p.score = int(d["score"])
		p.col = int(d["col"])
		p.stamina = int(d["stamina"])
		for k in p.stats:
			p.stats[k] = int(d["stats"][k])
		return p


var layout: ZoneLayout
var rng := RandomNumberGenerator.new()
var seed_value: int
var players: Array[PlayerState] = []
var points_to_win: int
var points_played := 0
var rally_length := 0
## The longest rally of the match so far, in shots.
var longest_rally := 0
## Index of the player who hits next.
var turn := 0
var incoming_type: int = BallType.NONE
var incoming_zone: Zone = null
## True while the ball to reply to came off a `heavy` card. Cleared by the
## reply (it was that reply's problem) and at every point start.
var incoming_heavy := false
## Starts between points: call start_point() to begin the first one.
var phase: Phase = Phase.POINT_OVER


func _init(p_seed: int, decks: Array, p_layout: ZoneLayout, p_points_to_win: int = DEFAULT_POINTS_TO_WIN) -> void:
	layout = p_layout
	seed_value = p_seed
	points_to_win = p_points_to_win
	rng.seed = p_seed
	for i in 2:
		var p := PlayerState.new()
		# A fresh typed copy, whatever the caller's array type: the caller's
		# deck is never shuffled in place.
		var deck: Array[Card] = []
		deck.assign(decks[i])
		shuffle(deck, rng)
		p.deck = deck
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


func _stamina() -> Array:
	return [players[0].stamina, players[1].stamina]


func _score() -> Array:
	return [players[0].score, players[1].score]


## Begin a point. Returns the events the presenter should play back.
func start_point() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	rally_length = 0
	for p in players:
		p.col = HOME_COL
		p.stamina = mini(STAMINA_MAX, p.stamina + STAMINA_REGEN)
		p.draw_to(HAND_SIZE, rng)
	turn = server()
	incoming_type = BallType.NONE
	incoming_zone = null
	incoming_heavy = false
	phase = Phase.RALLY
	events.append({"type": "point_start", "server": turn, "score": _score(), "stamina": _stamina()})
	events.append(_turn_event())
	return events


func _turn_event() -> Dictionary:
	return {
		"type": "turn",
		"player": turn,
		"incoming_type": incoming_type,
		"incoming_zone": incoming_zone,
		"incoming_heavy": incoming_heavy,
		"stamina": _stamina(),
	}


## Zones `player` may aim at: the whole of the other half.
func legal_targets(player: int) -> Array[Zone]:
	return layout.zones_on(side_of(opponent_of(player)))


## The shot as the resolver sees it. `tired` is judged against the stamina the
## player has right now, before paying, so odds() and apply() agree.
func build_shot(player: int, card: Card, zone: Zone) -> RallyResolver.Shot:
	var shot := RallyResolver.Shot.new()
	shot.card = card
	shot.incoming_type = incoming_type
	shot.incoming_risk = (0.0 if incoming_zone == null else incoming_zone.risk) + (HEAVY_RISK if incoming_heavy else 0.0)
	shot.target = zone
	shot.opponent_col = players[opponent_of(player)].col
	shot.tired = card.cost > players[player].stamina
	return shot


func odds(player: int, card_index: int, zone: Zone) -> Dictionary:
	return RallyResolver.odds(build_shot(player, players[player].hand[card_index], zone))


## What a shot event's `kind` says about the result, for callouts and stats:
##   "ace"      an outright winner on the serve (no incoming ball),
##   "edge"     an outright winner into an edge lane (col 0 or 4),
##   "winner"   any other outright winner,
##   "tired"    a fault by a tired play (the card cost more than the player had),
##   "fault"    any other fault,
##   "returned" the ball came back and the rally goes on.
static func kind_of(outcome: int, tired: bool, on_serve: bool, zone: Zone) -> String:
	match outcome:
		RallyResolver.Outcome.WINNER:
			if on_serve:
				return "ace"
			return "edge" if zone.is_edge_col() else "winner"
		RallyResolver.Outcome.FAULT:
			return "tired" if tired else "fault"
	return "returned"


## An action is a plain dictionary so it can be sent as-is:
##   {"type": "shot", "player": 0, "card": 2, "row": 1, "col": 3}
## `card` is an index into that player's hand; `row`/`col` pick a zone on the
## other half. Returns the events that happened, in order. The `shot` event
## carries `cost`, `tired`, `keyword`, `kind` and the stamina of both players
## after the shot; `point_start` and `turn` carry `stamina` too. A malformed
## or out-of-turn action pushes a warning, changes nothing and returns [], so
## a bad dictionary off the wire can never raise a script error here.
func apply(action: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var type := str(action.get("type", ""))
	if type != "shot":
		push_warning("MatchState.apply: unknown action type '%s'" % type)
		return events
	if phase != Phase.RALLY:
		push_warning("MatchState.apply: no rally in progress")
		return events
	var player := _int_field(action, "player")
	if player != turn:
		push_warning("MatchState.apply: it is player %d's turn, not %d" % [turn, player])
		return events
	var me := players[player]
	var card_index := _int_field(action, "card")
	if card_index < 0 or card_index >= me.hand.size():
		push_warning("MatchState.apply: bad card index %d" % card_index)
		return events
	var zone := layout.find(side_of(opponent_of(player)), _int_field(action, "row"), _int_field(action, "col"))
	if zone == null:
		push_warning("MatchState.apply: bad target zone")
		return events

	var card: Card = me.hand[card_index]
	var them := players[opponent_of(player)]
	var on_serve := incoming_type == BallType.NONE
	var shot := build_shot(player, card, zone)
	me.stamina = 0 if shot.tired else me.stamina - card.cost
	if card.keyword == "rest":
		me.stamina = mini(STAMINA_MAX, me.stamina + REST_AMOUNT)
	me.hand.remove_at(card_index)
	if card.keyword == "exhaust":
		me.exhausted.append(card)
	else:
		me.discard.append(card)
	var result := RallyResolver.resolve(shot, rng)
	var outcome: int = result["outcome"]
	incoming_heavy = false
	rally_length += 1
	me.stats["shots"] += 1
	if shot.tired:
		me.stats["tired_plays"] += 1
	if outcome == RallyResolver.Outcome.FAULT:
		me.stats["faults"] += 1
	elif outcome == RallyResolver.Outcome.WINNER:
		me.stats["winners"] += 1
	if outcome != RallyResolver.Outcome.FAULT and card.keyword == "sap":
		them.stamina = maxi(0, them.stamina - SAP_AMOUNT)
	events.append({
		"type": "shot",
		"player": player,
		"card": card,
		"target": zone,
		"outcome": outcome,
		"kind": kind_of(outcome, shot.tired, on_serve, zone),
		"incoming_type": incoming_type,
		"quality": result["quality"],
		"cost": card.cost,
		"tired": shot.tired,
		"keyword": card.keyword,
		"stamina": _stamina(),
		"rally_length": rally_length,
	})

	match outcome:
		RallyResolver.Outcome.FAULT:
			events.append_array(_end_point(opponent_of(player)))
		RallyResolver.Outcome.WINNER:
			events.append_array(_end_point(player))
		_:
			them.col = zone.col
			incoming_type = card.produces
			incoming_zone = zone
			incoming_heavy = card.keyword == "heavy"
			turn = opponent_of(player)
			me.draw_to(HAND_SIZE, rng)
			events.append(_turn_event())
	return events


## An action field as an int: ints, floats and numeric strings convert,
## anything else (a missing key, a dictionary off the wire) is -1, which every
## range check rejects. int(Variant) would raise on a Dictionary or an Array.
static func _int_field(action: Dictionary, key: String, fallback: int = -1) -> int:
	var v: Variant = action.get(key, fallback)
	match typeof(v):
		TYPE_INT, TYPE_FLOAT:
			return int(v)
		TYPE_STRING:
			return int(v) if String(v).is_valid_int() else fallback
	return fallback


func _end_point(winner: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	players[winner].score += 1
	points_played += 1
	longest_rally = maxi(longest_rally, rally_length)
	phase = Phase.POINT_OVER
	events.append({
		"type": "point",
		"winner": winner,
		"score": _score(),
		"points_to_win": points_to_win,
		"rally_length": rally_length,
	})
	if players[winner].score >= points_to_win:
		phase = Phase.MATCH_OVER
		events.append({
			"type": "match_over",
			"winner": winner,
			"score": _score(),
			"longest_rally": longest_rally,
			"stats": [players[0].stats.duplicate(), players[1].stats.duplicate()],
		})
	return events


## Snapshot for reconnects, replays or spectators. Cards travel as ids. The
## seed and the RNG state travel as decimal strings: JSON parses numbers as
## doubles, which lose the low bits of a 64-bit value, and a peer that
## resumes from a snapshot must roll the same shots as the one that sent it.
func to_dict() -> Dictionary:
	return {
		"seed": str(seed_value),
		"rng_state": str(rng.state),
		"players": [players[0].to_dict(), players[1].to_dict()],
		"points_to_win": points_to_win,
		"points_played": points_played,
		"rally_length": rally_length,
		"longest_rally": longest_rally,
		"turn": turn,
		"incoming_type": incoming_type,
		"incoming_zone": null if incoming_zone == null else incoming_zone.to_dict(),
		"incoming_heavy": incoming_heavy,
		"phase": phase,
	}


## Rebuilds a match from to_dict() output, in memory or after a JSON round
## trip. The seed and rng_state may be ints (older snapshots) or the decimal
## strings to_dict() writes.
static func from_dict(d: Dictionary, p_layout: ZoneLayout) -> MatchState:
	var empty: Array[Card] = []
	var s := MatchState.new(_as_int(d["seed"]), [empty, empty], p_layout, int(d["points_to_win"]))
	s.rng.state = _as_int(d["rng_state"])
	s.players = [PlayerState.from_dict(d["players"][0]), PlayerState.from_dict(d["players"][1])]
	s.points_played = int(d["points_played"])
	s.rally_length = int(d["rally_length"])
	s.longest_rally = int(d["longest_rally"])
	s.turn = int(d["turn"])
	s.incoming_type = int(d["incoming_type"])
	s.incoming_zone = null if d["incoming_zone"] == null else p_layout.from_dict(d["incoming_zone"])
	s.incoming_heavy = bool(d["incoming_heavy"])
	s.phase = int(d["phase"]) as Phase
	return s


## A 64-bit value from a snapshot: an int or float as it is, a decimal string
## with all its bits (int(String) would go through a double).
static func _as_int(v: Variant) -> int:
	return int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else String(v).to_int()
