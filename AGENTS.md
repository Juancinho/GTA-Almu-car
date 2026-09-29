# Agent instructions

## Scope and architecture

- Advance the smallest complete playable loop first. Follow `TASKS.md` dependencies and update statuses with evidence.
- `game/` contains runtime code. Keep player, vehicle, pedestrian, traffic, police, mission and UI systems separate. Use data/resources for mission definitions and vehicle tuning.
- `tools/world/` owns geographic transformation and edited district data. `tools/blender/` owns asset generation. Never hand-edit an output in `generated/`; edit its source/seed and regenerate.
- Keep deterministic seeds and input provenance in generation reports. Do not fetch network data during the game.
- Avoid proprietary game assets, unlicensed music, and other games' maps, names and UI. The world is the real Almuñécar at 1:1 built from licensed data (OSM ODbL, CNIG MDT05 CC BY 4.0) with attribution; real public place and street names are allowed, but businesses, brands, characters and police insignia must be fictional (D-013, D-014).
- Art must meet `docs/ART_DIRECTION.md`: no shipped flat untextured primitives; every landmark is accepted against its reference board with day and night captures.

## Style and performance

- GDScript: typed public interfaces, small scene-bound scripts, explicit signals, no hidden global state beyond justified autoload services. Use snake_case for files and identifiers.
- Python: type hints for tooling interfaces, argparse CLI, useful errors including asset/stage/path, deterministic behavior. Blender generators must validate mesh bounds, polygon counts, UVs when needed, materials and export files.
- Favor instancing, low-poly silhouettes, cheap collision, distance-based simulation and budgets in `docs/PERFORMANCE_BUDGET.md`. Do not add many unique materials or per-frame AI loops without measurement.
- World sectors should be independently loadable even if the first district is loaded all at once.

## Verification commands

1. `pwsh -File .\tools\validate.ps1` checks dependencies, Python, asset reports, Godot import, a scripted smoke test and a full mission route using simulated input. It fails on Godot stderr errors even if the Windows GUI executable returns 0.
2. `pwsh -File .\tools\validate.ps1 -Capture` also renders a seafront frame. Other views: `godot --path game --script res://tests/capture.gd -- --view town|castle|car` (use the project-local executable).
3. Regenerate Blender assets with `blender --background --python tools/blender/generate.py -- --kind palm|building|compact_car --seed 7401 --out game/assets/procedural/<kind>.glb`; inspect JSON reports and GLB imports.
4. Run `godot --path game --script res://tests/performance.gd` for an indicative 1920×1080 offscreen sample, then launch a playable build and inspect seafront, old town, castle silhouette and a mission frame. Record hardware/FPS and screenshots. Do not claim stable 60 FPS from the offscreen sample alone.

## Definition of done

An implemented system has a concrete scene/script/data path, a passing relevant validation, and one end-to-end interaction or visual check where feasible. Mark unverified work `IMPLEMENTED BUT NOT VERIFIED`. Record blockers honestly. Update docs and tasks with each milestone. Never substitute TODO comments for working behavior.
