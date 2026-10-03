# Full open-world crime game scope (the "complete GTA" bar)

The owner's target is a complete open-world crime game of the kind a large studio would ship, set in a faithful Almuñécar. This file lists every pillar such a game needs, what exists today, and what is missing, so work can be prioritised against the whole and not only the next feature. Status words: **done** (playable, with an automated test), **partial** (playable but thin or untested by a human), **missing**.

Rules that still apply: each item needs a playable interaction, an automated test where possible, a performance check on the GTX 1650 target (`validate.ps1 -Perf`) and a human pass before it is called finished (see `ROADMAP.md`).

## 1. World

| Pillar | Status | Notes / next step |
|---|---|---|
| 1:1 central town from OSM + terrain | partial | 1,252 buildings, roads, beaches, castle, Peñón. Remaining districts (S4–S6, N-340, Marina del Este) missing. |
| Enterable interiors | partial | 21 venues (shops, casino with upstairs, bank, church, gym, clothing, barber, apartments) + 3 walk-in residential blocks with real stairs and lift. Need: police station, hospital, town hall, garage workshop variety, more upper floors with missions. |
| Day/night, lamps, car lights | done | 48-min day; lamp pool; car head/tail lamps use the models' own lamp surfaces; police light bars flash. |
| Weather | partial | Clear / cloudy / rain spells: grey sky, dimmed sun, haze, rain around the camera with its own sound, dark glossy wet asphalt and paving that dry slowly, longer braking on wet roads; saved. Missing: levante wind, storms with lightning, fewer pedestrians in rain. |
| Sea, boats, swimming | partial | Boats and swimming/diving exist; marina, jet-ski and harbour missing. |
| Streaming / larger map | missing | Required before districts beyond the central sector (WORLD-007). |
| Collectibles | done | 30 Phoenician amphorae with rewards (10/20/30); 5 unique stunt jumps on the beaches (slow motion, 250 € each). Next: viewpoints (miradores), graffiti tags. |

## 2. Player

| Pillar | Status | Notes |
|---|---|---|
| Movement, sprint, jump, swim, dive | done | |
| Melee, firearms, aiming, reload | done | Fists, bat, pistol, SMG, shotgun, rifle; grenades and Molotovs (G throw, H switch; blast, fire pool, crime); TAB weapon wheel in slow motion. Missing: sniper scope, cover system, lock-on. |
| Health, armour, hospital, arrest | done | Armour bar and vests (soak damage first), first-aid kits, food/rest, hospital and arrest. |
| Money, safehouse, save | done | Safehouse bed saves; garage keeps a car. Next: buy properties with income. |
| Clothing / barber | partial | Codex venues change style; persistence covered. |
| Smoking / eating / drinking | done | Tobacco shops, cafés, restaurants, bars. |
| Phone / contacts | done | ↑ phone: contacts with work (call → waypoint), Taller Poniente, Sargento Molina (bribe), quick save, stats. Missing: incoming mission calls and texts. |

## 3. Vehicles

| Pillar | Status | Notes |
|---|---|---|
| Cars, handling, damage, fire | done | 9 car variants, ram damage, burning, explosion. |
| Kerbs and suspension | done | No lips: every road/paving ribbon ends in a sloping skirt into the ground and the kerb is a sloped stone band (`tests/kerbs.gd`: real car and player cross road and paseo edges); visual suspension soaks steps; a ramp launch only after a sustained climb (no kerb hops). |
| Lights and sirens | done | Head/tail lamp glow, police bar flashing in pursuit and at roadblocks. |
| Motorbikes, scooters, bicycles, buses, vans, ambulance, fire engine | missing | Needs models (ART-012). |
| Helicopters / planes | partial | Police helicopter AI only; player-flyable aircraft missing. |
| Radio stations | partial | Three original procedural stations (Q cycles, live clock so stations keep playing). Missing: DJ voice lines, more tracks, per-vehicle memory. |
| Garage tuning / respray | partial | Respray clears wanted (Taller Poniente); tuning missing. |

## 4. Law enforcement

