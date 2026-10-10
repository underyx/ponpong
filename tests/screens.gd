## Every screen class and CardView, without a window. Each screen is built
## from synthetic args in every mode it has, added under the root, and must
## hand out a focusable first_focus() and report every action its row in the
## design table lists through `done`, with its data. Every screen is also
## driven through its real buttons (a click must deliver the bound action),
## and CardView is filled with all 25 cards in hand mode (every incoming type,
## stamina 0 and 6) and in deck mode. Exit code 1 on any failure.
## Usage: godot --headless -s tests/screens.gd
extends SceneTree

const SCREENS_DIR := "res://scripts/screens/"
const INCOMING_TYPES := [BallType.NONE, BallType.FLAT, BallType.HIGH, BallType.SPIN, BallType.FAST]
const MATCH_STATS := [
	{"shots": 12, "winners": 5, "faults": 3, "tired_plays": 2},
	{"shots": 11, "winners": 2, "faults": 4, "tired_plays": 0},
]
const NEXT_BOSS := {"name": "Ilse Varga, Champion", "blurb": "Has already beaten you in her head.",
	"points_to_win": 9, "deck_summary": "Smash x2, Flat Kill x2, Loop x2", "boss": true}
const NEXT_PLAIN := {"name": "Jax Dunn", "blurb": "Every ball is a kill ball if you believe.",
	"points_to_win": 7, "deck_summary": "Smash x3, Drive x3, Flick x3", "boss": false}

