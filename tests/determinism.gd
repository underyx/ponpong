## Proves the rules run without any scene and are deterministic: two
## MatchStates with the same seed, driven by the same actions, must produce
## identical events and scores. Also round-trips a snapshot through to_dict().
## Usage: godot --headless -s tests/determinism.gd
extends SceneTree


func _initialize() -> void:
	var layout := ZoneLayout.new()
	var failures := 0
	for seed_value in [1, 42, 20261010]:
		var a := _new_match(seed_value, layout)
		var b := _new_match(seed_value, layout)
		var log_a := _play(a, layout)
		var log_b := _play(b, layout)
		var same := log_a == log_b
		print("seed %d: %d events, scores %s vs %s, identical=%s" % [
			seed_value, log_a.size(), [a.players[0].score, a.players[1].score],
			[b.players[0].score, b.players[1].score], same])
		if not same:
			failures += 1

	# Snapshot round trip mid-match.
	var c := _new_match(7, layout)
	c.start_point()
	for i in 3:
		if c.phase != MatchState.Phase.RALLY:
			c.start_point()
		c.apply(AIController.choose(c, c.turn))
	var d := MatchState.from_dict(c.to_dict(), layout)
	var tail_c := _play(c, layout)
	var tail_d := _play(d, layout)
	var same_tail := tail_c == tail_d
	print("snapshot round trip: %d remaining events, identical=%s" % [tail_c.size(), same_tail])
	if not same_tail:
		failures += 1

	print("determinism: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(0 if failures == 0 else 1)


func _new_match(seed_value: int, layout: ZoneLayout) -> MatchState:
	return MatchState.new(seed_value, [CardLibrary.starter_deck(), CardLibrary.starter_deck()], layout)


## Drive a match to the end with the AI on both sides, logging what happened.
func _play(m: MatchState, _layout: ZoneLayout) -> Array:
	var log: Array = []
	if m.phase != MatchState.Phase.RALLY:
		log.append_array(_flatten(m.start_point()))
	var guard := 0
	while m.phase != MatchState.Phase.MATCH_OVER and guard < 2000:
		guard += 1
		if m.phase == MatchState.Phase.POINT_OVER:
			log.append_array(_flatten(m.start_point()))
			continue
		var action := AIController.choose(m, m.turn)
		log.append(action)
		log.append_array(_flatten(m.apply(action)))
	return log


func _flatten(events: Array[Dictionary]) -> Array:
	var out: Array = []
	for e in events:
		var row := {"type": e["type"]}
		for k in ["player", "server", "winner", "outcome", "incoming_type", "score"]:
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
