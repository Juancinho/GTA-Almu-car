# World design and geographic data

## First district

Target a roughly 600 × 600 m playable area spanning a compressed Puerta del Mar/Altillo promenade, Peñón del Santo silhouette and rising old-town streets toward a simplified Castillo de San Miguel. Sea and beach border the south, hills frame the north and west. Add Majuelo garden language at one edge. Geographic fidelity is deliberately edited to preserve short driving routes, clear sightlines and a compact mission loop.

## Coordinate contract

Store a fixed WGS84 origin `(lat0, lon0)` and extraction bounding box in the world manifest **when source data is selected**. Do not invent these values. For source point latitude `φ` and longitude `λ` in radians, use a local tangent approximation:

`east_m = R * cos(φ0) * (λ - λ0)` and `north_m = R * (φ - φ0)`, with `R = 6378137 m`.

Godot uses `(x, y, z) = (east_m, elevation_m, -north_m)`. A separately versioned, deterministic **design transform** compresses road spacing/rotates selected blocks after raw conversion; it must not overwrite raw coordinates. Unit tests should cover axis sign, roundtrip error and expected distances.

## Pipeline

1. Query a modest bounded OSM extract using a documented provider and timestamp; save raw `.osm` or `.pbf` under `source_assets/osm/` with URL, query, acquisition date, license and checksum. Respect provider usage policy and retry limits.
2. Parse road centerlines, building footprints, coastline, parks, paths and selected POIs into normalized JSON. Keep source IDs and tags in provenance data.
3. Reproject, simplify polylines/polygons, repair intersections, manually classify walkable/driveable edges and record edits in a versioned design layer.
4. Generate road meshes, sidewalks, terrain masks, building parcels, lane graph and minimap geometry from the same normalized data and seed.
5. Review scale, visibility and collision in Godot; edit the design layer rather than raw OSM.

No network request belongs in gameplay. The first playable block may be hand-authored while the OSM pipeline is developed, but must conform to the same scene/data schema.

## Attribution

OSM data is licensed under ODbL. Include **“Map data © OpenStreetMap contributors”** and a link to [openstreetmap.org/copyright](https://www.openstreetmap.org/copyright) in credits and the in-game map/attribution UI. Record the scope of source data and make any derivative database available as required before distribution; review this obligation at release. This attribution guidance follows the [OSM legal FAQ](https://wiki.openstreetmap.org/wiki/Legal_FAQ). Do not copy OSM raster map tiles into the game.
