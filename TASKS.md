# Tasks

Status vocabulary: **DONE**, **IMPLEMENTED BUT NOT VERIFIED**, **BLOCKED**, **PLANNED**. Update with proof (command result, file, screenshot, playthrough) before changing status.

| ID | Description | Dependencies | Status | Acceptance criteria / evidence |
|----|-------------|--------------|--------|--------------------------------|
| SETUP-001 | Inspect Windows/tool environment | None | DONE | Versions, paths, GPU, disk and Codex diagnostics in `SETUP_STATUS.md`. |
| SETUP-002 | Initialize Git/LFS and repository layout | SETUP-001 | DONE | Git repository, attributes/ignore and documented directories. |
| SETUP-003 | Bootstrap Godot/Blender | SETUP-001 | DONE | `tools/bootstrap.ps1` exits 0 with Godot 4.7.2 and Blender 5.2.2 LTS. |
| DESIGN-001 | Define first playable and art/world rules | SETUP-001 | DONE | Design documents and decision log present; gameplay subject to later tests. |
| WORLD-001 | Build world coordinate + OSM reference pipeline | SETUP-003 | DONE | One cached 1.5 MB OSM extract, metadata/hash, 1,973 normalized features, axis/roundtrip/simplification unit tests. Runtime integration is separate work. |
| WORLD-002 | Greybox seafront district | SETUP-003 | DONE | 3 east-west and 4 north-south roads (now `game/data/world/road_network.json`), beach/promenade, castle and Peñón silhouettes, collisions, seafront/town/castle captures. Human session `docs/evidence/session_2026-09-29T20-13-03_human.json` (111 s, 72 key presses, 1,364 mouse motions, no gamepad) walked the promenade and drove seafront → old town → castle without blocking geometry. |
| GAME-001 | Third-person player and camera | WORLD-002 | DONE | Walk/sprint/jump smoke; spring-arm camera and driving auto-follow added 2026-09-29. Human session `docs/evidence/session_2026-09-29T20-13-03_human.json` (111 s, 72 key presses, 1,364 mouse motions, no gamepad): walked spawn → Alba (21 s) → car (42 s) with mouse camera; tester reported controls “va perfecto”. |
| GAME-002 | First driveable compact car | GAME-001 | DONE | Brake/reverse, handbrake turn, smoothed steering and normal-based impacts; smoke + road-path route trial pass. Human drove the full El Recado route and post-mission free roam; tester approved handling. Tuning continues under QA. |
| ART-001 | Shared Blender generation framework | SETUP-003 | IMPLEMENTED BUT NOT VERIFIED | Deterministic building/palm/car GLBs, reports and Godot imports pass; palm visually reviewed, building/car integration pending. |
| GAME-003 | Pedestrian and traffic simulation | GAME-002, WORLD-002 | IMPLEMENTED BUT NOT VERIFIED | 15 pedestrians and 3 traffic cars; smoke verifies traffic movement; avoidance and budget playtest pending. |
| GAME-004 | Wanted/police level 0–2 | GAME-003 | DONE | Road-graph police spawn near the witness, lose sight behind buildings, sweep toward last seen heading, arrest a slow player (smoke). Route trial: 9–11 s seen pursuit, 10–30 s evasion. Human session: escaped a level-1 pursuit during the mission (t 60.8 → 79.6 s) and was arrested once in free roam (t 106.6 s). |
| GAME-005 | Objective framework and El Recado | GAME-004 | DONE | JSON objectives with `fail_checkpoint`; arrest returns to “Entra en el coche rojo”. Human fresh launch completed El Recado with controls only in 92.8 s (`mission_completed` event). |
| UI-001 | HUD, minimap, pause, settings, audio buses | GAME-005 | IMPLEMENTED BUT NOT VERIFIED | HUD street names, arrest progress, police minimap blips, F2 perf overlay, F6 session report, F11 fullscreen. Human used HUD/minimap during the mission; human pause, save/load, restart and F3/F4 not yet exercised (no such events in the session log). Pause/save/load smoke passes. |
| WORLD-003 | Design layer over OSM (supersedes compressed layout) | WORLD-001 | PLANNED | `source_assets/world/design_layer.json` with per-feature offsets/overrides and reasons; tool applies it deterministically; unit tests. |
| ART-002 | Integrate and review generated car/building models | ART-001, GAME-002 | IMPLEMENTED BUT NOT VERIFIED | Compact car GLB replaces runtime car boxes and has a rear-view screenshot; generated building integration, close/mid/far review and seat validation remain. |
| QA-001 | Full human playthrough and handling/pursuit tuning | GAME-005, UI-001 | DONE | Human session `docs/evidence/session_2026-09-29T20-13-03_human.json` (111 s, 72 key presses, 1,364 mouse motions, no gamepad): fresh launch → El Recado complete with controls only, real police pursuit escaped, one arrest in free roam, no blocking geometry. Automated: `validate.ps1 -Perf` VALIDATION PASS on Windows. Remaining UI checks tracked in QA-002. |
| PERF-001 | Optimization and in-game performance | UI-001, ART-001 | DONE | `validate.ps1 -Perf` on GTX 1650 / Ryzen 5 5600H, fullscreen 1920×1080 with animated CC0 people and textures (`docs/evidence/session_2026-09-29T21-0*`): vsync 120.0 FPS avg and 1 % low (max 8.43 ms); uncapped 455.3 FPS avg, 360 FPS 1 % low, max 5.23 ms, ≤617 draw calls, ≤515k primitives across on_foot/driving/pursuit. Export and licences moved to BUILD-001. |
| QA-002 | Human pause/save/load/restart and settings check | UI-001 | PLANNED | Session log shows pause, F5/F9, R and F3/F4 events with a valid restored position; free-roam evasion outside the mission. |
| ART-003 | Street-facing façades, doors and shopfronts | ART-002, WORLD-002 | DONE | MultiMesh façade dressing in `world.gd`; captures reviewed; measured within PERF-001 (≤617 draw calls); tester reviewed the new look (“mejor”). |
| GAME-006 | Traffic on the road graph | GAME-003, WORLD-002 | IMPLEMENTED BUT NOT VERIFIED | 12 lane-following cars with visible drivers, random turns, deadlock reversal; `tests/traffic_soak.gd` 60 s: 0 jammed, 479–585 m each. Human feel and -Perf re-measure pending. |
| BUILD-001 | Windows export and credits/licenses | PERF-001 | PLANNED | Exported .exe launches outside the editor, credits list OSM ODbL and original assets. |
| ART-004 | CC0 people, cars and PBR textures | ART-001, GAME-003 | DONE | Pinned CC0 import pipeline with hashes (`validate.ps1` check passes on Windows); animated people, mission/police/traffic cars and triplanar textures in play; performance in PERF-001; tester reviewed the look (“mejor”). |
| GAME-007 | Health, damage, wasted and hospital respawn | GAME-004 | IMPLEMENTED BUT NOT VERIFIED | Punch, knockdowns, run-over reports, vehicle damage/fire/explosion, HAS MUERTO → health centre (-100 €); `tests/damage_test.gd` passes headless. Windows validation and human play pending. |
| GAME-008 | Carjacking and money | GAME-006, GAME-007 | IMPLEMENTED BUT NOT VERIFIED | Carjack ejects fleeing driver (smoke test); money HUD, +500 € mission reward, -100 € arrest/death, saved. Police-witnessed carjacking still to add. |
| VIS-001 | Sky, sea and atmosphere | ART-004 | PLANNED | Procedural sky with sun, distance fog, animated sea; frame time re-measured with -Perf. |
| UI-002 | GTA-style HUD | UI-001, GAME-007 | IMPLEMENTED BUT NOT VERIFIED | Stars, health bar, money and banners done; armour bar and round minimap pending (UI-003). |

