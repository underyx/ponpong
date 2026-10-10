## Proves the run rules are deterministic and the libraries are whole:
## two RunStates with the same seed, driven by the same decisions through
## real AI-vs-AI matches, must produce identical events and end states; a
## snapshot round trip mid-run must continue identically; the opponent draw
## and reward offers must obey their rules on 200 seeds; the card pool and
## the roster must resolve. Usage: godot --headless -s tests/run_determinism.gd
extends SceneTree

var failures := 0
var layout := ZoneLayout.new()


func _initialize() -> void:
	_case_determinism()
	_case_snapshot()
	_case_integrity()
	_case_offers()
	_case_library()
	print("run determinism: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(0 if failures == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL: %s" % what)


# --- 1. two runs, same seed, same decisions ---------------------------------

func _case_determinism() -> void:
	for seed_value in [5, 11, 2026]:
		var a := RunState.new(seed_value)
		var b := RunState.new(seed_value)
		var log_a := _drive(a, 0)
		var log_b := _drive(b, 0)
		var same := log_a == log_b
		print("seed %d: %d events, %d matches, phase %s, hearts %d, deck %d, identical=%s" % [
			seed_value, log_a.size(), a.history.size(), RunState.Phase.keys()[a.phase], a.hearts, a.deck.size(), same])
		_check(same, "seed %d: event logs differ" % seed_value)
		_check(a.deck == b.deck, "seed %d: final decks differ" % seed_value)
		_check(a.opponents == b.opponents, "seed %d: opponent sequences differ" % seed_value)
		_check(a.hearts == b.hearts, "seed %d: hearts differ" % seed_value)
		_check(a.phase == b.phase, "seed %d: phases differ" % seed_value)
		_check(a.to_dict() == b.to_dict(), "seed %d: to_dict() differs" % seed_value)
		_check(a.phase == RunState.Phase.WON or a.phase == RunState.Phase.LOST, "seed %d: run did not finish" % seed_value)


# --- 2. snapshot round trip after the second match --------------------------

func _case_snapshot() -> void:
	var c := RunState.new(77)
	var k := 0
	var played := 0
	var guard := 0
	while played < 2 and guard < 20:
		guard += 1
		if c.phase == RunState.Phase.MATCH:
			c.apply(_play_match(c))
			played += 1
		elif c.phase == RunState.Phase.REWARD or c.phase == RunState.Phase.REMOVE:
			c.apply(_decision(c, k))
			k += 1
		else:
			break
	var d := RunState.from_dict(c.to_dict())
	_check(d != null, "snapshot: from_dict(to_dict()) returned null")
	if d == null:
		return
	_check(d.to_dict() == c.to_dict(), "snapshot: to_dict() differs right after the round trip")
	var tail_c := _drive(c, k)
	var tail_d := _drive(d, k)
	print("snapshot round trip after 2 matches: %d remaining events, identical=%s" % [tail_c.size(), tail_c == tail_d])
	_check(tail_c == tail_d, "snapshot: tails differ")
	_check(c.to_dict() == d.to_dict(), "snapshot: final to_dict() differs")


# --- 3. opponent draw and config integrity ----------------------------------

func _case_integrity() -> void:
	var shadow_seen := false
	for seed_value in 200:
		var run := RunState.new(seed_value)
		_check_opponents(run, seed_value)
		if run.opponents[5] == OpponentLibrary.SHADOW:
			shadow_seen = true
			run.stage = 5
			var cfg := run.match_config()
			_check(cfg["opponent_deck"] == cfg["player_deck"], "seed %d: shadow deck is not the player's deck" % seed_value)
			_check(cfg["points_to_win"] == 9, "seed %d: boss is not first to 9" % seed_value)
			_check(cfg["opponent"]["boss"] == true, "seed %d: shadow profile is not a boss" % seed_value)
	_check(shadow_seen, "no seed in 0..199 drew your_shadow")
	var cfg := RunState.new(1).match_config()
	for key in ["seed", "stage", "stages", "hearts", "points_to_win", "opponent", "player_deck", "opponent_deck"]:
		_check(cfg.has(key), "match_config lacks %s" % key)
	_check(cfg["opponent_deck"] == OpponentLibrary.deck_ids(OpponentLibrary.OPENER), "stage 0 opponent deck is not the opener's")
	_check(cfg["points_to_win"] == 5, "stage 0 is not first to 5")
	print("integrity: 200 opponent draws checked")


