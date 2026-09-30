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
| MIS-001 | Mission scripting v2 | GAME-005 | IMPLEMENTED BUT NOT VERIFIED | `data/missions/index.json` registry with contacts, unlock chain and blip letters; objectives `talk_to`, `enter_vehicle` (specific vehicle), `reach_area` (anchor/venue/workshop/contact/live target, time limit, on-foot/vehicle/no-wanted), `escape_police`, `destroy_vehicle` (chase, escape distance), `beat_up`, `wait`; multi-line dialogue; spawned vehicles/enemies with reset on failure; suspend/resume; completed missions saved. `tests/missions.gd` passes (VM + cloud). Human playthrough and cutscene cameras pending. |
| MIS-002 | Missions 2–4 (Hielo, La cuota, El coche del concejal) | MIS-001 | IMPLEMENTED BUT NOT VERIFIED | Hielo para el chiringuito (Paco: timed SUV run to Mercado Azul and back, fist fight with two tough gorrones, 300 €), La cuota (Alba: three beach-bar envelopes on foot, ram the fleeing orange sports car, 600 €), El coche del concejal (Alba: steal a car in the old town, lose the police, deliver to Taller Poniente, 800 €). Scripted completion, timeout reset and save/load in `tests/missions.gd`. Pescadores moves to MIS-003 once boats exist (GAME-014). Human playthrough pending. |
| MIS-003 | Missions 5–8 (Majuelo, Siete Palacios, furgón, Najarra) | MIS-002, INT-005, GAME-011 | PLANNED | Same. |
| MIS-004 | Missions 9–12 (lancha, Calle Real, castillo, Poniente) | MIS-003, GAME-012 | PLANNED | Same, plus credits roll. |
| MIS-005 | Side activities and collectibles | GAME-015 | PLANNED | Taxi, bus, races, vigilante, Phoenician coins. |

## UI and production

| ID | Description | Dependencies | Status | Acceptance criteria / evidence |
|----|-------------|--------------|--------|--------------------------------|
| UI-003 | Round minimap, full map with real street names, waypoints | WORLD-005 | IN PROGRESS | Done: GPS route to the objective along the road graph, off-map objective arrow, contact letters, heading arrow, speed-dependent zoom; 3D objective column, target arrows and floating contact letters (`mission_markers.gd`); mission title card, big objective text, countdown and target status. Remaining: full map (M) with street names and player waypoints. |
| UI-004 | Main menu, settings, pause with restart; key remap | UI-001 | PLANNED | R moves to pause menu, remapping saved. |
| QA-003 | Scripted regression suite per sector | WORLD-005 | PLANNED | Walk/drive/traffic/police soak per sector in validate.ps1. |

## Complete-game production targets

These tasks describe the requested end product. They are **PLANNED** until the acceptance evidence exists; the playable build currently covers only a fraction of them.