## Faithful Almuñécar world

| ID | Description | Dependencies | Status | Acceptance criteria / evidence |
|----|-------------|--------------|--------|--------------------------------|
| WORLD-004 | Terrain from CNIG MDT05 | WORLD-001 | PLANNED | Cached tiles with URL/date/hash/CC BY 4.0 note; 1 m heightmap for S1–S5; roads flattened; height error vs source < 0.5 m on 20 sample points (unit test). |
| WORLD-005 | Generate S1 Puerta del Mar from OSM at 1:1 | WORLD-003, WORLD-004, ART-005 | PLANNED | Roads/lane graph, pavements, buildings from footprints with zone storeys, coastline and beach from data; greybox removed for S1; El Recado rerouted and its route test passes; screenshots vs references. |
| WORLD-006 | Generate S2 old town and S3 castle/San Miguel | WORLD-005 | PLANNED | Pedestrian lanes and steps walkable, restricted driving zones, slopes from DEM; castle and church placed on real footprints. |
| WORLD-007 | Sector streaming | WORLD-005 | PLANNED | Sectors load/unload by distance without hitches > 8 ms on GTX 1650 (-Perf trace); save/load across sectors. |
| WORLD-008 | S4 San Cristóbal and S5 modern centre | WORLD-006 | PLANNED | Peñón, Najarra, beaches, avenues and bus station; traffic across all sectors. |
| WORLD-009 | Sea, beaches and coastline | WORLD-005, VIS-003 | PLANNED | Dark gravel beaches with real profiles, boats, shoreline foam, swimming/boat boundaries. |
| WORLD-010 | Expansion S6: Velilla, Cotobro, N-340, Marina del Este | WORLD-008 | PLANNED | New OSM/DEM extracts, highway driving and marina. |

