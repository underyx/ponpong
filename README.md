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
- First to 7. Serve switches every two points.

## Where things are

| Path | What it is |
| --- | --- |
| `scenes/main.tscn` | The whole scene: table, paddles, ball, camera, sky, UI. |
| `scripts/game.gd` | The turn loop and state machine on the scene root. |
| `scripts/card.gd` | The `Card` resource: power, control, matchups, flight shape. |
| `scripts/card_library.gd` | The starter deck. Add cards here. |
| `scripts/zone_grid.gd` | Builds the 2x5 zones per half, their risk and reward, and draws them. |
| `scripts/zone.gd` | One zone: side, row, lane, rect, risk, reward, highlight state. |
| `scripts/rally_resolver.gd` | Pure logic: card + incoming ball + target zone + opponent lane into odds and an outcome. |
| `scripts/opponent_ai.gd` | Weighted tables for how the opponent replies, where they aim, and where they stand. |
| `scripts/ball_flight.gd` | Tweened quadratic-curve ball movement, bounce squash, net fault. |
| `scripts/hand_ui.gd` | Builds the row of card buttons. |
| `shaders/toon.gdshader` | The stylised look. Tweak bands, rim, halftone per material. |
| `shaders/outline.gdshader` | Inverted-hull outline used as every toon material's next pass. |
| `shaders/zone.gdshader` | Zone fill, border, risk halftone and highlight tint. |
| `shaders/floor.gdshader` | Faded grid floor. |
| `materials/*.tres` | One toon material per surface, so colours tune in the inspector. |

## Obvious next steps

- A deck screen between matches (the Slay the Spire layer).
- Give the opponent their own deck and stances instead of reply tables.
- Energy or stamina so Smash cannot be spammed.
- A ball trail and paddle impact particles; the shader is ready for more drama.

## Headless checks

Both scripts under `tests/` run without the editor and are what CI would call:

```sh
godot --headless --path . -s tests/autoplay.gd      # plays a full match with random cards
xvfb-run godot --path . --rendering-driver opengl3 -s tests/screenshot.gd -- ./shots
```
