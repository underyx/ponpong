## Renders a couple of frames to PNG. Needs a real (or virtual) display:
##   xvfb-run godot --rendering-driver opengl3 -s tests/screenshot.gd -- /out/dir
extends SceneTree

var game: Node
var frames := 0
var out_dir := "/tmp"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 40:
		_save("01_hand.png")
	if frames == 41 and game.phase == game.Phase.PLAYER_TURN:
		game._on_card_chosen(0)
	if frames == 52:
		_save("02_shot.png")
	if frames == 70:
		_save("03_bounce.png")
	if frames == 90:
		_save("04_reply.png")
		return true
	return false


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(out_dir.path_join(name))
	print("saved %s (%s) err=%d" % [name, img.get_size(), err])
