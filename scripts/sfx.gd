## Every sound in the game, synthesised at boot. No audio files: each clip is
## a short AudioStreamWAV rendered from a small recipe (sines, squares,
## triangles, a seeded noise source and an envelope), soft-clipped, normalised
## and given a fade-out so nothing clicks. One node lives in main.tscn; the
## static play() reaches it from anywhere and does nothing when there is no
## Sfx in the tree, so screenshots and tests run without one.
##
## The match never calls this directly: the Director connects the match's
## `fx` signal and the ball's `bounced` / `netted` signals to on_fx(),
## on_bounced() and on_netted(), which map feel moments to clip names.
class_name Sfx
extends Node

## The one Sfx in the tree, or null.
static var instance: Sfx

const MIX_RATE := 22050
## AudioStreamPlayers sharing the work; a seventh sound steals the oldest.
const POOL_SIZE := 6
## Every clip is normalised to this peak before the soft clip's tail.
const PEAK := 0.7
## Fade-out at the end of every clip, so a cut tone never clicks.
const FADE_SECONDS := 0.005
## A clip never renders shorter than this: the very short ticks keep a
## silent tail, and every stream has enough data for a test to inspect.
const MIN_SECONDS := 0.03
## Seed of the noise source, so every boot sounds the same.
const NOISE_SEED := 7
## A swing this powerful is a smash.
const SMASH_POWER := 0.8
## Every clip built at boot, in this order.
const NAMES: Array[String] = ["paddle_hit", "smash_hit", "bounce", "net", "out", "winner", "point_won",
	"point_lost", "match_won", "match_lost", "heart_lost", "tired", "stamina_tick", "rally_up",
	"ui_move", "ui_accept", "ui_back", "card_select", "card_play", "reward_pick"]
## Per-clip trim in dB on top of the normalisation, so ticks sit under hits.
const GAIN_DB := {
	"ui_move": -10.0, "stamina_tick": -8.0, "card_select": -5.0, "card_play": -3.0,
	"bounce": -3.0, "net": -2.0, "paddle_hit": -2.0, "rally_up": -3.0,
}
## Note frequencies the recipes use.
const C5 := 523.25
const D4 := 293.66
const E5 := 659.25
const F4 := 349.23
const G4 := 392.00
const G5 := 783.99
const A4 := 440.00
const C6 := 1046.50
const E6 := 1318.51

## Clip name -> AudioStreamWAV.
var streams: Dictionary = {}

var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _noise_rng := RandomNumberGenerator.new()


func _ready() -> void:
	instance = self
	_build_streams()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "Player%d" % (i + 1)
		p.bus = "Master"
		add_child(p)
		_players.append(p)


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Plays clip `name` on a free player, with a little random pitch so repeats
## do not sound like a machine. Does nothing without an Sfx in the tree.
static func play(name: String, pitch_jitter := 0.05, volume_db := 0.0) -> void:
	if instance == null or not is_instance_valid(instance):
		return
	instance._play(name, pitch_jitter, volume_db)


func _play(name: String, pitch_jitter: float, volume_db: float) -> void:
	var stream: AudioStreamWAV = streams.get(name)
	if stream == null:
		push_warning("Sfx: no clip named '%s'" % name)
		return
	if _players.is_empty():
		return
	var player: AudioStreamPlayer = null
	for p in _players:
		if not p.playing:
			player = p
			break
	if player == null:
		player = _players[_next_player]
		_next_player = (_next_player + 1) % _players.size()
	player.stream = stream
	# Presenter side: a random pitch is allowed here.
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.volume_db = float(GAIN_DB.get(name, 0.0)) + volume_db
	player.play()


# --- the feel contract ---------------------------------------------------------

## A MatchScene `fx` moment, by name; see game.gd for the data of each.
func on_fx(name: String, data: Dictionary) -> void:
	match name:
		"swing":
			play("smash_hit" if float(data.get("power", 0.0)) >= SMASH_POWER else "paddle_hit", 0.06)
			if bool(data.get("tired", false)):
				play("tired")
		"landed":
			_on_landed(data)
		"point":
			play("point_won" if int(data.get("winner", -1)) == 0 else "point_lost", 0.02)
		"match_over":
			play("match_won" if bool(data.get("won", false)) else "match_lost", 0.0)
		"card_select":
			play("card_select")
		"zone_commit":
			play("card_play", 0.08)
		"rally":
			play("rally_up", 0.02)
		"stamina":
			if int(data.get("delta", 0)) < 0:
				play("stamina_tick")


