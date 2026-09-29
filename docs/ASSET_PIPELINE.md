# Asset pipeline

## Inputs and outputs

Editable sources live in `source_assets/`; deterministic Blender/Python scripts in `tools/blender/` and `tools/world/`; throwaway intermediate outputs in `generated/`; selected runtime GLB/textures in `game/assets/`. Each runtime asset records generator command, seed, source hashes, Blender version, triangle count, bounds, material count and license in a JSON manifest. Keep source assets under Git LFS when binary and large.

## Generator framework

Use a shared primitive/material/export library and parameter presets rather than separate scripts with duplicated mesh logic. Start with one building family, one palm and one compact car; expand variants only after visual review. Asset IDs and seeds should produce identical geometry at the same tool version. Blender command convention: `blender --background --python tools/blender/generate.py -- --preset <name> --seed <integer> --out <path>`.

## Validation

Generation fails on zero-size objects, missing expected meshes/materials, unexpected face count, missing UVs on textured meshes, negative/non-unit transforms at export, missing collision proxy/seat markers when required, or absent GLB. Write structured reports even on failure. Import GLB in Godot headlessly and inspect one close, one medium and one far render. Generated textures need explicit color space and packing conventions; Blender-only shader nodes are not a deliverable.

## Audio

Use distinct SFX, music, ambience and UI buses. Initial sounds may be original synthesized placeholders with provenance. Do not fetch commercial recordings. Replace placeholders only with original or license-recorded assets.
