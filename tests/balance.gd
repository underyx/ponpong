## Balance report: the starter deck against every opponent, AI on both seats,
## plus a per-card table over every shot played. Prints numbers for the tuning
## pass and asserts only loose bounds, so it stays green while numbers move.
## Usage: godot --headless -s tests/balance.gd -- --runs 40   (default 40)
extends SceneTree

const DEFAULT_RUNS := 40
## A match this long is a stalemate, not a game.
const MAX_SHOTS := 500
const MIN_WIN_RATE := 0.20
const MAX_WIN_RATE := 0.85
const MIN_BEST_LAND := 0.45
## Where the tuning pass wants each starter win rate to land (report only).
const TARGETS := {
	"coach_pim": "0.65-0.85", "mara_vale": "0.45-0.65", "jax_dunn": "0.45-0.65", "dot_and_dash": "0.45-0.65",
	"oona_sato": "0.35-0.55", "big_rig": "0.35-0.55", "kit_marlow": "0.35-0.55",
	"ilse_varga": "0.25-0.45", "your_shadow": "0.40-0.55",
}
const INCOMING_TYPES := [BallType.NONE, BallType.FLAT, BallType.HIGH, BallType.SPIN, BallType.FAST]

var layout := ZoneLayout.new()
var failures := 0
## card id -> {played, tired, landed, winner, point_won}
var card_stats: Dictionary = {}


func _initialize() -> void:
	var runs := _parse_runs()
	for id in CardLibrary.ALL_IDS:
		card_stats[id] = {"played": 0, "tired": 0, "landed": 0, "winner": 0, "point_won": 0}
	print("balance: %d matches per opponent, starter deck on seat 0 with default AI params" % runs)
	print("")
	print("%-13s %3s %5s %11s %6s %6s %11s %11s  %s" % [
		"opponent", "to", "win", "pts for/ag", "rally", "shots", "tired y/t", "stam y/t", "target"])
	var opponents := OpponentLibrary.all_ids()
	for i in opponents.size():
		var id: String = opponents[i]
		var r := _run_opponent(id, i, runs)
		print("%-13s %3d %5.2f %5.1f/%-5.1f %6.2f %6.1f %5.2f/%-5.2f %5.2f/%-5.2f  %s" % [
			id, r["points_to_win"], r["win_rate"], r["points_for"], r["points_against"], r["rally"],
			r["shots"], r["tired"][0], r["tired"][1], r["stamina"][0], r["stamina"][1], TARGETS.get(id, "")])
		_check(r["win_rate"] >= MIN_WIN_RATE and r["win_rate"] <= MAX_WIN_RATE,
			"%s: starter win rate %.2f outside [%.2f, %.2f]" % [id, r["win_rate"], MIN_WIN_RATE, MAX_WIN_RATE])
		_check(r["max_shots"] <= MAX_SHOTS, "%s: a match ran to %d shots" % [id, r["max_shots"]])
	print("")
	print("%-14s %6s %7s %7s %7s %7s %9s" % ["card", "played", "tired%", "landed%", "winner%", "ptwon%", "bestland"])
	for id in CardLibrary.ALL_IDS:
		var s: Dictionary = card_stats[id]
		var n := maxi(1, int(s["played"]))
		var best := _best_case_land(id)
		print("%-14s %6d %7.2f %7.2f %7.2f %7.2f %9.2f" % [
			id, s["played"], float(s["tired"]) / n, float(s["landed"]) / n, float(s["winner"]) / n,
			float(s["point_won"]) / n, best])
		_check(best >= MIN_BEST_LAND, "%s: best-case land %.2f below %.2f" % [id, best, MIN_BEST_LAND])
	print("")
	print("balance: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(0 if failures == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL: %s" % what)


func _parse_runs() -> int:
	var args := OS.get_cmdline_user_args()
	var runs := DEFAULT_RUNS
	for i in args.size():
		var a: String = args[i]
		if a == "--runs" and i + 1 < args.size():
			runs = int(args[i + 1])
		elif a.begins_with("--runs="):
			runs = int(a.substr("--runs=".length()))
	return maxi(1, runs)


