# Brisa de Poniente

An original third-person open-world crime game in a 1:1 recreation of Almuñécar, Granada. Working title: **Brisa de Poniente**. The long-term product goal is a full game with detailed streets and interiors, a broad vehicle fleet, combat, systemic police response, varied characters and a substantial story. The playable build is still an early prototype; see [design](docs/GAME_DESIGN.md), [roadmap](docs/ROADMAP.md) and [tasks](TASKS.md).

## Current state

An early playable prototype runs in Godot 4.7.2. The previously committed district passed automated and human El Recado playthroughs, with performance evidence in [performance](docs/PERFORMANCE_BUDGET.md) and `docs/evidence/`. An in-progress replacement now generates a larger 1:1 central sector. It imports, launches and passes smoke and damage tests, but its full mission route currently stalls near the old town. This migration is unfinished; see [tasks](TASKS.md).

## Run and verify

From the repository root on Windows:

```powershell
pwsh -File .\tools\run.ps1
```

The launcher refreshes Godot's script-class registry before opening the game. This is useful after the current sector migration added `SectorWorld` and moved `world.gd`. For validation, run `pwsh -File .\tools\validate.ps1`; `-Perf` adds fullscreen route benchmarks. The full route test is currently under review with the new sector, so a validation failure there does not imply the game cannot launch.

Start near the seafront. Move with WASD, aim the camera with the mouse, sprint with Shift, jump with Space and interact with E. Find Alba on the promenade to begin **El Recado**. In a car, WASD drives, Space is the handbrake and E exits; the camera settles behind the car when you stop moving the mouse. Driving through the old-town pedestrian zone in view of pedestrians calls the police: break line of sight to lose them, and do not stop next to a patrol or you will be arrested and sent back to the car. Escape pauses; R restarts; F5/F9 save/load; F3/F4 cycle quality and volume; F2 shows FPS; F6 writes a session report; F11 toggles fullscreen. Gamepad: left stick move, right stick camera, A jump, X interact, B brake, LB sprint, Start pause.

Every interactive session writes `generated/playtests/session_<time>_human.json` when the mission is completed, on restart or when the window closes (after 20 s): objective timestamps, police and arrest events, input device counts and frame times per context. Attach it as playtest evidence.

`pwsh -File .\tools\validate.ps1 -Capture` also renders a seafront frame to `generated/`. See [SETUP_STATUS.md](SETUP_STATUS.md) for the exact local tool versions.

## Repository

| Path | Responsibility |
|------|----------------|
| `game/` | Godot project, scenes, scripts and imported runtime assets. |
| `tools/world/` | OSM import, coordinate conversion and deterministic layout tools. |
| `tools/blender/` | Parametric mesh/material/animation generators. |
| `assets/` | Curated, source controlled non-Godot content and licenses. |
| `source_assets/` | Editable original source assets and legally acquired inputs. |
| `generated/` | Rebuilt outputs; ignored except documentation. |
| `tests/` | Focused tooling and gameplay validation. |
| `docs/` | Working design, budgets, pipeline and decisions. |

The current development step is to make the new 1:1 central sector reliable, then raise its street-level art quality and build the first detailed interior, combat loop and story chapter. The complete-game target remains in the roadmap. Contributions must follow [AGENTS.md](AGENTS.md).

## Data and licensing

All bespoke game content is original or uses a recorded compatible license. People, cars and surface textures currently include CC0 assets by Quaternius and ambientCG, imported reproducibly by `tools/third_party/import_assets.py` (see [asset pipeline](docs/ASSET_PIPELINE.md) and `game/assets/third_party/CREDITS.md`). Additional PBR texture candidates and their licences are recorded there before import. The cached OSM reference extract requires attribution and ODbL handling described in [world design](docs/WORLD_DESIGN.md). The new central sector is generated from cached world data; no network request occurs during gameplay.