var failures := 0
var frames := 0
## [action, data] pairs as `done` delivers them.
var received: Array = []
var focus_warned := false


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 2:
		return false
	_test_card_view()
	_test_hand_ui()
	_test_main_menu()
	_test_pause()
	_test_match_end()
	_test_reward()
	_test_deck()
	_test_run_end()
	print("screens: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(0 if failures == 0 else 1)
	return true


func _check(ok: bool, what: String) -> bool:
	if not ok:
		failures += 1
		push_error("FAIL: %s" % what)
	return ok


# --- helpers -------------------------------------------------------------------

## A screen of the class in `file`, set up with `args` and mounted under the
## root, with its focus checked and `done` connected. Null when the script is
## missing (counted as a failure, so a half-merged tree cannot pass).
func _open(file: String, args: Dictionary, label: String) -> UiScreen:
	var path := SCREENS_DIR + file
	if not _check(ResourceLoader.exists(path), "%s: %s is missing" % [label, path]):
		return null
	var script: GDScript = load(path)
	var screen: UiScreen = script.new()
	screen.setup(args)
	_mount(screen, label)
	return screen


func _mount(screen: UiScreen, label: String) -> void:
	root.add_child(screen)
	_check_focus(screen, label)
	screen.done.connect(_on_done)


func _on_done(action: String, data: Dictionary) -> void:
	received.append([action, data])


func _close(screen: UiScreen) -> void:
	if screen == null:
		return
	root.remove_child(screen)
	screen.free()


## first_focus() must be a visible control that takes focus, and grabbing it
## must make it the viewport's focus owner. Headless builds may report no
## owner at all; that is a warning, the desktop screenshot is the bar there.
func _check_focus(screen: UiScreen, label: String) -> void:
	var f := screen.first_focus()
	if not _check(f != null, "%s: first_focus() is null" % label):
		return
	_check(f.focus_mode == Control.FOCUS_ALL, "%s: first_focus() does not take focus" % label)
	_check(f.is_visible_in_tree(), "%s: first_focus() is hidden" % label)
	if f is BaseButton:
		_check(not (f as BaseButton).disabled, "%s: first_focus() is a disabled button" % label)
	f.grab_focus()
	var owner := root.gui_get_focus_owner()
	if owner == null:
		if not focus_warned:
			focus_warned = true
			push_warning("%s: no focus owner after grab_focus() (headless); not asserted" % label)
		return
	_check(owner == f, "%s: focus owner is %s, not first_focus()" % [label, owner])


## press(action, data) must deliver exactly that through `done`.
func _expect(screen: UiScreen, action: String, data: Dictionary, label: String) -> void:
	if screen == null:
		return
	received.clear()
	screen.press(action, data)
	_check(received.size() == 1 and received[0][0] == action and received[0][1] == data,
		"%s: press(%s, %s) delivered %s" % [label, action, data, received])


## Emits a button's `pressed` as a click would and returns what `done` got.
func _click(button: BaseButton) -> Array:
	received.clear()
	if button != null:
		button.pressed.emit()
	return received.duplicate()


func _card_views(node: Node) -> Array[CardView]:
	var out: Array[CardView] = []
	for child in node.get_children():
		if child is CardView:
			out.append(child)
		out.append_array(_card_views(child))
	return out


func _buttons_with_text(node: Node, text: String) -> Array[Button]:
	var out: Array[Button] = []
	for child in node.get_children():
		if child is Button and (child as Button).text == text:
			out.append(child)
		out.append_array(_buttons_with_text(child, text))
	return out


## The one button reading `text` under `node`, or null (counted as a failure).
func _button(node: Node, text: String, label: String) -> Button:
	var found := _buttons_with_text(node, text)
	_check(found.size() == 1, "%s: %d buttons read '%s', expected 1" % [label, found.size(), text])
	return found[0] if found.size() == 1 else null


func _labels_text(node: Node) -> String:
	var out := ""
	for child in node.get_children():
		if child is Label:
			out += (child as Label).text + "\n"
		out += _labels_text(child)
	return out


# --- CardView -------------------------------------------------------------------

func _test_card_view() -> void:
	var view := CardView.new()
	root.add_child(view)
	var filled := 0
	for id in CardLibrary.ALL_IDS:
		var card := CardLibrary.by_id(id)
		for incoming in INCOMING_TYPES:
			for stamina in [0, 6]:
				view.set_card(card, incoming, stamina)
				filled += 1
				_check(view.card == card, "CardView %s: card not kept" % id)
				_check(view.tired == (card.cost > stamina), "CardView %s: tired %s at stamina %d" % [id, view.tired, stamina])
				_check(view.tooltip_text == card.flavor, "CardView %s: tooltip is not the flavor" % id)
				_check(view.copies == 1, "CardView %s: copies %d in hand mode" % [id, view.copies])
				var face := _labels_text(view)
				_check(card.title in face, "CardView %s: title missing from the face" % id)
				if card.is_strong_vs(incoming):
					_check("STRONG vs %s" % BallType.label(incoming) in face, "CardView %s: STRONG line missing vs %d" % [id, incoming])
				elif card.is_weak_vs(incoming):
					_check("weak vs %s" % BallType.label(incoming) in face, "CardView %s: weak line missing vs %d" % [id, incoming])
				if card.keyword != "":
					_check(card.keyword_text() in face, "CardView %s: keyword line missing" % id)
		view.set_card(card)
		filled += 1
		_check(not view.tired, "CardView %s: tired in deck mode" % id)
		_check(view.modulate == Color.WHITE, "CardView %s: dimmed in deck mode" % id)
		var summary := CardView.matchup_summary(card)
		_check(summary == "" or summary in _labels_text(view), "CardView %s: matchup summary missing" % id)
		view.set_card(card, BallType.NONE, -1, 3)
		filled += 1
		_check(view.copies == 3, "CardView %s: copies %d, not 3" % [id, view.copies])
		_check("x3" in _labels_text(view), "CardView %s: x3 badge missing" % id)
	_check(filled == CardLibrary.ALL_IDS.size() * (INCOMING_TYPES.size() * 2 + 2), "CardView: fill count %d" % filled)
	_check(view.custom_minimum_size == CardView.SIZE, "CardView: minimum size is not SIZE")
	_check(view.focus_mode == Control.FOCUS_ALL, "CardView: does not take focus")
	_check(not view.toggle_mode, "CardView: toggle_mode on by default")
	view.set_selected(true)
	_check(view.selected, "CardView: set_selected(true) not kept")
	view.set_selected(false)
	_check(not view.selected, "CardView: set_selected(false) not kept")
	view.set_tired(true)
	_check(view.tired and view.modulate != Color.WHITE, "CardView: set_tired(true) does not dim")
	view.set_tired(false)
	_check(view.modulate == Color.WHITE, "CardView: set_tired(false) stays dim")
	_check(CardView.cost_dots(0) == "○" and CardView.cost_dots(3) == "●●●", "CardView: cost dots")
	_check(CardView.matchup_summary(CardLibrary.topspin()) == "+Flat +High   -Fast", "CardView: matchup summary format")
	_check(CardView.matchup_summary(CardLibrary.flick()) == "", "CardView: matchup summary for no matchups")
	_check(CardView.is_tired(CardLibrary.smash(), 2) and not CardView.is_tired(CardLibrary.smash(), -1),
		"CardView: is_tired")
	root.remove_child(view)
	view.free()
	print("card view: %d faces filled" % filled)


# --- HandUI --------------------------------------------------------------------

func _test_hand_ui() -> void:
	var hand := HandUI.new()
	root.add_child(hand)
	var chosen: Array = []
	hand.card_chosen.connect(func(i: int) -> void: chosen.append(i))
	var cards: Array[Card] = [CardLibrary.smash(), CardLibrary.block(), CardLibrary.drop_shot(), CardLibrary.topspin()]
	hand.show_hand(cards, BallType.HIGH, 2)
	var views := hand.views()
	_check(views.size() == 4, "HandUI: %d views, not 4" % views.size())
	if views.size() == 4:
		for i in 4:
			_check(views[i].name == "Card%d" % (i + 1), "HandUI: card %d named %s" % [i, views[i].name])
			_check(views[i].toggle_mode, "HandUI: card %d is not a toggle" % i)
			_check(views[i].card == cards[i], "HandUI: card %d holds the wrong card" % i)
			_check(views[i].get_node(views[i].focus_neighbor_left) == views[(i + 3) % 4], "HandUI: card %d left neighbour" % i)
			_check(views[i].get_node(views[i].focus_neighbor_right) == views[(i + 1) % 4], "HandUI: card %d right neighbour" % i)
			_check(views[i].get_node(views[i].focus_neighbor_top) == views[i], "HandUI: card %d top neighbour" % i)
			_check(views[i].get_node(views[i].focus_neighbor_bottom) == views[i], "HandUI: card %d bottom neighbour" % i)
		_check(views[0].tired and not views[1].tired and not views[3].tired, "HandUI: tired flags at stamina 2")
		hand.set_selected(2)
		_check(views[2].selected and views[2].button_pressed and not views[0].selected, "HandUI: set_selected(2)")
		views[1].pressed.emit()
		_check(chosen == [1], "HandUI: card_chosen got %s" % [chosen])
		_check(views[1].selected and not views[2].selected, "HandUI: a press moves the selection")
		hand.set_selected(-1)
		_check(not views[1].selected, "HandUI: set_selected(-1) clears")
		hand.set_enabled(false)
		_check(views[0].disabled and views[3].disabled, "HandUI: set_enabled(false)")
		hand.set_enabled(true)
		_check(not views[0].disabled, "HandUI: set_enabled(true)")
		hand.focus_index(3)
		var owner := root.gui_get_focus_owner()
		if owner != null:
			_check(owner == views[3], "HandUI: focus_index(3) focused %s" % owner)
			hand.focus_first()
			_check(root.gui_get_focus_owner() == views[0], "HandUI: focus_first()")
	hand.focus_index(9)
	hand.clear()
	_check(hand.get_child_count() == 0, "HandUI: clear() leaves %d children" % hand.get_child_count())
	hand.show_hand(cards.slice(0, 2), BallType.NONE, -1)
	_check(hand.views().size() == 2 and not hand.views()[0].tired, "HandUI: stamina -1 never tires")
	root.remove_child(hand)
	hand.free()
	print("hand ui: ok")


# --- the screens -----------------------------------------------------------------

func _test_main_menu() -> void:
	for has_save in [false, true]:
		var label := "main_menu(has_save=%s)" % has_save
		var s := _open("main_menu_screen.gd", {"has_save": has_save, "version": "0.1.0", "last_seed": 20261010}, label)
		if s == null:
			continue
		_check(s.back_action == "", "%s: back_action is '%s'" % [label, s.back_action])
		# press() carries every action of the design's row, including the
		# Settings button that only arrives in M4.
		for action in ["new_run", "continue", "settings", "quit"]:
			_expect(s, action, {}, label)
		_check(_click(_button(s, "New Run", label)) == [["new_run", {}]], "%s: New Run button" % label)
		var continues := _buttons_with_text(s, "Continue")
		_check(continues.size() == (1 if has_save else 0), "%s: %d Continue buttons" % [label, continues.size()])
		if continues.size() == 1:
			_check(_click(continues[0]) == [["continue", {}]], "%s: Continue button" % label)
		_check(_click(_button(s, "Quit", label)) == [["quit", {}]], "%s: Quit button" % label)
		_close(s)
	print("main menu: ok")


func _test_pause() -> void:
	var s := _open("pause_screen.gd", {}, "pause")
	if s != null:
		_check(s.back_action == "resume", "pause: back_action is '%s'" % s.back_action)
		for action in ["resume", "deck", "settings", "abandon"]:
			_expect(s, action, {}, "pause")
		_check(_click(_button(s, "Resume", "pause")) == [["resume", {}]], "pause: Resume button")
		_check(_click(_button(s, "Deck", "pause")) == [["deck", {}]], "pause: Deck button")
		# Abandon asks twice: the first click only arms the button.
		var abandon := _button(s, PauseScreen.ABANDON_TEXT, "pause")
		if abandon != null:
			_check(_click(abandon).is_empty() and abandon.text == PauseScreen.CONFIRM_TEXT, "pause: first Abandon only arms")
			_check(_click(abandon) == [["abandon", {}]], "pause: second Abandon fires")
		_close(s)
	print("pause: ok")


func _test_match_end() -> void:
	var cases := [
		["won", {"won": true, "score": [7, 4], "hearts": 2, "stats": MATCH_STATS, "longest_rally": 9, "run_over": false}],
		["lost", {"won": false, "score": [3, 7], "hearts": 1, "stats": MATCH_STATS, "longest_rally": 5, "run_over": false}],
		["lost run_over", {"won": false, "score": [0, 7], "hearts": 0, "stats": MATCH_STATS, "longest_rally": 2, "run_over": true}],
		["champion", {"won": true, "score": [9, 8], "hearts": 1, "stats": MATCH_STATS, "longest_rally": 15, "run_over": true}],
	]
	for c in cases:
		var label := "match_end(%s)" % c[0]
		var s := _open("match_end_screen.gd", c[1], label)
		if s == null:
			continue
		_check(s.back_action == "", "%s: back_action is '%s'" % [label, s.back_action])
		_expect(s, "continue", {}, label)
		_check(_click(_button(s, "Continue", label)) == [["continue", {}]], "%s: Continue button" % label)
		_check(s.first_focus() is Button and (s.first_focus() as Button).text == "Continue", "%s: first focus is not Continue" % label)
		_close(s)
	print("match end: ok")


func _test_run_end() -> void:
	var stats := RunState.new(1).stats.duplicate()
	stats["matches_won"] = 3
	stats["points_won"] = 21
	stats["points_lost"] = 17
	for won in [true, false]:
		var label := "run_end(won=%s)" % won
		var s := _open("run_end_screen.gd", {"won": won, "stage": 5 if won else 3, "opponent_name": "Jax Dunn",
			"stats": stats, "seed": 20261010, "deck_size": 15}, label)
		if s == null:
			continue
		_check(s.back_action == "", "%s: back_action is '%s'" % [label, s.back_action])
		for action in ["new_run", "retry", "menu"]:
			_expect(s, action, {}, label)
		_check(_click(_button(s, "New Run", label)) == [["new_run", {}]], "%s: New Run button" % label)
		_check(_click(_button(s, "Retry this seed", label)) == [["retry", {}]], "%s: Retry button" % label)
		_check(_click(_button(s, "Main Menu", label)) == [["menu", {}]], "%s: Main Menu button" % label)
		var text := _labels_text(s)
		_check(("CHAMPION" in text) == won and ("RUN OVER" in text) != won, "%s: headline" % label)
		_check("Seed 20261010" in text, "%s: seed line" % label)
		_close(s)
	print("run end: ok")


func _test_reward() -> void:
	var offer := ["power_loop", "lunge", "backhand_flip"]
	for trim in [true, false]:
		var label := "reward(trim=%s)" % trim
		var s := _open("reward_screen.gd", {"offer": offer, "trim_available": trim, "deck_size": 15, "deck_max": 20,
			"hearts": 2, "stage": 2, "stages": 6, "next": NEXT_BOSS if trim else NEXT_PLAIN}, label)
		if s == null:
			continue
		var r := s as RewardScreen
		_check(r.back_action == "", "%s: back_action is '%s'" % [label, r.back_action])
		var views := _card_views(r)
		_check(views.size() == 3, "%s: %d CardViews, not 3" % [label, views.size()])
		for i in views.size():
			_check(views[i].card.id == offer[i], "%s: card %d is %s" % [label, i, views[i].card.id])
			_check(not views[i].toggle_mode, "%s: reward card %d toggles" % [label, i])
			_check(_click(views[i]) == [["pick", {"index": i}]], "%s: clicking card %d" % [label, i])
		_check(r.first_focus() == views[0] if not views.is_empty() else false, "%s: first focus is not the first card" % label)
		_check(_click(r.skip_button) == [["skip", {}]], "%s: Skip button" % label)
		_check(_click(r.deck_button) == [["deck", {}]], "%s: View deck button" % label)
		_check((r.trim_button != null) == trim, "%s: trim button present=%s" % [label, r.trim_button != null])
		_check(_buttons_with_text(r, "Remove a card instead").size() == (1 if trim else 0), "%s: trim button count" % label)
		if trim:
			_check(_click(r.trim_button) == [["trim", {}]], "%s: trim button" % label)
		var text := _labels_text(r)
		_check("Deck: 15 cards, hearts 2, stage 3 of 6" in text, "%s: footer line" % label)
		var next: Dictionary = NEXT_BOSS if trim else NEXT_PLAIN
		_check("Next: %s (first to %d)" % [next["name"], next["points_to_win"]] in text, "%s: next opponent line" % label)
		_check(String(next["blurb"]) in text and String(next["deck_summary"]) in text, "%s: blurb and summary" % label)
		_check(("BOSS" in text) == bool(next["boss"]), "%s: BOSS tag shown=%s" % [label, "BOSS" in text])
		_expect(r, "pick", {"index": 2}, label)
		_expect(r, "skip", {}, label)
		_expect(r, "trim", {}, label)
		_expect(r, "deck", {}, label)
		_close(r)
	# A full deck cannot take a card: the picks are disabled and Skip gets focus.
	var full := _open("reward_screen.gd", {"offer": offer, "trim_available": false, "deck_size": 20, "deck_max": 20,
		"hearts": 1, "stage": 4, "stages": 6, "next": NEXT_BOSS}, "reward(full)")
	if full != null:
		for v in _card_views(full):
			_check(v.disabled, "reward(full): card %s still enabled" % v.card.id)
		_check(full.first_focus() == (full as RewardScreen).skip_button, "reward(full): first focus is not Skip")
		_close(full)
	# No scouting data at all must still build.
	var bare := _open("reward_screen.gd", {"offer": offer}, "reward(bare)")
	if bare != null:
		_check(_card_views(bare).size() == 3, "reward(bare): cards")
		_close(bare)
	print("reward: ok")


func _test_deck() -> void:
	var deck: Array = CardLibrary.starter_ids()
	deck.append("moonball")
	deck.append("line_chop")
	var distinct := {}
	for id in deck:
		distinct[id] = true
	# View mode, from the pause menu and from the reward screen.
	for from in ["pause", "reward"]:
		var label := "deck(view from %s)" % from
		var s := _open("deck_screen.gd", {"deck": deck, "mode": "view", "reason": "", "return": from, "deck_min": 10}, label)
		if s == null:
			continue
		var d := s as DeckScreen
		_check(d.back_action == "back", "%s: back_action is '%s'" % [label, d.back_action])
		var views := _card_views(d)
		_check(views.size() == distinct.size(), "%s: %d CardViews for %d ids" % [label, views.size(), distinct.size()])
		var total := 0
		for i in views.size():
			total += views[i].copies
			_check(views[i].copies == deck.count(views[i].card.id), "%s: %s shows x%d" % [label, views[i].card.id, views[i].copies])
			_check(not views[i].toggle_mode, "%s: view-mode card toggles" % label)
			if i > 0:
				var a := views[i - 1].card
				var b := views[i].card
				_check(a.cost < b.cost or (a.cost == b.cost and a.title < b.title),
					"%s: %s before %s is not cost-then-title order" % [label, a.title, b.title])
		_check(total == deck.size(), "%s: copies add up to %d, not %d" % [label, total, deck.size()])
		_check(d.remove_button == null and d.keep_button == null, "%s: remove buttons in view mode" % label)
		_check(_click(d.back_button) == [["back", {}]], "%s: Back button" % label)
		var text := _labels_text(d)
		_check("Your deck (%d)" % deck.size() in text, "%s: header" % label)
		_check("0-cost x4 · 1-cost x8 · 2-cost x2 · 3-cost x2" in text, "%s: cost curve: %s" % [label, DeckScreen.cost_curve(deck)])
		_expect(d, "back", {}, label)
		_close(d)
	# Remove mode for both reasons: pick a card, remove it, or keep them all.
	for reason in ["regroup", "trim"]:
		var label := "deck(remove %s)" % reason
		var s := _open("deck_screen.gd", {"deck": deck, "mode": "remove", "reason": reason, "return": "", "deck_min": 10}, label)
		if s == null:
			continue
		var d := s as DeckScreen
		_check(d.back_action == "", "%s: back_action is '%s'" % [label, d.back_action])
		_check(d.first_focus() is CardView, "%s: first focus is not a card" % label)
		var views := _card_views(d)
		_check(views.size() == distinct.size(), "%s: %d CardViews" % [label, views.size()])
		_check(d.remove_button != null and d.remove_button.disabled, "%s: Remove enabled before a pick" % label)
		_check(_click(d.remove_button).is_empty(), "%s: a disabled Remove still fired" % label)
		var target := views[views.size() - 1]
		_check(target.toggle_mode, "%s: remove-mode card is not a toggle" % label)
		_click(target)
		_check(target.selected and not d.remove_button.disabled, "%s: picking a card enables Remove" % label)
		_click(views[0])
		_check(views[0].selected and not target.selected, "%s: picking another card moves the mark" % label)
		_click(views[0])
		_check(not views[0].selected and d.remove_button.disabled, "%s: picking the marked card again clears it" % label)
		_click(target)
		var expected_index := deck.find(target.card.id)
		_check(_click(d.remove_button) == [["remove", {"index": expected_index}]], "%s: Remove selected" % label)
		_check(_click(d.keep_button) == [["skip", {}]], "%s: Keep all" % label)
		var text := _labels_text(d)
		_check(DeckScreen.HEADERS[reason] in text, "%s: header" % label)
		_expect(d, "remove", {"index": 0}, label)
		_expect(d, "skip", {}, label)
		_close(d)
	# At the minimum nothing can be removed, whatever is picked.
	var small: Array = deck.slice(0, 10)
	var at_min := _open("deck_screen.gd", {"deck": small, "mode": "remove", "reason": "trim", "return": "", "deck_min": 10}, "deck(at min)")
	if at_min != null:
		var d := at_min as DeckScreen
		_click(_card_views(d)[0])
		_check(d.remove_button.disabled, "deck(at min): Remove enabled at the minimum")
		_check(_click(d.remove_button).is_empty(), "deck(at min): Remove fired at the minimum")
		_check(_click(d.keep_button) == [["skip", {}]], "deck(at min): Keep all")
		_close(d)
	# Grouping and the cost curve as pure helpers.
	var groups := DeckScreen.group(["smash", "lob", "smash", "topspin"])
	_check(groups.size() == 3 and groups[0]["id"] == "lob" and groups[1]["id"] == "topspin" and groups[2]["id"] == "smash",
		"deck: group order %s" % [groups])
	_check(groups[2]["count"] == 2 and groups[2]["index"] == 0, "deck: smash group %s" % [groups[2]])
	_check(DeckScreen.cost_curve(["smash", "block"]) == "0-cost x1 · 1-cost x0 · 2-cost x0 · 3-cost x1", "deck: cost curve")
	_check(DeckScreen.grid_size(25).y == DeckScreen.grid_size(15).y and DeckScreen.grid_size(5).y < DeckScreen.grid_size(10).y,
		"deck: the scroll area caps at %d rows" % DeckScreen.VISIBLE_ROWS)
	print("deck: ok")
