# Asset pipeline

## Inputs and outputs

Editable sources live in `source_assets/`; deterministic Blender/Python scripts in `tools/blender/` and `tools/world/`; throwaway intermediate outputs in `generated/`; selected runtime GLBs in `game/assets/`. Current GLB reports record kind, seed, source/output hashes, Blender version, mesh dimensions, material names, UV counts and triangle counts. Keep binary source assets under Git LFS when large. These Blender models are original project assets.

## Generator framework

`tools/blender/generate.py` provides shared primitive/material/export helpers and three kinds: `palm`, `building`, `compact_car`. Example: `.\.tools\blender\blender.exe --background --python tools/blender/generate.py -- --kind palm --seed 7401 --out game/assets/procedural/palm.glb`. The three GLBs, hash/mesh reports and Godot import are checked by `tools/verify_assets.py`; palms and the compact car are used in the world. The building model is a validated export awaiting runtime integration. Audio placeholders are synthesized by `py -3.13 tools/audio/generate.py` and described in their report.

## Validation

Current generation fails on zero-size meshes, missing materials or UVs, polygon budget overflow, missing collision proxy for building/car, or absent GLB output. The car also exports a driver-seat marker. The report is written on success; failures raise a clear error. Godot import and a representative screenshot are checked, with broader close/mid/far asset review still planned. Future generated textures need explicit color space and packing conventions; Blender-only shader nodes are not a deliverable.

## Audio

Use distinct SFX, music, ambience and UI buses. Initial sounds may be original synthesized placeholders with provenance. Do not fetch commercial recordings. Replace placeholders only with original or license-recorded assets.
