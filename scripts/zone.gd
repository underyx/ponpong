## One target area on the table. Each half is split 5 across by 2 deep.
class_name Zone
extends RefCounted

enum State { IDLE, HOVER, TARGET, INCOMING }

## +1 is the opponent's half, -1 the player's half.
var side: int
## 0 is the short row by the net, 1 the deep row by the end line.
var row: int
## 0..4 across the table, 0 and 4 being the narrow edge lanes.
var col: int
## In table space: x along the length, y across the width (world z).
var rect: Rect2
## 0..1, how easy the zone is to miss. Edges and the deep row are riskier.
var risk: float
## Pressure bonus for landing here: the same edges that are risky also win points.
var reward: float
var mesh: MeshInstance3D
var material: ShaderMaterial
var state: State = State.IDLE
var covered := false


func center() -> Vector3:
	var c := rect.get_center()
	return Vector3(c.x, 0.0, c.y)


func is_edge_col() -> bool:
	return col == 0 or col == 4


func is_deep() -> bool:
	return row == 1


func label() -> String:
	var depth := "deep" if is_deep() else "short"
	var lane: String = ["far-left", "left", "middle", "right", "far-right"][col]
	return "%s %s" % [depth, lane]
