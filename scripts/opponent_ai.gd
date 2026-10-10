## The opponent does not hold cards yet. They stand in a lane, answer each shot
## type with a plausible reply, and aim it at a zone on your side.
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

## Which row each reply type tends to land in: weight for short, weight for deep.
const ROW_BY_TYPE := {
	BallType.FLAT: [1, 1],
	BallType.HIGH: [1, 3],
	BallType.SPIN: [3, 1],
	BallType.FAST: [1, 4],
}


static func reply_to(received: int, rng: RandomNumberGenerator) -> int:
	return _weighted_pick(REPLIES.get(received, REPLIES[BallType.FLAT]), rng)


static func serve(rng: RandomNumberGenerator) -> int:
	return _weighted_pick(SERVES, rng)


## Pick a landing zone on the player's side for a reply of `type`, trying to
## play away from the lane the player is standing in while mostly avoiding edges.
static func aim(grid: ZoneGrid, type: int, player_col: int, rng: RandomNumberGenerator) -> Zone:
	var row_weights: Array = ROW_BY_TYPE.get(type, [1, 1])
	var row := _weighted_pick([[0, row_weights[0]], [1, row_weights[1]]], rng)
	var col_table: Array = []
	for col in 5:
		var w := 4
		if col == 0 or col == 4:
			w = 1
		if absi(col - player_col) >= 2:
			w += 2
		elif col == player_col:
			w = maxi(1, w - 2)
		col_table.append([col, w])
	var col := _weighted_pick(col_table, rng)
	return grid.zone(-1, row, col)


## After hitting a reply the opponent drifts toward the middle, with some slack.
static func reposition(current_col: int, rng: RandomNumberGenerator) -> int:
	var options: Array = [[2, 3], [1, 2], [3, 2], [current_col, 2]]
	return _weighted_pick(options, rng)


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
