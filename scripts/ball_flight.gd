## Moves the ball along quadratic curves with tweens. No physics anywhere.
class_name BallFlight
extends Node3D

var _tween: Tween
var _squash_tween: Tween


## Kills the flight and the bounce squash. A killed tween never emits
## `finished`, so a shot() suspended on either is dropped with it, and the
## ball is left round for whatever places it next.
func stop() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	if _squash_tween and _squash_tween.is_valid():
		_squash_tween.kill()
	scale = Vector3.ONE


## Fly from the current position to `to`, peaking `apex` above the higher
## endpoint, over `duration` seconds. Awaitable.
func fly_to(to: Vector3, apex: float, duration: float) -> void:
	stop()
	var from := global_position
	var mid := (from + to) * 0.5
	var top := maxf(from.y, to.y) + apex
	# Control point height so the curve's apex lands on `top`.
	var ctrl := Vector3(mid.x, 2.0 * top - (from.y + to.y) * 0.5, mid.z)
	_tween = create_tween()
	_tween.tween_method(
		func(t: float) -> void:
			global_position = _quadratic(from, ctrl, to, t)
			rotation.z -= 0.35,
		0.0, 1.0, duration)
	await _tween.finished


## A two-leg shot: paddle to bounce point, then bounce point to the far paddle.
func shot(bounce: Vector3, to: Vector3, apex: float, speed: float) -> void:
	var base := 0.42 / speed
	await fly_to(bounce, apex, base)
	await _squash()
	await fly_to(to, apex * 0.6, base * 0.8)


## Fault: the ball thuds into the net and drops back on the shooter's side.
func into_net(net_point: Vector3, speed: float, from_side: int = -1) -> void:
	await fly_to(net_point, 0.08, 0.3 / speed)
	var drop := net_point + Vector3(0.08 * float(from_side), -0.12, 0.0)
	await fly_to(drop, 0.02, 0.25)


func _squash() -> void:
	_squash_tween = create_tween()
	_squash_tween.tween_property(self, "scale", Vector3(1.3, 0.7, 1.3), 0.04)
	_squash_tween.tween_property(self, "scale", Vector3.ONE, 0.07)
	await _squash_tween.finished


static func _quadratic(a: Vector3, c: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(c, t).lerp(c.lerp(b, t), t)
