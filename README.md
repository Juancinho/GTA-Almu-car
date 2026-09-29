# Brisa de Poniente

An original third-person coastal action game prototype set in a compressed, fictionalized interpretation of Almuñécar, Granada. Working title: **Brisa de Poniente**. It evokes the Costa Tropical without using a proprietary franchise name. The name is provisional; see [decisions](docs/DECISIONS.md).

## Current state

An early playable prototype now runs in Godot 4.7.2. Automated tests cover walk/sprint/jump, driving, a witnessed police incident, escape, pause and save/load. A second test completes **El Recado from the seafront spawn with simulated movement and interaction input, without teleports**. A stationary 1080p offscreen performance sample is documented; a human playthrough and sustained in-game 60 FPS measurement are still required. See [tasks](TASKS.md).

## Run and verify

From the repository root on Windows:

```powershell
pwsh -File .\tools\validate.ps1
& .\.tools\godot\godot.exe --path .\game
```

Start near the seafront. Move with WASD, aim the camera with the mouse, sprint with Shift, jump with Space and interact with E. Find Alba on the promenade to begin **El Recado**. In a car, WASD drives, Space brakes and E exits. Escape pauses; R restarts; F5/F9 save/load; F3/F4 cycle quality and volume. Gamepad movement, jump, interact and pause have initial mappings.

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

All bespoke game content is original or uses a recorded compatible license. The cached OSM reference extract requires attribution and ODbL handling described in [world design](docs/WORLD_DESIGN.md). The currently playable road layout is authored separately from that data. No OSM request occurs during gameplay.
