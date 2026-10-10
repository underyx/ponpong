## The run loop. Owns the RunState, the one MatchScene (always in the tree:
## the 3D table is every menu's backdrop) and whichever screen is up, and
## routes every screen action to the next thing: a match, a reward, the deck,
## the end of the run. Pause freezes the match through the tree's pause flag;
## this node and the Screens layer process always, so menus keep working.
class_name Director
extends Node

signal screen_changed(name: String)
signal device_changed(gamepad: bool)

const VERSION := "0.2.0"
## Where a run is saved by default; see `save_path`.
const SAVE_PATH := "user://run.json"
## Fade through black between screens; both are 0 headlessly so tests
## advance in two frames while running the same code path.
const FADE_OUT := 0.12
const FADE_IN := 0.18
## Screens that keep the tree paused while they are up.
const PAUSE_FAMILY := ["pause"]
## How long the reward screen stays up after a pick, so the chosen card's
## lift and the others' fade (CardView.RAISE_TIME, FADE_TIME) can be seen
## before the match replaces the screen. 0 headlessly, like the fades.
const PICK_HOLD := 0.3
## screen/action pairs whose screen plays its own sound for the choice, so
## the generic click stays out of the way of it.
const SELF_VOICED := ["reward/pick"]

var run: RunState
var match_scene: MatchScene
var screen: UiScreen
## Name of the screen that is up or on its way; "" during a match.
var screen_name := ""
var transitioning := false
## Seed of the next run; -1 draws one. Tests pin it.
var next_seed := -1
## True while the last input came from a joypad.
var gamepad := false
## Seed of the last run started or loaded, for the menu's footer; -1 for none.
var last_seed := -1
## The save file this Director reads and writes. Tests point it at a file of
## their own before adding the node, so a headless check never touches the
## player's run.
var save_path := SAVE_PATH

var _screens: CanvasLayer
var _fade: ColorRect
var _fade_tween: Tween
## Bumped by every show_screen so a superseded transition stops after its await.
var _show_gen := 0
## A screen built by show_screen that is still waiting for the fade-out. A
## second show_screen or a close_screen kills that fade, and a killed tween
## never emits `finished`, so the waiting call cannot free it: whoever
## supersedes it does.
var _pending: UiScreen


func _ready() -> void:
	InputSetup.register()
	# The player's volume, window mode and shake choice, before anything
	# makes a sound or a frame is drawn.
	Settings.load_and_apply()
	# Hit stop restores to the time scale the game booted with (--time-scale
	# included), and is off headlessly, where frames are not time.
	Feel.base_time_scale = Engine.time_scale
	Feel.enabled = not _headless()
	match_scene = $Match
	_screens = $Screens
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screens.add_child(_fade)
	match_scene.match_finished.connect(_on_match_finished)
	device_changed.connect(match_scene.set_gamepad)
	# The sounds follow the match through its signals; the match never calls
	# them. Children are ready before their parent, so the Sfx node (when the
	# scene has one) has already claimed its static instance here.
	var sfx := Sfx.instance
	if sfx != null:
		match_scene.fx.connect(sfx.on_fx)
		match_scene.ball.bounced.connect(sfx.on_bounced)
		match_scene.ball.netted.connect(sfx.on_netted)
	match_scene.set_idle(true)
	show_screen("main_menu", _menu_args())


func _process(_delta: float) -> void:
	# A gamepad needs somewhere to be: if focus got lost (a freed button, a
	# click on nothing), put it back on the screen's first control.
	if screen != null and is_instance_valid(screen) and get_viewport().gui_get_focus_owner() == null:
		var f := screen.first_focus()
		if f != null:
			f.grab_focus()


func _input(event: InputEvent) -> void:
	_track_device(event)
	if event.is_action_pressed("fullscreen"):
		get_viewport().set_input_as_handled()
		toggle_fullscreen()
		return
	if run != null and screen == null and not transitioning and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		toggle_pause()