func _check_opponents(run: RunState, seed_value: int) -> void:
	var o := run.opponents
	_check(o.size() == 6, "seed %d: %d opponents" % [seed_value, o.size()])
	if o.size() != 6:
		return
	_check(o[0] == OpponentLibrary.OPENER, "seed %d: stage 0 is %s" % [seed_value, o[0]])
	_check(OpponentLibrary.TIER_A.has(o[1]) and OpponentLibrary.TIER_A.has(o[2]) and o[1] != o[2],
		"seed %d: tier A draw %s" % [seed_value, [o[1], o[2]]])
	_check(OpponentLibrary.TIER_B.has(o[3]) and OpponentLibrary.TIER_B.has(o[4]) and o[3] != o[4],
		"seed %d: tier B draw %s" % [seed_value, [o[3], o[4]]])
	_check(OpponentLibrary.BOSSES.has(o[5]), "seed %d: boss %s" % [seed_value, o[5]])


# --- 4. offers and deck bounds over 200 synthetic runs -----------------------

## Match results here are synthetic (a test RNG decides who won), so the run
## layer alone is exercised on many seeds without playing 1400 matches.
func _case_offers() -> void:
	var offers := 0
	var rares := 0
	var finished := 0
	var test_rng := RandomNumberGenerator.new()
	for seed_value in 200:
		test_rng.seed = 9000 + seed_value
		var run := RunState.new(seed_value)
		var k := seed_value
		var guard := 0
		while run.phase != RunState.Phase.WON and run.phase != RunState.Phase.LOST and guard < 40:
			guard += 1
			_check(run.hearts >= 0, "seed %d: hearts below 0" % seed_value)
			_check(run.stage >= 0 and run.stage < RunState.STAGES, "seed %d: stage %d" % [seed_value, run.stage])
			_check(run.deck.size() >= RunState.DECK_MIN and run.deck.size() <= RunState.DECK_MAX,
				"seed %d: deck size %d" % [seed_value, run.deck.size()])
			var events: Array[Dictionary] = []
			if run.phase == RunState.Phase.MATCH:
				var stage_before := run.stage
				var won := test_rng.randf() < 0.7
				var score := [7, 3] if won else [4, 7]
				events = run.apply({"type": "match_result", "winner": 0 if won else 1, "score": score,
					"longest_rally": 1 + test_rng.randi_range(0, 9), "tired_plays": [1, 0]})
				_check(not events.is_empty(), "seed %d: match_result produced no events" % seed_value)
				for e in events:
					if e["type"] == "reward_offer":
						offers += 1
						rares += _check_offer(e["cards"], stage_before, seed_value)
						_check(e["cards"] == run.offer, "seed %d: reward_offer cards differ from run.offer" % seed_value)
						_check(bool(e["trim_available"]) == RunState.TRIM_AFTER_STAGES.has(stage_before),
							"seed %d: trim_available wrong after stage %d" % [seed_value, stage_before])
			else:
				var before := run.deck.size()
				var action := _decision(run, k)
				k += 1
				events = run.apply(action)
				_check(not events.is_empty(), "seed %d: %s produced no events" % [seed_value, action])
				if action["type"] == "pick_reward" and int(action["index"]) >= 0:
					_check(run.deck.size() == before + 1, "seed %d: pick did not add a card" % seed_value)
				if action["type"] == "remove_card":
					_check(run.deck.size() == before - 1, "seed %d: remove did not remove a card" % seed_value)
		_check(run.phase == RunState.Phase.WON or run.phase == RunState.Phase.LOST, "seed %d: run did not finish" % seed_value)
		_check(run.deck.size() >= RunState.DECK_MIN and run.deck.size() <= RunState.DECK_MAX,
			"seed %d: final deck size %d" % [seed_value, run.deck.size()])
		_check(run.hearts >= 0, "seed %d: final hearts %d" % [seed_value, run.hearts])
		_check(run.stage < RunState.STAGES, "seed %d: final stage %d" % [seed_value, run.stage])
		if run.phase == RunState.Phase.WON:
			finished += 1
			_check(run.stage == RunState.STAGES - 1 and run.stats["matches_won"] == RunState.STAGES,
				"seed %d: won without winning 6 stages" % seed_value)
		else:
			_check(run.hearts == 0 and run.stats["matches_lost"] == RunState.HEARTS, "seed %d: lost with hearts left" % seed_value)
	_check(offers > 0 and rares > 0, "no offers or no rares in 200 runs")
	print("offers: %d offers checked over 200 synthetic runs, %d rares, %d runs won" % [offers, rares, finished])
	_case_invalid_actions()


