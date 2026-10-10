## Headless test of the whole run loop. Boots the Director like the game
## does, presses the menus by action name, plays every match with a mix of
## AI picks and random cards (so tired plays and faults happen), pauses once
## mid-rally and checks the match froze, walks the zone cursor once with real
## input events, retries the seed when no match was ever won, and finishes on
## the main menu once the run ended and every screen was seen. Along the way
## it checks the feel layer keeps its promises: no `fx` moment fires while
## the match is paused, the time scale is back at base on every screen, and
## the Sfx node built every clip with sound in it. It also round-trips the
## settings (from the pause menu: F11 twice, which saves by itself, then a
## toggle and the slider that only Back can write, and Back must write a
## file that loads back; from the main menu on the way out) and the save
## file (after the first match end, load_run() must resume the run and
## Continue must land on the same screen).
## Usage: godot --headless --fixed-fps 60 -s tests/autoplay.gd
extends SceneTree

const SEED := 20261010
const MAX_FRAMES := 60000
const MAX_RUNS := 6
const REQUIRED_SCREENS := ["main_menu", "match_end", "reward", "deck", "pause", "run_end", "settings"]
## Where this test saves its runs and its settings, so a check never touches
## the player's.
const TEST_SAVE := "user://test_run.json"
const TEST_SETTINGS := "user://test_settings.cfg"
## What the settings slider is set to from the pause menu and from the main
## menu; the file must hand each back.
const PAUSE_VOLUME := 0.35
const MENU_VOLUME := 0.5
## How many frames the pause invariant watches the frozen match: longer than
## a ball flight plus AI_THINK_TIME at 60 fps, so a timer or tween that keeps
## running while paused moves the state inside the window.
const PAUSE_WATCH_FRAMES := 150
## Frames to wait for a screen the test asked for before failing.
const SCREEN_TIMEOUT := 30
## Share of local turns played by AIController; the rest are random cards
## into random zones.
const AI_SHARE := 0.7

var director: Director
var frames := 0
var failures := 0
var visited: Dictionary = {}
var last_screen := "<boot>"
var focus_failed_screen: UiScreen
var runs := 0
var plays := 0
var tired_plays := 0
var points := 0
var last_score := ""
var finishing := false
## Rewards taken as a card (not a skip or a trim) through the Director.
var real_picks := 0
var deck_viewed_from_reward := false
var trim_taken := false
var removes := 0
var pause_done := false
var pause_step := 0
var pause_frame := 0
var pause_snapshot: Dictionary = {}
var pause_ball := Vector3.ZERO
var pause_paddles: Array = []
var pause_log := ""
## `fx` moments the match has emitted, and the count when it was paused.
var fx_events := 0
var pause_fx := 0
## Frames that began with the clock slowed by a hit stop.
var stop_frames := 0
var cursor_done := false
var cursor_step := 0
var cursor_frame := 0
## What the Screen shake toggle was flipped to on the settings screen from
## pause; the file must hand it back.
var shake_expect := false
## After the first match end the run is reloaded from its file; the next
## screen must be this one.
var continue_expect := ""
var continue_checked := false
## The settings visit from the main menu, on the way out: 0 not yet, 1 open.
var settings_menu_step := 0
var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	rng.seed = SEED


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 1:
		_boot()
		return false
	if frames > MAX_FRAMES:
		_fail("timed out after %d frames" % frames)
		return _finish()
	_watch_score()
	if not is_equal_approx(Engine.time_scale, Feel.base_time_scale):
		stop_frames += 1
	if director.transitioning:
		return false
	var name := director.screen_name
	if name != last_screen:
		last_screen = name
		visited[name] = int(visited.get(name, 0)) + 1
		print("  [%5d] screen: %s" % [frames, name if name != "" else "match"])
		# Every screen change resets any hit stop; a stuck slow motion would
		# show here first.
		_check(is_equal_approx(Engine.time_scale, Feel.base_time_scale),
			"time scale %.3f is not base %.3f on screen %s" % [Engine.time_scale, Feel.base_time_scale, name])
		if continue_expect != "":
			_check(name == continue_expect, "the reloaded run continued to %s, not %s" % [name if name != "" else "match", continue_expect])
			continue_expect = ""
	_check_focus(name)
	if pause_step > 0:
		_pause_flow()
		return false
	match name:
		"main_menu":
			# The run file never outlives a run: no Continue at boot, none
			# after the run end.
			_check(not bool(director.screen.args.get("has_save", false)), "main menu offers Continue with no run to resume")
			if finishing:
				return _finish_via_settings()
			_press("new_run")
		"":
			_drive_match()
		"pause":
			# Only the pause flow opens this screen; anything else is a stray.
			_fail("pause screen appeared outside the pause flow")
			_press("resume")
		"settings":
			# From pause the pause flow drives it; this is the main menu's.
			_settings_from_menu()
		"match_end":
			_check(is_equal_approx(Engine.time_scale, Feel.base_time_scale), "time scale is back to base on match_end")
			_continue_check()
			_press("continue")
		"reward":
			_reward()
		"deck":
			_deck()
		"run_end":
			_run_end()
		_:
			_fail("unknown screen '%s'" % name)
	return false


