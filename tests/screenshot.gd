## Renders the run's screens to PNG. Needs a real (or virtual) display:
##   xvfb-run godot --rendering-driver opengl3 -s tests/screenshot.gd -- /out/dir
## Drives the Director with a pinned seed, waiting for each state rather than
## counting frames, because software GL frame times vary. After the first
## point it applies run actions directly instead of playing matches out.
extends SceneTree

const SEED := 20261010
## Frames to let a screen lay out before saving it.
const SETTLE := 3
## Wall-clock seconds to let an entrance play out before saving: the hand's
## deal-in and the reward cards' flip-in take about 0.4 s whatever the frame
## rate, so these two are waited for by the clock, not by frames.
const ENTRY_SETTLE := 0.6
## Frames after the ball's bounce before 04_shot: the puff has been emitted
## and drawn, the ring has started to spread, the trail still reaches back
## to the paddle. 05_bounce is the frame after.
const BOUNCE_SETTLE := 2
## While the shot is in the air the clock is scaled so that one frame
## advances the effects by about this much, whatever the renderer's real
## frame time: software GL can take a third of a second per frame, longer
## than the puff and the ring live. On a desktop this is close to no change.
const SHOT_FRAME_TIME := 1.0 / 30.0
const MIN_SHOT_SCALE := 0.05
## Where this test saves its run, so a check never touches the player's.
const TEST_SAVE := "user://test_run.json"

var director: Director
var frames := 0
## Defaults to the user data dir, which exists on every platform.
var out_dir := OS.get_user_data_dir().path_join("shots")
var step := 0
var wait_until := 0
## The step also waits for this OS tick (microseconds) to pass.
var wait_until_usec := 0
## Set by the ball's bounced signal once the committed shot hits the table.
var bounced := false
## PNGs that could not be written; the exit code reports them.
var failures := 0
## Real seconds the last frame took, from the OS clock, for the shot window.
var frame_seconds := 1.0 / 60.0
var _last_tick := 0
var _saved_base_scale := 1.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]


func _process(_delta: float) -> bool:
	frames += 1
	var tick := Time.get_ticks_usec()
	if _last_tick > 0:
		frame_seconds = float(tick - _last_tick) / 1000000.0
	_last_tick = tick
	if frames == 1:
		_boot()
		return false
	if frames > 3000:
		push_error("screenshot: timed out at step %d" % step)
		quit(1)
		return true
	if director.transitioning or frames < wait_until or tick < wait_until_usec:
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
				_next(SETTLE, ENTRY_SETTLE)
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
				m.ball.bounced.connect(func(_pos: Vector3) -> void: bounced = true, CONNECT_ONE_SHOT)
				_slow_clock()
				m.choose_zone(m._cursor_zone())
				_next()
		6:
			if bounced:
				_next(BOUNCE_SETTLE)
		7:
			_save("04_shot.png")
			_next(1)
		8:
			_save("05_bounce.png")
			_restore_clock()
			_next(1)
		9:
			if m.input_open:
				var stats := [m.state.players[0].stats.duplicate(), m.state.players[1].stats.duplicate()]
				director._on_match_finished(0, [5, 3], 7, stats)
				_next(SETTLE)
		10:
			if name == "match_end":
				_save("07_match_end.png")
				director.screen.press("continue")
				_next(SETTLE)
		11:
			# The reward cards flip in once the screen is up: let them finish.
			if name == "reward":
				_next(SETTLE, ENTRY_SETTLE)
		12:
			_save("08_reward.png")
			director.screen.press("deck")
			_next(SETTLE)
		13:
			if name == "deck":
				_save("09_deck.png")
				_lose_the_run(director.run)
				director._route()
				_next(SETTLE)
		14:
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


## Moves to the next step after `settle` frames and `seconds` of wall time.
func _next(settle := 1, seconds := 0.0) -> void:
	step += 1
	wait_until = frames + settle
	wait_until_usec = Time.get_ticks_usec() + int(seconds * 1000000.0)


## Scales the clock so a frame moves the shot's effects by SHOT_FRAME_TIME.
## Feel's base scale follows, so a hit stop during the shot restores to the
## same slow clock instead of the real one.
func _slow_clock() -> void:
	var scale := clampf(SHOT_FRAME_TIME / maxf(frame_seconds, 0.001), MIN_SHOT_SCALE, 1.0)
	_saved_base_scale = Feel.base_time_scale
	Feel.base_time_scale = scale
	Engine.time_scale = scale
	print("screenshot: frame %.3f s, shot clock at %.2f" % [frame_seconds, scale])


func _restore_clock() -> void:
	Feel.base_time_scale = _saved_base_scale
	Feel.reset()


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
	print("saved %s (%s) err=%d, frame %.3f s" % [name, img.get_size(), err, frame_seconds])


static func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
