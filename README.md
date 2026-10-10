# ponpong

A turn-based ping pong deckbuilder in stylised 3D, built with Godot 4.

There is no physics. A rally is a sequence of card plays: you pick a shot card
against the incoming ball, the resolver decides whether it lands, wins outright
or comes back, and the 3D scene plays the shot back by tweening the ball along a
curve. Everything on screen wears a toon shader with banded light, rim light,
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

- Top of the screen shows the score and the **incoming ball** (Flat, High,
  Spin or Fast). On your serve it says Serve and nothing has a bonus.
- Your hand is four cards. Each card lists its power, control, what kind of
  ball it sends, and whether it is **strong** or **weak** against the incoming
  one.
- Play a card. The resolver rolls control plus or minus the matchup. Too low
  and you fault into the net. Otherwise it lands, and power decides whether it
  is a clean winner or the opponent gets it back. If it comes back, the
  opponent's reply becomes your next incoming ball.
- First to 7. Serve switches every two points.

## Where things are

| Path | What it is |
| --- | --- |
| `scenes/main.tscn` | The whole scene: table, paddles, ball, camera, sky, UI. |
| `scripts/game.gd` | The turn loop and state machine on the scene root. |
| `scripts/card.gd` | The `Card` resource: power, control, matchups, flight shape. |
| `scripts/card_library.gd` | The starter deck. Add cards here. |
| `scripts/rally_resolver.gd` | Pure logic that turns card + incoming ball into an outcome. |
| `scripts/opponent_ai.gd` | Weighted tables for how the opponent replies and serves. |
| `scripts/ball_flight.gd` | Tweened quadratic-curve ball movement, bounce squash, net fault. |
| `scripts/hand_ui.gd` | Builds the row of card buttons. |
| `shaders/toon.gdshader` | The stylised look. Tweak bands, rim, halftone per material. |
| `shaders/outline.gdshader` | Inverted-hull outline used as every toon material's next pass. |
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
