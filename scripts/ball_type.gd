## The kind of ball coming at a player. Cards are strong or weak against these.
class_name BallType
extends RefCounted

enum { NONE, FLAT, HIGH, SPIN, FAST }

const NAMES := {
	NONE: "Serve",
	FLAT: "Flat",
	HIGH: "High",
	SPIN: "Spin",
	FAST: "Fast",
}

const HINTS := {
	NONE: "You serve. Anything goes.",
	FLAT: "A neutral ball. Topspin or chop both work.",
	HIGH: "A floaty lob. Smash it, or drop it short.",
	SPIN: "Heavy backspin. Chop it back or loop it.",
	FAST: "A rocket. Block or lob, do not smash.",
}

static func label(type: int) -> String:
	return NAMES.get(type, "?")

static func hint(type: int) -> String:
	return HINTS.get(type, "")