## First-to for an opponent, from the stage its tier plays at.
func _points_for(id: String) -> int:
	var stage := 0
	if OpponentLibrary.TIER_A.has(id):
		stage = 1
	elif OpponentLibrary.TIER_B.has(id):
		stage = 3
	elif OpponentLibrary.BOSSES.has(id):
		stage = 5
	return int(RunState.POINTS_TO_WIN[stage])


## `runs` matches against one opponent. Returns the row for the report.
func _run_opponent(id: String, index: int, runs: int) -> Dictionary:
	var ai: Dictionary = OpponentLibrary.profile(id)["ai"]
	var points_to_win := _points_for(id)
	var opponent_ids: Array = OpponentLibrary.deck_ids(id)
	if id == OpponentLibrary.SHADOW:
		opponent_ids = CardLibrary.ids_of(CardLibrary.starter_deck())
	var wins := 0
	var points_for := 0
	var points_against := 0
	var points := 0
	var shots := 0
	var seat_shots := [0, 0]
	var seat_tired := [0, 0]
	var stamina_sum := [0.0, 0.0]
	var point_starts := 0
	var max_shots := 0
	for i in runs:
		var seed_value := 100000 * (index + 1) + i
		var decks := [CardLibrary.starter_deck(), CardLibrary.from_ids(opponent_ids)]
		var m := MatchState.new(seed_value, decks, layout, points_to_win)
		var match_shots := 0
		var pending: Array = []
		var guard := 0
		while m.phase != MatchState.Phase.MATCH_OVER and guard < MAX_SHOTS + 100:
			guard += 1
			if m.phase == MatchState.Phase.POINT_OVER:
				m.start_point()
				point_starts += 1
				for p in 2:
					stamina_sum[p] += float(m.players[p].stamina)
				continue
			var action := AIController.choose(m, m.turn, AIController.DEFAULTS) if m.turn == 0 else AIController.choose(m, m.turn, ai)
			for e in m.apply(action):
				match String(e["type"]):
					"shot":
						match_shots += 1
						var shooter := int(e["player"])
						var card: Card = e["card"]
						var tired := bool(e.get("tired", false))
						var outcome := int(e["outcome"])
						seat_shots[shooter] += 1
						if tired:
							seat_tired[shooter] += 1
						var s: Dictionary = card_stats[card.id]
						s["played"] += 1
						if tired:
							s["tired"] += 1
						if outcome != RallyResolver.Outcome.FAULT:
							s["landed"] += 1
						if outcome == RallyResolver.Outcome.WINNER:
							s["winner"] += 1
						pending.append([card.id, shooter])
					"point":
						points += 1
						var winner := int(e["winner"])
						for entry in pending:
							if entry[1] == winner:
								card_stats[entry[0]]["point_won"] += 1
						pending.clear()
		shots += match_shots
		max_shots = maxi(max_shots, match_shots)
		points_for += m.players[0].score
		points_against += m.players[1].score
		if m.players[0].score > m.players[1].score:
			wins += 1
	var n := float(maxi(1, runs))
	return {
		"points_to_win": points_to_win,
		"win_rate": float(wins) / n,
		"points_for": float(points_for) / n,
		"points_against": float(points_against) / n,
		"rally": float(shots) / float(maxi(1, points)),
		"shots": float(shots) / n,
		"tired": [float(seat_tired[0]) / float(maxi(1, seat_shots[0])), float(seat_tired[1]) / float(maxi(1, seat_shots[1]))],
		"stamina": [stamina_sum[0] / float(maxi(1, point_starts)), stamina_sum[1] / float(maxi(1, point_starts))],
		"max_shots": max_shots,
	}


## Land chance of an untired card into the short middle against its best
## matchup: the ceiling a card can ever show the player.
func _best_case_land(id: String) -> float:
	var card := CardLibrary.by_id(id)
	var zone := layout.find(1, 0, 2)
	var best := 0.0
	for incoming in INCOMING_TYPES:
		var shot := RallyResolver.Shot.new()
		shot.card = card
		shot.incoming_type = incoming
		shot.incoming_risk = 0.0
		shot.target = zone
		shot.opponent_col = MatchState.HOME_COL
		best = maxf(best, float(RallyResolver.odds(shot)["land"]))
	return best
