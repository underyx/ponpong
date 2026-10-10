## The ball's impacts: a puff of little spheres where it bounces, a ring that
## spreads on the table under it, and a grey puff off the net. The three
## children are built in _ready from CPUParticles3D and a quad with a shader,
## so they render the same under software GL as on a desktop. VisualFx calls
## bounce(), hit() and net(); nothing here listens to anything.
class_name ImpactFx
extends Node3D

const PUFF_AMOUNT := 12
const PUFF_LIFETIME := 0.3
const PUFF_SPEED_MIN := 0.6
const PUFF_SPEED_MAX := 1.2
## Puff spheres are over half the ball's size and leave upward in a cone,
## so none of them is lost under the table top and a bounce in the far
## zones still reads from the match camera.
const PUFF_RADIUS := 0.02
const PUFF_SPREAD := 80.0
const NET_COLOR := Color(0.72, 0.70, 0.76)
## The ring quad's side, in metres, and how it spreads: scale RING_FROM -> 1
## while `fade` goes 1 -> 0, over RING_TIME. It starts at nearly half size
## so that it is already a ring, not a dot, in the frame after the bounce.
const RING_SIZE := 0.4
const RING_FROM := 0.45
const RING_TIME := 0.35
## Lifted off the table so the ring sits above the zone quads.
const RING_LIFT := 0.004
## A bounce ring is this much of a winner's.
const BOUNCE_RING := 0.6

var puff: CPUParticles3D
var net_puff: CPUParticles3D
var ring: MeshInstance3D

var _ring_material: ShaderMaterial
var _ring_tween: Tween


func _ready() -> void:
	puff = _make_puff("Puff", Color.WHITE)
	add_child(puff)
	ring = _make_ring()
	add_child(ring)
	net_puff = _make_puff("Net", NET_COLOR)
	add_child(net_puff)
	_prime()


## Draws each effect once, fully transparent, so the driver compiles their
## shaders at boot rather than on the first shot (a visible hitch on a slow
## GPU, and a lost frame under software GL).
func _prime() -> void:
	for p in [puff, net_puff]:
		p.global_position = Vector3(0.0, -10.0, 0.0)
		p.color = Color(1.0, 1.0, 1.0, 0.0)
		p.restart()
	ring.global_position = Vector3(0.0, -10.0, 0.0)
	_ring_material.set_shader_parameter("fade", 0.0)
	ring.visible = true
	_ring_tween = create_tween()
	_ring_tween.tween_interval(PUFF_LIFETIME)
	_ring_tween.tween_callback(ring.hide)


## The ball hit the table at `pos`: a puff and a small ring in the card's colour.
func bounce(pos: Vector3, color: Color) -> void:
	_burst(puff, pos, color)
	_spread_ring(pos, color, BOUNCE_RING)


## A winner landed at `pos`: the full ring.
func hit(pos: Vector3, color: Color) -> void:
	_spread_ring(pos, color, 1.0)


## The ball thudded into the net at `pos`: a grey puff.
func net(pos: Vector3) -> void:
	_burst(net_puff, pos, NET_COLOR)


## Stops everything at once, for a new match.
func stop_all() -> void:
	puff.emitting = false
	net_puff.emitting = false
	_kill_ring()
	ring.visible = false


func _burst(p: CPUParticles3D, pos: Vector3, color: Color) -> void:
	p.global_position = pos
	p.color = color
	p.restart()


func _spread_ring(pos: Vector3, color: Color, size: float) -> void:
	_kill_ring()
	ring.global_position = pos + Vector3(0.0, RING_LIFT, 0.0)
	ring.scale = Vector3.ONE * RING_FROM * size
	_ring_material.set_shader_parameter("color", color)
	_ring_material.set_shader_parameter("fade", 1.0)
	ring.visible = true
	_ring_tween = create_tween().set_parallel(true)
	_ring_tween.tween_property(ring, "scale", Vector3.ONE * size, RING_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_ring_tween.tween_method(_set_ring_fade, 1.0, 0.0, RING_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_ring_tween.chain().tween_callback(ring.hide)


func _set_ring_fade(value: float) -> void:
	_ring_material.set_shader_parameter("fade", value)


func _kill_ring() -> void:
	if _ring_tween != null and _ring_tween.is_valid():
		_ring_tween.kill()


static func _make_puff(p_name: String, color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = p_name
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = PUFF_AMOUNT
	p.lifetime = PUFF_LIFETIME
	p.direction = Vector3.UP
	p.spread = PUFF_SPREAD
	p.initial_velocity_min = PUFF_SPEED_MIN
	p.initial_velocity_max = PUFF_SPEED_MAX
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.0
	p.color = color
	var sphere := SphereMesh.new()
	sphere.radius = PUFF_RADIUS
	sphere.height = PUFF_RADIUS * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	sphere.material = m
	p.mesh = sphere
	return p


func _make_ring() -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(RING_SIZE, RING_SIZE)
	var mi := MeshInstance3D.new()
	mi.name = "Ring"
	mi.mesh = quad
	_ring_material = ShaderMaterial.new()
	_ring_material.shader = preload("res://shaders/ring.gdshader")
	mi.material_override = _ring_material
	# A quad faces +z; turn it to face up and lie on the table.
	mi.rotation.x = -PI / 2.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi
