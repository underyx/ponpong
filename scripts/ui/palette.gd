## Every colour and font the game draws with, in one place, so the 3D
## materials, the shaders' defaults, the UI kit, the card faces and the
## generated art agree. The look is a risograph print of a club hall: ink,
## paper, ping-pong orange and table blue, with the shadows gone violet and
## a halftone where the print thins out. tools/build_art.py carries the
## same values for the SVG assets; change both.
class_name Palette
extends RefCounted

## The dark of the print: outlines, panels over the match, the hall walls.
const INK := Color("1a1830")
const INK_SOFT := Color("2b2846")
## The paper the menus are printed on, and the light text over the scene.
const PAPER := Color("f5eedc")
const PAPER_BRIGHT := Color("fff9ea")
## Text that should recede: captions, footers, the second line.
const PAPER_DIM := Color("b9b2a3")
const INK_DIM := Color("6f6a84")
## The ball, the accent, the misregistered second colour under titles.
const ORANGE := Color("ff7a2e")
## Focus rings, your stamina, the gold of a rare card.
const YELLOW := Color("ffc83d")
## The table, and their stamina.
const BLUE := Color("2f6eb8")
const BLUE_DEEP := Color("214f8a")
const BLUE_LIGHT := Color("7db7f0")
## Good news: a strong matchup, a won match, an uncommon card.
const TEAL := Color("1fae8a")
## Bad news: a weak matchup, a lost heart, a tired card.
const PINK := Color("f0486e")
## Where the toon shader puts its shadows.
const VIOLET := Color("5a3f8e")
## The hall floor.
const WOOD := Color("c98b55")
const WOOD_DARK := Color("8c5a33")

## Card frames by Card.Rarity: paper, teal, gold.
const RARITY := {0: Color("e9e1cc"), 1: Color("1fae8a"), 2: Color("ffc83d")}
const RARITY_NAMES := {0: "Common", 1: "Uncommon", 2: "Rare"}

## Display type: Lilita One, for everything that shouts. Body type: Rubik,
## for everything that explains. Both are OFL fonts under assets/fonts.
static var display: Font = preload("res://theme/fonts/display.tres")
static var body: Font = preload("res://theme/fonts/body.tres")
static var body_medium: Font = preload("res://theme/fonts/body_medium.tres")
static var body_bold: Font = preload("res://theme/fonts/body_bold.tres")


## The two halves of the table, by Zone.side.
static func table_fill(side: int) -> Color:
	return BLUE if side > 0 else BLUE.lerp(BLUE_DEEP, 0.12)