func _boot() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	director = scene.instantiate()
	director.next_seed = SEED
	director.save_path = TEST_SAVE
	_remove_test_save()
	# The Director reads the settings in _ready: point it at a file of this
	# test's own first, with the defaults in the statics and no file yet.
	Settings.path = TEST_SETTINGS
	Settings.reset()
	_remove_test_settings()
	root.add_child(director)
	_check(is_equal_approx(Settings.master_volume, Settings.DEFAULT_MASTER_VOLUME) and Settings.screen_shake
		and not Settings.fullscreen, "settings are the defaults with no file")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(Settings.DEFAULT_MASTER_VOLUME)),
		"the Master bus is at the default volume after boot")
	# The Director turns hit stop off headlessly; turn it back on so the
	# time-scale checks below watch stops that really happened and were
	# really undone.
	Feel.enabled = true
	director.match_scene.fx.connect(func(_name: String, _data: Dictionary) -> void: fx_events += 1)
	print("autoplay: director loaded, run seed %d" % SEED)


# --- settings and continue -------------------------------------------------------

## On the way out: the main menu opens Settings once, the slider is moved,
## Back saves it, and the file must hand the new volume back.
func _finish_via_settings() -> bool:
	if settings_menu_step == 0:
		settings_menu_step = 1
		_press("settings")
		return false
	_check(FileAccess.file_exists(TEST_SETTINGS), "Back from the menu's settings wrote %s" % TEST_SETTINGS)
	Settings.master_volume = 0.0
	_check(Settings.load() and is_equal_approx(Settings.master_volume, MENU_VOLUME),
		"the menu's volume change was saved (file says %.2f)" % Settings.master_volume)
	return _finish()


## The settings screen opened from the main menu: unpaused, returns to the
## menu, the slider holds focus and moves the Master bus.
func _settings_from_menu() -> void:
	var s := director.screen as SettingsScreen
	if s == null:
		_fail("the settings screen is not a SettingsScreen")
		_press("back")
		return
	_check(settings_menu_step == 1, "settings opened from the menu outside the final visit")
	_check(String(s.args.get("return", "")) == "main_menu", "settings from the menu return to '%s'" % s.args.get("return", ""))
	_check(not paused, "tree paused under the settings screen from the menu")
	_check(s.first_focus() == s.slider and root.gui_get_focus_owner() == s.slider, "the slider holds focus on the settings screen")
	s.slider.value = MENU_VOLUME
	_check(is_equal_approx(Settings.master_volume, MENU_VOLUME), "the slider set master_volume (%.2f)" % Settings.master_volume)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(MENU_VOLUME)), "the Master bus follows the slider")
	_check(s.percent_label.text == Settings.percent(MENU_VOLUME), "percent label reads '%s'" % s.percent_label.text)
	_press("back")


## The settings screen opened from pause: still paused, returns to pause, the
## slider holds focus, and F11 is fired (its effect is checked next frame by
## the pause flow). The toggle and the slider are changed later, after the
## second F11, by _change_settings_from_pause().
func _settings_from_pause() -> void:
	var s := director.screen as SettingsScreen
	if s == null:
		_fail("the settings screen from pause is not a SettingsScreen")
		return
	_check(paused, "tree unpaused under the settings screen from pause")
	_check(String(s.args.get("return", "")) == "pause", "settings from pause return to '%s'" % s.args.get("return", ""))
	_check(s.first_focus() == s.slider and root.gui_get_focus_owner() == s.slider, "the slider holds focus on settings from pause")
	_check(not Settings.fullscreen, "fullscreen already on before F11")
	_fire("fullscreen")
	print("  [%5d] settings from pause: F11 fired" % frames)


