# Art direction — faithful Almuñécar

**Target: contemporary stylised realism that a local recognises at street level.** Not a generic Mediterranean town and not PS2-era primitives: every sector must read as the real Almuñécar (Costa Tropical, Granada) from the player's eye height, at day and at night. Readability and frame rate still win over micro-detail, but no shipped surface may be a flat untextured box.

## Recognition targets (must be identifiable in a blind screenshot test)

| Place | What must read | Key visual traits |
|-------|----------------|-------------------|
| Castillo de San Miguel | Hilltop fortress above the sea, west of Puerta del Mar | Weathered tan-grey masonry curtain walls, **four round towers on the entrance façade**, crenellations, ramps/stairs from Barrio de San Miguel; museum courtyard. |
| Peñón del Santo | Rock outcrop into the bay separating Playa San Cristóbal (west) from Puerta del Mar (east) | ~30 m dark grey rock, stepped path and ramps with pines, **white cross** and small viewpoint plaza on top, lit at night. |
| Paseo del Altillo / Puerta del Mar | Seafront promenade | Palm rows, patterned paving, bronze **Phoenician monument**, benches, lamp posts, beach bars; 6–10 storey 1970s–90s apartment blocks with continuous balconies, awnings and ground-floor terraces facing the sea. |
| Beaches | Puerta del Mar, San Cristóbal, Calabajío (later Velilla, Cotobro) | **Dark grey fine sand and gravel ("chinos"), not golden**; turquoise shallow water; fishing boats and sun loungers. |
| Parque El Majuelo | Botanical park below the castle | Dense subtropical planting (palms, ficus, bamboo, cacti), **Roman fish-salting factory ruins** (rectangular vats), open-air stage. |
| Old town / Barrio de San Miguel | Steep lanes up to the castle | **Whitewashed lime façades**, coloured plinths (zócalos), wrought-iron window grilles (rejas), small balconies, flower pots, terracotta tile roofs and flat roof terraces, stepped streets (Cuesta del Castillo, Calle Alfareros), narrow widths 2–5 m. |
| Plaza de la Constitución / Calle Real | Civic heart | Town hall, orange trees, fountain, café terraces, pedestrian shopping street. |
| Iglesia de la Encarnación | Early-17th-century church (Herrera plans, Ambrosio de Vico) | Sober stone/plaster volume, **slender bell tower with spire** dominating the upper old town. |
| Palacete de La Najarra | Mid-19th-century neo-Arab palace, near San Cristóbal | Horseshoe arches, tiled plinths, tower, garden with cypresses and palms. |
| Roman aqueduct | Stone arch sections inland | Rubble-stone arches with brick detailing crossing lanes/gardens. |
| Cueva de Siete Palacios | Underground Roman vaulted rooms (museum) | Seven barrel-vaulted chambers under the old town — hero interior. |
| Sierra backdrop | Hills to the north | Terraced subtropical orchards (avocado, custard apple) and scattered white houses, not smooth green mounds. |

Sources used for these traits: tourism and heritage pages cited in `WORLD_DESIGN.md`. Collect a reference board of **own or licence-recorded photos** per landmark in `source_assets/reference/<place>/` (with licence notes) before modelling it; never ship reference photos as textures unless their licence allows it.

## Palette and light

Lime white `#EEE9DF`, warm plaster `#D9C3A0`, ochre plinth `#C99A52`, Almuñécar blue plinth `#3E6E9E`, terracotta `#A65A3A`, castle stone `#A89A84`, dark beach grey `#5B5A57`, sea turquoise `#2E8C95`→deep `#1D4E6B`, palm green `#4F6540`, bougainvillea magenta `#B0306A`. Late-afternoon default with a full **day/night cycle**: hard warm sun, cool sky fill, haze over the sea, orange sodium street lights and lit shop windows at night. Tonemap filmic, no strong bloom, clamp white façades.

## Geometry and texture quality bar

| Asset class | Triangles (LOD0) | Textures | Notes |
|-------------|------------------|----------|-------|
| Generic building (per façade module set) | 1–6 k per building | Shared façade atlases 1–2 K, trims, decals | Modular kit: ground floor (shop/garage/door), upper floors (balcony, window, reja), roof (tile/terrace/parapet). Footprints from OSM. |
| Hero landmark | 20–120 k | Unique 2 K sets allowed | Castle, Peñón, church, Najarra, Majuelo ruins, aqueduct, Phoenician monument. |
| Characters | 8–20 k | 1–2 K | Varied locals/tourists/police/workers; faces readable at 3 m; idle/walk/run/sit/talk/phone/aim/shoot/hit/fall. |
| Vehicles | 8–25 k | 1 K + shared glass/lights | Spanish-plausible fleet, no real badges. |
| Props | 50–2 k | Atlases | Benches, lamp posts, bins, bollards, planters, kiosks, beach loungers, boats. |

LOD1 at ~40 m (≈50 %), LOD2 at ~120 m (≈15 %), impostors beyond 300 m for hills. Texel density ≈ 256 px/m at street level. Use decals for grime, damp at plinths, graffiti (original), road markings. Collision: boxes/convex per module; stairs as ramps with step visuals.

## Materials

`M_<family>_<variant>` naming. PBR (albedo, normal, roughness; AO/height where useful), CC0 or original only (see `ASSET_PIPELINE.md`). Whitewash uses a lime plaster set tinted per building with slight colour variance; plinths and window frames from a colour table per street; roofs terracotta tile or cement terrace. Asphalt with patches and markings, pavements with local mosaic/stone patterns, promenade with its own pattern.

## Vehicles, people and signage

- Fleet: compact hatchbacks and saloons, small vans, delivery vans, scooters and motorbikes (common in town), bicycles, urban buses, white taxis, fictional **Policía Local** (white/blue with checker band) and a fictional national-police style unit for higher wanted levels, ambulances, fishing boats, small speedboats, jet skis. No real logos, plates are fictional.
- Population: residents of all ages, tourists (summer), workers (waiters, delivery, fishermen), police; dress by season.
- Signage: real street names from OpenStreetMap (ODbL, attribution in credits) on ceramic street plaques; **businesses, brands and characters are fictional** (original shop names, no real company names even if present in OSM).

## Review and acceptance

Each landmark and sector is accepted only with: side-by-side screenshots against its reference board at matching viewpoints, a day and a night capture, LOD/draw-call numbers from `validate.ps1 -Perf`, and a human review note in `TASKS.md`.
