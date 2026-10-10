## Every card in the game, the starter deck and the id lookups. Deckbuilding
## adds ids from the pool here; the rules only ever see Card instances made by
## by_id() so a deck can cross a wire or a save file as a list of strings.
class_name CardLibrary
extends RefCounted

## Every card id, in the order the pool is listed. The rarity pools, rewards and
## save validation all key off this list.
const ALL_IDS: Array[String] = ["topspin", "smash", "chop", "block", "lob", "drop_shot", "flick", "push", "drive",
	"backhand_flip", "fish", "kick_serve", "counter_drive", "loop", "line_chop", "lunge", "moonball", "ace_serve",
	"banana_flick", "breather", "flat_kill", "heavy_chop", "angle_drive", "last_gasp", "power_loop"]


# --- the starter seven --------------------------------------------------------

static func topspin() -> Card:
	return Card.make("topspin", "Topspin", "Loop it over. Reliable, a little pressure.",
		0.35, 0.80, BallType.SPIN,
		[BallType.FLAT, BallType.HIGH], [BallType.FAST],
		Color(0.95, 0.60, 0.25), 0.40, 1.0, -1, 1)


static func smash() -> Card:
	return Card.make("smash", "Smash", "Put it away. Wild against anything but a lob. Loves the deep row.",
		0.90, 0.45, BallType.FAST,
		[BallType.HIGH], [BallType.FAST, BallType.SPIN],
		Color(0.90, 0.30, 0.30), 0.18, 1.7, 1, 3)


static func chop() -> Card:
	return Card.make("chop", "Chop", "Slice under it. Eats spin and pace for breakfast.",
		0.25, 0.85, BallType.SPIN,
		[BallType.SPIN, BallType.FAST], [BallType.HIGH],
		Color(0.45, 0.70, 0.95), 0.45, 0.85, -1, 1)


static func block() -> Card:
	return Card.make("block", "Block", "Just get the paddle there. Safe, soft, flat.",
		0.15, 0.95, BallType.FLAT,
		[BallType.FAST], [],
		Color(0.75, 0.75, 0.80), 0.30, 1.0, -1, 0)


static func lob() -> Card:
	return Card.make("lob", "Lob", "Sky it deep. Buys time, hands them a smash.",
		0.10, 0.90, BallType.HIGH,
		[BallType.FAST], [BallType.HIGH],
		Color(0.60, 0.85, 0.60), 1.20, 0.6, 1, 0)


static func drop_shot() -> Card:
	return Card.make("drop_shot", "Drop Shot", "Dink it just over the net. Short row only, really.",
		0.70, 0.55, BallType.FLAT,
		[BallType.HIGH, BallType.SPIN], [BallType.FAST],
		Color(0.85, 0.65, 0.95), 0.22, 0.75, 0, 2)


static func flick() -> Card:
	return Card.make("flick", "Flick", "A wristy, flat jab. Decent against everything, great against nothing.",
		0.50, 0.65, BallType.FAST,
		[], [],
		Color(0.95, 0.85, 0.40), 0.25, 1.3, 1, 1)


# --- commons ------------------------------------------------------------------

static func push() -> Card:
	return Card.make("push", "Push", "Nudge it back with a bit of under. The polite option.",
		0.20, 0.90, BallType.SPIN,
		[BallType.SPIN], [BallType.FAST],
		Color(0.55, 0.80, 0.85), 0.28, 0.80, 0, 0)


static func drive() -> Card:
	return Card.make("drive", "Drive", "A firm, flat drive. The honest attack.",
		0.55, 0.68, BallType.FAST,
		[BallType.HIGH, BallType.FLAT], [BallType.SPIN],
		Color(0.95, 0.50, 0.35), 0.24, 1.4, 1, 1)


static func backhand_flip() -> Card:
	return Card.make("backhand_flip", "Backhand Flip", "Over the table, around the ball. Eats underspin.",
		0.55, 0.62, BallType.FLAT,
		[BallType.SPIN], [BallType.FAST],
		Color(0.95, 0.70, 0.55), 0.28, 1.2, 0, 1)


