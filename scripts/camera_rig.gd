## The match camera and its feel: a trauma-driven shake, a fov punch on hard
## shots, a lean toward the landing lane, a dolly toward the server, a slow
## orbit around the table while the menus are up and a push-in when the match
## ends. It replaces the plain Camera3D in match.tscn; the presenter reaches
## it only through has_method(), so the scene also runs without it.
##
## The play pose is whatever the presenter's look_at() left the camera in,
## captured the first time anything here needs it. Every frame the transform
## is rebuilt from that pose plus the drift, the orbit blend and the lean, and
## the shake goes through h_offset/v_offset, so the effects compose instead of
## fighting over one transform. Pausable with the match.
class_name CameraRig
extends Camera3D

## Peak shake offset in metres at full trauma (trauma is squared first).
const SHAKE_MAX := 0.06
## Trauma lost per second.
const TRAUMA_DECAY := 2.5
## How fast the shake noise is sampled.
const SHAKE_RATE := 40.0
## Horizontal frame offset at a full lean, and how long the lean takes.
const LEAN := 0.05
const LEAN_TIME := 0.2
## Dolly toward the server at a point start, and how long it takes.
const DRIFT := 0.15
const DRIFT_TIME := 0.6
## How long the drift and the lean take to come back on a shot.
const SETTLE_TIME := 0.3
## Orbit around the table while the menus are up, in degrees per second,
## blending in and out over ORBIT_BLEND seconds.
const ORBIT_SPEED := 6.0
const ORBIT_BLEND := 0.8
const ORBIT_CENTER := Vector3(0.0, ZoneLayout.TOP_Y, 0.0)
## The fov punch: in fast, back slower.
const PUNCH_IN := 0.06
const PUNCH_OUT := 0.25
## Match over: the fov closes by this much over PUSH_IN_TIME.
const PUSH_IN := 8.0
const PUSH_IN_TIME := 1.2

## Off, shake() does nothing visible. The Settings screen flips this.
var shake_enabled := true
## 0..1, decays by itself; shake() adds to it.
var trauma := 0.0
## Current dolly along the table, in metres; tweened by serve_drift/settle.
var drift := 0.0
## Current lean, in metres of horizontal frame offset; tweened by lean/settle.
var lean_offset := 0.0

var _play_pose := Transform3D.IDENTITY
var _pose_captured := false
var _base_fov := 44.0
var _orbiting := false
var _orbit_blend := 0.0
var _orbit_angle := 0.0
var _time := 0.0
var _noise := FastNoiseLite.new()
var _drift_tween: Tween
var _lean_tween: Tween
var _fov_tween: Tween


func _ready() -> void:
	_base_fov = fov
	_noise.seed = 7
	_noise.frequency = 0.5


func _process(delta: float) -> void:
	_capture_pose()
	_time += delta
	if _orbiting:
		_orbit_angle += deg_to_rad(ORBIT_SPEED) * delta
	_orbit_blend = move_toward(_orbit_blend, 1.0 if _orbiting else 0.0, delta / ORBIT_BLEND)
	var play := Transform3D(_play_pose.basis, _play_pose.origin + Vector3(drift, 0.0, 0.0))
	if _orbit_blend > 0.0:
		transform = play.interpolate_with(_orbit_pose(), _orbit_blend)
	else:
		transform = play
	trauma = maxf(0.0, trauma - TRAUMA_DECAY * delta)
	var amount := trauma * trauma * SHAKE_MAX if shake_enabled else 0.0
	h_offset = lean_offset + amount * _noise.get_noise_1d(_time * SHAKE_RATE)
	v_offset = amount * _noise.get_noise_1d(_time * SHAKE_RATE + 100.0)


# --- API ----------------------------------------------------------------------

## Adds `amount` of trauma (0..1); the shake is trauma squared, so small hits
## barely register and a big one is a thump.
func shake(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)


## A quick fov kick of `delta_fov` degrees (negative zooms in), back in a beat.
func punch(delta_fov: float) -> void:
	_kill(_fov_tween)
	_fov_tween = create_tween()
	_fov_tween.tween_property(self, "fov", _base_fov + delta_fov, PUNCH_IN)
	_fov_tween.tween_property(self, "fov", _base_fov, PUNCH_OUT).set_ease(Tween.EASE_OUT)


## Leans the frame toward world z (the landing lane): the far lanes lean the
## full LEAN, the middle not at all. Undone by settle() on the next shot.
func lean(z: float) -> void:
	var target := clampf(z / ZoneLayout.HALF_WIDTH, -1.0, 1.0) * LEAN
	_kill(_lean_tween)
	_lean_tween = create_tween()
	_lean_tween.tween_property(self, "lean_offset", target, LEAN_TIME).set_ease(Tween.EASE_OUT)


## Dollies DRIFT metres toward the server's end of the table over DRIFT_TIME.
## Undone by settle() on the first shot.
func serve_drift(server: int) -> void:
	_kill(_drift_tween)
	_drift_tween = create_tween()
	_drift_tween.tween_property(self, "drift", DRIFT * float(MatchState.side_of(server)), DRIFT_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Brings the drift and the lean back to the play pose: every swing.
func settle() -> void:
	_kill(_drift_tween)
	_kill(_lean_tween)
	_drift_tween = create_tween()
	_drift_tween.tween_property(self, "drift", 0.0, SETTLE_TIME).set_ease(Tween.EASE_OUT)
	_lean_tween = create_tween()
	_lean_tween.tween_property(self, "lean_offset", 0.0, LEAN_TIME).set_ease(Tween.EASE_OUT)


## On: circle the table slowly, for the menus. Off: blend back to the play
## pose over ORBIT_BLEND. Either way the shot effects are cleared and the fov
## is back to base, so a match never inherits the last one's push-in.
func orbit(on: bool) -> void:
	_capture_pose()
	if on and not _orbiting:
		_orbit_angle = 0.0
	_orbiting = on
	_kill(_drift_tween)
	_kill(_lean_tween)
	_kill(_fov_tween)
	drift = 0.0
	lean_offset = 0.0
	trauma = 0.0
	fov = _base_fov


## Match over: the fov closes slowly on the table.
func push_in() -> void:
	_kill(_fov_tween)
	_fov_tween = create_tween()
	_fov_tween.tween_property(self, "fov", _base_fov - PUSH_IN, PUSH_IN_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# --- helpers --------------------------------------------------------------------

## The play pose is the transform the camera has when first asked: after the
## presenter's look_at() in its _ready, before the first frame.
func _capture_pose() -> void:
	if _pose_captured:
		return
	_pose_captured = true
	_play_pose = transform


## Where the camera is on its circle at the current angle, looking at the
## middle of the table.
func _orbit_pose() -> Transform3D:
	var around := (_play_pose.origin - ORBIT_CENTER).rotated(Vector3.UP, _orbit_angle)
	var origin := ORBIT_CENTER + around
	return Transform3D(Basis.looking_at(ORBIT_CENTER - origin, Vector3.UP), origin)


static func _kill(t: Tween) -> void:
	if t != null and t.is_valid():
		t.kill()
