## Headless smoke test of the presenter: run the main scene and, whenever the
## local player may act, play a random card into a random zone, until the
## match ends. Random picks ignore stamina on purpose, so tired plays happen.
## Usage: godot --headless -s tests/autoplay.gd
extends SceneTree

var game: Node
var frames := 0
var plays := 0
var tired_plays := 0
var last_log := ""


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	print("autoplay: scene loaded")


func _process(_delta: float) -> bool:
	frames += 1
	var log_text: String = game.log_label.text
	if log_text != last_log:
		last_log = log_text
		print("  [%4d] %s   (%s · %s)" % [frames, log_text, game.score_label.text, game.stamina_label.text])
	# Wait for the presenter to drain (ball flight, point hold, the callout)
	# before freeing the scene, or its coroutines never unwind.
	if game.state.phase == MatchState.Phase.MATCH_OVER and plays > 0 and not game._pumping:
		var score: Array = [game.state.players[0].score, game.state.players[1].score]
		print("autoplay: match over after %d local plays (%d tired), %d frames. YOU %d - %d THEM" % [
			plays, tired_plays, frames, score[0], score[1]])
		for p in 2:
			print("autoplay: player %d stats %s, longest rally %d" % [p, game.state.players[p].stats, game.state.longest_rally])
		root.remove_child(game)
		game.free()
		return true
	if game.input_open:
		var hand: Array = game.state.players[0].hand
		var stamina: int = game.state.players[0].stamina
		var pick: int = randi() % hand.size()
		# Half the time, reach for the costliest card in hand, so stamina runs
		# dry and the tired path through the presenter gets exercised too.
		if randi() % 2 == 0:
			for i in hand.size():
				if (hand[i] as Card).cost > (hand[pick] as Card).cost:
					pick = i
		var card: Card = hand[pick]
		var zones: Array = game.state.legal_targets(0)
		var zone: Zone = zones[randi() % zones.size()]
		var odds: Dictionary = game.state.odds(0, pick, zone)
		var tired := card.cost > stamina
		if tired:
			tired_plays += 1
		print("  [%4d] incoming=%s, stamina %d -> %s (cost %d%s) to %s (lands %d%%)" % [
			frames, BallType.label(game.state.incoming_type), stamina, card.title, card.cost,
			", TIRED" if tired else "", zone.label(), roundi(odds["land"] * 100.0)])
		game._on_card_chosen(pick)
		game.choose_zone(zone)
		plays += 1
	if frames > 30000:
		push_error("autoplay: timed out")
		quit(1)
		return true
	return false