## Every id distinct, known, and of a rarity whose weight for this stage is
## positive. Returns the number of rares in the offer.
func _check_offer(cards: Array, stage_before: int, seed_value: int) -> int:
	var rares := 0
	_check(cards.size() == RunState.OFFER_SIZE, "seed %d: offer of %d" % [seed_value, cards.size()])
	var weights: Dictionary = RunState.WEIGHTS_EARLY if stage_before <= 1 else RunState.WEIGHTS_LATE
	for i in cards.size():
		var id: String = cards[i]
		_check(CardLibrary.ALL_IDS.has(id), "seed %d: offer has unknown id %s" % [seed_value, id])
		for j in cards.size():
			if j != i:
				_check(cards[j] != id, "seed %d: offer repeats %s" % [seed_value, id])
		var card := CardLibrary.by_id(id)
		if card == null:
			continue
		_check(CardLibrary.pool(card.rarity).has(id), "seed %d: %s is not in pool(%d)" % [seed_value, id, card.rarity])
		_check(int(weights.get(card.rarity, 0)) > 0, "seed %d: rarity %d has weight 0 after stage %d" % [seed_value, card.rarity, stage_before])
		if card.rarity == Card.Rarity.RARE:
			rares += 1
	return rares


## Out-of-phase and out-of-range actions must change nothing and return [].
## Each one pushes a warning by design, so this block is noisy on purpose.
func _case_invalid_actions() -> void:
	print("invalid actions: the warnings that follow are expected")
	var run := RunState.new(3)
	var before := run.to_dict()
	for action in [{"type": "pick_reward", "index": 0}, {"type": "trim_instead"}, {"type": "remove_card", "index": 0},
			{"type": "skip_remove"}, {"type": "nonsense"}, {}, {"type": "match_result", "winner": 2, "score": [0, 0]}]:
		var events := run.apply(action)
		_check(events.is_empty(), "invalid action %s returned events" % [action])
	_check(run.to_dict() == before, "invalid actions changed the run")
	run.apply({"type": "match_result", "winner": 0, "score": [5, 2], "longest_rally": 4, "tired_plays": [0, 1]})
	_check(run.phase == RunState.Phase.REWARD, "a win did not open the reward phase")
	_check(run.apply({"type": "pick_reward", "index": 3}).is_empty(), "pick_reward past the offer returned events")
	_check(run.apply({"type": "pick_reward", "index": -2}).is_empty(), "pick_reward below -1 returned events")
	_check(run.apply({"type": "trim_instead"}).is_empty(), "trim_instead was allowed after stage 0")
	_check(run.apply({"type": "match_result", "winner": 0, "score": [5, 2]}).is_empty(), "match_result during reward returned events")
	# Regroup: the deck never drops below DECK_MIN.
	var loser := RunState.new(4)
	loser.deck.resize(RunState.DECK_MIN)
	loser.apply({"type": "match_result", "winner": 1, "score": [2, 5], "longest_rally": 2, "tired_plays": [0, 0]})
	_check(loser.phase == RunState.Phase.REMOVE and loser.remove_reason == "regroup", "a loss did not open regroup")
	_check(loser.hearts == RunState.HEARTS - 1, "a loss did not cost a heart")
	_check(loser.apply({"type": "remove_card", "index": 0}).is_empty(), "remove_card at DECK_MIN returned events")
	var tail := loser.apply({"type": "skip_remove"})
	_check(tail.size() == 1 and tail[0]["type"] == "rematch" and tail[0]["stage"] == 0, "skip_remove after regroup is not a rematch")
	_check(loser.phase == RunState.Phase.MATCH and loser.remove_reason == "", "regroup did not return to the match phase")
	# A full deck turns a pick into a skip.
	var full := RunState.new(6)
	while full.deck.size() < RunState.DECK_MAX:
		full.deck.append("block")
	full.apply({"type": "match_result", "winner": 0, "score": [5, 0], "longest_rally": 1, "tired_plays": [0, 0]})
	var picked := full.apply({"type": "pick_reward", "index": 0})
	_check(full.deck.size() == RunState.DECK_MAX and picked.size() == 1 and picked[0]["type"] == "next_match",
		"a pick with a full deck did not become a skip")