## A fault into an out zone (an edge lane or the deep row) is the ball going
## long; a fault in the middle hits the net, which the ball reports itself.
## A winner by the local player gets its fanfare; theirs is the point sound.
func _on_landed(data: Dictionary) -> void:
	var zone: Zone = data.get("zone")
	if int(data.get("outcome", -1)) == RallyResolver.Outcome.FAULT:
		if zone != null and (zone.is_edge_col() or zone.is_deep()):
			play("out")
		return
	var kind := String(data.get("kind", ""))
	if (kind == "ace" or kind == "edge" or kind == "winner") and int(data.get("player", -1)) == 0:
		play("winner", 0.02)


func on_bounced(_position: Vector3) -> void:
	play("bounce", 0.08)


func on_netted(_position: Vector3) -> void:
	play("net")


# --- the recipes -------------------------------------------------------------------

func _build_streams() -> void:
	_noise_rng.seed = NOISE_SEED
	streams.clear()
	streams["paddle_hit"] = _synth(0.06, _paddle_sample)
	streams["smash_hit"] = _synth(0.18, func(t: float) -> float:
		return _paddle_sample(t) + 1.2 * _sine(60.0, t) * _env(t, 0.003, 0.09))
	streams["bounce"] = _synth(0.07, func(t: float) -> float:
		return _chirp(420.0, 260.0, 0.07, t) * _env(t, 0.001, 0.035))
	streams["net"] = _finish(_smooth(_render(0.18, func(t: float) -> float:
		return _noise() * _env(t, 0.002, 0.08)), 8))
	streams["out"] = _synth(0.12, func(t: float) -> float:
		return _chirp(300.0, 150.0, 0.12, t) * _env(t, 0.002, 0.07))
	streams["winner"] = _synth(0.24, func(t: float) -> float:
		return 0.5 * _sequence([C5, E5, G5], 0.08, t, _square, 0.05))
	streams["point_won"] = _synth(0.14, func(t: float) -> float:
		return _sequence([E5, A4 * 2.0], 0.07, t, _tri, 0.045))
	streams["point_lost"] = _synth(0.24, func(t: float) -> float:
		return _sequence([A4, D4], 0.12, t, _tri, 0.08))
	streams["match_won"] = _synth(0.5, func(t: float) -> float:
		return 0.6 * _sequence([C5, E5, G5, C6, E6], 0.1, t, _square, 0.07) \
			+ 0.5 * _sequence([C5, E5, G5, C6, E6], 0.1, t, _tri, 0.09))
	streams["match_lost"] = _synth(0.64, func(t: float) -> float:
		return _sequence([A4, G4, F4, D4], 0.16, t, _tri, 0.11))
	streams["heart_lost"] = _synth(0.25, func(t: float) -> float:
		return _chirp(110.0, 55.0, 0.25, t) * _env(t, 0.005, 0.15))
	streams["tired"] = _synth(0.3, func(t: float) -> float:
		return sin(TAU * 90.0 * t + 2.5 * sin(TAU * 6.0 * t)) * _env(t, 0.01, 0.18))
	streams["stamina_tick"] = _synth(0.02, func(t: float) -> float:
		return _sine(1200.0, t) * _env(t, 0.001, 0.007))
	streams["rally_up"] = _synth(0.15, func(t: float) -> float:
		return _sequence([600.0, 800.0, 1000.0], 0.05, t, _sine, 0.025))
	streams["ui_move"] = _synth(0.02, func(t: float) -> float:
		return _sine(1500.0, t) * _env(t, 0.001, 0.007))
	streams["ui_accept"] = _synth(0.05, func(t: float) -> float:
		return _chirp(800.0, 1200.0, 0.05, t) * _env(t, 0.002, 0.03))
	streams["ui_back"] = _synth(0.05, func(t: float) -> float:
		return _chirp(1200.0, 800.0, 0.05, t) * _env(t, 0.002, 0.03))
	streams["card_select"] = _synth(0.04, func(t: float) -> float:
		return _sine(600.0, t) * _env(t, 0.002, 0.02))
	streams["card_play"] = _whoosh(0.09)
	streams["reward_pick"] = _synth(0.4, func(t: float) -> float:
		var s := 0.0
		var notes := [E5, G5, C6]
		for i in notes.size():
			var local := t - 0.1 * i
			if local >= 0.0:
				var f: float = notes[i]
				s += (_sine(f, local) + 0.3 * _sine(2.0 * f, local)) * _env(local, 0.003, 0.12)
		return s)
	for name in NAMES:
		if not streams.has(name):
			push_error("Sfx: clip '%s' was not built" % name)


