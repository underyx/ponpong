## Proves the rules run without any scene and are deterministic: two
## MatchStates with the same seed, driven by the same actions, must produce
## identical events and scores. Also round-trips a snapshot through to_dict(),
## checks the stamina invariants on every apply(), and unit-tests stamina, the
## six keywords, points_to_win and the AI personalities.
## Usage: godot --headless -s tests/determinism.gd
extends SceneTree

const SEEDS := [1, 42, 20261010]
const DECK_SIZE := 14
const SHORT_MIDDLE := Vector2i(0, 2)

var layout := ZoneLayout.new()
var failures := 0


func _initialize() -> void:
	_test_pool_matches()
	_test_snapshot()
	_test_stamina()
	_test_invalid_actions()
	_test_keywords()
	_test_points_to_win()
	_test_ai_personalities()
	print("determinism: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(0 if failures == 0 else 1)


func _check(ok: bool, what: String) -> bool:
	if not ok:
		failures += 1
		push_error("FAIL: %s" % what)
	return ok


# --- 1 + 3: pool decks against every opponent, with invariants ---------------

func _test_pool_matches() -> void:
	var keywords_seen := {}
	for seed_value in SEEDS:
		var deck := _pool_deck(seed_value)
		for id in OpponentLibrary.all_ids():
			var ai: Dictionary = OpponentLibrary.profile(id)["ai"]
			var ptw: int = RunState.POINTS_TO_WIN[_stage_of(id)]
			var a := _pool_match(seed_value, deck, id, ptw)
			var b := _pool_match(seed_value, deck, id, ptw)
			var log_a := _play(a, ai, true, keywords_seen)
			var log_b := _play(b, ai, false, {})
			var same := log_a == log_b
			print("seed %d vs %s (to %d): %d events, scores %s vs %s, identical=%s" % [
				seed_value, id, ptw, log_a.size(), [a.players[0].score, a.players[1].score],
				[b.players[0].score, b.players[1].score], same])
			_check(same, "seed %d vs %s: logs differ" % [seed_value, id])
			_check(a.phase == MatchState.Phase.MATCH_OVER, "seed %d vs %s: match did not end" % [seed_value, id])
			_check(maxi(a.players[0].score, a.players[1].score) == ptw, "seed %d vs %s: winner has %d, not %d" % [
				seed_value, id, maxi(a.players[0].score, a.players[1].score), ptw])
	for kw in Card.KEYWORDS:
		if kw != "":
			_check(keywords_seen.has(kw), "keyword %s was never played" % kw)
	print("pool matches: keywords exercised %s" % [keywords_seen.keys()])


func _stage_of(id: String) -> int:
	if OpponentLibrary.TIER_A.has(id):
		return 1
	if OpponentLibrary.TIER_B.has(id):
		return 3
	if OpponentLibrary.BOSSES.has(id):
		return 5
	return 0


## 14 ids drawn from the whole pool by a seeded RNG, so keyword cards show up.
func _pool_deck(seed_value: int) -> Array[String]:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var ids: Array[String] = []
	for i in DECK_SIZE:
		ids.append(CardLibrary.ALL_IDS[r.randi_range(0, CardLibrary.ALL_IDS.size() - 1)])
	return ids


func _opponent_deck(id: String, player_deck: Array[String]) -> Array[String]:
	var ids := OpponentLibrary.deck_ids(id)
	return player_deck.duplicate() if ids.is_empty() else ids


func _pool_match(seed_value: int, deck: Array[String], opponent: String, ptw: int) -> MatchState:
	return MatchState.new(seed_value,
		[CardLibrary.from_ids(deck), CardLibrary.from_ids(_opponent_deck(opponent, deck))], layout, ptw)


## Drive a match to the end with the AI on both sides (seat 1 with `ai1`),
## logging what happened. With `check`, the stamina and hand invariants are
## asserted after every start_point() and apply().
func _play(m: MatchState, ai1: Dictionary, check: bool, keywords_seen: Dictionary) -> Array:
	var log: Array = []
	var guard := 0
	while m.phase != MatchState.Phase.MATCH_OVER and guard < 4000:
		guard += 1
		if m.phase != MatchState.Phase.RALLY:
			var before := _stamina(m)
			var events := m.start_point()
			log.append_array(_flatten(events))
			if check:
				for p in 2:
					_check(m.players[p].stamina == mini(MatchState.STAMINA_MAX, int(before[p]) + MatchState.STAMINA_REGEN),
						"regen: player %d went %d -> %d" % [p, before[p], m.players[p].stamina])
				_check(events[0]["stamina"] == _stamina(m), "point_start carries the stamina after regen")
			continue
		var player := m.turn
		var action := AIController.choose(m, player, ai1 if player == 1 else {})
		var before := _stamina(m)
		var events := m.apply(action)
		log.append(action)
		log.append_array(_flatten(events))
		if check:
			_check_shot(m, events, before, player, keywords_seen)
	_check(guard < 4000, "match ran away")
	return log


func _stamina(m: MatchState) -> Array:
	return [m.players[0].stamina, m.players[1].stamina]


func _check_shot(m: MatchState, events: Array[Dictionary], before: Array, player: int, keywords_seen: Dictionary) -> void:
	if not _check(not events.is_empty() and events[0]["type"] == "shot", "apply() must start with a shot event"):
		return
	var e := events[0]
	var other := MatchState.opponent_of(player)
	var cost := int(e["cost"])
	var tired := bool(e["tired"])
	var keyword := String(e["keyword"])
	var outcome := int(e["outcome"])
	var kind := String(e["kind"])
	var card: Card = e["card"]
	var zone: Zone = e["target"]
	keywords_seen[keyword] = true
	_check(tired == (cost > int(before[player])), "tired must be cost > stamina before (cost %d, before %d, tired %s)" % [cost, before[player], tired])
	var expect_me: int = 0 if tired else int(before[player]) - cost
	if keyword == "rest":
		expect_me = mini(MatchState.STAMINA_MAX, expect_me + MatchState.REST_AMOUNT)
	var expect_them: int = int(before[other])
	if keyword == "sap" and outcome != RallyResolver.Outcome.FAULT:
		expect_them = maxi(0, expect_them - MatchState.SAP_AMOUNT)
	var after: Array = e["stamina"]
	_check(int(after[player]) == expect_me, "%s: shooter stamina %d, expected %d" % [card.id, after[player], expect_me])
	_check(int(after[other]) == expect_them, "%s: receiver stamina %d, expected %d" % [card.id, after[other], expect_them])
	_check(after == _stamina(m), "shot event carries the after-state")
	_check(int(e["rally_length"]) == m.rally_length or m.rally_length == 0, "shot carries rally_length")
	for p in 2:
		var ps := m.players[p]
		_check(ps.stamina >= 0 and ps.stamina <= MatchState.STAMINA_MAX, "stamina out of range: %d" % ps.stamina)
		_check(ps.hand.size() <= MatchState.HAND_SIZE, "hand too big: %d" % ps.hand.size())
		for c in ps.exhausted:
			_check(not ps.hand.has(c) and not ps.deck.has(c) and not ps.discard.has(c), "exhausted %s came back" % c.id)
	if keyword == "exhaust":
		_check(m.players[player].exhausted.has(card), "%s should be in exhausted" % card.id)
	else:
		_check(not m.players[player].exhausted.has(card), "%s should not be in exhausted" % card.id)
	match outcome:
		RallyResolver.Outcome.FAULT:
			_check(kind == ("tired" if tired else "fault"), "fault kind %s (tired %s)" % [kind, tired])
		RallyResolver.Outcome.WINNER:
			var expected := "ace" if int(e["incoming_type"]) == BallType.NONE else ("edge" if zone.is_edge_col() else "winner")
			_check(kind == expected, "winner kind %s, expected %s" % [kind, expected])
		_:
			_check(kind == "returned", "returned kind %s" % kind)
			_check(m.incoming_heavy == (keyword == "heavy"), "incoming_heavy after a %s reply" % keyword)


func _flatten(events: Array[Dictionary]) -> Array:
	var out: Array = []
	for e in events:
		var row := {"type": e["type"]}
		for k in ["player", "server", "winner", "outcome", "incoming_type", "score", "cost", "tired", "keyword",
				"kind", "stamina", "rally_length", "longest_rally", "stats", "incoming_heavy", "points_to_win"]:
			if e.has(k):
				row[k] = e[k]
		if e.has("card"):
			row["card"] = (e["card"] as Card).id
		if e.has("target"):
			row["target"] = (e["target"] as Zone).to_dict()
		if e.has("incoming_zone") and e["incoming_zone"] != null:
			row["incoming_zone"] = (e["incoming_zone"] as Zone).to_dict()
		out.append(row)
	return out


# --- 2: snapshot round trip ----------------------------------------------------

func _test_snapshot() -> void:
	var opponent := "ilse_varga"
	var ai: Dictionary = OpponentLibrary.profile(opponent)["ai"]
	var c := _pool_match(7, _pool_deck(7), opponent, 9)
	c.start_point()
	for i in 12:
		if c.phase != MatchState.Phase.RALLY:
			c.start_point()
		c.apply(AIController.choose(c, c.turn, ai if c.turn == 1 else {}))
	var snap := c.to_dict()
	for k in ["points_to_win", "incoming_heavy", "longest_rally", "rally_length"]:
		_check(snap.has(k), "to_dict is missing %s" % k)
	for k in ["stamina", "exhausted", "stats"]:
		_check(snap["players"][0].has(k), "player to_dict is missing %s" % k)
	var d := MatchState.from_dict(snap, layout)
	_check(d.to_dict() == snap, "from_dict(to_dict()) must reproduce the dict")
	_check(d.points_to_win == 9, "points_to_win survives the snapshot")
	var tail_c := _play(c, ai, false, {})
	var tail_d := _play(d, ai, false, {})
	var same_tail := tail_c == tail_d
	print("snapshot round trip: %d remaining events, identical=%s" % [tail_c.size(), same_tail])
	_check(same_tail, "snapshot tails differ")


# --- 4: stamina unit checks ------------------------------------------------------

func _deck_of_only(id: String, n: int) -> Array[Card]:
	var deck: Array[Card] = []
	for i in n:
		deck.append(CardLibrary.by_id(id))
	return deck


## Keep the rally going for `player` without a point start (so no regen).
func _force_turn(s: MatchState, player: int) -> void:
	s.phase = MatchState.Phase.RALLY
	s.turn = player
	s.players[player].draw_to(MatchState.HAND_SIZE, s.rng)


## Play hand[0] of `player` into `cell` (row, col) of the other half.
func _shot(s: MatchState, player: int, cell: Vector2i = SHORT_MIDDLE) -> Dictionary:
	var events := s.apply({"type": "shot", "player": player, "card": 0, "row": cell.x, "col": cell.y})
	return events[0] if not events.is_empty() else {}


func _test_stamina() -> void:
	var s := MatchState.new(3, [_deck_of_only("smash", 14), _deck_of_only("block", 14)], layout)
	_check(_stamina(s) == [6, 6], "both start at STAMINA_MAX")
	s.start_point()
	_check(_stamina(s) == [6, 6], "regen at the first point is capped at 6")
	_check(s.turn == 0, "player 0 serves first")
	var e1 := _shot(s, 0)
	_check(not e1["tired"] and s.players[0].stamina == 3, "first Smash: 6 -> 3, not tired")
	_force_turn(s, 0)
	var e2 := _shot(s, 0)
	_check(not e2["tired"] and s.players[0].stamina == 0, "second Smash: 3 -> 0, not tired")
	_force_turn(s, 0)
	var e3 := _shot(s, 0)
	_check(e3["tired"] and s.players[0].stamina == 0, "third Smash is tired and stamina stays 0")
	_check(s.players[0].stats["tired_plays"] == 1 and s.players[0].stats["shots"] == 3, "stats count shots and tired plays")
	if int(e3["outcome"]) == RallyResolver.Outcome.FAULT:
		_check(e3["kind"] == "tired", "a tired fault has kind tired")
	s.players[1].stamina = 0
	_force_turn(s, 1)
	var e4 := _shot(s, 1)
	_check(not e4["tired"] and s.players[1].stamina == 0, "Block at 0 stamina is never tired")
	s.players[0].stamina = 0
	s.players[1].stamina = 5
	s.phase = MatchState.Phase.POINT_OVER
	var ev := s.start_point()
	_check(_stamina(s) == [1, 6], "start_point regen is +1, capped at 6: %s" % [_stamina(s)])
	_check(ev[0]["stamina"] == [1, 6] and ev[1]["stamina"] == [1, 6], "point_start and turn carry stamina")
	s.phase = MatchState.Phase.POINT_OVER
	s.start_point()
	_check(_stamina(s) == [2, 6], "second regen: %s" % [_stamina(s)])

	var f := MatchState.new(3, [_deck_of_only("smash", 14), _deck_of_only("block", 14)], layout)
	f.start_point()
	var z := layout.find(1, 0, 2)
	var fresh: float = f.odds(0, 0, z)["land"]
	f.players[0].stamina = 2
	var tired_land: float = f.odds(0, 0, z)["land"]
	_check(f.build_shot(0, f.players[0].hand[0], z).tired, "build_shot marks a tired shot before paying")
	_check(tired_land < fresh, "tired odds %.2f should be below %.2f" % [tired_land, fresh])
	print("stamina units: smash 6 -> 3 -> 0 -> tired, block free, regen ok, odds %.2f -> %.2f tired" % [fresh, tired_land])


# --- 4b: malformed actions ------------------------------------------------------------

## A bad dictionary must warn, return [] and leave the state alone: never a
## script error. Each action pushes a warning by design, so this is noisy.
func _test_invalid_actions() -> void:
	print("invalid actions: the warnings that follow are expected")
	var s := MatchState.new(3, [CardLibrary.starter_deck(), CardLibrary.starter_deck()], layout)
	s.start_point()
	var before := s.to_dict()
	var actions := [
		{"type": "shot"},
		{},
		{"type": "nonsense", "player": 0, "card": 0, "row": 0, "col": 2},
		{"type": "shot", "player": 1, "card": 0, "row": 0, "col": 2},
		{"type": "shot", "player": 0, "card": 9, "row": 0, "col": 2},
		{"type": "shot", "player": 0, "card": 0, "row": 5, "col": 2},
		# Wrongly typed fields, as a bad peer could send them.
		{"type": "shot", "player": {}, "card": 0, "row": 0, "col": 2},
		{"type": "shot", "player": 0, "card": [], "row": 0, "col": 2},
		{"type": "shot", "player": 0, "card": 0, "row": {}, "col": 2},
		{"type": {}, "player": 0, "card": 0, "row": 0, "col": 2},
	]
	for action in actions:
		_check(s.apply(action).is_empty(), "invalid action %s returned events" % [action])
	_check(s.to_dict() == before, "invalid actions changed the match")
	_check(s.phase == MatchState.Phase.RALLY and s.turn == 0, "invalid actions moved the rally on")
	# An empty hand is an empty choice, not an out-of-bounds read.
	var hand_backup: Array[Card] = s.players[0].hand.duplicate()
	s.players[0].hand.clear()
	_check(AIController.choose(s, 0).is_empty(), "choose() on an empty hand should return {}")
	s.players[0].hand = hand_backup
	print("invalid actions: %d rejected, state unchanged" % actions.size())
	# A plain (untyped) Array of Cards is as good a deck as a typed one, and
	# the caller's array is copied, not shuffled in place.
	var untyped: Array = []
	for c in CardLibrary.starter_deck():
		untyped.append(c)
	var order_before: Array = untyped.duplicate()
	var u := MatchState.new(1, [untyped, untyped], layout)
	_check(u.players.size() == 2 and u.players[0].deck.size() == 14 and u.players[1].deck.size() == 14,
		"an untyped deck builds a match with two 14-card decks")
	_check(untyped == order_before, "the caller's deck was shuffled in place")
	_check(u.players[0].deck.is_typed(), "the deck copy is a typed array")
	u.players[0].deck.clear()
	_check(u.players[1].deck.size() == 14 and untyped.size() == 14, "each player got a copy of their own")


# --- 5: keyword unit checks ------------------------------------------------------

func _test_keywords() -> void:
	# rest: +2 after paying, capped at 6.
	var r := MatchState.new(11, [_deck_of_only("breather", 14), _deck_of_only("block", 14)], layout)
	r.start_point()
	r.players[0].stamina = 3
	_shot(r, 0)
	_check(r.players[0].stamina == 5, "breather at 3 -> 5, got %d" % r.players[0].stamina)
	_force_turn(r, 0)
	r.players[0].stamina = 5
	_shot(r, 0)
	_check(r.players[0].stamina == 6, "breather at 5 is capped at 6, got %d" % r.players[0].stamina)
	var fish := MatchState.new(11, [_deck_of_only("fish", 14), _deck_of_only("block", 14)], layout)
	fish.start_point()
	fish.players[0].stamina = 0
	_shot(fish, 0)
	_check(fish.players[0].stamina == 2, "fish at 0 -> 2, got %d" % fish.players[0].stamina)

	# sap: opponent loses 2 when the shot lands, floor 0, nothing on a fault.
	var m := MatchState.new(11, [_deck_of_only("moonball", 14), _deck_of_only("block", 14)], layout)
	m.start_point()
	var em := _shot(m, 0)
	_check(int(em["outcome"]) != RallyResolver.Outcome.FAULT, "a serve moonball into the short middle lands")
	_check(m.players[1].stamina == 4, "moonball that lands: they go 6 -> 4, got %d" % m.players[1].stamina)
	_force_turn(m, 0)
	m.players[1].stamina = 1
	m.incoming_type = BallType.NONE
	m.incoming_zone = null
	_shot(m, 0)
	_check(m.players[1].stamina == 0, "sap floors at 0, got %d" % m.players[1].stamina)
	_force_turn(m, 0)
	m.players[1].stamina = 6
	m.incoming_type = BallType.HIGH
	m.incoming_zone = layout.find(-1, 1, 0)
	var ef := _shot(m, 0, Vector2i(1, 0))
	_check(int(ef["outcome"]) == RallyResolver.Outcome.FAULT, "a weak moonball from a deep edge into a deep edge faults")
	_check(m.players[1].stamina == 6, "sap does nothing on a fault, got %d" % m.players[1].stamina)

	# exhaust: the card leaves for the match and never redraws.
	var x_deck: Array[Card] = [CardLibrary.flat_kill()]
	x_deck.append_array(_deck_of_only("block", 5))
	var x := MatchState.new(11, [x_deck, _deck_of_only("block", 14)], layout)
	x.start_point()
	var kills := 0
	for i in 30:
		_force_turn(x, 0)
		x.incoming_type = BallType.NONE
		x.incoming_zone = null
		var e := _shot(x, 0)
		if e["card"].id == "flat_kill":
			kills += 1
			_check(x.players[0].exhausted.size() == 1 and x.players[0].exhausted[0].id == "flat_kill", "flat_kill goes to exhausted")
			_check(not x.players[0].discard.has(e["card"]), "flat_kill is not in discard")
	_check(kills == 1, "flat_kill was played %d times in 30 plays, expected once" % kills)
	var ids_left: Array = CardLibrary.ids_of(x.players[0].hand) + CardLibrary.ids_of(x.players[0].deck) + CardLibrary.ids_of(x.players[0].discard)
	_check(not ids_left.has("flat_kill"), "flat_kill never redraws after the reshuffle")
	var x2 := MatchState.from_dict(x.to_dict(), layout)
	_check(x2.players[0].exhausted.size() == 1, "exhausted survives a snapshot")

	# steady: half the zone risk.
	var lc := MatchState.new(11, [_deck_of_only("line_chop", 14), _deck_of_only("block", 14)], layout)
	lc.start_point()
	var deep_edge := layout.find(1, 1, 0)
	var steady_land: float = lc.odds(0, 0, deep_edge)["land"]
	lc.players[0].hand[0].keyword = ""
	var plain_land: float = lc.odds(0, 0, deep_edge)["land"]
	_check(steady_land > plain_land, "line_chop at a deep edge: steady %.2f should beat plain %.2f" % [steady_land, plain_land])

	# reach: the incoming zone does not matter.
	var lu := MatchState.new(11, [_deck_of_only("lunge", 14), _deck_of_only("block", 14)], layout)
	lu.start_point()
	lu.incoming_type = BallType.FLAT
	var mid := layout.find(1, 0, 2)
	lu.incoming_zone = layout.find(-1, 1, 0)
	var reach_awkward: float = lu.odds(0, 0, mid)["land"]
	lu.incoming_zone = layout.find(-1, 0, 2)
	var reach_easy: float = lu.odds(0, 0, mid)["land"]
	_check(is_equal_approx(reach_awkward, reach_easy), "lunge odds %.2f from a deep edge equal %.2f from the middle" % [reach_awkward, reach_easy])
	lu.players[0].hand[0].keyword = ""
	lu.incoming_zone = layout.find(-1, 1, 0)
	var plain_awkward: float = lu.odds(0, 0, mid)["land"]
	_check(plain_awkward < reach_easy, "without reach the deep edge hurts: %.2f < %.2f" % [plain_awkward, reach_easy])

	# heavy: the reply is harder, then it is forgotten.
	var hv: MatchState = null
	var returned := false
	for seed_value in range(1, 60):
		hv = MatchState.new(seed_value, [_deck_of_only("loop", 14), _deck_of_only("flick", 14)], layout)
		hv.start_point()
		var e := _shot(hv, 0)
		if int(e["outcome"]) == RallyResolver.Outcome.RETURNED:
			returned = true
			break
	_check(returned, "found a seed where the loop comes back")
	if returned:
		_check(hv.incoming_heavy and hv.turn == 1, "a returned loop sets incoming_heavy for the reply")
		var reply_zone := layout.find(-1, 0, 2)
		var heavy_land: float = hv.odds(1, 0, reply_zone)["land"]
		hv.incoming_heavy = false
		var light_land: float = hv.odds(1, 0, reply_zone)["land"]
		hv.incoming_heavy = true
		_check(heavy_land < light_land, "heavy reply odds %.2f should be below %.2f" % [heavy_land, light_land])
		_shot(hv, 1, Vector2i(0, 2))
		_check(not hv.incoming_heavy, "incoming_heavy is cleared by the reply")
		hv.phase = MatchState.Phase.POINT_OVER
		hv.incoming_heavy = true
		hv.start_point()
		_check(not hv.incoming_heavy, "incoming_heavy is cleared at point start")
	print("keywords: rest, sap, exhaust, steady (%.2f > %.2f), reach, heavy ok" % [steady_land, plain_land])


# --- 6: points_to_win ----------------------------------------------------------------

func _test_points_to_win() -> void:
	var m := MatchState.new(99, [CardLibrary.from_ids(_pool_deck(99)), CardLibrary.starter_deck()], layout, 9)
	var log := _play(m, {}, false, {})
	var last: Dictionary = log.back()
	if not _check(last["type"] == "match_over", "a 9-point match ends with match_over"):
		return
	var score: Array = last["score"]
	_check(score.max() == 9 and score.min() < 9, "first to 9: %s" % [score])
	_check(int(last["longest_rally"]) == m.longest_rally and m.longest_rally > 0, "match_over carries longest_rally %d" % m.longest_rally)
	var shots := 0
	for row in log:
		if row.has("kind"):
			shots += 1
	var stats: Array = last["stats"]
	_check(stats.size() == 2 and int(stats[0]["shots"]) + int(stats[1]["shots"]) == shots, "match_over stats count every shot")
	var ends: int = int(stats[0]["winners"]) + int(stats[0]["faults"]) + int(stats[1]["winners"]) + int(stats[1]["faults"])
	_check(ends == m.points_played, "every point ends with a winner or a fault")
	print("points_to_win 9: %s, longest rally %d, stats %s" % [score, m.longest_rally, stats])


# --- 7: AI personalities ---------------------------------------------------------------

func _test_ai_personalities() -> void:
	var deck := _pool_deck(5)
	for id in OpponentLibrary.all_ids():
		var ai: Dictionary = OpponentLibrary.profile(id)["ai"]
		var s := _pool_match(5, deck, id, 7)
		s.start_point()
		for i in 5:
			if s.phase != MatchState.Phase.RALLY:
				s.start_point()
			s.apply(AIController.choose(s, s.turn, ai if s.turn == 1 else {}))
		if s.phase != MatchState.Phase.RALLY:
			s.start_point()
		var snap := s.to_dict()
		var a := MatchState.from_dict(snap, layout)
		var b := MatchState.from_dict(snap, layout)
		var pa := AIController.choose(a, a.turn, ai)
		var pb := AIController.choose(b, b.turn, ai)
		_check(pa == pb, "%s: choose() differs on identical states: %s vs %s" % [id, pa, pb])
		var c1 := MatchState.from_dict(snap, layout)
		var c2 := MatchState.from_dict(snap, layout)
		var c3 := MatchState.from_dict(snap, layout)
		var d1 := AIController.choose(c1, c1.turn)
		var d2 := AIController.choose(c2, c2.turn, {})
		var d3 := AIController.choose(c3, c3.turn, AIController.DEFAULTS)
		_check(d1 == d2 and d2 == d3, "%s: default params must be the same as none" % id)
	print("ai personalities: %d profiles deterministic" % OpponentLibrary.all_ids().size())
	_test_ai_tie_break()


## Equal values are broken by card index, then zone order, never by how the
## sort happened to arrange them: four identical cards on the serve, with the
## opponent in the middle lane so the mirror zones tie exactly.
func _test_ai_tie_break() -> void:
	var s := MatchState.new(8, [_deck_of_only("topspin", 14), _deck_of_only("block", 14)], layout)
	s.start_point()
	_check(s.turn == 0 and s.players[1].col == MatchState.HOME_COL, "tie break setup: serve against the middle lane")
	var opts := AIController._options(s, 0, AIController.DEFAULTS)
	_check(opts.size() == MatchState.HAND_SIZE * 10, "every card into every zone: %d options" % opts.size())
	var top: float = opts[0][0]
	var tied: Array = opts.filter(func(o: Array) -> bool: return o[0] == top)
	_check(tied.size() >= 2, "the top value should be tied (%d options)" % tied.size())
	var first_tied: Array = tied[0]
	for o in tied:
		if int(o[3]) < int(first_tied[3]):
			first_tied = o
	_check(int(opts[0][1]) == 0, "tie goes to the lowest card index, got %d" % int(opts[0][1]))
	_check(int(opts[0][3]) == int(first_tied[3]), "tie goes to the first inserted option (zone order)")
	var first_zone: Zone = first_tied[2]
	var pick := AIController.choose(s, 0, {"greed": 1.0})
	_check(int(pick["card"]) == 0 and int(pick["row"]) == first_zone.row and int(pick["col"]) == first_zone.col,
		"choose() with greed 1 takes card 0 into the first tied zone, got %s" % [pick])
	# The order the options come in must not matter: a reversed copy sorts
	# back to the same head (the whole `spread` window and more).
	var rev := opts.duplicate()
	rev.reverse()
	rev.sort_custom(AIController._better)
	_check(rev.slice(0, 8) == opts.slice(0, 8), "sorting the options in reverse order changes the top picks")
	_check(rev == opts, "sorting the options in reverse order changes the whole order")
	print("ai tie break: %d tied at %.3f, pick card 0 into %s" % [tied.size(), top, first_zone.label()])
