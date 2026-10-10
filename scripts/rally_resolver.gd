## Turns "this card, at that zone, against this incoming ball" into an outcome.
## Pure logic, no nodes, so it can be unit-tested or tuned in isolation.
class_name RallyResolver
extends RefCounted

enum Outcome { FAULT, WINNER, RETURNED }

const STRONG_BONUS := 0.25
const WEAK_PENALTY := 0.35
const NOISE := 0.15
const LAND_THRESHOLD := 0.45
## How much of the final pressure converts into an outright winner.
const WINNER_SCALE := 0.75
## How much an awkward incoming zone (edges, deep) hurts your control.
const REACH_PENALTY := 0.6
const ROW_PREF_BONUS := 0.15
## Aiming into the lane the opponent stands in, next to it, or away from it.
const COVER_CENTER := -0.18
const COVER_NEAR := -0.05
const COVER_OPEN := 0.15


## Everything that goes into one shot, before the dice.
class Shot:
	var card: Card
	var incoming_type: int
	var incoming_risk: float
	var target: Zone
	var opponent_col: int

	func quality() -> float:
		var q := card.control
		if card.is_strong_vs(incoming_type):
			q += STRONG_BONUS
		if card.is_weak_vs(incoming_type):
			q -= WEAK_PENALTY
		q -= target.risk
		q -= incoming_risk * REACH_PENALTY
		return q

	func pressure() -> float:
		var p := card.power + target.reward
		if card.is_strong_vs(incoming_type):
			p += 0.15
		if card.likes_row(target.row):
			p += ROW_PREF_BONUS
		var gap := absi(target.col - opponent_col)
		if gap == 0:
			p += COVER_CENTER
		elif gap == 1:
			p += COVER_NEAR
		else:
			p += COVER_OPEN
		return p


## Probabilities shown to the player before they commit: {land, win}.
static func odds(shot: Shot) -> Dictionary:
	var land := clampf((shot.quality() - LAND_THRESHOLD + NOISE) / (2.0 * NOISE), 0.0, 1.0)
	var win := clampf(shot.pressure() * WINNER_SCALE, 0.0, 1.0)
	return {"land": land, "win": win}


## Returns {outcome, quality, pressure}.
static func resolve(shot: Shot, rng: RandomNumberGenerator) -> Dictionary:
	var quality := shot.quality() + rng.randf_range(-NOISE, NOISE)
	var pressure := shot.pressure()
	var outcome := Outcome.RETURNED
	if quality < LAND_THRESHOLD:
		outcome = Outcome.FAULT
	elif rng.randf() < pressure * WINNER_SCALE:
		outcome = Outcome.WINNER
	return {"outcome": outcome, "quality": quality, "pressure": pressure}
