## One playable shot. Cards live in the deck; playing one resolves a shot.
class_name Card
extends Resource

enum Rarity { COMMON, UNCOMMON, RARE }

## Every keyword a card may carry; "" is none. One keyword per card, no stacking.
const KEYWORDS := ["", "rest", "sap", "exhaust", "steady", "reach", "heavy"]
## The one line of card text each keyword shows.
const KEYWORD_HELP := {
	"rest": "Rest: +2 stamina.",
	"sap": "Sap: they lose 2 stamina.",
	"exhaust": "Exhaust: once per match.",
	"steady": "Steady: half the zone risk.",
	"reach": "Reach: awkward balls do not matter.",
	"heavy": "Heavy: their reply is harder.",
}

## Stable identifier used when a card is sent over the wire or saved.
@export var id: String = "shot"
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
## Stamina paid to play it. Over budget is still legal, but the shot is tired.
@export_range(0, 3) var cost: int = 1
@export var rarity: int = Rarity.COMMON
## One of KEYWORDS; "" for none.
@export var keyword: String = ""


static func make(p_id: String, p_title: String, p_flavor: String, p_power: float, p_control: float,
		p_produces: int, p_strong: Array[int], p_weak: Array[int], p_color: Color,
		p_arc: float, p_speed: float, p_prefers_row: int = -1,
		p_cost: int = 1, p_rarity: int = Rarity.COMMON, p_keyword: String = "") -> Card:
	var c := Card.new()
	c.id = p_id
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
	c.cost = p_cost
	c.rarity = p_rarity
	c.keyword = p_keyword
	return c


func is_strong_vs(incoming: int) -> bool:
	return strong_vs.has(incoming)


func is_weak_vs(incoming: int) -> bool:
	return weak_vs.has(incoming)


func likes_row(row: int) -> bool:
	return prefers_row == row


## The keyword's card text, or "" when the card has none.
func keyword_text() -> String:
	return KEYWORD_HELP.get(keyword, "")
