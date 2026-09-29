# Roadmap

Milestones are ordered by prerequisites. A milestone is complete only when its acceptance evidence is recorded in `TASKS.md`; design text alone does not qualify.

| Milestone | Deliverable | Acceptance criteria |
|-----------|-------------|---------------------|
| M0 | Reproducible environment and repository | Tools detected, setup guide and bootstrap, docs, Git/LFS, headless engine commands demonstrated. Currently blocked on Godot/Blender. |
| M1 | Small greybox district | Sea/beach, promenade, 3+ connected streets, rise toward castle, static collision and traversal screenshot. |
| M2 | Player | Walk, sprint, jump, orbit camera, interact prompt; keyboard and controller smoke test. |
| M3 | First car | Enter, drive, brake/reverse, exit without clipping; satisfying handling test route. |
| M4 | Procedural art | Reproducible building/palm/car generation, recognizable seafront and castle silhouette, visual review. |
| M5 | Pedestrians | 12+ varied NPCs, idle/wander/flee, distance budget measured. |
| M6 | Traffic | Moving lane-following vehicles, basic avoidance and spawn budget. |
| M7 | Police | Witnessed incident → level 1/2 pursuit → search → escape; no permanent omniscience. |
| M8 | Mission framework | Objective resources, progress/restart/save/load tests. |
| M9 | El Recado | Fresh-start complete mission from NPC to castle drop with police escape. |
| M10 | UI/minimap/audio | HUD, minimap, pause/settings, original placeholder sound buses and controls. |
| M11 | Optimization | Recorded 1080p profile on target class PC, scalable settings, major spikes fixed. |
| M12 | Polish | Visual QA pass, regression playthrough, credits/licenses and distributable Windows build. |

Do not start a later feature merely to populate a checklist when its preceding playable interaction is broken.

## Current evidence (2026-09-29)

M0 is complete. M1–M10 have initial implementations in one small district; headless import, three Python tests, asset/hash checks and two gameplay tests pass. `game/tests/route_trial.gd` starts at the seafront, sends movement and interaction input, drives the street network, triggers a witnessed incident, escapes police and completes the castle delivery without teleporting. This establishes technical reachability, **not human handling quality**. Screenshot review covered seafront, town, car and castle views. The next work is a human playthrough, route/police tuning, integration of generated car/building models and measured performance before M11/M12 can be accepted.
