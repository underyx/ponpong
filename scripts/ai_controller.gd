## Picks actions for a computer-controlled player by looking at the odds of
## every card into every zone. Uses the match's own RNG so it is deterministic
## for a given state. Online, a RemoteController will fill the same role by
## handing over actions it received from the other peer.
class_name AIController
extends RefCounted

## How often the AI takes the best option rather than one of the next best.
const GREED := 0.65


static func choose(state: MatchState, player: int) -> Dictionary:
	var me := state.players[player]
	var options: Array = []
	for i in me.hand.size():
		for zone in state.legal_targets(player):
			var o := state.odds(player, i, zone)
			var land: float = o["land"]
			var win: float = o["win"]
			# Expected value of the point: win it now, lose it now, or keep going.
			var value := land * win - (1.0 - land) + land * (1.0 - win) * 0.1
			options.append([value, i, zone])
	options.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var pick: Array = options[0]
	if state.rng.randf() > GREED:
		pick = options[state.rng.randi_range(0, mini(2, options.size() - 1))]
	var zone: Zone = pick[2]
	return {"type": "shot", "player": player, "card": pick[1], "row": zone.row, "col": zone.col}
