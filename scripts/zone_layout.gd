## The 2x5 zones on both halves: geometry, risk and reward. Pure data, built
## once and shared by the match state (for rules) and the ZoneGrid (for pixels).
class_name ZoneLayout
extends RefCounted

const HALF_LENGTH := 1.37
const HALF_WIDTH := 0.7625
const TOP_Y := 0.7625

## Width of each lane across the table, as fractions. Edges are thin.
const COL_FRACTIONS := [0.12, 0.21, 0.34, 0.21, 0.12]
## Depth of the short (net side) and deep (end line) rows, as fractions.
const ROW_FRACTIONS := [0.62, 0.38]
const COL_RISK := [0.22, 0.08, 0.0, 0.08, 0.22]
const ROW_RISK := [0.0, 0.12]
const COL_REWARD := [0.28, 0.10, 0.0, 0.10, 0.28]
const ROW_REWARD := [0.0, 0.14]

var zones: Array[Zone] = []


func _init() -> void:
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
			zones.append(zone)
			z_cursor += width
		x_cursor += depth


func zones_on(side: int) -> Array[Zone]:
	return zones.filter(func(z: Zone) -> bool: return z.side == side)


func find(side: int, row: int, col: int) -> Zone:
	for z in zones:
		if z.side == side and z.row == row and z.col == col:
			return z
	return null


func from_dict(d: Dictionary) -> Zone:
	return find(int(d["side"]), int(d["row"]), int(d["col"]))


func at_point(world_point: Vector3) -> Zone:
	var p := Vector2(world_point.x, world_point.z)
	for z in zones:
		if z.rect.has_point(p):
			return z
	return null


## Across-the-table position of a lane's centre, in world z.
func lane_z(col: int) -> float:
	return find(1, 0, col).center().z
