## A ribbon behind the ball in flight: the last few ball positions as a
## camera-facing triangle strip in an ImmediateMesh, rebuilt every frame in
## the colour of the card that hit it, thinning and fading toward the tail.
## begin() at the swing, end() when the ball lands; after end() the tail
## drains into the ball over a few frames instead of vanishing. A sibling of
## the Ball under World; it reads the ball through ball_path, nothing more.
class_name BallTrail
extends MeshInstance3D

## Positions remembered while active, one per frame.
const POINTS := 12
## Half-width of the ribbon at its head, in metres, before width_scale: as
## wide as the ball, so it reads as a comet tail and not a hair.
const WIDTH := 0.035
const HEAD_ALPHA := 0.8
## Points dropped per frame once the trail has ended.
const DRAIN := 2
## A sample closer than this to the last one is not recorded.
const MIN_STEP := 0.0005

@export var ball_path: NodePath = ^"../Ball"

var active := false
var color := Color(1.0, 0.85, 0.45)
var width_scale := 1.0

var _ball: Node3D
## In this node's local space, oldest first.
var _points: Array[Vector3] = []
var _mesh := ImmediateMesh.new()
var _drawn := false


func _ready() -> void:
	_ball = get_node_or_null(ball_path) as Node3D
	if _ball == null:
		push_warning("BallTrail: no ball at %s" % ball_path)
	mesh = _mesh
	material_override = _make_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_prime()


## Draws one ribbon under the floor, so the driver compiles the material at
## boot rather than at the first swing; it drains away on the first frame.
func _prime() -> void:
	_points = [Vector3(0.0, -10.0, 0.0), Vector3(0.01, -10.0, 0.0)]
	_rebuild()


func _process(_delta: float) -> void:
	if active and _ball != null:
		_push(to_local(_ball.global_position))
	else:
		for i in DRAIN:
			if not _points.is_empty():
				_points.pop_front()
	_rebuild()


## Starts recording behind the ball in `p_color`; `p_width_scale` multiplies
## WIDTH (a soft shot leaves a thread, a hard one a streak).
func begin(p_color: Color, p_width_scale := 1.0) -> void:
	color = p_color
	width_scale = p_width_scale
	_points.clear()
	active = true


## Stops recording; the tail drains into the ball over the next frames.
func end() -> void:
	active = false


## Drops the trail at once.
func clear() -> void:
	active = false
	_points.clear()
	_rebuild()


func _push(p: Vector3) -> void:
	if not _points.is_empty() and _points[_points.size() - 1].distance_to(p) < MIN_STEP:
		return
	_points.append(p)
	while _points.size() > POINTS:
		_points.pop_front()


## Two vertices per point, offset sideways in the plane facing the camera,
## narrowing and fading from the head to the tail.
func _rebuild() -> void:
	var n := _points.size()
	if n < 2:
		if _drawn:
			_mesh.clear_surfaces()
			_drawn = false
		return
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var eye := to_local(camera.global_position) if camera != null else Vector3(0.0, 10.0, 0.0)
	var half := WIDTH * width_scale
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var last_side := Vector3.FORWARD
	for i in n:
		var p := _points[i]
		var dir := _points[mini(i + 1, n - 1)] - _points[maxi(i - 1, 0)]
		var side := dir.cross(eye - p)
		if side.length_squared() < 1e-12:
			side = last_side
		else:
			side = side.normalized()
			last_side = side
		var t := float(i) / float(n - 1)
		# The alpha fades linearly; the width holds longer, so the ribbon
		# reads as a tail and not a thread.
		var w := half * sqrt(t)
		var c := Color(color.r, color.g, color.b, HEAD_ALPHA * t)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p + side * w)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p - side * w)
	_mesh.surface_end()
	_drawn = true


static func _make_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m