## 60 ms of noise with a fast decay under a 900 -> 500 Hz sweep: the paddle.
func _paddle_sample(t: float) -> float:
	return 0.8 * _noise() * exp(-60.0 * t) + _chirp(900.0, 500.0, 0.06, t) * _env(t, 0.001, 0.03)


## A rising noise whoosh: dark (smoothed) at the start, bright and loud at
## the end, cut by the clip's own fade.
func _whoosh(seconds: float) -> AudioStreamWAV:
	var raw := _render(seconds, func(_t: float) -> float: return _noise())
	var dark := _smooth(raw, 6)
	var n := raw.size()
	for i in n:
		var u := float(i) / float(n)
		raw[i] = lerpf(dark[i], raw[i], u) * pow(u, 1.5)
	return _finish(raw)


# --- the synthesiser -------------------------------------------------------------

## Renders `fn(t)` for `seconds` and turns it into a stream.
func _synth(seconds: float, fn: Callable) -> AudioStreamWAV:
	return _finish(_render(seconds, fn))


## `fn(t: float) -> float` sampled at MIX_RATE for `seconds` (at least
## MIN_SECONDS, the rest silent).
func _render(seconds: float, fn: Callable) -> PackedFloat32Array:
	var n := maxi(1, ceili(maxf(seconds, MIN_SECONDS) * MIX_RATE))
	var sound := ceili(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = float(fn.call(float(i) / MIX_RATE)) if i < sound else 0.0
	return out


## Soft clip, normalise to PEAK, fade the tail and pack as 16-bit mono.
func _finish(samples: PackedFloat32Array) -> AudioStreamWAV:
	var n := samples.size()
	var peak := 0.0
	for i in n:
		samples[i] = tanh(samples[i])
		peak = maxf(peak, absf(samples[i]))
	var gain := PEAK / peak if peak > 0.0 else 0.0
	var fade := mini(n, ceili(FADE_SECONDS * MIX_RATE))
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var s := samples[i] * gain
		if i >= n - fade:
			s *= float(n - i) / float(fade)
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## A running average over the last `window` samples: a crude low-pass that
## takes the hiss out of noise.
static func _smooth(samples: PackedFloat32Array, window: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(samples.size())
	var sum := 0.0
	for i in samples.size():
		sum += samples[i]
		if i >= window:
			sum -= samples[i - window]
		out[i] = sum / float(mini(i + 1, window))
	return out


static func _sine(f: float, t: float) -> float:
	return sin(TAU * f * t)


static func _square(f: float, t: float) -> float:
	return 1.0 if fmod(f * t, 1.0) < 0.5 else -1.0


static func _tri(f: float, t: float) -> float:
	return 4.0 * absf(fmod(f * t + 0.75, 1.0) - 0.5) - 1.0


## A sine whose pitch glides from `f0` to `f1` over `seconds`, with the phase
## integrated so the glide is smooth.
static func _chirp(f0: float, f1: float, seconds: float, t: float) -> float:
	return sin(TAU * (f0 * t + (f1 - f0) * t * t / (2.0 * seconds)))


func _noise() -> float:
	return _noise_rng.randf_range(-1.0, 1.0)


## A linear attack then an exponential decay with time constant `decay`.
static func _env(t: float, attack: float, decay: float) -> float:
	if t < attack:
		return t / attack
	return exp(-(t - attack) / decay)


## Notes in `freqs` played one after another, `each` seconds apart, each
## through `wave(f, t)` and a plucked envelope.
static func _sequence(freqs: Array, each: float, t: float, wave: Callable, decay: float) -> float:
	var index := clampi(int(t / each), 0, freqs.size() - 1)
	var local := t - each * index
	return float(wave.call(float(freqs[index]), local)) * _env(local, 0.003, decay)
