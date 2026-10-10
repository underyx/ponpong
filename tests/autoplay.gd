## Headless test of the whole run loop. Boots the Director like the game
## does, presses the menus by action name, plays every match with a mix of
## AI picks and random cards (so tired plays and faults happen), pauses once
## mid-rally and checks the match froze, walks the zone cursor once with real
## input events, retries the seed when no match was ever won, and finishes on
## the main menu once the run ended and every screen was seen.
## Usage: godot --headless --fixed-fps 60 -s tests/autoplay.gd
extends SceneTree

const SEED := 20261010
const MAX_FRAMES := 60000
const MAX_RUNS := 6
const REQUIRED_SCREENS := ["main_menu", "match_end", "reward", "deck", "pause", "run_end"]
## Where this test saves its runs, so a check never touches the player's.
const TEST_SAVE := "user://test_run.json"
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
var cursor_done := false
var cursor_step := 0
var cursor_frame := 0
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
	if director.transitioning:
		return false
	var name := director.screen_name
	if name != last_screen:
		last_screen = name
		visited[name] = int(visited.get(name, 0)) + 1
		print("  [%5d] screen: %s" % [frames, name if name != "" else "match"])
	_check_focus(name)
	if pause_step > 0:
		_pause_flow()
		return false
	match name:
		"main_menu":
			if finishing:
				return _finish()
			_press("new_run")
		"":
			_drive_match()
		"pause":
			# Only the pause flow opens this screen; anything else is a stray.
			_fail("pause screen appeared outside the pause flow")
			_press("resume")
		"match_end":
			_check(is_equal_approx(Engine.time_scale, 1.0), "time scale is 1.0 on match_end")
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
	root.add_child(director)
	print("autoplay: director loaded, run seed %d" % SEED)


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
## from the pause menu, and resume restores everything.
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
				_press("resume")
				pause_step = 5
				pause_frame = frames
			elif frames - pause_frame > SCREEN_TIMEOUT:
				_fail("pause screen did not come back from the deck")
				pause_done = true
				pause_step = 0
		5:
			if director.screen_name == "":
				_check(not is_paused, "tree unpaused after resume")
				_check(is_equal_approx(Engine.time_scale, 1.0), "time scale restored after resume")
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
	# Every screen the Director built was either shown or freed: an
	# interrupted fade must not leak the screen it was about to show.
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(orphans == 0, "%d orphan nodes at the end of the run" % orphans)
	print("autoplay: %d run(s), %d local plays (%d tired), %d reward picks, %d score changes, %d frames, screens %s" % [
		runs, plays, tired_plays, real_picks, points, frames, visited])
	print("autoplay: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	root.remove_child(director)
	director.free()
	_remove_test_save()
	quit(0 if failures == 0 else 1)
	return true


static func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