## After the second F11 has written the file: flip the Screen shake toggle
## and move the slider. Every F11 saves all the statics, so these changes
## come last, after the final save, and the file must not hold them yet;
## only Back can write them, which the pause flow checks after it.
func _change_settings_from_pause() -> void:
	var s := director.screen as SettingsScreen
	if s == null:
		_fail("the settings screen from pause is not a SettingsScreen")
		return
	var volume_before := Settings.master_volume
	shake_expect = not Settings.screen_shake
	s.shake_button.button_pressed = shake_expect
	_check(Settings.screen_shake == shake_expect, "the Screen shake toggle sets Settings.screen_shake")
	var rig := director.match_scene.camera as CameraRig
	_check(rig != null and rig.shakes() == shake_expect, "the camera rig follows the Screen shake toggle at once")
	s.slider.value = PAUSE_VOLUME
	_check(is_equal_approx(Settings.master_volume, PAUSE_VOLUME), "the slider set master_volume (%.2f)" % Settings.master_volume)
	var saved_shake: Variant = _settings_file_value("screen_shake")
	var saved_volume: Variant = _settings_file_value("master_volume")
	_check(saved_shake == (not shake_expect) and typeof(saved_volume) == TYPE_FLOAT
		and is_equal_approx(float(saved_volume), volume_before),
		"the file already holds the new shake and volume before Back (shake %s, volume %s)" % [saved_shake, saved_volume])
	print("  [%5d] settings from pause: shake -> %s, volume %.2f, not on disk yet" % [frames, shake_expect, PAUSE_VOLUME])


## After the first match end the run file must resume to the same place:
## load_run() replaces the run with the saved copy and Continue routes on.
func _continue_check() -> void:
	if continue_checked or bool(director.screen.args.get("run_over", false)):
		return
	continue_checked = true
	var before: Dictionary = director.run.to_dict()
	var expect := _route_screen(director.run.phase)
	_check(FileAccess.file_exists(TEST_SAVE), "the run was saved at match end")
	_check(director.load_run(), "load_run() resumes the run saved at match end")
	_check(director.run.to_dict() == before, "the resumed run equals the one that was saved")
	continue_expect = expect
	print("  [%5d] reloaded the run from its file; Continue must land on %s" % [frames, expect])


## The screen _route() shows for a run phase.
static func _route_screen(phase: int) -> String:
	match phase:
		RunState.Phase.REWARD:
			return "reward"
		RunState.Phase.REMOVE:
			return "deck"
		RunState.Phase.MATCH:
			return ""
	return "run_end"


## A value from the settings file as it is on disk, or null without a file.
static func _settings_file_value(key: String) -> Variant:
	var cf := ConfigFile.new()
	if cf.load(TEST_SETTINGS) != OK:
		return null
	return cf.get_value(Settings.SECTION, key, null)


# --- screens -------------------------------------------------------------------

func _reward() -> void:
	if not deck_viewed_from_reward:
		deck_viewed_from_reward = true
		_press("deck")
		return
	var args: Dictionary = director.screen.args
	if not trim_taken and bool(args.get("trim_available", false)):
		trim_taken = true
		_press("trim")
		return
	# (visits % 4) - 1, as the design schedules it; the deck detour above is
	# the first visit, so the first real pick takes card 1 and the fourth
	# visit skips.
	var index := (int(visited.get("reward", 0)) % 4) - 1
	if index < 0:
		_press("skip")
	else:
		real_picks += 1
		_press("pick", {"index": index})


func _deck() -> void:
	var mode := String(director.screen.args.get("mode", "view"))
	if mode == "view":
		_press("back")
	elif removes == 0:
		removes += 1
		_press("remove", {"index": 0})
	else:
		_press("skip")


func _run_end() -> void:
	runs += 1
	var run := director.run
	var args: Dictionary = director.screen.args
	print("autoplay: run %d over, %s at stage %d vs %s, deck %d, stats %s" % [
		runs, "WON" if bool(args["won"]) else "LOST", int(args["stage"]) + 1, String(args["opponent_name"]),
		run.deck.size(), run.stats])
	if (int(visited.get("reward", 0)) == 0 or real_picks == 0) and runs < MAX_RUNS:
		director.next_seed += 1
		pause_done = false
		pause_step = 0
		cursor_done = false
		cursor_step = 0
		print("autoplay: no reward card picked yet, retrying with seed %d" % director.next_seed)
		_press("new_run")
	else:
		finishing = true
		_press("menu")