## F11 anywhere: the window mode flips, is applied and is saved at once. A
## Settings screen that is up shows the change.
func toggle_fullscreen() -> void:
	Settings.fullscreen = not Settings.fullscreen
	Settings.apply()
	Settings.save()
	if screen is SettingsScreen:
		(screen as SettingsScreen).refresh()


# --- run flow ----------------------------------------------------------------

func start_run(seed_value: int) -> void:
	run = RunState.new(seed_value)
	last_seed = seed_value
	print("director: new run, seed %d, opponents %s" % [seed_value, run.opponents])
	save_run()
	start_match()


func start_match() -> void:
	var cfg := run.match_config()
	var opponent: Dictionary = cfg["opponent"]
	close_screen()
	get_tree().paused = false
	match_scene.set_idle(false)
	match_scene.start({
		"seed": cfg["seed"],
		"decks": [CardLibrary.from_ids(cfg["player_deck"]), CardLibrary.from_ids(cfg["opponent_deck"])],
		"points_to_win": cfg["points_to_win"],
		"ai": opponent["ai"],
		"opponent_id": opponent["id"],
		"opponent_name": opponent["name"],
		"blurb": opponent["blurb"],
		"paddle_color": opponent["paddle_color"],
		"boss": opponent["boss"],
		"hearts": cfg["hearts"],
		"stage": cfg["stage"],
		"stages": cfg["stages"],
	})


## Where the run goes next, by its phase.
func _route() -> void:
	match run.phase:
		RunState.Phase.MATCH:
			start_match()
		RunState.Phase.REWARD:
			show_screen("reward", _reward_args())
		RunState.Phase.REMOVE:
			show_screen("deck", {"mode": "remove", "reason": run.remove_reason, "deck": run.deck.duplicate(),
				"return": "", "deck_min": RunState.DECK_MIN})
		_:
			clear_save()
			show_screen("run_end", _run_end_args())


func _on_match_finished(winner: int, score: Array, longest_rally: int, stats: Array) -> void:
	if run == null:
		return
	run.apply({"type": "match_result", "winner": winner, "score": score, "longest_rally": longest_rally,
		"tired_plays": [int(stats[0]["tired_plays"]), int(stats[1]["tired_plays"])]})
	var over := run.phase == RunState.Phase.WON or run.phase == RunState.Phase.LOST
	if over:
		clear_save()
	else:
		save_run()
	show_screen("match_end", {"won": winner == 0, "score": score, "hearts": run.hearts, "stats": stats,
		"longest_rally": longest_rally, "run_over": over})


