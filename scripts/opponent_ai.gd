## The opponent does not hold cards yet. They answer each shot type with a
## plausible reply, which becomes the player's next incoming ball.
class_name OpponentAI
extends RefCounted

## For each ball type the opponent receives: weighted replies.
const REPLIES := {
	BallType.FLAT: [[BallType.FLAT, 3], [BallType.SPIN, 3], [BallType.FAST, 2], [BallType.HIGH, 1]],
	BallType.HIGH: [[BallType.FAST, 6], [BallType.FLAT, 2]],
	BallType.SPIN: [[BallType.SPIN, 4], [BallType.FLAT, 3], [BallType.HIGH, 1]],
	BallType.FAST: [[BallType.HIGH, 4], [BallType.FLAT, 3], [BallType.FAST, 1]],
}

const SERVES := [[BallType.SPIN, 4], [BallType.FLAT, 3], [BallType.FAST, 2]]


static func reply_to(received: int, rng: RandomNumberGenerator) -> int:
	return _weighted_pick(REPLIES.get(received, REPLIES[BallType.FLAT]), rng)


static func serve(rng: RandomNumberGenerator) -> int:
	return _weighted_pick(SERVES, rng)


static func _weighted_pick(table: Array, rng: RandomNumberGenerator) -> int:
	var total := 0
	for entry in table:
		total += int(entry[1])
	var roll := rng.randi_range(1, total)
	for entry in table:
		roll -= int(entry[1])
		if roll <= 0:
			return int(entry[0])
	return int(table[0][0])