# --- 5. library integrity ---------------------------------------------------

func _case_library() -> void:
	var ids := CardLibrary.ALL_IDS
	_check(ids.size() == 25, "ALL_IDS has %d ids" % ids.size())
	var seen: Dictionary = {}
	var pooled := 0
	for id in ids:
		_check(not seen.has(id), "duplicate id %s" % id)
		seen[id] = true
		var card := CardLibrary.by_id(id)
		_check(card != null and card.id == id, "by_id(%s) does not round-trip" % id)
		if card == null:
			continue
		_check(card.cost >= 0 and card.cost <= 3, "%s cost %d" % [id, card.cost])
		_check(card.rarity >= 0 and card.rarity <= 2, "%s rarity %d" % [id, card.rarity])
		_check(Card.KEYWORDS.has(card.keyword), "%s keyword '%s'" % [id, card.keyword])
	for rarity in 3:
		var pool := CardLibrary.pool(rarity)
		pooled += pool.size()
		for id in pool:
			_check(ids.has(id), "pool(%d) has unknown id %s" % [rarity, id])
			var card := CardLibrary.by_id(id)
			_check(card != null and card.rarity == rarity, "pool(%d) has %s" % [rarity, id])
		for other in 3:
			if other != rarity:
				for id in pool:
					_check(not CardLibrary.pool(other).has(id), "%s is in pool(%d) and pool(%d)" % [id, rarity, other])
	_check(pooled == ids.size(), "pools cover %d of %d ids" % [pooled, ids.size()])
	_check(CardLibrary.ids_of(CardLibrary.starter_deck()).size() == 14, "starter deck is not 14 cards")

	var all := OpponentLibrary.all_ids()
	_check(all.size() == 9, "%d opponents" % all.size())
	for id in all:
		var p := OpponentLibrary.profile(id)
		for key in ["id", "name", "blurb", "deck", "ai", "paddle_color", "boss"]:
			_check(p.has(key), "profile(%s) lacks %s" % [id, key])
		_check(p.get("id", "") == id, "profile(%s).id is %s" % [id, p.get("id", "")])
		for key in AIController.DEFAULTS:
			_check(p["ai"].has(key), "profile(%s).ai lacks %s" % [id, key])
		var deck := OpponentLibrary.deck_ids(id)
		for card_id in deck:
			_check(ids.has(card_id), "%s plays unknown card %s" % [id, card_id])
		var expected := 14
		if id == OpponentLibrary.SHADOW:
			expected = 0
		elif id == "ilse_varga":
			expected = 16
		_check(deck.size() == expected, "%s has %d cards, expected %d" % [id, deck.size(), expected])
		_check(bool(p["boss"]) == OpponentLibrary.BOSSES.has(id), "%s boss flag" % id)

	var good := RunState.new(12).to_dict()
	_check(RunState.from_dict({}) == null, "from_dict({}) is not null")
	var wrong_version := good.duplicate(true)
	wrong_version["version"] = 0
	_check(RunState.from_dict(wrong_version) == null, "from_dict with version 0 is not null")
	var bad_card := good.duplicate(true)
	bad_card["deck"][0] = "not_a_card"
	_check(RunState.from_dict(bad_card) == null, "from_dict with an unknown card id is not null")
	var bad_opponent := good.duplicate(true)
	bad_opponent["opponents"][2] = "nobody"
	_check(RunState.from_dict(bad_opponent) == null, "from_dict with an unknown opponent id is not null")
	var missing := good.duplicate(true)
	missing.erase("hearts")
	_check(RunState.from_dict(missing) == null, "from_dict with a missing key is not null")
	var bad_phase := good.duplicate(true)
	bad_phase["phase"] = 9
	_check(RunState.from_dict(bad_phase) == null, "from_dict with a bad phase is not null")
	_case_phase_consistency(good)
	var bad_state := good.duplicate(true)
	bad_state["rng_state"] = "not a number"
	_check(RunState.from_dict(bad_state) == null, "from_dict with a bad rng_state is not null")
	var int_state := good.duplicate(true)
	int_state["rng_state"] = _state_as_int(good)
	var from_int := RunState.from_dict(int_state)
	_check(from_int != null and from_int.rng.state == RunState.from_dict(good).rng.state, "from_dict does not accept an int rng_state")
	# An older save wrote the seed as a plain int; it still loads.
	var int_seed := good.duplicate(true)
	int_seed["seed"] = 12
	var from_int_seed := RunState.from_dict(int_seed)
	_check(from_int_seed != null and from_int_seed.seed_value == 12 and from_int_seed.to_dict() == good,
		"from_dict does not accept an int seed")
	var bad_seed := good.duplicate(true)
	bad_seed["seed"] = "twelve"
	_check(RunState.from_dict(bad_seed) == null, "from_dict with a bad seed string is not null")
	# Seeds past 53 bits survive JSON only because they travel as strings.
	for big_seed in [-9223372036854775000, 4611686018427400249]:
		var big := RunState.new(big_seed)
		var big_dict := big.to_dict()
		var parsed = JSON.parse_string(JSON.stringify(big_dict))
		var back: RunState = RunState.from_dict(parsed) if parsed is Dictionary else null
		_check(back != null and back.seed_value == big_seed, "seed %d does not survive a JSON round trip" % big_seed)
		_check(back != null and back.to_dict() == big_dict, "seed %d: to_dict() differs after a JSON round trip" % big_seed)
		_check(back != null and back.opponents == big.opponents, "seed %d: opponents differ after a JSON round trip" % big_seed)
	var restored := RunState.from_dict(good)
	_check(restored != null and restored.to_dict() == good, "from_dict(to_dict()) of a fresh run differs")
	var json_dict = JSON.parse_string(JSON.stringify(good))
	_check(json_dict is Dictionary and RunState.from_dict(json_dict) != null, "from_dict after a JSON round trip is null")
	if json_dict is Dictionary and RunState.from_dict(json_dict) != null:
		var via_json := RunState.from_dict(json_dict)
		_check(via_json.to_dict() == good, "from_dict after a JSON round trip does not reproduce to_dict()")
		_check(via_json.rng.state == restored.rng.state, "from_dict after a JSON round trip lost the RNG state")
	print("library: %d cards, %d opponents checked" % [ids.size(), all.size()])


