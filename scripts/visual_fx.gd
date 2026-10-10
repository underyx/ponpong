## Everything that moves on screen because of a feel moment: the camera rig,
## the ball trail, the impact particles, the paddle squash, the net wobble,
## the zone flashes, the score pop and the stamina pips. A node under the
## Match root; it subscribes to the presenter's `fx` signal and the ball's
## contact signals in _ready and is never called by name. The presenter
## emits, this node reacts, and the audio node does the same on its own.
class_name VisualFx
extends Node

const SHAKE_SWING := 0.45
const SHAKE_WINNER := 0.3
const SHAKE_NET := 0.15
## Swings at least this powerful shake the camera.
const HEAVY_SWING := 0.8
## Trail width by shot power: a lob leaves a thread, a smash a streak.
const TRAIL_WIDTH_MIN := 0.6
const TRAIL_WIDTH_MAX := 1.4
## The trail wears the card's colour pushed this far toward white, so a
## green card still shows over the green table; the puff and the ring a
## little less, since they sit on a lit zone.
const TRAIL_LIGHTEN := 0.35
const IMPACT_LIGHTEN := 0.3
## How much the zone under a bounce brightens: enough to mark the landing,
## not so much that the puff and the ring vanish against it. A winner gets
## the full flash when the point is called.
const BOUNCE_FLASH := 0.45
const SQUASH := Vector3(1.15, 0.85, 1.15)
const SQUASH_TIME := 0.08
## Net.scale.y after a net fault, in three steps of NET_WOBBLE_TIME / 3.
const NET_WOBBLE := [0.85, 1.05, 1.0]
const NET_WOBBLE_TIME := 0.3
const SCORE_POP := 1.25
const SCORE_FLASH_TIME := 0.4
const RALLY_POP := 1.3
const RALLY_POP_TIME := 0.3
const PIP_POP := 1.4
const PIP_POP_TIME := 0.25
const PIP_FLASH_TIME := 0.4
## The pip row shakes this far, in pixels, when a player hits 0.
const BAR_SHAKE := 3.0
const BAR_SHAKE_STEP := 0.05

var match_scene: MatchScene
var rig: CameraRig
var trail: BallTrail
var impact: ImpactFx
var grid: ZoneGrid
var paddles: Array[Node3D] = []
var net: Node3D
var score_label: Control
var rally_label: Control
## The two stamina pip rows, yours then theirs.
var pips: Array[HBoxContainer] = []

## Colour of the card last swung: what the bounce puff and ring wear.
var _color := UiKit.GOLD
var _paddle_tweens: Array[Tween] = [null, null]
var _pip_tweens: Dictionary = {}
var _score_tween: Tween
var _rally_tween: Tween
var _net_tween: Tween
var _bar_tween: Tween
var _bar_row: Control
var _bar_base := 0.0
## The presenter's idle flag as last seen. Its rising edge is a match torn
## down with nothing in flight reported (an abandon mid-flight emits no
## `landed`), so everything resets then. Starts true: the Director puts the
## scene idle at boot, after _bind(), and that must not count as an edge, or
## the effects' warm-up draws would be cut short.
var _was_idle := true


func _ready() -> void:
	match_scene = get_parent() as MatchScene
	if match_scene == null:
		match_scene = owner as MatchScene
	if match_scene == null:
		push_warning("VisualFx: not under a MatchScene, doing nothing")
		return
	match_scene.fx.connect(_on_fx)
	# The HUD rows this reads are built in the presenter's _ready, which runs
	# after this one: bind once the scene is ready.
	if match_scene.is_node_ready():
		_bind()
	else:
		match_scene.ready.connect(_bind, CONNECT_ONE_SHOT)


func _bind() -> void:
	rig = match_scene.camera as CameraRig
	trail = match_scene.get_node_or_null("World/Trail") as BallTrail
	impact = match_scene.get_node_or_null("World/ImpactFx") as ImpactFx
	grid = match_scene.grid
	paddles = match_scene.paddles
	net = match_scene.get_node_or_null("World/Table/Net") as Node3D
	score_label = match_scene.get_node_or_null("%ScoreLabel") as Control
	rally_label = match_scene.get_node_or_null("%RallyLabel") as Control
	pips = [
		match_scene.get_node_or_null("%MyPips") as HBoxContainer,
		match_scene.get_node_or_null("%TheirPips") as HBoxContainer,
	]
	if match_scene.ball != null:
		match_scene.ball.bounced.connect(_on_bounced)
		match_scene.ball.netted.connect(_on_netted)