## Art to the fidelity bar

| ID | Description | Dependencies | Status | Acceptance criteria / evidence |
|----|-------------|--------------|--------|--------------------------------|
| ART-005 | Almuñécar façade kit | ART-003 | PLANNED | Modular whitewash kit (ground floors, balconies, rejas, plinths, roofs/terraces, seafront block variant) generated in Blender with reports; per-zone palette; 20 reference comparisons. |
| ART-006 | Hero landmark: Castillo de San Miguel | WORLD-006, ART-010 | PLANNED | Curtain walls, four round entrance towers, ramps, courtyard; matches reference board from 5 viewpoints; LODs. |
| ART-007 | Hero landmarks: Peñón del Santo, Phoenician monument, Paseo | WORLD-005, ART-010 | PLANNED | Rock with stairs, pines, cross and viewpoint; promenade paving, palms, lamps, monument. |
| ART-008 | Hero landmarks: Iglesia de la Encarnación, Plaza de la Constitución, Najarra, aqueduct, Majuelo ruins | WORLD-006, ART-010 | PLANNED | Each accepted against its reference board (day and night). |
| ART-009 | Vegetation and props | ART-005 | PLANNED | 5 palm species, ficus, bougainvillea, orange trees, subtropical orchard terraces; benches, bins, lamps, kiosks, loungers, boats; instanced with LODs. |
| ART-010 | Reference photo library | none | PLANNED | `source_assets/reference/<place>/` with licence notes for every landmark and sector. |
| ART-011 | Character roster | ART-004 | PLANNED | ≥ 24 varied locals/tourists/workers, police units, story characters; aim/shoot/hit/talk/phone/sit animations. |
| ART-012 | Vehicle fleet | ART-004 | PLANNED | Compact, saloon, SUV, van, sports, scooter, motorbike, bicycle, bus, taxi, police car/bike, ambulance, boats; damage states and lights. |

## Visuals and audio

| ID | Description | Dependencies | Status | Acceptance criteria / evidence |
|----|-------------|--------------|--------|--------------------------------|
| VIS-002 | Day/night cycle and street lighting | VIS-001 | PLANNED | 24 h cycle, sodium lamps, lit windows, headlights; -Perf at noon and midnight. |
| VIS-003 | Sea and water shader | VIS-001 | PLANNED | Animated waves, turquoise shallows, foam at shore, boat wakes. |
| AUD-001 | Original music, radio and ambience | none | PLANNED | Original tracks only, in-car radio stations, sector ambience, sirens and vehicle audio with licences recorded. |

## Gameplay systems

