# Game design — Brisa de Poniente

Third-person open-world crime game in a faithful Almuñécar. Tone: grounded crime drama of the Costa Tropical — sea smuggling, summer-season rackets, property speculation, family loyalty — with the freedom, humour and chaos players expect from the genre. Characters, gangs and most businesses are fictional; Jaime Playa is the one named business explicitly requested by the product owner (D-018).

The playable Jaime Playa mission is **La noche de Jaime**: Marina, a fictional staff character, asks for sound equipment left near the Phoenician monument. The player brings it to Jaime Playa on foot and checks in with her for a €150 reward. It can be started at any time; **El Recado** resumes at its previous objective afterward. Finishing **El Recado** first marks Marina on the minimap. This is a short introductory venue mission; the larger chiringuito storyline and detailed interior remain planned.

## Complete-game target

The product target is a substantial standalone open-world game, not a single-mission demo. The 12 missions below are **the first story chapter**, not the full campaign. Plan three connected chapters with roughly 30–40 authored main missions, recurring characters, at least 15 replayable side activities, a varied vehicle fleet and a selection of fully playable interiors. These are planning targets, not implemented content. Grow the town and campaign only through finished, tested slices so each new system remains playable.

Every new district needs purposeful things to do: missions, shops or interiors, traffic, pedestrian behaviour, secrets and traversal routes. Each main mission must have a distinct premise, at least one memorable character beat, a gameplay variation, a checkpoint/failure path, and dialogue that changes with the situation. Do not inflate the count with repeated delivery objectives.

## Traversal, streets and town life

The sea is playable space: the character can enter the water, swim at the surface, dive for a limited breath, climb out on a reachable shore and be rescued if air runs out. Cars have grounded suspension/traction and collision, lose power at the shoreline and cannot drive along the sea bed. A boarded driver appears seated inside the cabin, with the on-foot body and collision hidden until a safe exit.

Street geometry must remain readable and driveable. Roads use licensed PBR asphalt with scaled markings and lane-appropriate centre/edge lines. Palm trunks and street furniture sit on pavements or planting strips after clearance checks against every driveable road. Building footprints must stay clear of the carriageway; where source footprints conflict, the design layer records a setback or removal rather than drawing a building over a lane. Sloped façades, entrances and road heights are checked together.

The town needs connected destinations: bank, jewellery shop, supermarket, vehicle workshop, restaurants and casino, plus a police station, fire station and health centre. Each is an enterable, furnished place with a useful interaction and NPC routine, not only a sign. Businesses and staff are fictional except the specifically requested Jaime Playa (D-018). Civilians have varied routines and dispositions; they can talk, react to danger, argue and fight when provoked. Emergency services respond to relevant incidents. Population density and interactions scale to the hardware budget.

## Pillars

1. **The real town as the playground**: every mission uses recognisable places (Peñón del Santo, castle, Calle Real, Majuelo, the beaches) and real street names.
2. **Responsive action**: on foot, driving, shooting and fleeing feel tight before content volume grows.
3. **Systemic consequences**: witnesses, police escalation, wrecked cars, fleeing crowds and money make every action matter.
4. **Serious missions with variety**: every mission combines at least two verbs (drive, chase, shoot, sneak, rob, escape, talk, sail).

## Core systems

| System | Scope for the first full district | Task |
|--------|-----------------------------------|------|
| Movement | Walk, sprint, jump, climb low walls, take stairs, crouch/cover | GAME-001, GAME-018 |
| Vehicles | Enter/exit/carjack, arcade handling per class, damage/fire/explosion, horn, radio, lock-on doors | GAME-002/006/007/008 |
| Combat | Melee (fists, bat, knife), firearms (pistol, SMG, shotgun, rifle), thrown (molotov, grenade); over-shoulder aim, gamepad soft lock, recoil, reload, ammo, hit reactions, cover | GAME-009 |
| Health | Health + armour, food/drinks at bars heal, hospital respawn with fee | GAME-007, GAME-010 |
| Wanted 1–5 | 1 local police foot/car, 2 more units + sirens, 3 national-police-style units + roadblocks, 4 helicopter + spike strips, 5 special unit; line-of-sight search, evade zones, respray at the garage clears level | GAME-004, GAME-012 |
| Crimes | Assault, run-over, carjacking seen by police, shop holdup, armed robbery, vehicle theft, shooting, resisting arrest — each with witness rules | GAME-007/011 |
| Economy | Money from missions, robberies, side jobs; spend on weapons, ammo, armour, clothes, car repairs/resprays, property | GAME-008, GAME-017 |
| Save | Safehouse beds and garages save game and vehicles; autosave after missions | GAME-017 |
| Phone | Mission contacts call/text, GPS waypoint, taxi, map | GAME-016, UI-003 |
| Day/night & weather | 24 h cycle (~48 min real), summer/winter crowds, rare storm | VIS-002 |
| Audio | Original score and radio stations (original music only), sirens, ambience per sector | AUD-001 |

