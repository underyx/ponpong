## One playable shot. Cards live in the deck; playing one resolves a shot.
class_name Card
extends Resource

@export var title: String = "Shot"
@export_multiline var flavor: String = ""
## 0..1: how hard the shot is to return when it lands.
@export_range(0.0, 1.0) var power: float = 0.4
## 0..1: how likely the shot is to land at all, before modifiers.
@export_range(0.0, 1.0) var control: float = 0.7
## What the opponent sees coming after this shot.
@export var produces: int = BallType.FLAT
## Incoming ball types this card punishes.
@export var strong_vs: Array[int] = []
## Incoming ball types this card struggles against.
@export var weak_vs: Array[int] = []
@export var color: Color = Color(0.9, 0.9, 0.9)
## -1: no preference. 0: likes the short row by the net. 1: likes the deep row.
@export var prefers_row: int = -1
## Shape of the ball flight when played: apex height and duration multiplier.
@export var arc_height: float = 0.35
@export var speed: float = 1.0


static func make(p_title: String, p_flavor: String, p_power: float, p_control: float,
		p_produces: int, p_strong: Array[int], p_weak: Array[int], p_color: Color,
		p_arc: float, p_speed: float, p_prefers_row: int = -1) -> Card:
	var c := Card.new()
	c.title = p_title
	c.flavor = p_flavor
	c.power = p_power
	c.control = p_control
	c.produces = p_produces
	c.strong_vs = p_strong
	c.weak_vs = p_weak
	c.color = p_color
	c.arc_height = p_arc
	c.speed = p_speed
	c.prefers_row = p_prefers_row
	return c


func is_strong_vs(incoming: int) -> bool:
	return strong_vs.has(incoming)


func is_weak_vs(incoming: int) -> bool:
	return weak_vs.has(incoming)


func likes_row(row: int) -> bool:
	return prefers_row == row