func _on_screen_done(action: String, data: Dictionary) -> void:
	# A click that lands during a fade belongs to the screen on its way out.
	if transitioning:
		return
	var key := "%s/%s" % [screen_name, action]
	if not SELF_VOICED.has(key):
		Sfx.play("ui_back" if action != "" and action == screen.back_action else "ui_accept")
	if screen != null:
		screen.on_accepted(action, data)
	match key:
		"main_menu/new_run":
			start_run(next_seed if next_seed >= 0 else randi())
		"main_menu/continue":
			if load_run():
				_route()
			else:
				show_screen("main_menu", _menu_args())
		"main_menu/settings":
			show_screen("settings", {"return": "main_menu"})
		"main_menu/quit":
			get_tree().quit()
		"pause/resume":
			toggle_pause()
		"pause/deck":
			show_screen("deck", {"mode": "view", "deck": run.deck.duplicate(), "return": "pause",
				"reason": "", "deck_min": RunState.DECK_MIN})
		"pause/settings":
			show_screen("settings", {"return": "pause"})
		"pause/abandon":
			abandon_run()
		"match_end/continue":
			_route()
		"reward/pick":
			run.apply({"type": "pick_reward", "index": int(data.get("index", -1))})
			save_run()
			# The screen stays up while the picked card lifts; a second click
			# meanwhile is a click during a transition and is dropped above.
			transitioning = true
			var my := _show_gen
			await get_tree().create_timer(0.0 if _headless() else PICK_HOLD, true, false, true).timeout
			if my != _show_gen:
				# Something else showed a screen meanwhile (it owns the flow now).
				return
			_route()
		"reward/skip":
			run.apply({"type": "pick_reward", "index": -1})
			save_run()
			_route()
		"reward/trim":
			run.apply({"type": "trim_instead"})
			save_run()
			_route()
		"reward/deck":
			show_screen("deck", {"mode": "view", "deck": run.deck.duplicate(), "return": "reward",
				"reason": "", "deck_min": RunState.DECK_MIN})
		"deck/back":
			if String(screen.args.get("return", "")) == "pause":
				show_screen("pause")
			else:
				_route()
		"deck/remove":
			run.apply({"type": "remove_card", "index": int(data.get("index", -1))})
			save_run()
			_route()
		"deck/skip":
			run.apply({"type": "skip_remove"})
			save_run()
			_route()
		"run_end/new_run":
			start_run(next_seed if next_seed >= 0 else randi())
		"run_end/retry":
			start_run(run.seed_value)
		"run_end/menu":
			match_scene.set_idle(true)
			show_screen("main_menu", _menu_args())
		"settings/back":
			# Every change was applied as it was made; leaving is what writes
			# the file.
			Settings.save()
			if String(screen.args.get("return", "")) == "pause":
				show_screen("pause")
			else:
				show_screen("main_menu", _menu_args())
		_:
			push_warning("Director: no route for %s" % key)


# --- screens -----------------------------------------------------------------

## Fades through black, swaps the screen, gives it focus and fades back.
func show_screen(name: String, args: Dictionary = {}) -> void:
	var next := _make_screen(name)
	if next == null:
		push_warning("Director: no screen named '%s'" % name)
		return
	_drop_pending()
	_pending = next
	_show_gen += 1
	var my := _show_gen
	transitioning = true
	screen_name = name
	# A hit stop must never outlive the moment it froze.
	Feel.reset()
	if not _keeps_pause(name, args):
		get_tree().paused = false
	await _fade_to(1.0, FADE_OUT)
	if my != _show_gen:
		# Superseded: the later call already dropped `next`.
		return
	_free_screen()
	_pending = null
	# Only the pause menu sits over a match that is still going; every other
	# screen covers one that is over, or none at all.
	match_scene.set_hud_visible(name == "pause")
	screen = next
	screen.name = name.to_pascal_case() + "Screen"
	screen.setup(args)
	_screens.add_child(screen)
	_screens.move_child(_fade, -1)
	screen.done.connect(_on_screen_done)
	var f := screen.first_focus()
	if f != null:
		f.grab_focus()
	# Wired after the first grab, so opening a screen is silent and only
	# moving around it ticks.
	_wire_focus_sounds(screen)
	await _fade_to(0.0, FADE_IN)
	if my != _show_gen:
		return
	transitioning = false
	screen_changed.emit(name)


## Drops the current screen at once; the match underneath is the transition.
func close_screen() -> void:
	_show_gen += 1
	_drop_pending()
	transitioning = false
	_free_screen()
	screen_name = ""
	match_scene.set_hud_visible(true)
	_fade.color.a = 0.0
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()


func toggle_pause() -> void:
	var tree := get_tree()
	if tree.paused:
		tree.paused = false
		close_screen()
		match_scene.refocus()
	else:
		tree.paused = true
		# The pause key has no button to click: it sounds like Esc.
		Sfx.play("ui_back")
		show_screen("pause")


func abandon_run() -> void:
	get_tree().paused = false
	clear_save()
	run = null
	match_scene.set_idle(true)
	show_screen("main_menu", _menu_args())


