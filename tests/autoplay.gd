## Headless smoke test of the presenter: run the main scene and, whenever the
## local player may act, play a random card into a random zone, until the
## match ends. Usage: godot --headless -s tests/autoplay.gd
extends SceneTree

var game: Node
var frames := 0
var plays := 0
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
		print("  [%4d] %s   (%s)" % [frames, log_text, game.score_label.text])
	if game.state.phase == MatchState.Phase.MATCH_OVER and plays > 0:
		var score: Array = [game.state.players[0].score, game.state.players[1].score]
		print("autoplay: match over after %d local plays, %d frames. YOU %d - %d THEM" % [plays, frames, score[0], score[1]])
		root.remove_child(game)
		game.free()
		return true
	if game.input_open:
		var hand: Array = game.state.players[0].hand
		var pick: int = randi() % hand.size()
		var zones: Array = game.state.legal_targets(0)
		var zone: Zone = zones[randi() % zones.size()]
		var odds: Dictionary = game.state.odds(0, pick, zone)
		print("  [%4d] incoming=%s -> %s to %s (lands %d%%)" % [
			frames, BallType.label(game.state.incoming_type), hand[pick].title, zone.label(), roundi(odds["land"] * 100.0)])
		game._on_card_chosen(pick)
		game.choose_zone(zone)
		plays += 1
	if frames > 30000:
		push_error("autoplay: timed out")
		quit(1)
		return true
	return false