# --- the match -------------------------------------------------------------

func _drive_match() -> void:
	var m := director.match_scene
	if m.state == null:
		return
	if _pause_flow():
		return
	if _cursor_flow():
		return
	if m.input_open and m.input_mode == MatchScene.InputMode.HAND:
		_play()


func _play() -> void:
	var m := director.match_scene
	var s := m.state
	var hand: Array = s.players[0].hand
	var pick := 0
	var zone: Zone
	var how := "ai"
	if rng.randf() < AI_SHARE:
		var action := AIController.choose(s, 0)
		pick = int(action["card"])
		zone = m.layout.find(1, int(action["row"]), int(action["col"]))
	else:
		how = "random"
		pick = rng.randi_range(0, hand.size() - 1)
		var zones: Array = s.legal_targets(0)
		zone = zones[rng.randi_range(0, zones.size() - 1)]
	var card: Card = hand[pick]
	var stamina: int = s.players[0].stamina
	var tired := card.cost > stamina
	if tired:
		tired_plays += 1
	var odds: Dictionary = s.odds(0, pick, zone)
	print("  [%5d] %s: %s (cost %d%s) to %s, stamina %d, lands %d%%" % [
		frames, how, card.title, card.cost, ", TIRED" if tired else "", zone.label(), stamina, roundi(odds["land"] * 100.0)])
	m._on_card_chosen(pick)
	m.choose_zone(zone)
	plays += 1


