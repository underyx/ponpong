# ponpong

A turn-based ping pong deckbuilder in stylised 3D, built with Godot 4.

There is no physics. A rally is a sequence of card plays: you pick a shot card
against the incoming ball, the resolver decides whether it lands, wins outright
or comes back, and the 3D scene plays the shot back by tweening the ball along a
curve. Shots are aimed at a 2 by 5 grid of unequal zones on the opponent's
half, seen from above. Everything on screen wears a toon shader with banded light, rim light,
halftone shadows and an inverted-hull outline.

## Open it

1. Install [Godot 4.6](https://godotengine.org/download) (any 4.4+ build should
   open it, 4.6 is what it was made with). The standard build is enough, no
   .NET needed.
2. In the Godot project manager choose **Import**, pick this folder's
   `project.godot`, then **Import & Edit**.
3. Press **F5** (or the play button) to run `scenes/main.tscn`.

The first import takes a few seconds while shaders compile.

## How a point plays

Play is 2D, seen from above. Each half of the table is split into a 2 by 5
grid of target zones: five lanes across, two rows deep. The lanes are unequal
on purpose. The far-left and far-right lanes are thin, and the deep row by the
end line is shallower than the short row by the net, because those are the
balls that go out. Risky zones are drawn with halftone dots; the bigger the
dots, the easier the zone is to miss.

- Both players hold a deck of the same cards. The opponent is an AI that
  weighs every card into every zone, so it faults into the corners sometimes
  too.
- Top of the screen shows the score and the **incoming ball**: its type (Flat,
  High, Spin or Fast) and which of your zones it lands in. Awkward landing
  zones cost you control on the reply. On your serve nothing has a bonus.
- Your hand is four cards. Each card lists its power, control, what kind of
  ball it sends, and whether it is **strong** or **weak** against the incoming
  one. Some cards have a favourite row: Drop Shot wants the short row, Smash,
  Lob and Flick want the deep row.
- Click a card, then hover their half. The hint line shows the odds for that
  card into that zone: how likely it lands, and how likely it wins outright if
  it does. Darker zones are the lanes the opponent is standing in; aiming away
  from them is worth more.
- Click a zone to commit. Too low a roll and you fault, into the net from the
  middle or just out from an edge. Otherwise the ball lands there and pressure
  decides whether it is a clean winner or comes back. If it comes back, the
  opponent's reply, and where it lands on your half, is your next incoming.
- Every card costs stamina (the dots on it; a hollow dot is free). You start
  with 6, get 1 back at the start of every point, and the score line shows
  both players' pools. You may always play a card you cannot afford: it empties
  your stamina and the shot is **tired**, a flat hit to its control that the
  hint line and the greyed card both warn you about. Smash twice, then play
  cheap until you have caught your breath. Keyword cards (Rest, Sap, Exhaust,
  Steady, Reach, Heavy) say what they do on the card.
- First to 5 against the opener, 7 after that and 9 against the boss. Serve
  switches every two points.

## How a run plays

New Run from the main menu starts a run of six stages: Coach Pim, two tier-A
opponents, two tier-B opponents and one of two bosses, drawn from the run's
seed. Every opponent has a name, a blurb, a deck of their own and an AI
personality; the VS banner and the reward screen scout the next one. Winning
a match offers one of three cards (or, after stages 2 and 4, a trim instead).
Losing one costs a heart and offers a regroup trim before the rematch; losing
with no hearts left ends the run. Esc or Start pauses, with the deck and a
two-step Abandon on the pause menu. The run end screen shows the seed, and
"Retry this seed" replays the same six opponents with the same offers.

Everything plays with the mouse, the keyboard (1-4 picks a card, arrows or
WASD aim, Enter plays, Backspace un-picks, Q/E cycle cards, Esc pauses) or a
gamepad (A, d-pad or stick, B, the shoulders, Start). A gold ring marks what
has focus on every screen.

## How it is put together

The rules and the pictures are separate on purpose, because online multiplayer
is on the list.

- `MatchState` (`scripts/match_state.gd`) is the whole game with no nodes in
  it: two players with decks, hands, scores and lanes, whose turn it is, the
  incoming ball, and one seeded random number generator. You drive it with
  `start_point()` and `apply(action)`, where an action is a plain dictionary
  like `{"type": "shot", "player": 0, "card": 2, "row": 1, "col": 3}`. Both
  return a list of event dictionaries saying what happened.
