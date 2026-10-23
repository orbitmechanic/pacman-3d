# Architecture

Status: **playable v0.1.0** — maze, Pac-Man, scoring, ghosts, lives and the
full title → play → death / level-clear → game-over loop (PRs #1-#5). This
document evolves with each merged PR; keep sections in sync with the code.

## Design pillars

1. **Grid logic, not physics.** Pac-Man and ghosts move tile-to-tile with
   interpolation for presentation. Wall/dot/ghost collisions are tile
   equality checks in game logic, never `CharacterBody3D` physics. Why:
   deterministic, headless-testable, and faithful to the arcade original.
2. **Procedural everything.** The maze renders from the ASCII map data via
   instanced meshes (`MultiMeshInstance3D`); characters are built from
   primitive or generated meshes. Zero binary assets → the whole game is
   reviewable text.
3. **Pure decision functions.** Direction choice is a static function of
   (tile, current direction, target). Ghosts differ only in how they compute
   their target tile, which keeps behaviour explainable and unit-testable.
4. **GL Compatibility renderer.** Fast startup, works everywhere (desktop,
   web export candidates later).

## Structure

| Path | Responsibility |
| --- | --- |
| `scripts/MazeData.gd` | 28×31 maze as ASCII strings; tile queries, wrap logic, spawns |
| `scripts/MazeView.gd` | builds the 3D board (floor, walls, dots, pellets) and owns food counters |
| `scripts/GridMover.gd` | shared tile-to-tile movement, tunnel wrap, instant reversal, `decide` callback |
| `scripts/Pacman.gd` | input buffering, chomp animation, mouth facing travel |
| `scripts/PacMesh.gd` | generated sphere with a mouth wedge (`SphereMesh` has no phi sweep in 4.x) |
| `scripts/Ghost.gd` | one ghost: house release, target selection, frightened wandering, eaten return |
| `scripts/GhostMesh.gd` | generated ghost body: dome, sides, scalloped hem |
| `scripts/Game.gd` | score, levels, frightened window, scatter/chase waves, collisions, lives, game over |
| `scripts/Main.gd` | scene wiring, HUD updates, dev hooks (capture, demo, frighten) |
| `scripts/LivesDisplay.gd` | procedural remaining-lives pucks |
| `tests/*.gd` | headless `SceneTree` probes: logic assertions + deterministic state checks |

## Movement

`GridMover` is the only thing that moves an actor. It holds `cell`,
`to_cell`, `dir` and `progress` (0..1). At every tile boundary it calls the
actor's `decide(cell)` callback; returning `Vector2i.ZERO` stops the actor.
Requests for the reverse direction are honoured instantly (classic Pac-Man
reversal), anything else is queued as the actor's desired direction and
applied at the next boundary.

Tunnel rows wrap horizontally. The mover keeps an *unwrapped* interpolated
target so crossing the seam is visually continuous, then snaps its anchor to
the wrapped tile on arrival.

## Ghost AI

Four personalities compute a target tile each boundary:

| Ghost | Scatter corner | Chase target |
| --- | --- | --- |
| Blinky (red) | (25,0) | Pac-Man's tile |
| Pinky (pink) | (2,0) | 4 tiles ahead of Pac-Man |
| Inky (cyan) | (27,30) | Blinky's tile reflected through the tile 2 ahead of Pac-Man |
| Clyde (orange) | (0,30) | Pac-Man when farther than 8 tiles, otherwise his corner |

Waves start in scatter and alternate with `Game.WAVE_DURATIONS`
(7/20/7/20/5/20/5 s, then chase forever). A wave change reverses every
roaming ghost. The wave clock pauses while the frightened window is open.

`Ghost.choose_direction()` picks, among walkable neighbours excluding the
reverse, the one with the smallest squared distance to the target. It only
reverses at a dead end. Frightened ghosts instead pick a random legal turn
(seeded `RandomNumberGenerator`, so runs are reproducible).

### States

- `IN_HOUSE` — parked on a house tile, hovering visually, counting down to release.
  Blinky starts outside at `HOUSE_EXIT`; Pinky/Inky/Clyde wait 1.5/4/7 s.
- `LEAVING` — walks up through the door (`allow_door`) to `HOUSE_EXIT`,
  then returns to `ROAMING` and loses door access.
- `ROAMING` — normal scatter/chase/frightened behaviour. The only state that
  can collide with Pac-Man.
- `EATEN` — body hidden (eyes only), door access granted, heads home at
  12 tiles/s, re-enters the house and is released again after 1.2 s.

## Collisions, lives, levels

`Game.resolve_collisions()` compares nearest tiles once per physics tick. A
roaming ghost sharing Pac-Man's tile either eats him (lives−1, 1.2 s freeze,
reset of Pac-Man and the whole cast) or, while frightened, is eaten for
200/400/800/1600 points (chain resets on the next pellet or when Pac-Man
dies). At zero lives the game enters `GAME_OVER`. Clearing the board refills
food, keeps lives, resets the cast and advances the level.

