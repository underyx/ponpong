## Turns "this card against that incoming ball" into a shot outcome.
## Pure logic, no nodes, so it can be unit-tested or tuned in isolation.
class_name RallyResolver
extends RefCounted

enum Outcome { FAULT, WINNER, RETURNED }

const STRONG_BONUS := 0.25
const WEAK_PENALTY := 0.35
const NOISE := 0.15
const LAND_THRESHOLD := 0.45
## How much of a card's power converts into an outright winner.
const WINNER_SCALE := 0.75


## Returns {outcome, quality, card, incoming}.
static func resolve(card: Card, incoming: int, rng: RandomNumberGenerator) -> Dictionary:
	var quality := card.control
	if card.is_strong_vs(incoming):
		quality += STRONG_BONUS
	if card.is_weak_vs(incoming):
		quality -= WEAK_PENALTY
	quality += rng.randf_range(-NOISE, NOISE)

	var outcome := Outcome.RETURNED
	if quality < LAND_THRESHOLD:
		outcome = Outcome.FAULT
	else:
		var pressure := card.power
		if card.is_strong_vs(incoming):
			pressure += 0.15
		if rng.randf() < pressure * WINNER_SCALE:
			outcome = Outcome.WINNER

	return {
		"outcome": outcome,
		"quality": quality,
		"card": card,
		"incoming": incoming,
	}