## Pausable with the match; abandon_run() unpauses before it idles the
## scene, so the edge is seen on the next frame.
func _process(_delta: float) -> void:
	if match_scene == null or match_scene.idle == _was_idle:
		return
	_was_idle = match_scene.idle
	if _was_idle:
		_reset()


# --- the fx contract ------------------------------------------------------------

func _on_fx(fx_name: String, data: Dictionary) -> void:
	match fx_name:
		"match_start":
			_reset()
		"point_start":
			if rig != null:
				rig.serve_drift(int(data["server"]))
		"zone_commit":
			if grid != null:
				grid.commit_flash(data["zone"])
		"swing":
			_on_swing(data)
		"landed":
			_on_landed(data)
		"point":
			_pop_score(int(data["winner"]) == MatchScene.LOCAL)
		"rally":
			_pop_rally()
		"stamina":
			_on_stamina(data)
		"match_over":
			if rig != null:
				rig.push_in()


func _on_swing(data: Dictionary) -> void:
	var player := int(data["player"])
	var power := float(data["power"])
	_color = data["color"]
	if player >= 0 and player < paddles.size():
		_squash(player)
	if trail != null:
		trail.begin(_color.lightened(TRAIL_LIGHTEN), lerpf(TRAIL_WIDTH_MIN, TRAIL_WIDTH_MAX, clampf(power, 0.0, 1.0)))
	if rig != null:
		rig.settle()
		if power >= HEAVY_SWING:
			rig.shake(SHAKE_SWING)


func _on_landed(data: Dictionary) -> void:
	var outcome := int(data["outcome"])
	var zone: Zone = data["zone"]
	var pos: Vector3 = data["pos"]
	if trail != null:
		trail.end()
	# The zone already lit up at the bounce; a winner gets the full flash
	# with its ring, as the point is called.
	if outcome == RallyResolver.Outcome.WINNER:
		if grid != null:
			grid.landing_flash(zone)
		if impact != null:
			impact.hit(pos, _color)
		if rig != null:
			rig.shake(SHAKE_WINNER)
	if rig != null:
		rig.lean(pos.z)


## The bounce is where the ball lands: the puff, and the zone under it
## lights up now rather than when the flight ends at the far paddle. A net
## fault never bounces, so it never flashes a zone.
func _on_bounced(pos: Vector3) -> void:
	if impact != null:
		impact.bounce(pos, _color.lightened(IMPACT_LIGHTEN))
	if grid != null and grid.layout != null:
		grid.landing_flash(grid.layout.at_point(pos), BOUNCE_FLASH)


func _on_netted(pos: Vector3) -> void:
	if impact != null:
		impact.net(pos)
	_wobble_net()
	if rig != null:
		rig.shake(SHAKE_NET)


func _on_stamina(data: Dictionary) -> void:
	var player := int(data["player"])
	var value := int(data["value"])
	var delta := int(data["delta"])
	if player < 0 or player >= pips.size() or pips[player] == null:
		return
	var row := pips[player]
	var cells := _cells(row)
	if delta > 0:
		for i in range(maxi(value - delta, 0), mini(value, cells.size())):
			_pop_pip(cells[i])
	else:
		for i in range(maxi(value, 0), mini(value - delta, cells.size())):
			_flash_pip(cells[i])
	if value == 0:
		_shake_bar(row)


## The cells of a row made by UiKit.pips() (Panels) or UiKit.bolts()
## (TextureRect glyphs), in order.
static func _cells(row: Control) -> Array[Control]:
	var out: Array[Control] = []
	for child in row.get_children():
		if child is Panel or child is TextureRect:
			out.append(child)
	return out


# --- 3D ------------------------------------------------------------------------------

## The paddle flattens against the ball and springs back.
func _squash(player: int) -> void:
	var paddle := paddles[player]
	_kill(_paddle_tweens[player])
	paddle.scale = SQUASH
	_paddle_tweens[player] = create_tween()
	_paddle_tweens[player].tween_property(paddle, "scale", Vector3.ONE, SQUASH_TIME).set_ease(Tween.EASE_OUT)


