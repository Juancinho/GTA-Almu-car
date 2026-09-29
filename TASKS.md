# Tasks

Status vocabulary: **DONE**, **IMPLEMENTED BUT NOT VERIFIED**, **BLOCKED**, **PLANNED**. Update with proof (command result, file, screenshot, playthrough) before changing status.

| ID | Description | Dependencies | Status | Acceptance criteria / evidence |
|----|-------------|--------------|--------|--------------------------------|
| SETUP-001 | Inspect Windows/tool environment | None | DONE | Versions, paths, GPU, disk and Codex diagnostics in `SETUP_STATUS.md`. |
| SETUP-002 | Initialize Git/LFS and repository layout | SETUP-001 | DONE | Git repository, attributes/ignore and documented directories. |
| SETUP-003 | Bootstrap Godot/Blender | SETUP-001 | BLOCKED | `tools/bootstrap.ps1` exits 0 with compatible engines; engines missing on 2026-09-29. |
| DESIGN-001 | Define first playable and art/world rules | SETUP-001 | DONE | Design documents and decision log present; gameplay subject to later tests. |
| WORLD-001 | Build world coordinate + OSM import pipeline | SETUP-003 | PLANNED | Cached legal source, deterministic transform, unit tests and manifest. |
| WORLD-002 | Greybox seafront district | SETUP-003 | PLANNED | 3 connected streets, beach/promenade, old-town rise, castle silhouette, collision and screenshot. |
| GAME-001 | Third-person player and camera | WORLD-002 | PLANNED | Walk/run/jump/orbit/interaction in playable smoke test. |
| GAME-002 | First driveable compact car | GAME-001 | PLANNED | Enter/drive/reverse/brake/exit on test route. |
| ART-001 | Shared Blender generation framework | SETUP-003 | PLANNED | Deterministic building/palm/car GLBs with validation reports and Godot import. |
| GAME-003 | Pedestrian and traffic simulation | GAME-002, WORLD-002 | PLANNED | Budgeted movement and basic avoidance in gameplay. |
| GAME-004 | Wanted/police level 0–2 | GAME-003 | PLANNED | Witnessed incident, chase, search, escape tests. |
| GAME-005 | Objective framework and El Recado | GAME-004 | PLANNED | Complete fresh-start mission with save/restart. |
| UI-001 | HUD, minimap, pause, settings, audio buses | GAME-005 | PLANNED | Legible UI, correct markers, pause/restart/save/load and original sounds. |
| PERF-001 | Optimization and release smoke pass | UI-001, ART-001 | PLANNED | Measured 1080p performance, visual QA, Windows build and licenses. |
