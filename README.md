# Brisa de Poniente

An original third-person open-world crime game in a 1:1 recreation of Almuñécar, Granada. Working title: **Brisa de Poniente**. The long-term product goal is a full game with detailed streets and interiors, a broad vehicle fleet, combat, systemic police response, varied characters and a substantial story. The playable build is still an early prototype; see [design](docs/GAME_DESIGN.md), [roadmap](docs/ROADMAP.md) and [tasks](TASKS.md).

## Current state

An early playable prototype runs in Godot 4.7.2. The previously committed district passed automated and human El Recado playthroughs, with performance evidence in [performance](docs/PERFORMANCE_BUDGET.md) and `docs/evidence/`. An in-progress replacement now generates a larger 1:1 central sector. It imports, launches and passes the scripted El Recado route, swimming, car-water boundary, road clearance and civilian-reaction checks. The wider game scope remains in [tasks](TASKS.md).

## Run and verify

From the repository root on Windows:

```powershell
pwsh -File .\tools\run.ps1
```

The launcher refreshes Godot's script-class registry before opening the game. This is useful after the current sector migration added `SectorWorld` and moved `world.gd`. For validation, run `pwsh -File .\tools\validate.ps1`; `-Perf` adds fullscreen route benchmarks.

Start near the seafront. Move with WASD, aim the camera with the mouse, sprint with Shift, jump with Space and interact with E. Find Alba on the promenade to begin **El Recado**. In a car, WASD drives, Space is the handbrake and E exits; the camera settles behind the car when you stop moving the mouse. Driving through the old-town pedestrian zone in view of pedestrians calls the police: break line of sight to lose them, and do not stop next to a patrol or you will be arrested and sent back to the car. Letters over people and on the map mark missions; follow the yellow GPS route and the glowing column. M opens the town map (click to set a waypoint). Weapons are found as spinning pickups: 1–4 or the wheel switch, right mouse aims, left mouse/F attacks, R reloads. Escape pauses (R there restarts); F5/F9 save/load; F3/F4 cycle quality and volume; F2 shows FPS; F6 writes a session report; F11 toggles fullscreen. Gamepad: left stick move, right stick camera, A jump, X interact, B brake, LB sprint, Start pause.

In the sea, use WASD to swim, hold C to dive, and Space to rise for air. The air meter appears while diving. E also talks to nearby civilians; their replies and reactions vary.

Every interactive session writes `generated/playtests/session_<time>_human.json` when the mission is completed, on restart or when the window closes (after 20 s): objective timestamps, police and arrest events, input device counts and frame times per context. Attach it as playtest evidence.

Jaime Playa is near the Phoenician monument. Speak to Marina there at any time to start **La noche de Jaime**; your progress in **El Recado** resumes afterward. Finishing **El Recado** first puts a marker on Marina.

Taller Poniente is marked in green on the minimap near Avenida de Europa. Enter its street door with E; park a car nearby and speak to the mechanic at the counter to repair it for 75 €. E by the exit returns to the street.

Mercado Azul near Calle de Mariana Pineda and La Brisa on Paseo Puerta del Mar are also enterable. Food costs 15 € and restores 30 health; the restaurant menu costs 35 € and restores full health. Walk to the counter and press E, or press E at the exit to return to the street. Their locations are marked on the minimap.

Caja Poniente is on Plaza de Madrid. Enter with E, use the teller to deposit 100 € cash or the ATM to withdraw 100 € from your account. The bank balance is saved with the game and is unaffected by hospital or arrest fees, which use your cash. The bank appears as a gold marker on the minimap.

Joyería Faro is off Calle de la Puerta de Granada. Its display can be robbed once for 250 €, triggering a staffed alarm and police response. The stolen display remains empty in saved games; loading a save from before the robbery restores it. It appears as a pink marker on the minimap.

Mercado Azul, La Brisa, Caja Poniente and Joyería Faro now have visible street-level interiors behind their glass storefronts. The Iglesia de la Encarnación and the fictional Galería Costa Tropical are also enterable with E; rest in the church or buy food at the gallery counter. Along the promenade, additional bars, restaurants and an estanco have signs and outdoor terraces, and five more open beach bars join Jaime Playa. Meals at their counters cost 35 € and restore health. The individual street storefront interiors are still in development.

`pwsh -File .\tools\validate.ps1 -Capture` also renders a seafront frame to `generated/`. See [SETUP_STATUS.md](SETUP_STATUS.md) for the exact local tool versions.

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

The current development step is to make the new 1:1 central sector reliable, raise its street-level art quality, deepen the first three interiors and build the combat loop and story chapter. The complete-game target remains in the roadmap. Contributions must follow [AGENTS.md](AGENTS.md).

## Data and licensing

All bespoke game content is original or uses a recorded compatible license. People, cars and surface textures currently include CC0 assets by Quaternius, ambientCG and Poly Haven, imported reproducibly (see [asset pipeline](docs/ASSET_PIPELINE.md) and `assets/third_party/`). Additional PBR texture candidates and their licences are recorded there before import. The cached OSM reference extract requires attribution and ODbL handling described in [world design](docs/WORLD_DESIGN.md). The new central sector is generated from cached world data; no network request occurs during gameplay.
