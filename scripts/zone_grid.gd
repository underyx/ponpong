## Builds and owns the 2x5 zones on both halves, draws them on the table top,
## and answers "which zone is under this world point".
class_name ZoneGrid
extends Node3D

const HALF_LENGTH := 1.37
const HALF_WIDTH := 0.7625
const TOP_Y := 0.7625
const LIFT := 0.003

## Width of each lane across the table, as fractions. Edges are thin.
const COL_FRACTIONS := [0.12, 0.21, 0.34, 0.21, 0.12]
## Depth of the short (net side) and deep (end line) rows, as fractions.
const ROW_FRACTIONS := [0.62, 0.38]
const COL_RISK := [0.22, 0.08, 0.0, 0.08, 0.22]
const ROW_RISK := [0.0, 0.12]
const COL_REWARD := [0.28, 0.10, 0.0, 0.10, 0.28]
const ROW_REWARD := [0.0, 0.14]

const FILL_PLAYER := Color(0.12, 0.47, 0.38)
const FILL_OPPONENT := Color(0.13, 0.42, 0.44)
const HIGHLIGHT := {
	Zone.State.IDLE: Color(1.0, 0.8, 0.3),
	Zone.State.HOVER: Color(1.0, 0.92, 0.55),
	Zone.State.TARGET: Color(1.0, 0.55, 0.2),
	Zone.State.INCOMING: Color(0.55, 0.8, 1.0),
}

var zone_shader: Shader = preload("res://shaders/zone.gdshader")
var zones: Array[Zone] = []


func _ready() -> void:
	for side in [-1, 1]:
		_build_side(side)


func _build_side(side: int) -> void:
	var x_cursor := 0.0
	for row in 2:
		var depth: float = HALF_LENGTH * ROW_FRACTIONS[row]
		var z_cursor := -HALF_WIDTH
		for col in 5:
			var width: float = 2.0 * HALF_WIDTH * COL_FRACTIONS[col]
			var zone := Zone.new()
			zone.side = side
			zone.row = row
			zone.col = col
			var x0 := x_cursor if side > 0 else -(x_cursor + depth)
			zone.rect = Rect2(x0, z_cursor, depth, width)
			zone.risk = COL_RISK[col] + ROW_RISK[row]
			zone.reward = COL_REWARD[col] + ROW_REWARD[row]
			_make_mesh(zone)
			zones.append(zone)
			z_cursor += width
		x_cursor += depth


func _make_mesh(zone: Zone) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(zone.rect.size.x, zone.rect.size.y)
	var mat := ShaderMaterial.new()
	mat.shader = zone_shader
	mat.set_shader_parameter("fill", FILL_OPPONENT if zone.side > 0 else FILL_PLAYER)
	mat.set_shader_parameter("size", plane.size)
	mat.set_shader_parameter("risk", zone.risk)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = zone.center() + Vector3(0.0, TOP_Y + LIFT, 0.0)
	mi.name = "Zone_%s_%d_%d" % ["O" if zone.side > 0 else "P", zone.row, zone.col]
	add_child(mi)
	zone.mesh = mi
	zone.material = mat


func zones_on(side: int) -> Array[Zone]:
	return zones.filter(func(z: Zone) -> bool: return z.side == side)


func zone_at(world_point: Vector3) -> Zone:
	var p := Vector2(world_point.x, world_point.z)
	for z in zones:
		if z.rect.has_point(p):
			return z
	return null


func zone(side: int, row: int, col: int) -> Zone:
	for z in zones:
		if z.side == side and z.row == row and z.col == col:
			return z
	return null


## World position of a zone's centre, on the table surface.
func landing_point(z: Zone) -> Vector3:
	return z.center() + Vector3(0.0, TOP_Y, 0.0)


func set_state(z: Zone, state: Zone.State) -> void:
	z.state = state
	_apply(z)


func set_covered(side: int, cols: Array) -> void:
	for z in zones_on(side):
		z.covered = cols.has(z.col)
		_apply(z)


func clear_states(side: int) -> void:
	for z in zones_on(side):
		z.state = Zone.State.IDLE
		_apply(z)


func _apply(z: Zone) -> void:
	var strength := 0.0
	match z.state:
		Zone.State.HOVER:
			strength = 0.55
		Zone.State.TARGET:
			strength = 1.0
		Zone.State.INCOMING:
			strength = 0.8
	z.material.set_shader_parameter("highlight", strength)
	z.material.set_shader_parameter("highlight_color", HIGHLIGHT[z.state])
	z.material.set_shader_parameter("dim", 0.45 if z.covered else 0.0)