| ID | Description | Dependencies | Status | Acceptance criteria / evidence |
|----|-------------|--------------|--------|--------------------------------|
| GAME-009 | Weapons and aiming | GAME-007 | PLANNED | Bat, knife, pistol, SMG, shotgun, rifle, molotov, grenade; over-shoulder aim, gamepad soft lock, reload/ammo, hit reactions, weapon wheel; combat test. |
| GAME-010 | Armour, pickups and healing | GAME-009 | PLANNED | Armour bar, bar food/drink heals, ammo/health pickups; tests. |
| GAME-011 | Shop and petrol-station holdups | GAME-009, INT-003 | PLANNED | Aim at clerk → cash → alarm → police response; repeatable with cooldown; test. |
| GAME-012 | Wanted levels 3–5 | GAME-004, GAME-009 | PLANNED | Escalating units, roadblocks, spike strips, helicopter, respray clears; escape test at each level. |
| GAME-013 | Motorbikes, scooters and bicycles | GAME-002 | PLANNED | Lean/handling, fall-off on crash, fits old-town lanes; route test through Calle Real. |
| GAME-014 | Boats | WORLD-009 | PLANNED | Fishing boat, speedboat, jet ski with buoyancy and wake; sea chase test. |
| GAME-015 | Bus, taxi and delivery side jobs | GAME-006 | PLANNED | Bus route stops, taxi fares, deliveries with pay; tests. |
| GAME-016 | Phone, contacts and GPS | UI-003 | PLANNED | Calls/texts start missions, GPS route on road graph. |
| GAME-017 | Safehouses, garages, property | INT-002 | PLANNED | Save/load at beds, stored vehicles persist, buyable property income. |
| GAME-018 | Cover, crouch and climbing | GAME-009 | PLANNED | Snap to cover, blind fire, vault low walls; test course. |
| GAME-019 | Pedestrian interactions | GAME-003 | PLANNED | Talk, ask directions, intimidate, pickpocket, crowd panic to gunfire. |

## Interiors

| ID | Description | Dependencies | Status | Acceptance criteria / evidence |
|----|-------------|--------------|--------|--------------------------------|
| INT-001 | Interior framework | WORLD-005 | PLANNED | Door triggers on real façades, interior scenes load < 1 s, lighting, navmesh, save inside. |
| INT-002 | Safehouse flat on the Paseo | INT-001 | PLANNED | Bed save, wardrobe, stash, balcony view of the sea. |
| INT-003 | Shops: 24 h shop, gun shop, clothes/barber, garage | INT-001 | PLANNED | Buying works, holdup hooks, respray. |
| INT-004 | Beach bar, bank, jewellery shop, police station, health centre | INT-001 | PLANNED | Mission-ready layouts. |
| INT-005 | Heritage interiors: castle museum, Cueva de Siete Palacios, Najarra, church | INT-001, ART-006, ART-008 | PLANNED | Faithful to references; used by missions 5–11. |

## Missions

| ID | Description | Dependencies | Status | Acceptance criteria / evidence |
|----|-------------|--------------|--------|--------------------------------|
| MIS-001 | Mission scripting v2 | GAME-005 | PLANNED | Objectives with triggers, dialogue lines, cutscene cameras, checkpoints, fail states, rewards as data; editor-friendly; unit tests. |
| MIS-002 | Missions 2–4 (chiringuito, cuota, pescadores) | MIS-001, GAME-013, GAME-014 | PLANNED | Each has a scripted-input route test and a human playthrough log. |
| MIS-003 | Missions 5–8 (Majuelo, Siete Palacios, furgón, Najarra) | MIS-002, INT-005, GAME-011 | PLANNED | Same. |
| MIS-004 | Missions 9–12 (lancha, Calle Real, castillo, Poniente) | MIS-003, GAME-012 | PLANNED | Same, plus credits roll. |
| MIS-005 | Side activities and collectibles | GAME-015 | PLANNED | Taxi, bus, races, vigilante, Phoenician coins. |

## UI and production

| ID | Description | Dependencies | Status | Acceptance criteria / evidence |
|----|-------------|--------------|--------|--------------------------------|
| UI-003 | Round minimap, full map with real street names, waypoints | WORLD-005 | PLANNED | Map drawn from OSM layer with ODbL attribution; waypoint GPS. |
| UI-004 | Main menu, settings, pause with restart; key remap | UI-001 | PLANNED | R moves to pause menu, remapping saved. |
| QA-003 | Scripted regression suite per sector | WORLD-005 | PLANNED | Walk/drive/traffic/police soak per sector in validate.ps1. |
