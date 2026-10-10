## The rules of one run: six opponents, hearts, rewards and trims, with no
## nodes in it. Like MatchState it is seeded, driven by plain-dictionary
## actions through apply(), answers with events, and snapshots through
## to_dict() / from_dict(), so two copies fed the same seed and actions agree
## and a run can be saved between matches or sent to another peer.
##
## The whole opponent sequence is drawn at _init, so it is fixed the moment
## the seed is. Match seeds are rolled from the run RNG as they are needed.
## Only ids live here: card ids, opponent ids, never Card or Zone objects.
class_name RunState
extends RefCounted

enum Phase { MATCH, REWARD, REMOVE, WON, LOST }

const VERSION := 1
const STAGES := 6
const HEARTS := 2
const DECK_MIN := 10
const DECK_MAX := 20
const OFFER_SIZE := 3
const POINTS_TO_WIN := [5, 7, 7, 7, 7, 9]
const TRIM_AFTER_STAGES := [1, 3]
## Reward rarity weights (common / uncommon / rare) after stages 0-1 ...
const WEIGHTS_EARLY := {0: 60, 1: 30, 2: 10}
## ... and after stages 2-4.
const WEIGHTS_LATE := {0: 45, 1: 35, 2: 20}

var seed_value: int
var rng := RandomNumberGenerator.new()
## Card ids, the canonical deck.
var deck: Array[String] = []
## Six opponent ids in stage order, fixed at _init.
var opponents: Array[String] = []
## 0..STAGES - 1.
var stage := 0
var hearts := HEARTS
var phase := Phase.MATCH
## Seed of the pending or current match.
var match_seed := 0
## Three card ids while phase == REWARD.
var offer: Array[String] = []
## Whether "remove a card instead" is on the table, while phase == REWARD.
var trim_available := false
## "regroup" or "trim" while phase == REMOVE.
var remove_reason := ""
## One {"stage", "opponent", "won", "score"} per match played.
var history: Array[Dictionary] = []
var stats := {"matches_won": 0, "matches_lost": 0, "points_won": 0, "points_lost": 0,
	"cards_added": 0, "cards_removed": 0, "longest_rally": 0, "tired_plays": 0}


func _init(p_seed: int) -> void:
	seed_value = p_seed
	rng.seed = p_seed
	deck.assign(CardLibrary.ids_of(CardLibrary.starter_deck()))
	opponents.append(OpponentLibrary.OPENER)
	opponents.append_array(_pick(OpponentLibrary.TIER_A, 2))
	opponents.append_array(_pick(OpponentLibrary.TIER_B, 2))
	opponents.append_array(_pick(OpponentLibrary.BOSSES, 1))
	match_seed = rng.randi()


## `n` distinct ids from `pool`, in an order the run RNG decides.
func _pick(pool: Array, n: int) -> Array[String]:
	var a := pool.duplicate()
	MatchState.shuffle(a, rng)
	var out: Array[String] = []
	out.assign(a.slice(0, n))
	return out


func opponent_id() -> String:
	return opponents[stage]


func opponent() -> Dictionary:
	return OpponentLibrary.profile(opponent_id())


func points_to_win() -> int:
	return int(POINTS_TO_WIN[stage])


## Everything a match needs, as ids and plain values, so it can cross a wire.
## Your Shadow plays a copy of the player's deck.
func match_config() -> Dictionary:
	var id := opponent_id()
	var opponent_deck: Array[String] = []
	if id == OpponentLibrary.SHADOW:
		opponent_deck = deck.duplicate()
	else:
		opponent_deck = OpponentLibrary.deck_ids(id)
	return {
		"seed": match_seed,
		"stage": stage,
		"stages": STAGES,
		"hearts": hearts,
		"points_to_win": points_to_win(),
		"opponent": opponent(),
		"player_deck": deck.duplicate(),
		"opponent_deck": opponent_deck,
	}


