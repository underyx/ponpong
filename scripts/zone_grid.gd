## Draws a ZoneLayout on the table top and tints zones by state, with the
## small motions that make aiming legible: a hovered zone breathes, a
## committed one flashes and settles, and the zone the ball lands in lights
## up for a moment on top of whatever state it is in. All of it runs in
## _process on the materials' own parameters, so it pauses with the match
## and needs no tweens to kill.
class_name ZoneGrid
extends Node3D

enum State { IDLE, HOVER, TARGET, INCOMING }

const LIFT := 0.003
## The table's blue, a shade lighter on the player's half so the near end
## reads as "yours" at a glance.
const FILL_BOTTOM := Color(0.23, 0.49, 0.78)
const FILL_TOP := Palette.BLUE
## A lighter blue under the cursor (with yellow brackets), orange where the
## shot is going, pink where theirs is coming.
const HIGHLIGHT := {
	State.IDLE: Palette.BLUE_LIGHT,
	State.HOVER: Palette.BLUE_LIGHT,
	State.TARGET: Palette.ORANGE,
	State.INCOMING: Palette.PINK,
}
## Highlight strength at rest, by state.
const STRENGTH := {
	State.IDLE: 0.0,
	State.HOVER: 0.55,
	State.TARGET: 1.0,
	State.INCOMING: 0.8,
}
## The hover highlight breathes between these, at HOVER_PULSE_RATE rad/s.
const HOVER_PULSE_LOW := 0.45
const HOVER_PULSE_HIGH := 0.65
const HOVER_PULSE_RATE := 5.0
## A commit lifts the highlight to 1.0, decaying back over this long...
const COMMIT_DECAY := 0.4
## ...with a white flash of this much on top, so it reads even when the
## zone turns into the target in the same frame.
const COMMIT_FLASH := 0.6
## The landing flash: `flash` 1 -> 0 over this long.
const FLASH_DECAY := 0.3

var zone_shader: Shader = preload("res://shaders/zone.gdshader")
var layout: ZoneLayout
var _materials: Dictionary = {}
var _states: Dictionary = {}
var _covered: Dictionary = {}
## Zone -> highlight boost from a commit, decaying to 0.
var _boost: Dictionary = {}
## Zone -> white flash, decaying to 0.
var _flash: Dictionary = {}
## Zones with something to update this frame (hovered, boosted or flashing).
var _animated: Dictionary = {}
var _time := 0.0


func build(p_layout: ZoneLayout) -> void:
	layout = p_layout
	for zone in layout.zones:
		_make_mesh(zone)
		_states[zone] = State.IDLE
		_covered[zone] = false


func _process(delta: float) -> void:
	_time += delta
	for z in _animated.keys():
		var boost: float = _boost.get(z, 0.0)
		var flash: float = _flash.get(z, 0.0)
		if boost > 0.0:
			boost = maxf(0.0, boost - delta / COMMIT_DECAY)
			_boost[z] = boost
		if flash > 0.0:
			flash = maxf(0.0, flash - delta / FLASH_DECAY)
			_flash[z] = flash
		var state: State = _states[z]
		var strength: float = STRENGTH[state]
		if state == State.HOVER:
			var pulse := 0.5 + 0.5 * sin(_time * HOVER_PULSE_RATE)
			strength = lerpf(HOVER_PULSE_LOW, HOVER_PULSE_HIGH, pulse)
		var mat: ShaderMaterial = _materials[z]
		mat.set_shader_parameter("highlight", maxf(strength, boost))
		mat.set_shader_parameter("flash", flash)
		if boost <= 0.0 and flash <= 0.0 and state != State.HOVER:
			_animated.erase(z)


func _make_mesh(zone: Zone) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(zone.rect.size.x, zone.rect.size.y)
	var mat := ShaderMaterial.new()
	mat.shader = zone_shader
	mat.set_shader_parameter("fill", FILL_TOP if zone.side > 0 else FILL_BOTTOM)
	mat.set_shader_parameter("size", plane.size)
	mat.set_shader_parameter("risk", zone.risk)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = zone.center() + Vector3(0.0, ZoneLayout.TOP_Y + LIFT, 0.0)
	mi.name = "Zone_%s_%d_%d" % ["T" if zone.side > 0 else "B", zone.row, zone.col]
	add_child(mi)
	_materials[zone] = mat


## World position of a zone's centre, on the table surface.
func landing_point(z: Zone) -> Vector3:
	return z.center() + Vector3(0.0, ZoneLayout.TOP_Y, 0.0)


func state_of(z: Zone) -> State:
	return _states.get(z, State.IDLE)


func set_state(z: Zone, state: State) -> void:
	_states[z] = state
	_apply(z)


func set_covered(side: int, cols: Array) -> void:
	for z in layout.zones_on(side):
		_covered[z] = cols.has(z.col)
		_apply(z)


func clear_states(side: int) -> void:
	for z in layout.zones_on(side):
		_states[z] = State.IDLE
		_apply(z)


## Every zone back to idle and dark, flashes included: a point start.
func clear_all() -> void:
	_boost.clear()
	_flash.clear()
	_animated.clear()
	for z in layout.zones:
		_states[z] = State.IDLE
		_covered[z] = false
		_materials[z].set_shader_parameter("flash", 0.0)
		_apply(z)


## The zone a shot was just committed to: full highlight, settling over
## COMMIT_DECAY, with a white flash on top.
func commit_flash(z: Zone) -> void:
	if z == null or not _materials.has(z):
		return
	_boost[z] = 1.0
	_flash[z] = maxf(COMMIT_FLASH, float(_flash.get(z, 0.0)))
	_animated[z] = true


## The zone the ball landed in: a white flash of `strength` (0..1) that
## fades over FLASH_DECAY and leaves the zone's state as it was. A flash
## never dims one already brighter.
func landing_flash(z: Zone, strength := 1.0) -> void:
	if z == null or not _materials.has(z):
		return
	_flash[z] = maxf(clampf(strength, 0.0, 1.0), float(_flash.get(z, 0.0)))
	_animated[z] = true


func _apply(z: Zone) -> void:
	var state: State = _states[z]
	var mat: ShaderMaterial = _materials[z]
	mat.set_shader_parameter("highlight", maxf(float(STRENGTH[state]), float(_boost.get(z, 0.0))))
	mat.set_shader_parameter("highlight_color", HIGHLIGHT[state])
	mat.set_shader_parameter("dim", 1.0 if _covered[z] else 0.0)
	mat.set_shader_parameter("bracket", 1.0 if state == State.HOVER else 0.0)
	if state == State.HOVER:
		_animated[z] = true
