## Hit stop: a few frames of near-frozen time on a big hit, and the time scale
## the game goes back to afterwards. Static, so the presenter and the effects
## nodes share one token and a later stop always wins over an earlier one.
##
## The Director sets base_time_scale at boot (so --time-scale is honoured),
## turns it off headlessly, and calls reset() on every screen change so a
## stop can never outlive the match it was part of.
class_name Feel
extends RefCounted

## What Engine.time_scale returns to after a stop.
static var base_time_scale := 1.0
## Off under the headless driver, where frames are not time.
static var enabled := true
static var _token := 0


## Drops the time scale to `scale` for `seconds` of real time, then restores
## it, unless a newer stop or a reset() took over meanwhile. Nothing happens
## while the tree is paused: the pause menu owns the clock then.
static func hit_stop(tree: SceneTree, seconds := 0.07, scale := 0.05) -> void:
	if not enabled or tree.paused:
		return
	_token += 1
	var my := _token
	Engine.time_scale = scale
	# Processes while paused and ignores the time scale it just set, so the
	# stop cannot freeze itself.
	await tree.create_timer(seconds, true, false, true).timeout
	if my == _token:
		Engine.time_scale = base_time_scale


## Ends any stop at once and restores the base time scale.
static func reset() -> void:
	_token += 1
	Engine.time_scale = base_time_scale