| Pillar | Status | Notes |
|---|---|---|
| 1–5 stars, sight/search/escape | done | |
| Officers on foot, arrests, shooting | done | Arrest in a car only when stopped or pulled out. |
| Roadblocks | done | 3+ stars: two cars across the road ahead, officers behind. |
| Helicopter | done | 4+ stars: follows, keeps the player seen, searchlight at night, marksman. |
| Spike strips | done | 4+ star roadblocks lay a stinger on the approach; burst tyres limit the car to 9 m/s and make it wander until resprayed. |
| SWAT / Guardia Civil / military escalation | partial | 5 stars: faster roadblocks (up to three). Missing: Guardia Civil 4x4 model and uniforms (ART). |
| Bribes / police informants | done | Phone the bent sergeant: up to 3 stars cleared for 600 € a star. |

## 5. World life

| Pillar | Status | Notes |
|---|---|---|
| Pedestrians with activities | partial | ~100 civilians, workers, skaters, bathers, dancers; flee/fight. Missing: schedules, phone calls, groups, reactions to driving. |
| Traffic with lanes and junctions | partial | Lane-following, braking; junction priority and traffic lights missing. |
| Gangs and territories | missing | Rubén's crew should own the port and react on sight. |
| Random events | done | Bag snatch (catch the thief, keep the bag), stolen car (stop the thief, +250 €), cash van (wreck it, armed guards, 2 stars, 1,500–3,000 €). Red minimap blip; only in free roam. Next: gang ambushes, hitchhikers, drunk drivers. |

## 6. Missions and story

| Pillar | Status | Notes |
|---|---|---|
| Mission framework | done | Objectives, checkpoints, spawns, interiors, saves. |
| Chapter 1 | done | El Recado → … → La copia → El ático de Ferrer → Poniente (+ Jaime, Cuentas pendientes). |
| Chapters 2–3 | missing | ~25 more missions with new antagonists, heists with planning/crew choice, finale. |
| Side activities | partial | Taxi, street race, vigilante (police car), burglaries, office safe, shop holdups, stunt jumps, random street events. Missing: paramedic, firefighter, delivery, boat races, rampages, property income. |
| Cutscenes / voice | missing | In-engine cutscene camera and dialogue presentation. |

## 7. Presentation

| Pillar | Status | Notes |
|---|---|---|
| HUD, minimap, map with waypoint | done | |
| Menus (start, pause, settings, controls rebinding) | partial | Pause/settings exist; title screen and rebinding missing. |
| Audio mix: ambience, SFX, music | partial | Generated SFX (incl. explosion, throw, bottle smash), sea ambience, radio music. Missing: score during missions, police radio chatter. |
| Gamepad | partial | Look stick exists; full gamepad mapping and vibration missing. |
| Accessibility | missing | Subtitles size, colour-blind safe markers, aim assist. |

## 8. Technology

| Pillar | Status | Notes |
|---|---|---|
| Physics | done | Jolt Physics (≈2× cheaper than Godot Physics in pursuit). |
| Frame pacing | partial | Physics interpolation + camera on the interpolated body; shader warm-up at load; far civilians at 1/3 tick rate; car meshes merged per variant (47 → 18 draws per car); lighter foliage/palm LOD. Needs `validate.ps1 -Perf` on Windows. |
| Effects | partial | Soft round particles for smoke, fire and explosions (shared material). Missing: decals (scorch marks, bullet holes on walls), water splashes. |
| LOD / impostors | partial | Visibility ranges and chunked MultiMeshes; building impostors missing. |
| Windows export | missing | BUILD-001. |

## Priority order (next slices)

Done since this list was written: armour and first-aid kits, grenades/Molotovs, weapon wheel, radio, stunt jumps, random street events, spike strips, phone, bribes, weather, lip-free kerbs.

1. Windows `-Perf` measurement with Jolt + interpolation; fix any spike over 25 ms.
2. Incoming phone calls/texts that start missions.
3. Miradores (viewpoints that reveal the map), gang territory in the port (needs the Marina del Este district).
4. Guardia Civil 4x4 and uniforms at 5 stars.
5. Motorbikes and scooters (ART-012), then ambulance/fire engine side jobs.
6. Chapter 2 story outline and first three missions.
7. Levante wind and storms; fewer pedestrians in the rain.
