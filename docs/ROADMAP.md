# Roadmap

The full open-world scope (every pillar, status and next priorities) is tracked in `docs/GTA_SCOPE.md`.

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

## Update (2026-09-29, evening)

A human fresh-launch playthrough on the GTX 1650 PC completed El Recado in 92.8 s, escaping a road-following police pursuit; in-game frame times held the 120 Hz cap on foot, driving and in pursuit. M2, M3, M7 and M9 now have human evidence (`docs/evidence/`). Open for the slice: human pause/save/load/restart (QA-002), confirmed native 1080p and a Windows export (PERF-001, BUILD-001), street-facing façades (ART-003) and road-graph traffic (GAME-006).

## Next milestones (after the first vertical slice)

| Milestone | Deliverable | Acceptance criteria |
|-----------|-------------|---------------------|
| M13 | Real Puerta del Mar (S1) | OSM/DEM-generated sector with façade kit, Paseo landmarks, beach; El Recado rerouted; reference comparisons (WORLD-004/005, ART-005/007). |
| M14 | Combat and crime | Weapons, aiming, armour, holdups, wanted 3–5 (GAME-009…012). |
| M15 | Old town, castle and interiors | S2/S3 with castle and church, interior framework, safehouse and shops (WORLD-006, ART-006/008, INT-001…003). |
| M16 | Transport | Motorbikes, bicycles, boats, bus/taxi jobs (GAME-013…015, WORLD-009). |
| M17 | First story chapter | Missions 2–6 with authored dialogue, route tests and human logs (MIS-001…003). |
| M18 | Whole central town + chapter finale | S4/S5, streaming, missions 7–12, day/night, radio (WORLD-007/008, VIS-002, AUD-001, MIS-004). |
| M19 | Complete-game production | Expand to the remaining districts and roughly 30–40 main missions in three chapters; varied interiors, vehicles, combat, side activities and a recurring cast. Track each finished feature in TASKS. |
| M20 | Release candidate | Windows export, credits/licences, accessibility, full campaign regression, performance across every sector and a reviewed final art/audio pass. |

## Migration review (2026-09-30)

The in-progress 1:1 central-sector replacement contains 1,252 generated buildings after removing footprints that overlapped driveable roads. Import, smoke, damage, traffic, water, clearance and the automated El Recado route pass. The Jaime chiringuito mission, Taller Poniente, Mercado Azul, La Brisa, Caja Poniente and Joyería Faro now have playable interactions. The venues are first-pass furnished rooms; façades, water, interiors and the overall street scene still fall short of the requested high-quality visual target. PROD-001 remains open until human traversal and visual review confirm the sector.

## Continuation handoff (2026-09-30)

Weapon grips, the four inherited new venues, the casino upper floor and Inés's **Cuentas pendientes** now have automated and screenshot evidence in `docs/evidence/continuation_2026-09-30.md`. A hidden archive rewards exploration and persists its discovery. The casino traversal test walks up/down the stairs and saves inside the office; it is part of the standard validator.

Next production priorities remain: profile exterior frame-time spikes (the current 1080p stationary sample is 67.9 average / 39.1 FPS 1% low); human review of the new interior and aiming in motion; final authored interior/character art and sound; then expand walkable residential buildings, original fictional backstreets and side missions in measured slices. Do not close D-017, INT-006 or QA-004 on the basis of these additions.

The combat/water continuation adds shared physical hits for every shooter, saved breakable venue glass, procedural swimming and measured AI braking. It preserves chapter-one progression and casino traversal. Evidence and remaining scope are in `docs/evidence/combat_water_2026-09-30.md`; stable-60 acceptance for the expanded district is now tracked explicitly as PERF-002. Next combat work includes vehicle glazing, visible NPC firearms/aim poses, cover and reaction polish; traffic needs junction priority and lateral clearance. Complete these with worst-case performance and human checks before increasing district/population density or expanding the campaign.

## Neighbourhood and contact priority (2026-09-30)

The next slice supplies visible street collision, limited static step climbing, separate chassis/rounded tyre support and seated-driver correction. Six service shops and three residential buildings add 21 total enterable venues with six upstairs apartments. Nearby skaters/workers/dancers and adult beach residents broaden life without claiming full schedules. Physical NPC firearms, blue underwater fog, 32 movable chairs and wrapping HUD panels complete connected interactions.

Follow `docs/evidence/neighborhood_2026-09-30.md` for validation and measured limits. Do not close M11/M12 or D-017: campaign chapters two/three, final art, full suspension, vehicle glazing, crowded-room navigation, apartment ownership/activities, release export and stable frame-time acceptance remain. Prioritize those gaps and human traversal over more footprint filler. Every next expansion needs a measured GPU/AI budget and a complete playable route.