func _state_as_int(d: Dictionary) -> int:
	return String(d["rng_state"]).to_int()


## A phase that does not fit the rest of the dict is a tampered save, not a
## run to resume: from_dict returns null instead of handing apply() a state
## it can crash on (a reward after the boss would advance to stage 6).
func _case_phase_consistency(good: Dictionary) -> void:
	var offer := ["smash", "chop", "lob"]
	var reward_at_boss := good.duplicate(true)
	reward_at_boss["stage"] = RunState.STAGES - 1
	reward_at_boss["phase"] = RunState.Phase.REWARD
	reward_at_boss["offer"] = offer
	_check(RunState.from_dict(reward_at_boss) == null, "from_dict accepted a reward after the boss")
	var empty_offer := good.duplicate(true)
	empty_offer["phase"] = RunState.Phase.REWARD
	_check(RunState.from_dict(empty_offer) == null, "from_dict accepted a reward with no offer")
	var remove_no_reason := good.duplicate(true)
	remove_no_reason["phase"] = RunState.Phase.REMOVE
	_check(RunState.from_dict(remove_no_reason) == null, "from_dict accepted a remove phase with no reason")
	var match_with_offer := good.duplicate(true)
	match_with_offer["offer"] = offer
	_check(RunState.from_dict(match_with_offer) == null, "from_dict accepted a match phase with an offer")
	var match_with_reason := good.duplicate(true)
	match_with_reason["remove_reason"] = "trim"
	_check(RunState.from_dict(match_with_reason) == null, "from_dict accepted a match phase with a remove reason")
	var lost_with_hearts := good.duplicate(true)
	lost_with_hearts["phase"] = RunState.Phase.LOST
	_check(RunState.from_dict(lost_with_hearts) == null, "from_dict accepted a lost run with hearts left")
	var won_early := good.duplicate(true)
	won_early["phase"] = RunState.Phase.WON
	_check(RunState.from_dict(won_early) == null, "from_dict accepted a won run before the boss")
	# The consistent versions of the same phases still load.
	var reward_ok := good.duplicate(true)
	reward_ok["stage"] = 2
	reward_ok["phase"] = RunState.Phase.REWARD
	reward_ok["offer"] = offer
	_check(RunState.from_dict(reward_ok) != null, "from_dict rejected a consistent reward phase")
	var remove_ok := good.duplicate(true)
	remove_ok["phase"] = RunState.Phase.REMOVE
	remove_ok["remove_reason"] = "regroup"
	remove_ok["hearts"] = 1
	_check(RunState.from_dict(remove_ok) != null, "from_dict rejected a consistent remove phase")
	var lost_ok := good.duplicate(true)
	lost_ok["phase"] = RunState.Phase.LOST
	lost_ok["hearts"] = 0
	_check(RunState.from_dict(lost_ok) != null, "from_dict rejected a consistent lost run")
	var won_ok := good.duplicate(true)
	won_ok["phase"] = RunState.Phase.WON
	won_ok["stage"] = RunState.STAGES - 1
	_check(RunState.from_dict(won_ok) != null, "from_dict rejected a consistent won run")
	# And _advance() itself refuses to step past the last stage.
	var last := RunState.from_dict(reward_ok)
	last.stage = RunState.STAGES - 1
	print("phase consistency: the warning that follows is expected")
	_check(last.apply({"type": "pick_reward", "index": -1}).is_empty() and last.stage == RunState.STAGES - 1,
		"_advance() stepped past the last stage")
	print("phase consistency: 7 tampered saves rejected, 4 consistent ones loaded")


