## Picks actions for a computer-controlled player by looking at the odds of
## every card into every zone. Uses the match's own RNG so it is deterministic
## for a given state. Online, a RemoteController will fill the same role by
## handing over actions it received from the other peer.
class_name AIController
extends RefCounted

## Personality knobs, all optional. With these values the formula reduces to the
## plain expected value of the point, and the best option is taken `greed` of
## the time, otherwise one of the top `spread`.
##   greed       chance to take the single best option
##   spread      how many of the top options the other picks come from
##   aggression  >0 chases winners and shrugs off faults, <0 is fault-averse
##   row_bias    >0 prefers the deep row, <0 the short row
##   edge_bias   >0 prefers the edge lanes
##   thrift      >0 dislikes paying stamina
const DEFAULTS := {"greed": 0.65, "spread": 3, "aggression": 0.0, "row_bias": 0.0, "edge_bias": 0.0, "thrift": 0.0}


static func choose(state: MatchState, player: int, params: Dictionary = {}) -> Dictionary:
	var p := DEFAULTS.duplicate()
	p.merge(params, true)
	var options := _options(state, player, p)
	var pick: Array = options[0]
	if state.rng.randf() > float(p["greed"]):
		pick = options[state.rng.randi_range(0, mini(int(p["spread"]) - 1, options.size() - 1))]
	var zone: Zone = pick[2]
	return {"type": "shot", "player": player, "card": pick[1], "row": zone.row, "col": zone.col}


## Every card into every legal zone as [value, card index, zone, option index],
## best first. `p` is a complete parameter set (DEFAULTS merged with overrides).
static func _options(state: MatchState, player: int, p: Dictionary) -> Array:
	var me := state.players[player]
	var options: Array = []
	for i in me.hand.size():
		var card: Card = me.hand[i]
		for zone in state.legal_targets(player):
			var o := state.odds(player, i, zone)
			var land: float = o["land"]
			var win: float = o["win"]
			var aggression := float(p["aggression"])
			# Expected value of the point: win it now, lose it now, or keep going.
			var value := land * win * (1.0 + 0.6 * aggression) - (1.0 - land) * (1.0 - 0.4 * aggression) + land * (1.0 - win) * 0.1
			value += 0.08 * float(p["row_bias"]) * (1.0 if zone.row == 1 else -1.0)
			if zone.is_edge_col():
				value += 0.08 * float(p["edge_bias"])
			value -= 0.04 * float(p["thrift"]) * card.cost
			if card.keyword == "rest" and me.stamina <= 1:
				value += 0.05
			options.append([value, i, zone, options.size()])
	options.sort_custom(_better)
	return options


## Higher value first; equal values keep their option index order (card order,
## then zone order). A total order, so the pick never depends on how the sort
## happens to arrange ties, which Array.sort_custom() does not promise.
static func _better(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] > b[0]
	return a[3] < b[3]
