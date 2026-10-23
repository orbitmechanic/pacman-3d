# Architecture

Status: **maze + board render implemented** (PR #1). Movement, ghosts, and game
states are in progress. This document evolves with each merged PR; keep
sections in sync with the code.

## Design pillars

1. **Grid logic, not physics.** Pac-Man and ghosts move tile-to-tile with
   interpolation for presentation. Wall/dot/ghost collisions are tile
   equality checks in game logic, never `CharacterBody3D` physics. Why:
   deterministic, headless-testable, and faithful to the arcade original.
2. **Procedural everything.** The maze renders from the ASCII map data via
   instanced meshes (`MultiMeshInstance3D`); characters are built from
   primitive meshes. Zero binary assets → the whole game is reviewable text.
3. **GL Compatibility renderer.** Fast startup, works everywhere (desktop,
   web export candidates later).

## Planned structure

| Path | Responsibility |
| --- | --- |
| `scripts/MazeData.gd` | 28×31 maze as ASCII strings; tile queries, wrap logic |
| `scripts/MazeView.gd` | builds the 3D board (floor, walls, dots) from MazeData |
| `scripts/GridMover.gd` | shared tile-to-tile movement with interpolation |
| `scripts/Pacman.gd` | input buffering, chomp animation, eaten/eating signals |
| `scripts/Ghost.gd` | chase/scatter/frightened/eaten state machine |
| `scripts/Main.gd` | game state machine, score/lives/level, HUD, camera |
| `tests/*.gd` | headless `SceneTree` probes: logic assertions + screenshots |

## Validation

See *Validation gates* in [CONTRIBUTING.md](../CONTRIBUTING.md).
