## Headless smoke test: run the main scene and play the first card every turn
## until the match ends. Usage: godot --headless -s tests/autoplay.gd
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
	if game.phase == game.Phase.PLAYER_TURN:
		var hand_names := []
		for c in game.hand:
			hand_names.append(c.title)
		var pick: int = randi() % game.hand.size()
		print("  [%4d] incoming=%s hand=%s -> play %s" % [frames, BallType.label(game.incoming), hand_names, game.hand[pick].title])
		game._on_card_chosen(pick)
		plays += 1
	if game.phase == game.Phase.MATCH_OVER and plays > 0:
		print("autoplay: match over after %d plays, %d frames. %s" % [plays, frames, game.score_label.text])
		return true
	if frames > 20000:
		push_error("autoplay: timed out")
		quit(1)
		return true
	return false
