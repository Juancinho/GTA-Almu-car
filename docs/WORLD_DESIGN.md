# World design — Almuñécar at 1:1

## Fidelity goal

The playable world is **central Almuñécar at real scale and real layout**, generated from licensed geographic data and then hand-dressed. Streets, plazas, stairs, landmarks and coastline sit where they are in reality; the player should be able to navigate by real street names. Deliberate deviations (widened lanes for driving, a hidden interior, a gameplay shortcut) are recorded as design-layer edits with a reason, never by editing the raw data. This supersedes the earlier "compressed fictional" greybox (see D-013); the greybox stays only until WORLD-005 replaces it.

## Data sources and licences

| Layer | Source | Licence / attribution | Status |
|-------|--------|-----------------------|--------|
| Roads, paths, steps, building footprints, parks, coastline, names | OpenStreetMap extract cached in `source_assets/osm/altillo_2026-09-29.json` (1,400 buildings, 218 roads, 313 paths incl. steps, 41 parks) | ODbL — “Map data © OpenStreetMap contributors”, share-alike for the derived database | Cached, normalised (`game/data/world/osm_reference.json`) |
| Terrain elevation | CNIG/IGN **MDT05** (5 m DTM from LiDAR), Centro de Descargas CNIG | CC BY 4.0 — “© Instituto Geográfico Nacional” | To fetch once, cache with hash (WORLD-004) |
| Building heights | Not in the OSM extract (`building:levels` absent) | — | Design rule table per zone + manual overrides from reference photos (WORLD-005) |
| Visual reference | Own photos or licence-recorded images per landmark | Per file | `source_assets/reference/` (ART-010) |

No network request ever happens at runtime; every fetch is a tool step with URL, date, hash and licence in a metadata file.

## Coordinate contract

WGS84 origin **(36.7314508, −3.6902315)** on Paseo del Altillo. `east_m = R·cos φ0·(λ−λ0)`, `north_m = R·(φ−φ0)`, `R = 6378137 m`; Godot `(x, y, z) = (east_m, elevation_m, −north_m)`. The design transform is now identity for position (scale 1:1); design-layer edits are local offsets per feature ID in `source_assets/world/design_layer.json`. Unit tests cover axis signs, round trip and known distances.

## Sectors (streamable, generated in this order)

Positions are OSM centroids in metres (x east, z south of the origin) from `osm_reference.json`.

| Sector | Real area | Anchors (x, z) | Character |
|--------|-----------|----------------|-----------|
| S1 Puerta del Mar | Paseo del Altillo, Paseo Puerta del Mar, Playa Puerta del Mar | Paseo del Altillo (−13, 16); Calle Playa Puerta del Mar (−53, 44); Paseo Puerta del Mar (189, 41) | Seafront promenade, apartment blocks, beach bars, Phoenician monument, taxi rank. Player start. |
| S2 Old town | Plaza de la Constitución, Calle Real, Iglesia de la Encarnación, Plaza Nueva, Cueva de Siete Palacios | Plaza de la Constitución (−94, −240); Calle Real (−52, −195); Iglesia (−40, −345); Cueva Siete Palacios street (−73, −71); Plaza Nueva (−57, −315) | Pedestrian lanes, stairs, shops, town hall, church; car access restricted (wanted trigger zone). |
| S3 Castle and San Miguel | Castillo de San Miguel, Barrio de San Miguel, Parque El Majuelo | Castle (−221, 72); Majuelo (−300, 4); Cuesta del Castillo steps (−108, −186); Calle Alfareros steps (−171, −48) | Steep whitewashed barrio, castle museum, Roman salting ruins, concerts. |
| S4 San Cristóbal | Peñón del Santo, Playa and Paseo de San Cristóbal, Palacete de La Najarra | Paseo de San Cristóbal (−603, 77); Plaza San Cristóbal (−361, 229); Paseo de Prieto Moreno (−348, 241) | Beach promenade, restaurants, rock outcrop with cross, neo-Arab palace. |
| S5 Modern centre | Avenida de Europa, Avenida de Andalucía, Plaza de Madrid, bus station, aqueduct arches | Av. de Europa (−347, −111); Av. de Andalucía (63, −451); Plaza de Madrid (159, −85) | Through traffic, supermarket, bus station, schools, Roman aqueduct sections. |
| S6+ Expansion | Velilla, Calabajío, Cotobro, N-340 coast road, Marina del Este / La Herradura | outside current extract | Highway driving, marina, boats, coves — after S1–S5 ship. |

Each sector is its own scene with a manifest (feature IDs, bounds, LOD sets, navigation) and can load independently; streaming by distance comes with S2 (WORLD-007).

## Generation rules

- **Roads**: OSM `highway=*` → driveable (primary…residential, living_street) with lane counts, one-way tags and widths per class; `pedestrian`, `footway`, `steps` → walkable only, steps as ramps with visual treads. Lane graph for traffic/police and the minimap are generated from the same data (replaces `road_network.json` hand data).
- **Terrain**: MDT05 heightmap resampled to 1 m under S1–S5, roads flattened across their width, stairs following the slope; coastline from OSM with a beach profile.
- **Buildings**: every OSM footprint extruded; storeys from a zone table (old town 2–3, San Miguel 1–3, seafront 6–10, modern centre 4–7), overridden per building from references; façade kit chosen by zone; landmarks replaced by hero models aligned to their footprints.
- **Dressing**: palms and lamp posts along promenades at measured spacing, benches, bins, bollards, planters, beach loungers and boats by season, vegetation in parks.
- **Interiors**: entrances placed on real façades (see `GAME_DESIGN.md`), interiors as separate scenes loaded behind doors.

## Attribution

In-game credits and the pause/map screen show “Map data © OpenStreetMap contributors (ODbL)” and “Elevation: © Instituto Geográfico Nacional (CC BY 4.0)”. The derived road/building database is published on request as ODbL requires; review before any distribution. Real public place and street names are used; real businesses and people are not (OSM business names are replaced with fictional ones).

## References

[Granada Direct – Qué ver en Almuñécar](https://www.granadadirect.com/costa/almunecar/que-ver/) · [Granada Direct – playas](https://www.granadadirect.com/costa/almunecar/playas/) · [Almuñécar Info – historical & cultural](https://almunecarinfo.com/things-to-do-almunecar-spain/historical-cultural/) · [Andalucía – Palacete de La Najarra](https://en.andalucia.org/listing/palacete-de-la-najarra/16277101/) · [Andalucía – Iglesia de la Encarnación](https://en.andalucia.org/listing/church-of-encarnaci%c3%b3n/17073101/) · [Mapping Spain – Almuñécar](https://mappingspain.com/what-to-see-in-almunecar-and-impressions/) · [datos.gob.es – MDT05](https://datos.gob.es/es/catalogo/e0dat0002-modelo-digital-del-terreno-con-paso-de-malla-de-5-metros-mdt05-de-espana1) · [OSM legal FAQ](https://wiki.openstreetmap.org/wiki/Legal_FAQ).
