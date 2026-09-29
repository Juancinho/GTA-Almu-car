# Tasks

Status vocabulary: **DONE**, **IMPLEMENTED BUT NOT VERIFIED**, **BLOCKED**, **PLANNED**. Update with proof (command result, file, screenshot, playthrough) before changing status.

| ID | Description | Dependencies | Status | Acceptance criteria / evidence |
|----|-------------|--------------|--------|--------------------------------|
| SETUP-001 | Inspect Windows/tool environment | None | DONE | Versions, paths, GPU, disk and Codex diagnostics in `SETUP_STATUS.md`. |
| SETUP-002 | Initialize Git/LFS and repository layout | SETUP-001 | DONE | Git repository, attributes/ignore and documented directories. |
| SETUP-003 | Bootstrap Godot/Blender | SETUP-001 | DONE | `tools/bootstrap.ps1` exits 0 with Godot 4.7.2 and Blender 5.2.2 LTS. |
| DESIGN-001 | Define first playable and art/world rules | SETUP-001 | DONE | Design documents and decision log present; gameplay subject to later tests. |
| WORLD-001 | Build world coordinate + OSM reference pipeline | SETUP-003 | DONE | One cached 1.5 MB OSM extract, metadata/hash, 1,973 normalized features, axis/roundtrip/simplification unit tests. Runtime integration is separate work. |
| WORLD-002 | Greybox seafront district | SETUP-003 | IMPLEMENTED BUT NOT VERIFIED | 3 east-west and 4 north-south roads, beach/promenade, castle and Peñón silhouettes, collisions, seafront/town/castle captures. Full on-foot traversal pending. |
| GAME-001 | Third-person player and camera | WORLD-002 | IMPLEMENTED BUT NOT VERIFIED | Walk/sprint/jump and grounded smoke checks pass; input-driven route walks from spawn to Alba and car. Camera/feel human playtest pending. |
| GAME-002 | First driveable compact car | GAME-001 | IMPLEMENTED BUT NOT VERIFIED | Enter/exit, drive smoke and input-driven multi-street route pass; handling/reverse/obstacle human playtest pending. |
| ART-001 | Shared Blender generation framework | SETUP-003 | IMPLEMENTED BUT NOT VERIFIED | Deterministic building/palm/car GLBs, reports and Godot imports pass; palm visually reviewed, building/car integration pending. |
| GAME-003 | Pedestrian and traffic simulation | GAME-002, WORLD-002 | IMPLEMENTED BUT NOT VERIFIED | 15 pedestrians and 3 traffic cars; smoke verifies traffic movement; avoidance and budget playtest pending. |
| GAME-004 | Wanted/police level 0–2 | GAME-003 | IMPLEMENTED BUT NOT VERIFIED | Witnessed restricted-zone incident, level 1/2 units, search/escape logic and input-driven escape route pass; visible pursuit quality pending. |
| GAME-005 | Objective framework and El Recado | GAME-004 | IMPLEMENTED BUT NOT VERIFIED | JSON objectives and a fresh-start, no-teleport simulated-input route complete El Recado; human playthrough pending. |
| UI-001 | HUD, minimap, pause, settings, audio buses | GAME-005 | IMPLEMENTED BUT NOT VERIFIED | HUD/minimap screenshots, pause/save/load smoke, F3/F4 settings, generated WAVs and separate buses; UI/accessibility playtest pending. |
| WORLD-003 | Reconcile OSM reference with authored road/parcel design | WORLD-001, WORLD-002 | PLANNED | Source IDs and design offsets versioned; selected roads/buildings generated from edited reference without harming mission route. |
| ART-002 | Integrate and review generated car/building models | ART-001, GAME-002 | IMPLEMENTED BUT NOT VERIFIED | Compact car GLB replaces runtime car boxes and has a rear-view screenshot; generated building integration, close/mid/far review and seat validation remain. |
| QA-001 | Full human playthrough and handling/pursuit tuning | GAME-005, UI-001 | PLANNED | Fresh launch completes El Recado with controls only, police can actually pursue and be escaped, no blocking geometry. |
| PERF-001 | Optimization and release smoke pass | UI-001, ART-001 | PLANNED | Measured 1080p performance, visual QA, Windows build and licenses. |
