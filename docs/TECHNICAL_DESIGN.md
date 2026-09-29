# Technical design

## Runtime structure

Godot 4.7.x standard build, GDScript, Forward+ initially; measure compatibility renderer if GTX 1650 performance warrants it. `game/project.godot` is the project root. One `WorldRoot` loads the first district as a sector scene. Later districts can use the same sector interface without an early streaming framework.

| Subsystem | Responsibility | Boundary |
|-----------|----------------|----------|
| Player | CharacterBody3D locomotion, camera rig, interaction probe | Emits interaction intent; does not own mission logic. |
| Vehicle | Arcade tune resource, steering/engine/damage state, seats | Exposes enter/exit and drive state. |
| NPC | Small finite state machine, perception budget | Receives incidents and navigation goals. |
| Traffic | Lane graph and pooled vehicles | Near player: active; far: simplified/despawned. |
| Police | Witness report, last known position, search timer | Owns wanted state; mission subscribes to signals. |
| Mission | Data-driven objective resources and state machine | No hardcoded whole mission in HUD/player script. |
| UI | HUD, minimap, menus | Observes game state, never changes simulation directly. |
| Save | Versioned JSON snapshot with validation | Stores stable IDs, not node paths. |

## Data and coordinates

Meters are Godot units; X east, Z south, Y up. OSM input conversion and level compression are specified in `WORLD_DESIGN.md`. Generator outputs stable IDs and a manifest. Roads produce both visible geometry and lane/navigation metadata from one source. Runtime never calls OSM or Blender.

## Validation gates

1. Python unit tests for coordinate transform, deterministic seeds, topology and serialization.
2. Blender headless generation plus bounds, face count, UV/material and GLB report checks.
3. Godot headless import/parse with zero errors.
4. Interactive walk/drive/mission smoke test with saved evidence and screenshot review.
5. Measured FPS and profiler capture before claiming target performance.

Temporary placeholder art is allowed when it makes a real behavior test possible and is labelled. Runtime code must not silently depend on a generated file missing from the repository or build pipeline.
