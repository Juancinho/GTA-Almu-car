# Art direction

**Stylized Mediterranean PS2-era realism with modern lighting.** Broad shapes and color rhythm carry the town; details concentrate at eye level, landmark silhouettes and street corners.

| Element | Working rule |
|---------|--------------|
| Palette | Chalk white `#E9E1CC`, warm plaster `#D9BA91`, faded coral `#BD755E`, muted terracotta `#A66845`, sea teal `#2D7784`, palm green `#4F6540`, deep shadow blue `#394C5D`. |
| Lighting | Late afternoon sun around 35° elevation, warm direct light, cool sky fill, soft but legible shadow. Clamp white façade exposure; no strong bloom. |
| Geometry | Ordinary façade modules around 200–800 triangles per visible bay; unique small props typically <500 triangles; hero landmark pieces can use more only where silhouette benefits. These are initial targets to measure, not asset acceptance by themselves. |
| Textures | Shared 512–1024 px façade atlases; 256–512 px props; hero textures up to 2048 px with reason recorded. Reuse trims and colors. |
| Buildings | 2–5 floors generally, narrow fronts, uneven but aligned rooflines, balconies as repeated modules, shutters, awnings and selected tile bands. Avoid cloned window grids. |
| Roads | Dark warm asphalt, pale curbs, subtle wear, restrained markings; pedestrian promenade with tiled rhythm. Geometry and lane graph share source. |
| Vehicles | Original rounded low-poly compact, sedan, van, scooter and police variants; readable color blocks, simple glass and lights. No real badges. |
| Characters | Stylized proportions, simple face planes, silhouette clothing and material swaps. Idle/walk/run must read at distance. |
| Vegetation | 3–5 palm silhouettes, simple ornamental trees and shrub clumps; instanced and wind motion subtle. |
| Signage/props | Fictional Spanish names, ceramic street labels, benches, bins, lamps, bollards and beach objects. No commercial logos. |

## Material conventions

Name materials `M_<family>_<variant>` and keep them engine-compatible: base color, roughness, metallic where appropriate, optional normal. Stucco/plaster rough 0.8–0.95; asphalt 0.9; ceramic 0.45–0.7; metal 0.35–0.65; glass simple and sparing. Procedural Blender nodes must be baked or recreated in Godot, never assumed to transfer through GLB.

## LOD and collision

LOD0 within roughly 35 m, LOD1 from 35–90 m, LOD2 silhouette/impostor beyond 90 m, with cull distances chosen after visual profiling. Hero landmarks persist as low-detail silhouettes. Buildings use box/footprint collisions, not render meshes. Instancing and occlusion must be checked against visual breaks at street level.