func _wobble_net() -> void:
	if net == null:
		return
	_kill(_net_tween)
	net.scale.y = 1.0
	_net_tween = create_tween()
	for y in NET_WOBBLE:
		_net_tween.tween_property(net, "scale:y", float(y), NET_WOBBLE_TIME / NET_WOBBLE.size())


# --- HUD -------------------------------------------------------------------------------

## The score swells and flashes gold for your point, red for theirs.
func _pop_score(good: bool) -> void:
	if score_label == null:
		return
	_kill(_score_tween)
	score_label.pivot_offset = score_label.size * 0.5
	score_label.scale = Vector2.ONE * SCORE_POP
	score_label.modulate = UiKit.GOLD if good else UiKit.DANGER
	_score_tween = create_tween().set_parallel(true)
	_score_tween.tween_property(score_label, "scale", Vector2.ONE, SCORE_FLASH_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_score_tween.tween_property(score_label, "modulate", Color.WHITE, SCORE_FLASH_TIME)


## RALLY 7: the label pops from its left edge.
func _pop_rally() -> void:
	if rally_label == null:
		return
	_kill(_rally_tween)
	rally_label.pivot_offset = Vector2(0.0, rally_label.size.y * 0.5)
	rally_label.scale = Vector2.ONE * RALLY_POP
	_rally_tween = create_tween()
	_rally_tween.tween_property(rally_label, "scale", Vector2.ONE, RALLY_POP_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A pip that just lit swells and settles.
func _pop_pip(pip: Control) -> void:
	_kill(_pip_tweens.get(pip))
	pip.pivot_offset = pip.size * 0.5
	pip.scale = Vector2.ONE * PIP_POP
	var t := create_tween()
	t.tween_property(pip, "scale", Vector2.ONE, PIP_POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pip_tweens[pip] = t


## A pip that just went out flashes pink, then settles into its empty grey:
## a glyph through its modulate, a Panel through its style.
func _flash_pip(pip: Control) -> void:
	_kill(_pip_tweens.get(pip))
	var empty := Color(UiKit.MUTED, UiKit.PIP_EMPTY_ALPHA)
	pip.pivot_offset = pip.size * 0.5
	pip.scale = Vector2.ONE * PIP_POP
	var t := create_tween().set_parallel(true)
	t.tween_property(pip, "scale", Vector2.ONE, PIP_POP_TIME).set_ease(Tween.EASE_OUT)
	if pip is TextureRect:
		pip.modulate = UiKit.DANGER
		t.tween_property(pip, "modulate", empty, PIP_FLASH_TIME)
	else:
		var style := pip.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			style.bg_color = UiKit.DANGER
			t.tween_property(style, "bg_color", empty, PIP_FLASH_TIME)
	_pip_tweens[pip] = t


## The whole row shivers when its player is out of stamina.
func _shake_bar(row: Control) -> void:
	_settle_bar()
	_bar_row = row
	_bar_base = row.position.x
	_bar_tween = create_tween()
	for dx in [BAR_SHAKE, -BAR_SHAKE, BAR_SHAKE * 0.6, 0.0]:
		_bar_tween.tween_property(row, "position:x", _bar_base + float(dx), BAR_SHAKE_STEP)


# --- housekeeping ----------------------------------------------------------------------

## A new match: nothing from the last one may still be moving.
func _reset() -> void:
	if trail != null:
		trail.clear()
	if impact != null:
		impact.stop_all()
	for p in paddles.size():
		_kill(_paddle_tweens[p])
		paddles[p].scale = Vector3.ONE
	_kill(_net_tween)
	if net != null:
		net.scale = Vector3.ONE
	_kill(_score_tween)
	if score_label != null:
		score_label.scale = Vector2.ONE
		score_label.modulate = Color.WHITE
	_kill(_rally_tween)
	if rally_label != null:
		rally_label.scale = Vector2.ONE
	for t in _pip_tweens.values():
		_kill(t)
	_pip_tweens.clear()
	for row in pips:
		if row != null:
			for cell in _cells(row):
				cell.scale = Vector2.ONE
	_settle_bar()


## Ends a bar shake where it is and puts the row back where its container
## had it.
func _settle_bar() -> void:
	if _bar_tween != null and _bar_tween.is_valid():
		_bar_tween.kill()
		if _bar_row != null and is_instance_valid(_bar_row):
			_bar_row.position.x = _bar_base
	_bar_row = null


static func _kill(t: Variant) -> void:
	if t is Tween and (t as Tween).is_valid():
		(t as Tween).kill()