## Game states

`Game` is a small state machine; `Main` maps it onto the HUD, the camera and
the overlays. All transitions are exposed through `state_changed`.

```
TITLE ──start──> READY ──2 s──> PLAYING ──food=0──> LEVEL_CLEAR ──1.8 s──> READY
                               │                        (next level, faster)
                               └──hit──> DYING ──1.2 s──> READY … or GAME_OVER
                                                                    │
                                                            start (Enter)
                                                                    ▼
                                                                 READY
```

- **TITLE** — board frozen, title screen up, camera on the wide title framing.
  Enter/Space (`start` action) begins a run.
- **READY** — 2 s freeze with Pac-Man and the cast posed at their spawns; the
  camera eases from the title framing to the play framing.
- **PLAYING** — input, ghosts, food and collisions are live.
- **DYING** — 1.2 s freeze, Pac-Man shrinks and spins, camera shake; then a
  fresh READY (or GAME_OVER at zero lives).
- **LEVEL_CLEAR** — 1.8 s hold with the walls pulsing white and `LEVEL CLEAR`
  on screen; then the next level refills the board, re-tints the walls and
  plays 6 % faster per level (capped at +35 %).
- **GAME_OVER** — board frozen, red overlay and a restart prompt; Enter
  starts a new run.

Presentation details live outside the state machine: `MazeView` owns the wall
palette (one colour per level, `set_flash_amount`) and `LivesDisplay` draws
the remaining-life pucks with `_draw()`.

## Shipping

The same project ships to desktop and the browser:

- **GL Compatibility renderer** was chosen up front so the Web export is a
  real target rather than a port.
- **Web export runs without threads** (`variant/thread_support=false`) — no
  COOP/COEP response headers needed, so a stock static host works.
- **Procedural art pays off twice**: the Web `.pck` is ~60 KB, with only the
  engine's `.wasm` carrying the weight (gzip on the host handles the rest).
- `export_presets.cfg` excludes `tests/` and `docs/` from the package so
  probes and documentation never reach players.
- `.github/workflows/pages.yml` gates on the probes, exports, and deploys to
  GitHub Pages (`https://orbitmechanic.github.io/pacman-3d/`). Export
  templates are cached between runs.

## Validation

See *Validation gates* in [CONTRIBUTING.md](../CONTRIBUTING.md). Current
probes:

| Probe | Covers |
| --- | --- |
| `SmokeProbe` | scene loads, camera, board, cast and HUD nodes exist |
| `MazeProbe` | map symmetry, sealed border, food counts, reachability |
| `PacProbe` | walking, walls, tunnel, reversal, door block, arrivals, mouth mesh |
| `ScoreProbe` | dot/pellet scoring, no double-count, fright timing, level clear |
| `GhostProbe` | cast/spawns, scatter/chase targets, chooser rules, door release, fright speeds, 200→1600 chain, eaten return, lives, game over |
