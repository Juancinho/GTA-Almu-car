# Agent instructions

## Scope and architecture

- Advance the smallest complete playable loop first. Follow `TASKS.md` dependencies and update statuses with evidence.
- The product target is a full original open-world crime game (D-017): detailed Almuñécar districts and interiors, a varied fleet and weapon roster, systemic activities, character-led dialogue and a multi-chapter campaign. The current 12 missions are only chapter one. Build this in finished, tested slices; do not present the prototype as the complete product.
- `game/` contains runtime code. Keep player, vehicle, pedestrian, traffic, police, mission and UI systems separate. Use data/resources for mission definitions and vehicle tuning.
- `tools/world/` owns geographic transformation and edited district data. `tools/blender/` owns asset generation. Never hand-edit an output in `generated/`; edit its source/seed and regenerate.
- Keep deterministic seeds and input provenance in generation reports. Do not fetch network data during the game.
- Avoid proprietary game assets, unlicensed music, and other games' maps, names and UI. The 1:1 Almuñécar sector uses OSM (ODbL); terrain is provisional until CNIG MDT05 (CC BY 4.0) is integrated. Preserve required attribution. Real public place and street names are allowed, while businesses, brands, characters and police insignia stay fictional (D-013, D-014).
- Source high-quality PBR textures from licence-verified sources. Record URL, author, licence, map types and hashes before import; inspect material scale and visuals in-game and measure VRAM/frame time. `docs/ASSET_PIPELINE.md` holds researched candidates.
- Art must meet `docs/ART_DIRECTION.md`: no shipped flat untextured primitives; every landmark is accepted against its reference board with day and night captures.

## Style and performance

- GDScript: typed public interfaces, small scene-bound scripts, explicit signals, no hidden global state beyond justified autoload services. Use snake_case for files and identifiers.
- Python: type hints for tooling interfaces, argparse CLI, useful errors including asset/stage/path, deterministic behavior. Blender generators must validate mesh bounds, polygon counts, UVs when needed, materials and export files.
- Favor instancing, low-poly silhouettes, cheap collision, distance-based simulation and budgets in `docs/PERFORMANCE_BUDGET.md`. Do not add many unique materials or per-frame AI loops without measurement.
- World sectors should be independently loadable even if the first district is loaded all at once.

## Verification commands

1. `pwsh -File .\tools\run.ps1` refreshes new GDScript class registration and launches the game; `-ImportOnly` checks import without opening a window. `pwsh -File .\tools\validate.ps1` checks dependencies, Python, asset reports, Godot import, smoke, damage, traffic and a full mission route. It fails on Godot stderr errors even if the Windows GUI executable returns 0. The in-progress 1:1 migration currently stalls in the route test (PROD-001).
2. `pwsh -File .\tools\validate.ps1 -Capture` also renders a seafront frame. Other views: `godot --path game --script res://tests/capture.gd -- --view town|castle|car` (use the project-local executable).
3. Regenerate Blender assets with `blender --background --python tools/blender/generate.py -- --kind palm|building|compact_car --seed 7401 --out game/assets/procedural/<kind>.glb`; inspect JSON reports and GLB imports.
4. Run `godot --path game --script res://tests/performance.gd` for an indicative 1920×1080 offscreen sample, then launch a playable build and inspect seafront, old town, castle silhouette and a mission frame. Record hardware/FPS and screenshots. Do not claim stable 60 FPS from the offscreen sample alone.

## Definition of done

An implemented system has a concrete scene/script/data path, a passing relevant validation, and one end-to-end interaction or visual check where feasible. Mark unverified work `IMPLEMENTED BUT NOT VERIFIED`. Record blockers honestly. Update docs and tasks with each milestone. Never substitute TODO comments for working behavior.