## Once per run: Esc mid-rally, the match must not move for PAUSE_WATCH_FRAMES
## (the rules state, the ball, the paddles and the log line), the deck opens
## from the pause menu, then the settings (F11 twice, then a toggle and the
## slider that only Back can save, and Back writes a file that loads back),
## and resume restores everything.
func _pause_flow() -> bool:
	var m := director.match_scene
	var is_paused := paused
	match pause_step:
		0:
			if pause_done or m.state == null:
				return false
			if m.state.phase == MatchState.Phase.RALLY and not m.input_open:
				_fire("pause")
				pause_step = 1
				pause_frame = frames
				return true
			return false
		1:
			if director.screen_name == "pause":
				_check(is_paused, "tree paused after the pause action")
				pause_snapshot = m.state.to_dict()
				pause_ball = m.ball.global_position
				pause_paddles = [m.paddles[0].position, m.paddles[1].position]
				pause_log = m.log_label.text
				pause_fx = fx_events
				pause_step = 2
				pause_frame = frames
				print("  [%5d] paused mid-rally, watching %d frames" % [frames, PAUSE_WATCH_FRAMES])
			elif frames - pause_frame > SCREEN_TIMEOUT:
				_fail("the pause action did not open the pause screen")
				pause_done = true
				pause_step = 0
		2:
			if director.screen_name != "pause" or frames - pause_frame < PAUSE_WATCH_FRAMES:
				return true
			_check(m.state.to_dict() == pause_snapshot, "match state unchanged while paused")
			_check(m.ball.global_position == pause_ball, "ball frozen while paused")
			_check([m.paddles[0].position, m.paddles[1].position] == pause_paddles, "paddles frozen while paused")
			_check(m.log_label.text == pause_log, "log frozen while paused")
			_check(fx_events == pause_fx, "%d fx events fired while paused" % (fx_events - pause_fx))
			_check(is_paused, "tree still paused after %d frames" % PAUSE_WATCH_FRAMES)
			_press("deck")
			pause_step = 3
			pause_frame = frames
		3:
			if director.screen_name == "deck":
				var want := _distinct(director.run.deck)
				var got := _count_card_views(director.screen)
				_check(got == want, "deck screen shows %d card views for %d distinct ids" % [got, want])
				_check(is_paused, "tree still paused on the deck screen")
				_press("back")
				pause_step = 4
				pause_frame = frames
			elif frames - pause_frame > SCREEN_TIMEOUT:
				_fail("deck screen did not open from pause")
				pause_done = true
				pause_step = 0
		4:
			if director.screen_name == "pause":
				_check(is_paused, "tree still paused back on the pause screen")
				_press("settings")
				pause_step = 5
				pause_frame = frames
			elif frames - pause_frame > SCREEN_TIMEOUT:
				_fail("pause screen did not come back from the deck")
				pause_done = true
				pause_step = 0
		5:
			if director.screen_name == "settings":
				_settings_from_pause()
				pause_step = 6
				pause_frame = frames
			elif frames - pause_frame > SCREEN_TIMEOUT:
				_fail("settings screen did not open from pause")
				pause_done = true
				pause_step = 0
		6:
			# The F11 fired last frame has gone through the Director: the
			# setting flipped, was saved, and the screen followed.
			_check(director.screen_name == "settings", "still on settings after F11")
			_check(Settings.fullscreen, "F11 turned fullscreen on")
			_check(_settings_file_value("fullscreen") == true, "F11 saved fullscreen on")
			var s := director.screen as SettingsScreen
			_check(s != null and s.fullscreen_button.button_pressed and s.fullscreen_button.text == "On",
				"the settings screen followed F11")
			_fire("fullscreen")
			pause_step = 7
		7:
			# The second F11 has gone through and saved: now the changes that
			# only Back can write, then Back.
			_check(not Settings.fullscreen, "F11 turned fullscreen back off")
			_check(_settings_file_value("fullscreen") == false, "F11 saved fullscreen off")
			_change_settings_from_pause()
			_press("back")
			pause_step = 8
			pause_frame = frames
		8:
			if director.screen_name == "pause":
				_check(is_paused, "tree still paused back from settings")
				_check(FileAccess.file_exists(TEST_SETTINGS), "Back from settings left %s" % TEST_SETTINGS)
				# The file must hand back what the screen set after the last
				# F11 save: scramble the statics, load, compare.
				Settings.screen_shake = not shake_expect
				Settings.master_volume = 0.0
				_check(Settings.load(), "Settings.load() reads the file Back wrote")
				_check(Settings.screen_shake == shake_expect, "screen_shake %s did not come back from the file" % shake_expect)
				_check(is_equal_approx(Settings.master_volume, PAUSE_VOLUME), "master_volume came back as %.2f" % Settings.master_volume)
				_check(not Settings.fullscreen, "fullscreen came back on from the file")
				print("  [%5d] settings round trip held (shake %s, volume %.2f)" % [frames, shake_expect, Settings.master_volume])
				_press("resume")
				pause_step = 9
				pause_frame = frames
			elif frames - pause_frame > SCREEN_TIMEOUT:
				_fail("pause screen did not come back from settings")
				pause_done = true
				pause_step = 0
		9:
			if director.screen_name == "":
				_check(not is_paused, "tree unpaused after resume")
				_check(is_equal_approx(Engine.time_scale, Feel.base_time_scale), "time scale restored after resume")
				print("  [%5d] resumed; pause invariant held" % frames)
				pause_done = true
				pause_step = 0
			elif frames - pause_frame > SCREEN_TIMEOUT:
				_fail("resume did not close the pause screen")
				pause_done = true
				pause_step = 0
	return true


## Once per run: pick card 1 with the card_1 action, walk the cursor right
## four times and up once with ui_* events, check it sits on the deep
## far-right zone, then commit with ui_accept.
func _cursor_flow() -> bool:
	var m := director.match_scene
	if cursor_done:
		return false
	match cursor_step:
		0:
			if not (m.input_open and m.input_mode == MatchScene.InputMode.HAND):
				return false
			_fire("card_1")
			cursor_step = 1
			cursor_frame = frames
			return true
		1:
			if m.input_mode == MatchScene.InputMode.AIM and m.selected_index == 0:
				_fire("ui_right")
				cursor_step = 2
			elif frames - cursor_frame > SCREEN_TIMEOUT:
				_fail("card_1 did not select the first card (mode %d)" % m.input_mode)
				cursor_done = true
		2, 3, 4:
			_fire("ui_right")
			cursor_step += 1
		5:
			_fire("ui_up")
			cursor_step = 6
		6:
			var want := m.layout.find(1, 1, 4)
			_check(m.hover_zone == want, "cursor on the deep far-right after 4 rights and an up (at %s)" % [
				"nothing" if m.hover_zone == null else m.hover_zone.label()])
			_check(m.cursor == Vector2i(1, 4), "cursor value is (1, 4), got %s" % [m.cursor])
			_fire("ui_accept")
			cursor_step = 7
			cursor_frame = frames
		7:
			if not m.input_open:
				print("  [%5d] cursor path committed card 1 to the deep far-right" % frames)
				plays += 1
				cursor_done = true
			elif frames - cursor_frame > SCREEN_TIMEOUT:
				_fail("ui_accept did not commit the aimed shot")
				cursor_done = true
	return true