static func fish() -> Card:
	return Card.make("fish", "Fish", "Float it back and catch your breath.",
		0.08, 0.92, BallType.HIGH,
		[BallType.FAST, BallType.FLAT], [BallType.HIGH],
		Color(0.55, 0.80, 0.75), 1.40, 0.55, 1, 0, Card.Rarity.COMMON, "rest")


# Cost 2, not the 1 the pool was drafted with: at 1 the starter beat Oona Sato
# 10% of the time, under the 0.20 floor tests/balance.gd asserts.
static func kick_serve() -> Card:
	return Card.make("kick_serve", "Kick Serve", "Kicks up off the bounce. Only really a serve.",
		0.45, 0.72, BallType.SPIN,
		[BallType.NONE], [BallType.FAST],
		Color(0.95, 0.75, 0.35), 0.50, 1.0, 1, 2)


# --- uncommons ----------------------------------------------------------------

static func counter_drive() -> Card:
	return Card.make("counter_drive", "Counter Drive", "Take it on the rise. Their pace, your point.",
		0.65, 0.60, BallType.FAST,
		[BallType.FAST, BallType.HIGH], [BallType.SPIN],
		Color(0.95, 0.35, 0.55), 0.20, 1.6, -1, 1, Card.Rarity.UNCOMMON)


# Cost 3, not the 2 the pool was drafted with: at 2 the starter beat Oona Sato
# 10% of the time, under the 0.20 floor tests/balance.gd asserts.
static func loop() -> Card:
	return Card.make("loop", "Loop", "Wind up and brush it. It comes back wrong for them.",
		0.55, 0.70, BallType.SPIN,
		[BallType.FLAT, BallType.SPIN], [BallType.FAST],
		Color(0.95, 0.45, 0.15), 0.55, 0.9, 1, 3, Card.Rarity.UNCOMMON, "heavy")


static func line_chop() -> Card:
	return Card.make("line_chop", "Line Chop", "Hugs the sidelines without fear.",
		0.30, 0.75, BallType.SPIN,
		[BallType.SPIN, BallType.FAST], [BallType.HIGH],
		Color(0.35, 0.60, 0.90), 0.45, 0.85, -1, 1, Card.Rarity.UNCOMMON, "steady")


static func lunge() -> Card:
	return Card.make("lunge", "Lunge", "Stretch for it. Awkward balls cost nothing.",
		0.25, 0.72, BallType.FLAT,
		[BallType.FAST], [],
		Color(0.70, 0.80, 0.90), 0.30, 1.0, -1, 0, Card.Rarity.UNCOMMON, "reach")


static func moonball() -> Card:
	return Card.make("moonball", "Moonball", "So high they have to wait for it. Waiting is tiring.",
		0.08, 0.90, BallType.HIGH,
		[BallType.FAST, BallType.SPIN], [BallType.HIGH],
		Color(0.80, 0.95, 0.70), 1.60, 0.5, 1, 1, Card.Rarity.UNCOMMON, "sap")


static func ace_serve() -> Card:
	return Card.make("ace_serve", "Ace Serve", "First ball, last ball.",
		0.70, 0.55, BallType.FAST,
		[BallType.NONE], [BallType.FAST, BallType.SPIN],
		Color(0.95, 0.40, 0.45), 0.16, 1.6, 1, 2, Card.Rarity.UNCOMMON)


static func banana_flick() -> Card:
	return Card.make("banana_flick", "Banana Flick", "A flick with sidespin. Short, nasty.",
		0.60, 0.62, BallType.SPIN,
		[BallType.SPIN, BallType.FLAT], [BallType.FAST],
		Color(0.98, 0.85, 0.30), 0.30, 1.2, 0, 2, Card.Rarity.UNCOMMON)


static func breather() -> Card:
	return Card.make("breather", "Breather", "Float one back and breathe. Three deep breaths.",
		0.12, 0.88, BallType.FLAT,
		[], [BallType.FAST],
		Color(0.65, 0.90, 0.85), 0.50, 0.70, -1, 0, Card.Rarity.UNCOMMON, "rest")


# --- rares --------------------------------------------------------------------

