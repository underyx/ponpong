## Draws a ZoneLayout on the table top and tints zones by state.
class_name ZoneGrid
extends Node3D

enum State { IDLE, HOVER, TARGET, INCOMING }

const LIFT := 0.003
const FILL_BOTTOM := Color(0.12, 0.47, 0.38)
const FILL_TOP := Color(0.13, 0.42, 0.44)
const HIGHLIGHT := {
	State.IDLE: Color(1.0, 0.8, 0.3),
	State.HOVER: Color(1.0, 0.92, 0.55),
	State.TARGET: Color(1.0, 0.55, 0.2),
	State.INCOMING: Color(0.55, 0.8, 1.0),
}

var zone_shader: Shader = preload("res://shaders/zone.gdshader")
var layout: ZoneLayout
var _materials: Dictionary = {}
var _states: Dictionary = {}
var _covered: Dictionary = {}


func build(p_layout: ZoneLayout) -> void:
	layout = p_layout
	for zone in layout.zones:
		_make_mesh(zone)
		_states[zone] = State.IDLE
		_covered[zone] = false


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


func clear_all() -> void:
	for z in layout.zones:
		_states[z] = State.IDLE
		_covered[z] = false
		_apply(z)


func _apply(z: Zone) -> void:
	var state: State = _states[z]
	var strength := 0.0
	match state:
		State.HOVER:
			strength = 0.55
		State.TARGET:
			strength = 1.0
		State.INCOMING:
			strength = 0.8
	var mat: ShaderMaterial = _materials[z]
	mat.set_shader_parameter("highlight", strength)
	mat.set_shader_parameter("highlight_color", HIGHLIGHT[state])
	mat.set_shader_parameter("dim", 0.45 if _covered[z] else 0.0)
