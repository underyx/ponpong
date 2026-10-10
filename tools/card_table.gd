## Prints every card in CardLibrary as a Markdown table, so the README's card
## list is generated from the code and cannot drift from it.
## Usage: godot --headless --path . -s tools/card_table.gd
## Paste the output over the table in README.md.
extends SceneTree

const RARITY_NAMES := {Card.Rarity.COMMON: "common", Card.Rarity.UNCOMMON: "uncommon", Card.Rarity.RARE: "rare"}
const ROW_NAMES := {-1: "-", 0: "short", 1: "deep"}
const COLUMNS := ["id", "title", "cost", "rarity", "power", "control", "produces", "strong vs", "weak vs", "row", "keyword", "flavor"]


func _initialize() -> void:
	print("| " + " | ".join(COLUMNS) + " |")
	var rule: Array[String] = []
	for c in COLUMNS:
		rule.append("---")
	print("| " + " | ".join(rule) + " |")
	for id in CardLibrary.ALL_IDS:
		var card := CardLibrary.by_id(id)
		if card == null:
			continue
		print("| " + " | ".join(_row(card)) + " |")
	quit(0)


func _row(card: Card) -> Array[String]:
	return [
		_cell(card.id),
		_cell(card.title),
		str(card.cost),
		String(RARITY_NAMES.get(card.rarity, str(card.rarity))),
		"%.2f" % card.power,
		"%.2f" % card.control,
		BallType.label(card.produces),
		_types(card.strong_vs),
		_types(card.weak_vs),
		String(ROW_NAMES.get(card.prefers_row, str(card.prefers_row))),
		card.keyword if card.keyword != "" else "-",
		_cell(card.flavor),
	]


## "Flat, High", or "-" for none.
static func _types(types: Array[int]) -> String:
	if types.is_empty():
		return "-"
	var names: Array[String] = []
	for t in types:
		names.append(BallType.label(t))
	return ", ".join(names)


## A table cell must not carry a pipe or a line break.
static func _cell(text: String) -> String:
	return text.replace("|", "\\|").replace("\n", " ")
