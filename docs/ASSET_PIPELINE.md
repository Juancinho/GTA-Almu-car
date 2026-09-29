# Asset pipeline

## Inputs and outputs

Editable sources live in `source_assets/`; deterministic Blender/Python scripts in `tools/blender/` and `tools/world/`; throwaway intermediate outputs in `generated/`; selected runtime GLBs in `game/assets/`. Current GLB reports record kind, seed, source/output hashes, Blender version, mesh dimensions, material names, UV counts and triangle counts. Keep binary source assets under Git LFS when large. These Blender models are original project assets.

## Generator framework

`tools/blender/generate.py` provides shared primitive/material/export helpers and three kinds: `palm`, `building`, `compact_car`. Example: `.\.tools\blender\blender.exe --background --python tools/blender/generate.py -- --kind palm --seed 7401 --out game/assets/procedural/palm.glb`. The three GLBs, hash/mesh reports and Godot import are checked by `tools/verify_assets.py`; palms and the compact car are used in the world. The building model is a validated export awaiting runtime integration. Audio placeholders are synthesized by `py -3.13 tools/audio/generate.py` and described in their report.

## Validation

Current generation fails on zero-size meshes, missing materials or UVs, polygon budget overflow, missing collision proxy for building/car, or absent GLB output. The car also exports a driver-seat marker. The report is written on success; failures raise a clear error. Godot import and a representative screenshot are checked, with broader close/mid/far asset review still planned. Future generated textures need explicit color space and packing conventions; Blender-only shader nodes are not a deliverable.

## Audio

Use distinct SFX, music, ambience and UI buses. Initial sounds may be original synthesized placeholders with provenance. Do not fetch commercial recordings. Replace placeholders only with original or license-recorded assets.

## Third-party CC0 assets

Only CC0 sources, pinned by Git commit, enter the game. `assets/third_party/manifest.json` lists each source (repository, commit, author, license file) and every model/texture taken from it; `tools/third_party/import_assets.py --ktx <ktx>` sparse-fetches exactly those files, copies models to `game/assets/third_party/quaternius/`, decodes ambientCG KTX2 maps to PNG (Khronos KTX-Software 4.4.2 `ktx extract`) in `game/assets/third_party/ambientcg/`, and writes `assets/third_party/import_report.json` (SHA-256 per output) and `game/assets/third_party/CREDITS.md`. `--check` (run by `validate.ps1`) fails if an output or the manifest changed without re-import. Never edit outputs by hand; change the manifest and re-run. Current sources: Quaternius “Animated Men/Women Characters” and “Realistic Car Pack” (CC0, via beep2bleep/FreeAssetsByKenneyNLandQuaternius) and ambientCG (CC0, via Papyszoo/CC0-Public-Domain-Textures). The `Cop_SUV` model is excluded because its preview is marked Patreon-exclusive.