# --- helpers -----------------------------------------------------------------------

func _press(action: String, data: Dictionary = {}) -> void:
	print("  [%5d] press %s%s" % [frames, action, "" if data.is_empty() else " %s" % [data]])
	director.screen.press(action, data)


## A real input event, as the InputMap would produce it.
func _fire(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


func _watch_score() -> void:
	var m := director.match_scene
	if m == null or m.state == null or director.screen_name != "":
		return
	var text: String = m.score_label.text
	if text != last_score:
		last_score = text
		points += 1
		print("  [%5d] %s   (%s)" % [frames, text, m.log_label.text])


## Every frame a screen is up, something must hold focus for a gamepad.
## Reported once per screen instance so a miss does not flood the log.
func _check_focus(name: String) -> void:
	if name == "" or director.screen == null or director.screen == focus_failed_screen:
		return
	if root.gui_get_focus_owner() == null:
		focus_failed_screen = director.screen
		_fail("no focus owner on screen %s at frame %d" % [name, frames])


static func _distinct(ids: Array) -> int:
	var seen := {}
	for id in ids:
		seen[id] = true
	return seen.size()


## Buttons that carry a `card` (CardView and the like) anywhere under `node`.
static func _count_card_views(node: Node) -> int:
	var n := 0
	if node is Button and node.get("card") is Card:
		n += 1
	for child in node.get_children():
		n += _count_card_views(child)
	return n


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	failures += 1
	push_error("autoplay FAIL: %s" % what)
	print("  FAIL: %s" % what)


func _finish() -> bool:
	for s in REQUIRED_SCREENS:
		_check(visited.has(s), "screen %s was visited" % s)
	_check(runs == MAX_RUNS or real_picks > 0, "a reward card was picked through the Director")
	_check(is_equal_approx(Engine.time_scale, Feel.base_time_scale), "time scale is at base at the end")
	_check(stop_frames > 0, "a hit stop slowed the clock at some point during the run")
	_check(fx_events > 0, "the match emitted fx moments (%d)" % fx_events)
	_check_sfx()
	# Every screen the Director built was either shown or freed: an
	# interrupted fade must not leak the screen it was about to show.
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(orphans == 0, "%d orphan nodes at the end of the run" % orphans)
	_check(continue_checked, "the run was reloaded from its file after a match end")
	_check(settings_menu_step == 1, "settings were visited from the main menu")
	print("autoplay: %d run(s), %d local plays (%d tired), %d reward picks, %d score changes, %d frames (%d in hit stop), screens %s" % [
		runs, plays, tired_plays, real_picks, points, frames, stop_frames, visited])
	print("autoplay: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	root.remove_child(director)
	director.free()
	_remove_test_save()
	_remove_test_settings()
	Settings.reset()
	Settings.path = Settings.DEFAULT_PATH
	quit(0 if failures == 0 else 1)
	return true


## The Sfx node in main.tscn built every clip it names, each long enough to
## be a sound and not silent. Never played back here: the data is the test.
func _check_sfx() -> void:
	var sfx := Sfx.instance
	if sfx == null or not is_instance_valid(sfx):
		_fail("no Sfx node is in the tree")
		return
	_check(Sfx.NAMES.size() == 20, "Sfx names %d clips, not 20" % Sfx.NAMES.size())
	_check(sfx.streams.size() == Sfx.NAMES.size(), "Sfx built %d streams for %d names" % [
		sfx.streams.size(), Sfx.NAMES.size()])
	var silent := 0
	for name in Sfx.NAMES:
		var stream: AudioStreamWAV = sfx.streams.get(name)
		if stream == null:
			_fail("clip %s was not built" % name)
			continue
		var data := stream.data
		_check(data.size() > 1000, "clip %s has only %d bytes" % [name, data.size()])
		var has_sound := false
		for i in range(0, data.size() - 1, 2):
			if data.decode_s16(i) != 0:
				has_sound = true
				break
		if not has_sound:
			silent += 1
			_fail("clip %s is silent" % name)
	print("autoplay: sfx %d streams, %d silent" % [sfx.streams.size(), silent])


static func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))


static func _remove_test_settings() -> void:
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
