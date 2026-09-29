# Agent instructions

## Scope and architecture

- Advance the smallest complete playable loop first. Follow `TASKS.md` dependencies and update statuses with evidence.
- `game/` contains runtime code. Keep player, vehicle, pedestrian, traffic, police, mission and UI systems separate. Use data/resources for mission definitions and vehicle tuning.
- `tools/world/` owns geographic transformation and edited district data. `tools/blender/` owns asset generation. Never hand-edit an output in `generated/`; edit its source/seed and regenerate.
- Keep deterministic seeds and input provenance in generation reports. Do not fetch network data during the game.
- Avoid proprietary game assets, unlicensed music, copied maps, names and UI.

## Style and performance

- GDScript: typed public interfaces, small scene-bound scripts, explicit signals, no hidden global state beyond justified autoload services. Use snake_case for files and identifiers.
- Python: type hints for tooling interfaces, argparse CLI, useful errors including asset/stage/path, deterministic behavior. Blender generators must validate mesh bounds, polygon counts, UVs when needed, materials and export files.
- Favor instancing, low-poly silhouettes, cheap collision, distance-based simulation and budgets in `docs/PERFORMANCE_BUDGET.md`. Do not add many unique materials or per-frame AI loops without measurement.
- World sectors should be independently loadable even if the first district is loaded all at once.

## Verification commands

1. `pwsh -File .\tools\bootstrap.ps1`
2. Once engines exist: `& .\.tools\godot\godot.exe --headless --path .\game --editor --quit` for import/parse validation.
3. `py -3.13 -m unittest discover -s tests` for Python tooling tests when present.
4. Run Blender generators through `blender --background --python ... -- <args>`; inspect JSON reports and GLB imports.
5. Launch a playable build and inspect seafront, old town, castle silhouette and a mission frame. Record hardware/FPS and screenshots. Do not claim 60 FPS without measurement.

## Definition of done

An implemented system has a concrete scene/script/data path, a passing relevant validation, and one end-to-end interaction or visual check where feasible. Mark unverified work `IMPLEMENTED BUT NOT VERIFIED`. Record blockers honestly. Update docs and tasks with each milestone. Never substitute TODO comments for working behavior.
