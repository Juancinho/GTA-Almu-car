# Brisa de Poniente

An original third-person coastal action game prototype set in a compressed, fictionalized interpretation of Almuñécar, Granada. Working title: **Brisa de Poniente**. It evokes the Costa Tropical without using a proprietary franchise name. The name is provisional; see [decisions](docs/DECISIONS.md).

## Current state

An early playable prototype runs in Godot 4.7.2. Automated tests cover walk/sprint/jump, driving, a witnessed police incident, road-following pursuit, arrest, escape, pause and save/load; a route test completes **El Recado from the seafront spawn with simulated input, without teleports, evading a real pursuit**. A human playthrough on the target PC completed El Recado and in-game frame times held the 120 Hz cap while walking, driving and being chased (see [performance](docs/PERFORMANCE_BUDGET.md) and `docs/evidence/`). Native-1080p confirmation, a Windows export and a few UI checks remain. See [tasks](TASKS.md).

## Run and verify

From the repository root on Windows:

```powershell
pwsh -File .\tools\validate.ps1
pwsh -File .\tools\validate.ps1 -Perf   # adds fullscreen route benchmarks on the real GPU
& .\.tools\godot\godot.exe --path .\game
```

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

The immediate objective is one dense playable district and one complete mission loop. See [roadmap](docs/ROADMAP.md) and [tasks](TASKS.md). Contributions must follow [AGENTS.md](AGENTS.md).

## Data and licensing

All bespoke game content is original or uses a recorded compatible license. People, cars and surface textures are CC0 assets by Quaternius and ambientCG, imported reproducibly by `tools/third_party/import_assets.py` (see [asset pipeline](docs/ASSET_PIPELINE.md) and `game/assets/third_party/CREDITS.md`). The cached OSM reference extract requires attribution and ODbL handling described in [world design](docs/WORLD_DESIGN.md). The currently playable road layout is authored separately from that data. No OSM request occurs during gameplay.