static func flat_kill() -> Card:
	return Card.make("flat_kill", "Flat Kill", "One swing. Then it is gone.",
		0.95, 0.40, BallType.FAST,
		[BallType.HIGH, BallType.FLAT], [BallType.SPIN, BallType.FAST],
		Color(0.85, 0.20, 0.25), 0.15, 1.9, 1, 3, Card.Rarity.RARE, "exhaust")


static func heavy_chop() -> Card:
	return Card.make("heavy_chop", "Heavy Chop", "So much backspin they have to dig for it. Costs them.",
		0.30, 0.78, BallType.SPIN,
		[BallType.SPIN, BallType.FAST], [BallType.HIGH],
		Color(0.30, 0.50, 0.85), 0.50, 0.80, 1, 2, Card.Rarity.RARE, "sap")


static func angle_drive() -> Card:
	return Card.make("angle_drive", "Angle Drive", "Goes for the sidelines and usually finds them.",
		0.65, 0.55, BallType.FAST,
		[BallType.FLAT], [BallType.SPIN],
		Color(0.95, 0.65, 0.45), 0.22, 1.5, 0, 2, Card.Rarity.RARE, "steady")


static func last_gasp() -> Card:
	return Card.make("last_gasp", "Last Gasp", "Free. Once.",
		0.75, 0.60, BallType.FAST,
		[], [],
		Color(1.00, 0.95, 0.80), 0.25, 1.5, -1, 0, Card.Rarity.RARE, "exhaust")


static func power_loop() -> Card:
	return Card.make("power_loop", "Power Loop", "The loop that ends the point two shots later.",
		0.80, 0.60, BallType.SPIN,
		[BallType.FLAT, BallType.SPIN, BallType.HIGH], [BallType.FAST],
		Color(1.00, 0.40, 0.10), 0.50, 1.2, 1, 3, Card.Rarity.RARE, "heavy")


# --- lookups ------------------------------------------------------------------

## Rebuild a card from its id, for actions and snapshots that crossed the wire.
static func by_id(id: String) -> Card:
	match id:
		"topspin": return topspin()
		"smash": return smash()
		"chop": return chop()
		"block": return block()
		"lob": return lob()
		"drop_shot": return drop_shot()
		"flick": return flick()
		"push": return push()
		"drive": return drive()
		"backhand_flip": return backhand_flip()
		"fish": return fish()
		"kick_serve": return kick_serve()
		"counter_drive": return counter_drive()
		"loop": return loop()
		"line_chop": return line_chop()
		"lunge": return lunge()
		"moonball": return moonball()
		"ace_serve": return ace_serve()
		"banana_flick": return banana_flick()
		"breather": return breather()
		"flat_kill": return flat_kill()
		"heavy_chop": return heavy_chop()
		"angle_drive": return angle_drive()
		"last_gasp": return last_gasp()
		"power_loop": return power_loop()
	push_error("Unknown card id: %s" % id)
	return null


static func ids_of(cards: Array[Card]) -> Array:
	var out: Array = []
	for c in cards:
		out.append(c.id)
	return out


static func from_ids(ids: Array) -> Array[Card]:
	var out: Array[Card] = []
	for id in ids:
		out.append(by_id(String(id)))
	return out


## Ids of one rarity (a Card.Rarity value), in ALL_IDS order.
static func pool(rarity: int) -> Array[String]:
	var out: Array[String] = []
	for id in ALL_IDS:
		if by_id(id).rarity == rarity:
			out.append(id)
	return out


## "Smash x3, Drive x3, Flick x3, ...": a deck in one line, most copies first,
## ties by title. What the scouting panel shows about the next opponent.
static func summary(ids: Array) -> String:
	var counts: Dictionary = {}
	for id in ids:
		counts[String(id)] = int(counts.get(String(id), 0)) + 1
	var rows: Array = []
	for id in counts:
		rows.append([int(counts[id]), by_id(id).title])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] > b[0]
		return a[1] < b[1])
	var parts: Array[String] = []
	for row in rows:
		parts.append("%s x%d" % [row[1], row[0]])
	return ", ".join(parts)


## The starter deck as ids: what a new run begins with.
static func starter_ids() -> Array[String]:
	var out: Array[String] = []
	for id in ids_of(starter_deck()):
		out.append(String(id))
	return out


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
