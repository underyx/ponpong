## One peer of a headless two-player match, for tools/check_online.sh. Boots
## the Director like the game does, opens the lobby, hosts or joins the given
## room on the given relay, then plays every local turn with random legal
## shots from its own RNG (never the match's, which would desync the peers)
## until the match ends. Prints one ONLINE_RESULT line with the final score in
## the state's own seats; the script checks both peers print the same one.
## Usage: godot --headless -s tests/online_peer.gd -- --role=host --code=TEST --relay=ws://127.0.0.1:1884/mqtt
extends SceneTree

const MAX_FRAMES := 30000
const TEST_SAVE := "user://online_peer_%s.json"
const TEST_SETTINGS := "user://online_peer_settings.cfg"

var director: Director
var role := "guest"
var code := "TEST"
var frames := 0
var rng := RandomNumberGenerator.new()
var plays := 0
var opened := false
var joined := false
var room: OnlineRoom
var result := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("--role="):
			role = a.substr(7)
		elif a.begins_with("--code="):
			code = a.substr(7)
	rng.seed = hash(role)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 1:
		_boot()
		return false
	if not result.is_empty():
		return _finish()
	if frames > MAX_FRAMES:
		result = "FAIL timed out after %d frames on screen '%s'" % [frames, director.screen_name]
		return _finish()
	if director.online != null and director.online != room:
		room = director.online
		room.ended.connect(func(reason: String) -> void: result = "FAIL room ended: %s" % reason)
		room.status_changed.connect(func(text: String) -> void: print("  [%5d] %s: %s" % [frames, role, text]))
	if director.transitioning:
		return false
	match director.screen_name:
		"main_menu":
			if not opened:
				opened = true
				director.screen.press("online")
		"online":
			if not joined:
				joined = true
				if role == "host":
					director._start_online(true, code)
				else:
					director.screen.press("join", {"code": code})
		"":
			_play()
	return false


func _boot() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	director = scene.instantiate()
	director.save_path = TEST_SAVE % role
	Settings.path = TEST_SETTINGS
	Settings.reset()
	root.add_child(director)
	director.match_scene.match_finished.connect(_on_match_finished)


## A random legal shot for the local seat, from this test's own RNG.
func _play() -> void:
	var m := director.match_scene
	if m.state == null or m.idle or not m.input_open or m.input_mode != MatchScene.InputMode.HAND:
		return
	var hand: Array = m._player(0).hand
	if hand.is_empty():
		return
	var pick := rng.randi_range(0, hand.size() - 1)
	var zones: Array = m.layout.zones_on(1)
	var zone: Zone = zones[rng.randi_range(0, zones.size() - 1)]
	plays += 1
	print("  [%5d] %s plays %s to %s (seat %d)" % [frames, role, (hand[pick] as Card).title, zone.label(), m.local_seat])
	m._on_card_chosen(pick)
	m.choose_zone(zone)


func _on_match_finished(winner: int, score: Array, _longest_rally: int, _stats: Array) -> void:
	var st := director.match_scene.state
	result = "ONLINE_RESULT role=%s seat=%d seed=%d score=%d-%d points=%d plays=%d view_winner=%d view_score=%s" % [
		role, director.match_scene.local_seat, st.seed_value, st.players[0].score, st.players[1].score,
		st.points_played, plays, winner, score]


func _finish() -> bool:
	print(result)
	var ok := result.begins_with("ONLINE_RESULT")
	print("online peer %s: %s" % [role, "OK" if ok else "FAILED"])
	quit(0 if ok else 1)
	return true