- Controllers decide actions. `AIController` scores every card into every zone
  and picks one using the match's own RNG. The local player is the UI in
  `game.gd`. A future `RemoteController` just hands over actions received from
  the other peer.
- `game.gd` is the presenter. It queues the events and plays them back as
  tweens, labels and callouts. It never decides an outcome.
- `RallyResolver` and `ZoneLayout` are pure helpers the state uses.

Two copies of `MatchState` with the same seed and the same actions produce the
same match, event for event, and `to_dict()` / `from_dict()` snapshot a match
mid-rally. `tests/determinism.gd` checks both. So online play later means:
agree a seed when the match starts, send each action to the other peer as it
is made (Godot's high-level multiplayer RPCs or a tiny relay), run `apply()`
on both ends, and let each presenter play back its own events. The opponent's
AI is already a deck-holding player, not a reply table, so a human can take
that seat without touching the rules.

## Where things are

| Path | What it is |
| --- | --- |
| `scenes/main.tscn` | The root: the Director, one Match instance and the Screens layer. |
| `scenes/match.tscn` | The match: table, paddles, ball, camera, sky, HUD. |
| `scripts/director.gd` | The run loop: owns the RunState, starts matches, shows screens, pauses, saves. |
| `scripts/game.gd` | The match presenter: feeds actions to the state, plays back events. |
| `scripts/run_state.gd` | Pure, seeded, serialisable run: opponents, hearts, rewards, trims. |
| `scripts/opponent_library.gd` | The nine opponents: decks, AI personalities, paddle colours. |
| `scripts/input_setup.gd` | Registers the keyboard, mouse and gamepad actions at boot. |
| `scripts/ui/` | `UiKit` (palette and widget builders), `UiScreen` (screen base), `CardView` (one card face). |
| `scripts/screens/` | Main menu, pause, match end, reward, deck and run end, all code-built. |
| `scripts/match_state.gd` | Pure, seeded, serialisable match simulation. The thing to run on both peers. |
| `scripts/ai_controller.gd` | Picks actions for the computer player from the odds. |
| `scripts/card.gd` | The `Card` resource: power, control, cost, keyword, matchups, flight shape. |
| `scripts/card_library.gd` | All 25 cards, the starter deck and the id lookups. Add cards here. |
| `scripts/zone_layout.gd` | The 2x5 zones per half as data: geometry, risk and reward. |
| `scripts/zone.gd` | One zone: side, row, lane, rect, risk, reward. |
| `scripts/zone_grid.gd` | Draws a ZoneLayout on the table and tints zones by state. |
| `scripts/rally_resolver.gd` | Pure logic: card + incoming ball + target zone + opponent lane into odds and an outcome. |
| `scripts/ball_flight.gd` | Tweened quadratic-curve ball movement, bounce squash, net fault. |
| `scripts/hand_ui.gd` | The hand: a focusable strip of CardViews. |
| `shaders/toon.gdshader` | The stylised look. Tweak bands, rim, halftone per material. |
| `shaders/outline.gdshader` | Inverted-hull outline used as every toon material's next pass. |
| `shaders/zone.gdshader` | Zone fill, border, risk halftone and highlight tint. |
| `shaders/floor.gdshader` | Faded grid floor. |
| `materials/*.tres` | One toon material per surface, so colours tune in the inspector. |

## Obvious next steps

- Online multiplayer: a RemoteController plus seed and action exchange, see above.
- A ball trail and paddle impact particles; the shader is ready for more drama.

## Headless checks

The scripts under `tests/` and `tools/` run without the editor and are what CI would call
(`--fixed-fps 60` is a test flag only: it drops real-time sync so a whole match takes a second):

```sh
godot --headless --path . -s tests/determinism.gd       # match rules: same seed + actions = same match
godot --headless --path . -s tests/run_determinism.gd   # run rules, card pool and roster integrity
godot --headless --path . -s tests/balance.gd -- --runs 40   # starter vs every opponent: report + loose bounds
godot --headless --path . -s tests/screens.gd           # every screen and CardView, built from synthetic args
godot --headless --fixed-fps 60 --path . -s tests/autoplay.gd   # plays whole runs through the menus, pauses, aims
sh tools/check_rules_pure.sh                            # rules files never touch global RNG, nodes or time
xvfb-run godot --path . --rendering-driver opengl3 -s tests/screenshot.gd -- ./shots
```
