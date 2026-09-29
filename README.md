# Brisa de Poniente

An original third-person coastal action game prototype set in a compressed, fictionalized interpretation of Almuñécar, Granada. Working title: **Brisa de Poniente**. It evokes the Costa Tropical without using a proprietary franchise name. The name is provisional; see [decisions](docs/DECISIONS.md).

## Current state

M0 repository and design foundation are in progress. The game is **not yet playable**. Godot 4.7.x and Blender 5.2 LTS are missing; follow [SETUP_STATUS.md](SETUP_STATUS.md), then run `pwsh -File .\tools\bootstrap.ps1`.

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

All bespoke game content should be original or use a recorded compatible license. Any OpenStreetMap data use requires visible attribution and ODbL handling described in [world design](docs/WORLD_DESIGN.md). No OSM request occurs during gameplay.