func _make_screen(name: String) -> UiScreen:
	match name:
		"main_menu":
			return MainMenuScreen.new()
		"pause":
			return PauseScreen.new()
		"match_end":
			return MatchEndScreen.new()
		"reward":
			return RewardScreen.new()
		"deck":
			return DeckScreen.new()
		"run_end":
			return RunEndScreen.new()
		"settings":
			return SettingsScreen.new()
	return null


## Pause, and the screens opened from it, leave the tree paused.
static func _keeps_pause(name: String, args: Dictionary) -> bool:
	return PAUSE_FAMILY.has(name) or String(args.get("return", "")) == "pause"


## Every control on the screen that takes focus ticks when it gets it, so a
## gamepad can be heard moving. The hand does the same for its own cards.
static func _wire_focus_sounds(node: Node) -> void:
	if node is Control and (node as Control).focus_mode == Control.FOCUS_ALL:
		(node as Control).focus_entered.connect(func() -> void: Sfx.play("ui_move"))
	for child in node.get_children():
		_wire_focus_sounds(child)


func _free_screen() -> void:
	if screen != null and is_instance_valid(screen):
		_screens.remove_child(screen)
		screen.queue_free()
	screen = null


## Frees a screen whose fade-out was interrupted before it was shown.
func _drop_pending() -> void:
	if _pending != null and is_instance_valid(_pending) and _pending != screen:
		_pending.free()
	_pending = null


func _fade_to(alpha: float, seconds: float) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade, "color:a", alpha, 0.0 if _headless() else seconds)
	await _fade_tween.finished


static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


func _menu_args() -> Dictionary:
	return {"has_save": FileAccess.file_exists(save_path), "version": VERSION, "last_seed": last_seed}


## What the Reward screen shows about the opponent after this one.
func _reward_args() -> Dictionary:
	var next_stage := mini(run.stage + 1, RunState.STAGES - 1)
	var next_id: String = run.opponents[next_stage]
	var profile := OpponentLibrary.profile(next_id)
	var next_deck: Array = run.deck if next_id == OpponentLibrary.SHADOW else OpponentLibrary.deck_ids(next_id)
	return {
		"offer": run.offer.duplicate(),
		"trim_available": run.trim_available,
		"deck_size": run.deck.size(),
		"deck_max": RunState.DECK_MAX,
		"hearts": run.hearts,
		"stage": run.stage,
		"stages": RunState.STAGES,
		"next": {
			"id": next_id,
			"name": profile["name"],
			"blurb": profile["blurb"],
			"points_to_win": int(RunState.POINTS_TO_WIN[next_stage]),
			"deck_summary": CardLibrary.summary(next_deck),
			"boss": bool(profile["boss"]),
		},
	}


func _run_end_args() -> Dictionary:
	return {
		"won": run.phase == RunState.Phase.WON,
		"stage": run.stage,
		"opponent_name": run.opponent()["name"],
		"stats": run.stats.duplicate(),
		"seed": run.seed_value,
		"deck_size": run.deck.size(),
	}


# --- save file ---------------------------------------------------------------

func save_run() -> void:
	if run == null:
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("Director: cannot write %s (%s)" % [save_path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(run.to_dict()))
	f.close()


## Resumes the saved run; false (and no file) when there is none or it does
## not parse, so the menu can hide Continue.
func load_run() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	var loaded: RunState = null
	if typeof(parsed) == TYPE_DICTIONARY:
		loaded = RunState.from_dict(parsed)
	if loaded == null:
		push_warning("Director: %s is not a run this version can resume; removing it" % save_path)
		clear_save()
		return false
	run = loaded
	last_seed = run.seed_value
	return true


func clear_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


# --- input device ------------------------------------------------------------

func _track_device(event: InputEvent) -> void:
	var now := gamepad
	if event is InputEventJoypadButton:
		now = true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			now = true
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		now = false
	if now != gamepad:
		gamepad = now
		device_changed.emit(gamepad)
