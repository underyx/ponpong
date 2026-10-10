## The opponent roster: who you meet on a run, what they play and how they
## think. Pure data with no nodes, so a RunState can pick from it and a
## match config can carry an opponent across a wire as its id.
##
## Stage 0 is always the opener, stages 1-2 draw two of TIER_A, stages 3-4
## two of TIER_B and stage 5 one of BOSSES. "your_shadow" has no deck of its
## own: it plays a copy of the player's deck, which RunState.match_config()
## supplies.
class_name OpponentLibrary
extends RefCounted

const OPENER := "coach_pim"
const TIER_A: Array[String] = ["mara_vale", "jax_dunn", "dot_and_dash"]
const TIER_B: Array[String] = ["oona_sato", "big_rig", "kit_marlow"]
const BOSSES: Array[String] = ["ilse_varga", "your_shadow"]
const SHADOW := "your_shadow"

## Everything about one opponent. Decks are {card id: count} in the order the
## cards should be dealt into a deck; AI params feed AIController.choose().
const PROFILES := {
	# The tutorial: he feeds lobs to punish and picks loosely (greed 0.3 over
	# a wide spread), or his all-safe deck beats the starter 58% of the time.
	"coach_pim": {
		"name": "Coach Pim",
		"blurb": "Plays it safe and tells you so.",
		"deck": {"block": 3, "topspin": 2, "push": 2, "chop": 2, "lob": 5},
		"ai": {"greed": 0.30, "spread": 10, "aggression": 0.2, "row_bias": 0.0, "edge_bias": 0.0, "thrift": 0.5},
		"paddle_color": Color(0.45, 0.55, 0.75),
		"boss": false,
	},
	"mara_vale": {
		"name": "Mara \"Chopper\" Vale",
		"blurb": "Will not miss. Will not attack. Will wait for you to.",
		"deck": {"chop": 4, "line_chop": 3, "push": 2, "fish": 2, "block": 2, "heavy_chop": 1},
		"ai": {"greed": 0.60, "spread": 4, "aggression": -0.5, "row_bias": -0.3, "edge_bias": 0.3, "thrift": 0.6},
		"paddle_color": Color(0.25, 0.70, 0.65),
		"boss": false,
	},
	"jax_dunn": {
		"name": "Jax Dunn",
		"blurb": "Every ball is a kill ball if you believe.",
		"deck": {"smash": 2, "drive": 3, "flick": 3, "topspin": 2, "lob": 2, "block": 2},
		"ai": {"greed": 0.60, "spread": 3, "aggression": 0.7, "row_bias": 0.6, "edge_bias": 0.2, "thrift": 0.0},
		"paddle_color": Color(0.90, 0.25, 0.25),
		"boss": false,
	},
	"dot_and_dash": {
		"name": "Dot & Dash",
		"blurb": "Lob, lob, drop. Infuriating.",
		"deck": {"lob": 4, "fish": 3, "moonball": 2, "drop_shot": 2, "backhand_flip": 3},
		"ai": {"greed": 0.50, "spread": 5, "aggression": 0.3, "row_bias": 0.3, "edge_bias": 0.5, "thrift": 0.3},
		"paddle_color": Color(0.65, 0.85, 0.30),
		"boss": false,
	},
	# The spin wall. Drafted as loop x3, topspin x3, banana x2, kick serve x2,
	# chop x2, push x2, which the starter beat 10% of the time: every ball she
	# sent fed her own SPIN-strong replies. Her AI knobs do nothing to that,
	# so three of the spin feeders became lobs and a moonball, HIGH balls the
	# starter can smash, which puts her near 0.38.
	"oona_sato": {
		"name": "Oona Sato",
		"blurb": "Puts spin on her handshake.",
		"deck": {"loop": 3, "topspin": 1, "banana_flick": 2, "kick_serve": 1, "chop": 2, "push": 1, "lob": 3, "moonball": 1},
		"ai": {"greed": 0.75, "spread": 2, "aggression": 0.2, "row_bias": 0.0, "edge_bias": 0.4, "thrift": 0.2},
		"paddle_color": Color(0.60, 0.35, 0.80),
		"boss": false,
	},
	"big_rig": {
		"name": "Big Rig",
		"blurb": "A wall that hits back.",
		"deck": {"counter_drive": 3, "block": 2, "lunge": 1, "angle_drive": 2, "drive": 4, "flat_kill": 1, "breather": 1},
		"ai": {"greed": 0.70, "spread": 3, "aggression": 0.3, "row_bias": -0.2, "edge_bias": 0.6, "thrift": 0.4},
		"paddle_color": Color(0.55, 0.58, 0.62),
		"boss": false,
	},
	"kit_marlow": {
		"name": "Kit Marlow",
		"blurb": "Goes for the lines every time. Sometimes they are there.",
		"deck": {"ace_serve": 2, "drop_shot": 2, "angle_drive": 2, "kick_serve": 2, "flick": 2, "lob": 2, "last_gasp": 1, "smash": 1},
		"ai": {"greed": 0.60, "spread": 3, "aggression": 0.5, "row_bias": 0.0, "edge_bias": 0.8, "thrift": 0.0},
		"paddle_color": Color(0.95, 0.80, 0.25),
		"boss": false,
	},
	# Drafted with two each of smash, flat kill, loop, heavy chop, counter
	# drive and angle drive, she spent 31 stamina over 16 cards, played tired
	# 15% of the time and lost to the starter 71% of the time. Half the bombs
	# became drives and a backhand flip: cheaper, and the cards that win the
	# most points in the report.
	"ilse_varga": {
		"name": "Ilse Varga, Champion",
		"blurb": "Has already beaten you in her head.",
		"deck": {"smash": 1, "flat_kill": 1, "loop": 2, "heavy_chop": 2, "counter_drive": 2, "drive": 2, "backhand_flip": 1,
			"angle_drive": 1, "fish": 2, "breather": 1, "power_loop": 1},
		"ai": {"greed": 0.90, "spread": 2, "aggression": 0.3, "row_bias": 0.2, "edge_bias": 0.5, "thrift": 0.4},
		"paddle_color": Color(0.10, 0.08, 0.12),
		"boss": true,
	},
	"your_shadow": {
		"name": "Your Shadow",
		"blurb": "Plays your deck back at you. Greedy about it, too.",
		"deck": {},
		"ai": {"greed": 0.90, "spread": 2, "aggression": 0.0, "row_bias": 0.0, "edge_bias": 0.3, "thrift": 0.4},
		"paddle_color": Color(0.35, 0.10, 0.15),
		"boss": true,
	},
}


## {id, name, blurb, deck: {id: count}, ai: {...}, paddle_color, boss}.
## A fresh copy every call, so callers can edit it. Unknown ids push an
## error and return an empty dictionary.
static func profile(id: String) -> Dictionary:
	if not PROFILES.has(id):
		push_error("Unknown opponent id: %s" % id)
		return {}
	var p: Dictionary = (PROFILES[id] as Dictionary).duplicate(true)
	p["id"] = id
	return p


## The opponent's deck as a flat list of card ids, counts expanded in the
## order the profile lists them. Empty for your_shadow, whose deck is a copy
## of the player's and comes from RunState.match_config().
static func deck_ids(id: String) -> Array[String]:
	var out: Array[String] = []
	var p := profile(id)
	if p.is_empty():
		return out
	var deck: Dictionary = p["deck"]
	for card_id in deck:
		for i in int(deck[card_id]):
			out.append(String(card_id))
	return out


## Every opponent id, opener first, then tier A, tier B and the bosses.
static func all_ids() -> Array[String]:
	var out: Array[String] = [OPENER]
	out.append_array(TIER_A)
	out.append_array(TIER_B)
	out.append_array(BOSSES)
	return out