# --- driving a run ------------------------------------------------------------

## Play `run` to the end with real matches, logging every run event and a
## flattened copy of every match event. `k` numbers the decisions.
func _drive(run: RunState, k: int) -> Array:
	var log: Array = []
	var guard := 0
	while run.phase != RunState.Phase.WON and run.phase != RunState.Phase.LOST and guard < 40:
		guard += 1
		_check(run.hearts >= 0, "hearts below 0")
		_check(run.stage < RunState.STAGES, "stage past the last")
		if run.phase == RunState.Phase.MATCH:
			var match_log: Array = []
			var result := _play_match(run, match_log)
			log.append_array(match_log)
			log.append(result.duplicate(true))
			log.append_array(_flatten(run.apply(result)))
		else:
			var action := _decision(run, k)
			k += 1
			log.append(action.duplicate(true))
			log.append_array(_flatten(run.apply(action)))
	return log


## On REWARD: pick (k % 4) - 1, or trim when available and k % 3 == 0.
## On REMOVE: alternate remove_card(0) and skip_remove.
func _decision(run: RunState, k: int) -> Dictionary:
	if run.phase == RunState.Phase.REWARD:
		if run.trim_available and k % 3 == 0:
			return {"type": "trim_instead"}
		return {"type": "pick_reward", "index": (k % 4) - 1}
	if k % 2 == 0:
		return {"type": "remove_card", "index": 0}
	return {"type": "skip_remove"}