## Transport

Cars (compact, saloon, SUV, van, sports), scooters and motorbikes (tight old-town lanes), bicycles, urban bus (drivable + passenger), taxi (side job), police cars and bikes, ambulance, boats (fishing boat, speedboat, jet ski, smuggler RIB), later helicopter and paraglider over the Sierra. Each class has data-driven tuning in `game/data/vehicles/` (mass, top speed, acceleration, grip, damage, seats).

## Interiors

Entered through real façades; each is its own scene with navmesh, lighting and gameplay hooks.

| Interior | Location (real area) | Use |
|----------|----------------------|-----|
| Safehouse flat | Seafront block on Paseo del Altillo (fictional name) | Save, wardrobe, weapons stash, TV news |
| Beach bar (chiringuito) | Playa Puerta del Mar | Heal, missions, racket storyline |
| 24 h shop and petrol station | Modern centre / coast road | Holdups, snacks |
| Gun shop (armería, fictional) | Modern centre | Buy weapons/ammo/armour |
| Garage / body shop | Avenida de Europa area | Repair, respray (clears wanted), mods |
| Clothes shop and barber | Calle Real | Outfits (disguise lowers recognition) |
| Jewellery shop (fictional) | Calle Real | Heist target |
| Bank branch (fictional) | Plaza de la Constitución area | Heist finale |
| Police station | Modern centre | Impound, story break-in |
| Health centre | Modern centre | Respawn point |
| Castle museum and courtyard | Castillo de San Miguel | Night deal, shoot-out |
| Cueva de Siete Palacios | Old town (underground vaults) | Stealth/escape mission |
| Palacete de La Najarra | San Cristóbal | Party infiltration |
| Church (Encarnación) | Old town | Cutscene, procession event |

## Robberies and side activities

Shop and petrol-station holdups (aim at the clerk, bag the cash, escape the response), armoured-van hits on the coast road, car-theft export orders, jewellery and bank heists (planning + crew + execution), smuggling runs by sea at night, taxi, bus and delivery jobs, street races, beach-bar racket collection, vigilante police calls, collectibles (Phoenician coins hidden around town). Interactions with people: talk, ask directions, buy, intimidate (raise weapon), pickpocket, hire crew, recruit a driver.

## First story chapter (draft, fictional characters)

| # | Mission | Setting | Verbs |
|---|---------|---------|-------|
| 1 | El Recado (exists) | Paseo → old town → castle | talk, drive, escape |
| 2 | Hielo para el chiringuito | Beach bars, Calle Real | deliver on a scooter, fist fight |
| 3 | La cuota | Beach bars at night | intimidate, collect, chase |
| 4 | Pescadores | Fishing boats, Puerta del Mar | boat drive, pursuit at sea |
| 5 | Noche en el Majuelo | Concert in Parque El Majuelo | stealth, pickpocket a key card |
| 6 | Siete Palacios | Cueva de Siete Palacios | infiltration, escape through lanes |
| 7 | Furgón | Coast road | armoured-van robbery, 3-star escape |
| 8 | Fiesta en la Najarra | Palacete de La Najarra | disguise, eavesdrop, shoot-out |
| 9 | La lancha | Night bay, Peñón del Santo | speedboat chase vs rival smugglers |
| 10 | Calle Real | Jewellery heist | crew, timed robbery, motorbike getaway |
| 11 | El castillo | Castle museum | ambush, siege, helicopter |
| 12 | Poniente | Bank finale + escape to Marina del Este | heist, 5-star escape by sea |

Each mission is JSON/resource data (objectives, triggers, dialogue, checkpoints, fail conditions), testable by a scripted route like El Recado. Later chapters should broaden the cast and stakes across the whole municipality, with quieter character missions between chases, robberies and combat.

## Characters and dialogue

Create a cast bible before writing the second chapter: protagonist, Alba, allies, rivals, police contacts, shopkeepers and civilians each need a goal, relationships, a consistent speaking style and a change over the campaign. A mission script records who speaks, why the line matters, its delivery condition, subtitle timing and any alternate line for failure, arrest or replay. Conversations should respond to player actions; important choices can change allies, money or access to missions without requiring a fully branching plot. Write and review dialogue in natural Spanish suited to the Costa Tropical, with restrained regional detail and no copied lines from other games. Voice work, if added, must be original or licensed; subtitles remain complete without it.

## Input

Keyboard/mouse: WASD, mouse camera, Shift sprint, Space jump/handbrake, E interact/enter, F melee, right mouse aim, left mouse shoot, R reload (move restart to pause menu), Q/E wheel for weapon (hold Tab), G throw, H horn, C crouch, M map, phone ↑. Full gamepad parity.

## Content boundaries

Stylised, not gratuitous violence; no sexual content; no real people, logos or police insignia; businesses are fictional except the user-requested Jaime Playa venue (D-018); drugs are implied plot (smuggling) not depicted use. Acceptance for any mission: a scripted-input test completes it and a human playthrough log records it.
