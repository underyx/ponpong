## Renders the run's screens to PNG. Needs a real (or virtual) display:
##   xvfb-run godot --rendering-driver opengl3 -s tests/screenshot.gd -- /out/dir
## Drives the Director with a pinned seed, waiting for each state rather than
## counting frames, because software GL frame times vary. After the first
## point it applies run actions directly instead of playing matches out.
extends SceneTree

const SEED := 20261010
## Frames to let a screen lay out before saving it.
const SETTLE := 3
## Where this test saves its run, so a check never touches the player's.
const TEST_SAVE := "user://test_run.json"

var director: Director
var frames := 0
## Defaults to the user data dir, which exists on every platform.
var out_dir := OS.get_user_data_dir().path_join("shots")
var step := 0
var wait_until := 0
## PNGs that could not be written; the exit code reports them.
var failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 1:
		_boot()
		return false
	if frames > 3000:
		push_error("screenshot: timed out at step %d" % step)
		quit(1)
		return true
	if director.transitioning or frames < wait_until:
		return false
	var m := director.match_scene
	var name := director.screen_name
	match step:
		0:
			if name == "main_menu":
				_save("01_menu.png")
				director.screen.press("new_run")
				_next()
		1:
			if m.input_open and m.input_mode == MatchScene.InputMode.HAND:
				_tire_one_card(m)
				_next(SETTLE)
		2:
			_save("02_hand.png")
			m._select_card(0)
			m.cursor = Vector2i(1, 3)
			m._set_hover(m._cursor_zone())
			_next(SETTLE)
		3:
			_save("03_aim.png")
			director.toggle_pause()
			_next(SETTLE)
		4:
			if name == "pause":
				_save("06_pause.png")
				director.screen.press("resume")
				_next(SETTLE)
		5:
			if name == "":
				m.choose_zone(m._cursor_zone())
				_next(2)
		6:
			_save("04_shot.png")
			_next(3)
		7:
			_save("05_bounce.png")
			_next(1)
		8:
			if m.input_open:
				var stats := [m.state.players[0].stats.duplicate(), m.state.players[1].stats.duplicate()]
				director._on_match_finished(0, [5, 3], 7, stats)
				_next(SETTLE)
		9:
			if name == "match_end":
				_save("07_match_end.png")
				director.screen.press("continue")
				_next(SETTLE)
		10:
			if name == "reward":
				_save("08_reward.png")
				director.screen.press("deck")
				_next(SETTLE)
		11:
			if name == "deck":
				_save("09_deck.png")
				_lose_the_run(director.run)
				director._route()
				_next(SETTLE)
		12:
			if name == "run_end":
				_save("10_run_end.png")
				_remove_test_save()
				quit(0 if failures == 0 else 1)
				return true
	return false


func _boot() -> void:
	var made := DirAccess.make_dir_recursive_absolute(out_dir)
	if made != OK:
		push_error("screenshot: cannot create %s (%s)" % [out_dir, error_string(made)])
	print("screenshot: saving to %s" % out_dir)
	director = load("res://scenes/main.tscn").instantiate()
	director.next_seed = SEED
	director.save_path = TEST_SAVE
	_remove_test_save()
	root.add_child(director)


func _next(settle := 1) -> void:
	step += 1
	wait_until = frames + settle


## Leaves the player one stamina short of the costliest card in hand, so the
## hand shows a TIRED card and the pips show a gap.
func _tire_one_card(m: MatchScene) -> void:
	var hand: Array = m.state.players[0].hand
	var top := 0
	for card in hand:
		top = maxi(top, (card as Card).cost)
	if top == 0:
		return
	m.state.players[0].stamina = top - 1
	m._set_stamina([top - 1, m.state.players[1].stamina])
	m._open_input()


## Take the reward, then lose the next match twice: a regroup, then run over.
static func _lose_the_run(run: RunState) -> void:
	run.apply({"type": "pick_reward", "index": 0})
	run.apply({"type": "match_result", "winner": 1, "score": [3, 7], "longest_rally": 5, "tired_plays": [1, 0]})
	run.apply({"type": "skip_remove"})
	run.apply({"type": "match_result", "winner": 1, "score": [5, 7], "longest_rally": 9, "tired_plays": [2, 1]})


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name)
	var err := img.save_png(path)
	if err != OK:
		failures += 1
		push_error("screenshot: cannot write %s (%s)" % [path, error_string(err)])
	print("saved %s (%s) err=%d" % [name, img.get_size(), err])


static func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
