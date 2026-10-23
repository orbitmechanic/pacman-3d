# Contributing

## Ground rules

- **Typed GDScript everywhere** (`var x: int`, `func f() -> void`): it turns
  runtime bugs into parse-time errors.
- One class per file; `class_name` only for genuinely reusable nodes.
- Logic lives in `_physics_process`, presentation in `_process`.
- Naming: `snake_case` functions/vars, `PascalCase` classes, `UPPER_CASE`
  constants.
- No binary art assets: geometry and materials are procedural so everything
  stays reviewable as text.

## Workflow

1. Each feature/fix gets a **GitHub issue** (milestoned) and a **pull request**
   from a `feat/...`, `fix/...`, or `chore/...` branch.
2. Commits follow [Conventional Commits](https://www.conventionalcommits.org/)
   (`feat:`, `fix:`, `docs:`, `test:`, `chore:`, `refactor:`).
3. PRs must keep the validation gates green; CI runs them automatically.
4. Update `docs/ARCHITECTURE.md` in the same PR when the structure changes —
   docs travel with code.

## Validation gates

Run these before pushing (requires a local Godot 4.7 binary):

```bash
# Gate 1 - it imports and runs with zero engine errors
godot --headless --import
godot --headless --quit-after 120

# Gate 2 - logic probes (deterministic, headless, assert via exit code)
godot --headless -s res://tests/SmokeProbe.gd
godot --headless -s res://tests/MazeProbe.gd

# Gate 3 - visual check (real window, auto-quit)
godot --path . --position 100,100 -- --capture /tmp/shot.png --frames 90
```

`--capture <path> --frames N` is a dev hook in `scripts/Main.gd`: it renders
N frames then writes a PNG and exits, so screenshots are reproducible in CI
logs and code review.