## One AI-vs-AI match from the run's current config. Returns the
## match_result action; appends flattened match events to `match_log`.
func _play_match(run: RunState, match_log: Array = []) -> Dictionary:
	var cfg := run.match_config()
	var decks := [CardLibrary.from_ids(cfg["player_deck"]), CardLibrary.from_ids(cfg["opponent_deck"])]
	var m := MatchState.new(int(cfg["seed"]), decks, layout, int(cfg["points_to_win"]))
	var ai: Dictionary = cfg["opponent"]["ai"]
	var over: Dictionary = {}
	match_log.append_array(_flatten(m.start_point()))
	var guard := 0
	while m.phase != MatchState.Phase.MATCH_OVER and guard < 2000:
		guard += 1
		if m.phase == MatchState.Phase.POINT_OVER:
			match_log.append_array(_flatten(m.start_point()))
			continue
		var action := AIController.choose(m, m.turn) if m.turn == 0 else AIController.choose(m, m.turn, ai)
		match_log.append(action)
		var events := m.apply(action)
		match_log.append_array(_flatten(events))
		for e in events:
			if e["type"] == "match_over":
				over = e
	_check(not over.is_empty(), "match did not end")
	var winner := int(over.get("winner", 0 if m.players[0].score > m.players[1].score else 1))
	var score: Array = over.get("score", [m.players[0].score, m.players[1].score])
	var longest := int(over.get("longest_rally", m.get("longest_rally") if m.get("longest_rally") != null else 0))
	var tired: Array = [0, 0]
	if over.has("stats"):
		for i in 2:
			tired[i] = int(over["stats"][i].get("tired_plays", 0))
	else:
		for i in 2:
			var p_stats = m.players[i].get("stats")
			if p_stats is Dictionary:
				tired[i] = int(p_stats.get("tired_plays", 0))
	return {"type": "match_result", "winner": winner, "score": [int(score[0]), int(score[1])],
		"longest_rally": longest, "tired_plays": tired}


## Events as plain, comparable values: Cards become ids, Zones become dicts.
func _flatten(events: Array[Dictionary]) -> Array:
	var out: Array = []
	for e in events:
		out.append(_plain(e))
	return out


func _plain(v: Variant) -> Variant:
	if v is Card:
		return (v as Card).id
	if v is Zone:
		return (v as Zone).to_dict()
	if v is Dictionary:
		var d := {}
		for key in v:
			d[key] = _plain(v[key])
		return d
	if v is Array:
		var a := []
		for item in v:
			a.append(_plain(item))
		return a
	if v is Object:
		return str(v)
	return v