| ID | Description | Dependencies | Status | Acceptance criteria / evidence |
|----|-------------|--------------|--------|--------------------------------|
| PROD-001 | Stable 1:1 central sector | WORLD-005, QA-003 | IN PROGRESS | Fresh project import, visible launch, smoke, damage, traffic and full mission route pass against the same sector; no blocked objective or disappearing geometry. The current sector passes automated route and clearance checks; human traversal and visual review remain. |
| WORLD-011 | Building façades on slopes | WORLD-005 | IMPLEMENTED BUT NOT VERIFIED | Wall plinths and doors/windows sample local terrain; long seafront balconies use bays. `slope_buildings.gd` passes 83,799 detail positions over 242 steep edges; town capture reviewed. Human slope walk still needed. |
| MIS-006 | Jaime Playa venue and playable mission | WORLD-005, GAME-005 | IMPLEMENTED BUT NOT VERIFIED | Approximate beach-level chiringuito near the Phoenician monument, original sign/model, fictional contact Marina and four-objective music setup mission, available from the start without losing El Recado progress. `jaime_mission.gd` passes completion, €150 reward and save/load; Jaime capture reviewed. Human playthrough and exact location/art reference pass remain. |
| TEX-001 | Curated high-quality PBR material library | ART-005 | PLANNED | Source URL, author, CC0 licence, hashes and map types pinned for façade, stone, road, pavement, roof, sand/gravel and interior materials; correct Godot normal orientation/scale; near/mid/far review and VRAM/frame-time record. Candidate list in ASSET_PIPELINE. |
| INT-006 | Finished interior quality pass | INT-001, TEX-001 | PLANNED | Safehouse, shop, bar and garage each have distinct furnishings, decals, lighting, ambient audio, NPC navigation, working interactions and day/night screenshots. Expand the same review standard to mission interiors. |
| VEH-001 | Broad original vehicle roster | ART-012, GAME-013, GAME-014 | PLANNED | 20+ distinct vehicle archetypes across cars, vans, bikes, public service and boats; detailed exteriors/cabins, handling, lights, damage, sound and LODs; player and AI routes tested. |
| COMBAT-001 | Complete weapon and enemy loop | GAME-009, GAME-012 | PLANNED | Weapon categories, aiming/reload/ammo, hit reactions, cover, hostile AI, police escalation and balance; keyboard/gamepad tests and human combat playtest. |
| NARR-001 | Cast bible and dialogue pipeline | MIS-001 | PLANNED | Character goals, relationships and voice style; data-driven Spanish subtitles with conditional/replay lines, timing and editorial review; original/licensed voice only. |
| NARR-002 | Three-chapter main campaign | MIS-004, NARR-001 | PLANNED | Roughly 30–40 authored missions with varied verbs, checkpoints, rewards, route tests, character beats and human playthrough evidence; the existing 12-mission outline is chapter one. |
| SIDE-001 | Dense side content across the town | GAME-015, WORLD-008 | PLANNED | At least 15 replayable activities with distinct mechanics and rewards, plus secrets and meaningful free-roam interactions; QA per district. |
| QA-004 | Complete-game visual and release review | PROD-001, INT-006, NARR-002 | PLANNED | Day/night and interior reference comparisons, accessibility/subtitle review, full-campaign regression, licence audit, Windows export and measured performance on target hardware. |
| MOVE-001 | Swimming and diving | WORLD-009, GAME-001 | IN PROGRESS | Surface/dive/air and a continuous beach-entry/shore-return playtest pass in `water_and_dressing.gd`; swim animation and rescue handling remain. |
| VEH-002 | Grounded driving and water boundary | GAME-002, WORLD-009 | IN PROGRESS | Car water guard and seated driver pass scripted/visual checks; add suspension, slope-aware traction and shore collision/boat handoff. |
| WORLD-012 | Road and footprint clearance | WORLD-005 | DONE | `check_clearance.py` reports 0/1252 building overlaps; dressing test checks 418 palms plus lamps/benches; town and road captures reviewed. |
| ART-013 | Palm and asphalt material pass | TEX-001, WORLD-012 | IN PROGRESS | Poly Haven CC0 bark/normal and Clean Asphalt diffuse/normal/roughness are pinned by URL/hash and verified; tertiary edge lines and center dashes reviewed in a car capture. Improve frond materials, line junctions, night and close/far performance review. |
| INT-007 | Civilian destinations and services | INT-001, GAME-017 | IN PROGRESS | Taller Poniente repairs a parked car. Six other rooms now sit in physical surveyed buildings with glazed fronts: Mercado Azul, La Brisa, Caja Poniente, Joyería Faro, Iglesia de la Encarnación and Galería Costa Tropical. Food, deposits/withdrawals, one-time jewelry robbery, church rest and gallery food work; `venues.gd` covers entry/exit and saved transactions. The church/mall layouts are initial playable designs, not final heritage/commercial art. Casino, police and fire stations remain. |
| WORLD-013 | Distinct blocks and active seafront | WORLD-005, ART-013 | IN PROGRESS | Deterministic façade finishes, cornices, bays and selective 0.35–0.9 m modern setbacks; 12 named promenade/nearby storefronts include bars, restaurants and an estanco, with safe outdoor tables where space permits. Five additional open beach chiringuitos complement Jaime Playa, each with a staffed meal counter (35 € / full heal) covered by `venues.gd`. Add bespoke architecture, more citywide businesses and human visual review. |
| WORLD-014 | Lived-in town dressing | WORLD-005, ART-005 | IMPLEMENTED BUT NOT VERIFIED | `sector/town_dressing_builder.gd`: rooftop stair huts, water tanks, solar heaters, antennas and AC units; split AC units, geranium pots and bougainvillea aligned to the façade bays; striped canvas shop awnings; recycling containers with collision; zebra crossings at junctions; beach umbrellas, loungers and towels. Warmer façade palettes, green hillsides and a smooth-shaded Sierra backdrop. Instanced per 160 m chunk with short visibility ranges (build adds ~0.3 s). Cloud captures reviewed; Windows -Perf re-measure and human look review pending. |
| LIFE-001 | Denser reactive population | GAME-003, GAME-019 | IN PROGRESS | 56 seeded civilians plus contacts, varied greetings and provoked fights pass `civilian_life.gd`; add civic services, schedules, richer dialogue and measured crowd budgets. |
