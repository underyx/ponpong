## The starter deck. Deckbuilding later means adding to and editing this list.
class_name CardLibrary
extends RefCounted


static func topspin() -> Card:
	return Card.make("Topspin", "Loop it over. Reliable, a little pressure.",
		0.35, 0.80, BallType.SPIN,
		[BallType.FLAT, BallType.HIGH], [BallType.FAST],
		Color(0.95, 0.60, 0.25), 0.40, 1.0)


static func smash() -> Card:
	return Card.make("Smash", "Put it away. Wild against anything but a lob. Loves the deep row.",
		0.90, 0.45, BallType.FAST,
		[BallType.HIGH], [BallType.FAST, BallType.SPIN],
		Color(0.90, 0.30, 0.30), 0.18, 1.7, 1)


static func chop() -> Card:
	return Card.make("Chop", "Slice under it. Eats spin and pace for breakfast.",
		0.25, 0.85, BallType.SPIN,
		[BallType.SPIN, BallType.FAST], [BallType.HIGH],
		Color(0.45, 0.70, 0.95), 0.45, 0.85)


static func block() -> Card:
	return Card.make("Block", "Just get the paddle there. Safe, soft, flat.",
		0.15, 0.95, BallType.FLAT,
		[BallType.FAST], [],
		Color(0.75, 0.75, 0.80), 0.30, 1.0)


static func lob() -> Card:
	return Card.make("Lob", "Sky it deep. Buys time, hands them a smash.",
		0.10, 0.90, BallType.HIGH,
		[BallType.FAST], [BallType.HIGH],
		Color(0.60, 0.85, 0.60), 1.20, 0.6, 1)


static func drop_shot() -> Card:
	return Card.make("Drop Shot", "Dink it just over the net. Short row only, really.",
		0.70, 0.55, BallType.FLAT,
		[BallType.HIGH, BallType.SPIN], [BallType.FAST],
		Color(0.85, 0.65, 0.95), 0.22, 0.75, 0)


static func flick() -> Card:
	return Card.make("Flick", "A wristy, flat jab. Decent against everything, great against nothing.",
		0.50, 0.65, BallType.FAST,
		[], [],
		Color(0.95, 0.85, 0.40), 0.25, 1.3, 1)


## A 14-card starter deck with sensible ratios.
static func starter_deck() -> Array[Card]:
	var deck: Array[Card] = []
	for i in 3:
		deck.append(topspin())
	for i in 2:
		deck.append(smash())
	for i in 2:
		deck.append(chop())
	for i in 2:
		deck.append(block())
	for i in 2:
		deck.append(lob())
	for i in 2:
		deck.append(drop_shot())
	deck.append(flick())
	return deck