## Actions are plain dictionaries:
##   {"type": "match_result", "winner": 0|1, "score": [a, b], "longest_rally": n, "tired_plays": [t0, t1]}
##   {"type": "pick_reward", "index": i}   (i = -1 is Skip)
##   {"type": "trim_instead"}
##   {"type": "remove_card", "index": i}
##   {"type": "skip_remove"}
## Returns the events that happened, in order. Invalid actions push a
## warning and return nothing, like MatchState.apply().
func apply(action: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var type := String(action.get("type", ""))
	match type:
		"match_result":
			return _apply_match_result(action)
		"pick_reward":
			return _apply_pick_reward(action)
		"trim_instead":
			if phase != Phase.REWARD or not trim_available:
				push_warning("RunState.apply: trim_instead is not available now")
				return events
			offer = []
			trim_available = false
			remove_reason = "trim"
			phase = Phase.REMOVE
			events.append({"type": "remove_offer", "reason": remove_reason})
		"remove_card":
			return _apply_remove_card(action)
		"skip_remove":
			if phase != Phase.REMOVE:
				push_warning("RunState.apply: skip_remove outside the remove phase")
				return events
			return _after_remove()
		_:
			push_warning("RunState.apply: unknown action type '%s'" % type)
	return events


func _apply_match_result(action: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if phase != Phase.MATCH:
		push_warning("RunState.apply: match_result outside the match phase")
		return events
	var winner := int(action.get("winner", -1))
	if winner != 0 and winner != 1:
		push_warning("RunState.apply: bad winner %d" % winner)
		return events
	var score: Array = action.get("score", [0, 0])
	if score.size() != 2:
		push_warning("RunState.apply: bad score %s" % [score])
		return events
	var tired: Array = action.get("tired_plays", [0, 0])
	var my_tired := int(tired[0]) if tired.size() > 0 else 0
	history.append({"stage": stage, "opponent": opponent_id(), "won": winner == 0,
		"score": [int(score[0]), int(score[1])]})
	stats["points_won"] += int(score[0])
	stats["points_lost"] += int(score[1])
	stats["longest_rally"] = maxi(int(stats["longest_rally"]), int(action.get("longest_rally", 0)))
	stats["tired_plays"] += my_tired
	if winner == 0:
		stats["matches_won"] += 1
		events.append({"type": "match_won", "stage": stage})
		if stage == STAGES - 1:
			phase = Phase.WON
			events.append({"type": "run_over", "won": true})
		else:
			offer = _roll_offer()
			trim_available = TRIM_AFTER_STAGES.has(stage)
			phase = Phase.REWARD
			events.append({"type": "reward_offer", "cards": offer.duplicate(), "trim_available": trim_available})
	else:
		hearts -= 1
		stats["matches_lost"] += 1
		events.append({"type": "heart_lost", "hearts": hearts})
		if hearts == 0:
			phase = Phase.LOST
			events.append({"type": "run_over", "won": false})
		else:
			remove_reason = "regroup"
			match_seed = rng.randi()
			phase = Phase.REMOVE
			events.append({"type": "remove_offer", "reason": remove_reason})
	return events


func _apply_pick_reward(action: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if phase != Phase.REWARD:
		push_warning("RunState.apply: pick_reward outside the reward phase")
		return events
	var index := int(action.get("index", -1))
	if index < -1 or index >= offer.size():
		push_warning("RunState.apply: bad reward index %d" % index)
		return events
	if index >= 0:
		if deck.size() < DECK_MAX:
			var id := offer[index]
			deck.append(id)
			stats["cards_added"] += 1
			events.append({"type": "card_added", "id": id})
		else:
			push_warning("RunState.apply: deck is full (%d), the pick becomes a skip" % deck.size())
	events.append_array(_advance())
	return events


func _apply_remove_card(action: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if phase != Phase.REMOVE:
		push_warning("RunState.apply: remove_card outside the remove phase")
		return events
	if deck.size() <= DECK_MIN:
		push_warning("RunState.apply: the deck is already at its minimum of %d" % DECK_MIN)
		return events
	var index := int(action.get("index", -1))
	if index < 0 or index >= deck.size():
		push_warning("RunState.apply: bad deck index %d" % index)
		return events
	var id := deck[index]
	deck.remove_at(index)
	stats["cards_removed"] += 1
	events.append({"type": "card_removed", "id": id})
	events.append_array(_after_remove())
	return events


## Move on to the next stage with a fresh match seed.
func _advance() -> Array[Dictionary]:
	if stage >= STAGES - 1:
		push_warning("RunState._advance: no stage after %d" % stage)
		return []
	stage += 1
	match_seed = rng.randi()
	offer = []
	trim_available = false
	remove_reason = ""
	phase = Phase.MATCH
	return [{"type": "next_match", "stage": stage, "opponent": opponent_id(), "seed": match_seed}]


## After a trim the run advances; after a regroup the same opponent is
## replayed with the seed rolled on the loss.
func _after_remove() -> Array[Dictionary]:
	var reason := remove_reason
	remove_reason = ""
	if reason == "trim":
		return _advance()
	phase = Phase.MATCH
	return [{"type": "rematch", "stage": stage, "opponent": opponent_id(), "seed": match_seed}]


## Three distinct card ids: a rarity by weighted roll for this stage, then a
## card from that rarity's pool that is not already on offer.
func _roll_offer() -> Array[String]:
	var weights: Dictionary = WEIGHTS_EARLY if stage <= 1 else WEIGHTS_LATE
	var out: Array[String] = []
	for n in OFFER_SIZE:
		var rarity := _roll_rarity(weights)
		var candidates: Array[String] = []
		for id in CardLibrary.pool(rarity):
			if not out.has(id):
				candidates.append(id)
		if candidates.is_empty():
			for id in CardLibrary.ALL_IDS:
				if not out.has(id):
					candidates.append(id)
		out.append(candidates[rng.randi_range(0, candidates.size() - 1)])
	return out


func _roll_rarity(weights: Dictionary) -> int:
	var total := 0.0
	for rarity in weights:
		total += float(weights[rarity])
	var r := rng.randf() * total
	var last := 0
	for rarity in weights:
		last = int(rarity)
		r -= float(weights[rarity])
		if r < 0.0:
			return last
	return last


## Snapshot for saving between matches, or for another peer. The seed and the
## RNG state travel as decimal strings: JSON parses numbers as doubles, which
## lose the low bits of a 64-bit value, and a resumed run must roll the same
## offers and match seeds as an uninterrupted one.
func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"seed": str(seed_value),
		"rng_state": str(rng.state),
		"deck": deck.duplicate(),
		"opponents": opponents.duplicate(),
		"stage": stage,
		"hearts": hearts,
		"phase": phase,
		"match_seed": match_seed,
		"offer": offer.duplicate(),
		"trim_available": trim_available,
		"remove_reason": remove_reason,
		"history": history.duplicate(true),
		"stats": stats.duplicate(),
	}


## Rebuild a run from to_dict() output, possibly after a JSON round trip.
## Returns null on any missing key, wrong VERSION, bad value, unknown card or
## opponent id, or a phase that does not fit the stage, hearts, offer and
## remove reason, so a stale or edited save is simply not resumed. The seed
## and rng_state may be ints (older saves) or the decimal strings to_dict()
## writes.
static func from_dict(d: Dictionary) -> RunState:
	for key in ["version", "seed", "rng_state", "deck", "opponents", "stage", "hearts", "phase",
			"match_seed", "offer", "trim_available", "remove_reason", "history", "stats"]:
		if not d.has(key):
			return null
	if not _is_number(d["version"]) or int(d["version"]) != VERSION:
		return null
	for key in ["stage", "hearts", "phase", "match_seed"]:
		if not _is_number(d[key]):
			return null
	if not _is_integer_value(d["seed"]) or not _is_integer_value(d["rng_state"]):
		return null
	if typeof(d["trim_available"]) != TYPE_BOOL or typeof(d["remove_reason"]) != TYPE_STRING:
		return null
	if typeof(d["stats"]) != TYPE_DICTIONARY or typeof(d["history"]) != TYPE_ARRAY:
		return null
	if not _is_string_list(d["deck"]) or not _is_string_list(d["opponents"]) or not _is_string_list(d["offer"]):
		return null
	var deck_ids: Array[String] = []
	deck_ids.assign(d["deck"])
	var opponent_ids: Array[String] = []
	opponent_ids.assign(d["opponents"])
	var offer_ids: Array[String] = []
	offer_ids.assign(d["offer"])
	for id in deck_ids + offer_ids:
		if not CardLibrary.ALL_IDS.has(id):
			return null
	var known := OpponentLibrary.all_ids()
	for id in opponent_ids:
		if not known.has(id):
			return null
	var stage_value := int(d["stage"])
	var hearts_value := int(d["hearts"])
	var phase_value := int(d["phase"])
	if opponent_ids.size() != STAGES or stage_value < 0 or stage_value >= STAGES:
		return null
	if hearts_value < 0 or hearts_value > HEARTS or phase_value < Phase.MATCH or phase_value > Phase.LOST:
		return null
	if deck_ids.size() < DECK_MIN or deck_ids.size() > DECK_MAX or offer_ids.size() > OFFER_SIZE:
		return null
	var reason := String(d["remove_reason"])
	if not ["", "regroup", "trim"].has(reason):
		return null
	match phase_value:
		Phase.MATCH:
			if not offer_ids.is_empty() or reason != "":
				return null
		Phase.REWARD:
			if stage_value == STAGES - 1 or offer_ids.size() != OFFER_SIZE:
				return null
		Phase.REMOVE:
			if reason == "":
				return null
		Phase.WON:
			if stage_value != STAGES - 1:
				return null
		Phase.LOST:
			if hearts_value != 0:
				return null
	var stats_in: Dictionary = d["stats"]
	var s := RunState.new(_as_int(d["seed"]))
	for key in s.stats:
		if not stats_in.has(key) or not _is_number(stats_in[key]):
			return null
		s.stats[key] = int(stats_in[key])
	for entry in d["history"]:
		if typeof(entry) != TYPE_DICTIONARY:
			return null
		var e: Dictionary = entry
		if not e.has("stage") or not e.has("opponent") or not e.has("won") or not e.has("score"):
			return null
		if not _is_number(e["stage"]) or typeof(e["opponent"]) != TYPE_STRING or typeof(e["won"]) != TYPE_BOOL:
			return null
		if typeof(e["score"]) != TYPE_ARRAY or e["score"].size() != 2:
			return null
		if not _is_number(e["score"][0]) or not _is_number(e["score"][1]) or not known.has(e["opponent"]):
			return null
		s.history.append({"stage": int(e["stage"]), "opponent": String(e["opponent"]), "won": bool(e["won"]),
			"score": [int(e["score"][0]), int(e["score"][1])]})
	s.rng.state = _as_int(d["rng_state"])
	s.deck = deck_ids
	s.opponents = opponent_ids
	s.stage = stage_value
	s.hearts = hearts_value
	s.phase = phase_value as Phase
	s.match_seed = int(d["match_seed"])
	s.offer = offer_ids
	s.trim_available = bool(d["trim_available"])
	s.remove_reason = reason
	return s


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


## An int, a float or a decimal string such as to_dict() writes.
static func _is_integer_value(v: Variant) -> bool:
	if _is_number(v):
		return true
	return typeof(v) == TYPE_STRING and String(v).is_valid_int()


## The value of something _is_integer_value() accepted, with all 64 bits when
## it came as a string.
static func _as_int(v: Variant) -> int:
	return int(v) if _is_number(v) else String(v).to_int()


static func _is_string_list(v: Variant) -> bool:
	if typeof(v) != TYPE_ARRAY:
		return false
	for item in v:
		if typeof(item) != TYPE_STRING:
			return false
	return true
