# Performance budget

Target 1920×1080 at stable 60 FPS on a mid-range Windows gaming PC, with GTX 1650 as the detected local test GPU. Frame budget: 16.7 ms total. Automated visible routes are measured below; human traversal, worst-case combat/night and release export acceptance remain open.

| Area | Initial budget / rule | Verification |
|------|-----------------------|--------------|
| Draw calls | Aim <1,500 visible; favor shared materials and MultiMesh | Godot profiler and render statistics. |
| Visible triangles | Aim <2 million near street view | Capture worst-case seafront and dense old town. |
| Texture memory | Aim <512 MiB resident for first district | Profiler and GPU telemetry. |
| Pedestrians | 12–24 nearby full updates, distant at low frequency or hidden | Check frame time while driving. |
| Traffic | 8–16 active vehicles near player | Check collisions and lane behavior at speed. |
| Police | 1–3 active pursuit units for levels 1–2 | Measure path/perception cost. |
| Physics | Simple static colliders; no mesh collision on generic façades | Physics frame time. |
| World | One sector loaded initially; visibility and LOD on props/buildings | Screenshot and profile each sector edge. |

Offer resolution scale, shadow quality, draw distance and vegetation density settings. Do not reduce readability to meet performance; profile first and record hardware, renderer, settings, average FPS and 1% low for reproducible test routes.

First measurable structural change: batching windows/shutters into two `MultiMeshInstance3D` nodes reduced direct district children from 1,560 to 278 in the smoke scene while retaining the town view. F3 cycles detail/shadow quality.

Initial offscreen sample on 2026-09-29, after the compact car GLB runtime integration: Godot 4.7.2 Compatibility renderer, NVIDIA GeForce GTX 1650, 1920×1080 `SubViewport`, 90 warmup frames and 240 timed frames. `game/tests/performance.gd` reported 120.0 average FPS (8.34 ms) and 114.3 FPS 1% low (8.75 ms). The exact 120 FPS average suggests a display or engine cap; this is an indicative stationary-scene sample, not proof of stable 60 FPS during play, driving, police pursuit or a visible full-screen window. Repeat with Godot's profiler and a fixed worst-case gameplay route before closing PERF-001.

## In-game measurement (2026-09-29)

`game/scripts/perf_monitor.gd` records every rendered frame during play, grouped by context (`on_foot`, `driving`, `pursuit`), with draw calls and primitives. F2 shows it live; `game/scripts/playtest_log.gd` writes it with the session events to `generated/playtests/` (copied evidence in `docs/evidence/`).

| Run | Context | Frames | Avg FPS | 1 % low | Max frame | Avg / max draw calls |
|-----|---------|--------|---------|---------|-----------|----------------------|
| Automated El Recado route, visible window, vsync | on_foot | 543 | 120.0 | 120.0 | 8.33 ms | 290 / 300 |
| 〃 | driving | 2,657 | 120.0 | 120.0 | 8.33 ms | 397 / 576 |
| 〃 | pursuit | 5,310 | 120.0 | 120.0 | 8.39 ms | 313 / 576 |
| Human playthrough (111 s), vsync | on_foot | 5,382 | 120.0 | 120.0 | 12.13 ms | 394 |
| 〃 | driving | 3,391 | 120.0 | 120.0 | 8.33 ms | 410 |
| 〃 | pursuit | 4,334 | 120.0 | 120.0 | 8.33 ms | 349 |

Hardware: NVIDIA GeForce GTX 1650 (OpenGL 3.3, driver 592.27), AMD Ryzen 5 5600H, Windows 10.0.26200, 120 Hz display, Godot 4.7.2 Compatibility renderer, quality level 2 (shadows on). Frame pacing held the 120 Hz vsync cap throughout driving and pursuit, which exceeds the 60 FPS target with no dropped frames at the 1 % low.

Caveat: both reports stored the logical 1280×720 stretch size, not the real window, so these runs do not prove native 1920×1080. The monitor now records `window_size`, `render_size` and seconds spent per window size; `validate.ps1 -Perf` runs the route fullscreen twice (vsync and uncapped) to confirm 1080p and measure headroom.

### Native 1080p confirmation (2026-09-29, 21:03)

After adding animated CC0 people, CC0 cars and triplanar PBR textures, `validate.ps1 -Perf` ran the El Recado route fullscreen at 1920×1080 (window and screen size recorded):

| Pass | Context | Avg FPS | 1 % low | Max frame | Avg / max draw calls |
|------|---------|---------|---------|-----------|----------------------|
| vsync (120 Hz) | on_foot / driving / pursuit | 120.0 | 120.0 | 8.43 ms | 331–423 / 617 |
| uncapped | on_foot | 389.7 | 360.0 | 2.88 ms | 350 / 362 |
| uncapped | driving | 445.8 | 360.0 | 2.98 ms | 424 / 607 |
| uncapped | pursuit | 466.8 | 364.0 | 5.23 ms | 339 / 617 |

Those results describe the previous, smaller district. Re-measure the expanded 1:1 sector before using that headroom estimate.

### Expanded sector sample (2026-09-30)

Godot 4.7.2 Compatibility renderer on the GTX 1650, 1920×1080 `SubViewport`, 90 warmup and 240 timed frames: 81.3 average FPS (12.29 ms), 49.6 FPS 1% low (20.15 ms) in an isolated repeat. An earlier sample taken while the automated mission route also ran measured 78.5 / 42.7 FPS. These are offscreen stationary samples with the new 1,252 buildings, 418 palms, 56 roaming civilians and Taller Poniente. The isolated 1% low misses the 60 FPS target; profile worst-case streets and visible-window driving before raising population or committing to a stable-60 claim.

After adding Mercado Azul and La Brisa, the same isolated offscreen sample measured 81.0 average FPS (12.34 ms) and 50.2 FPS 1% low (19.94 ms). The two venues did not materially change this stationary result; the 1% low still misses the target. Capture log: `generated/performance_venues.out.log`.

After furnishing the venues, `performance.gd -- --view supermarket` and `--view restaurant` measured 120.0 average FPS each; 1% lows were 119.1 and 114.4 FPS respectively in isolated 1920×1080 offscreen views. The 120 FPS average is likely a cap, and these views exclude the demanding exterior street scene. Logs: `generated/performance_supermarket.out.log` and `generated/performance_restaurant.out.log`.

With Caja Poniente and Joyería Faro added, the same exterior sample measured 80.0 average FPS (12.50 ms) and 49.2 FPS 1% low (20.32 ms). The isolated jewellery interior measured 120.0 average / 119.0 FPS 1% low, apparently capped. The exterior still misses the stable 60 FPS target and needs a visible-window worst-case route before making performance claims. Logs: `generated/performance_outside_final.out.log` and `generated/performance_jewellery_final.out.log`.

After the physical storefronts, church/gallery, promenade commerce, five staffed beach bars, 2K Clean Asphalt material and tertiary-road edge lines, the 1080p exterior sample measured 69.1 average FPS (14.47 ms) and 44.2 FPS 1% low (22.60 ms). This is a material regression from the 80.0 / 49.2 sample. Planar road UVs removed unnecessary triplanar texture reads, and bar geometry was batched locally, but neither recovered the previous rate. Profiling draw calls, lights and texture cost in a visible-window drive is required before raising density or claiming stable 60 FPS. Log: `generated/performance_current.out.log`.

### Render-cost pass (2026-09-30, afternoon)

A human session at 1280×720 (quality 2) measured 70 FPS average and 45.6 FPS 1 % low in pursuit, 2.3–3.8 M primitives and up to 2,390 draw calls. A per-category breakdown of one street view (`RenderingServer` frame info in a software-GL capture, same scene) showed the costs and the fixes:

| Category | Before prim / draws | After prim / draws | Change |
|----------|--------------------|--------------------|--------|
| Whole frame | 2,273,621 / 1,742 | 783,264 / 1,220 | |
| Terrain | 835,848 / 31 | 78,540 / 63 | 128 m tiles culled by the camera, no shadow casting |
| Shadows (directional) | 1,509,055 / 647 | 128,068 / 336 | 2 splits, 150 m max; flat/small props do not cast |
| Façade details + balconies | 475,992 / 13 | 46,502 / 6 | balcony boxes chunked, 320 m range, no shadow |
| Lamps / benches | 193,448 / 46 | 23,116 / 46 | chunked, single-ring poles, no shadow |
| Palms | 84,028 / 141 | 123,708 / 43 | chunked, 11 frond meshes merged into one crown |
| Interiors + landmarks | 21,936 / 346 | 13,064 / 134 | furnished rooms drawn only within 45 m of their doors |

Vehicle and character scenes are loaded at start-up so the first police car no longer stalls the frame. Re-measure on Windows with `validate.ps1 -Perf`.

### Weapons and casino continuation (2026-09-30, Windows)

Isolated sequential samples after the functional regressions finished: local Godot 4.7.2, Compatibility / NVIDIA GTX 1650 driver 592.27, 1920×1080 SubViewport, 90 warmup frames and 240 measured frames, default quality. Existing CC0 texture assets were reused; no higher-resolution textures were imported.

| View | Average FPS | 1% low FPS | Average / p99 ms | Average draw calls | Texture MiB |
|------|-------------|------------|------------------|--------------------|-------------|
| Exterior spawn | 67.9 | 39.1 | 14.73 / 25.60 | 1124.4 | 106.6 |
| Casino lobby | 85.2 | 70.5 | 11.74 / 14.18 | 706.7 | 106.5 |

Commands: `godot.exe --path game --script res://tests/performance.gd` and the same with `-- --view casino`. Raw results are preserved in `docs/evidence/continuation_2026-09-30/performance_outside.txt` and `performance_casino.txt`. The counters report Godot texture allocation, not total resident GPU VRAM. No new visible-window human route was measured. These stationary samples do **not** establish stable 60 FPS; the exterior 1% low misses that target. Further population/district density should wait for profiling of that exterior bottleneck. The indoor camera, shared emissive materials and distance-gated rooms remain enabled in these samples.

### Ballistics and swimming continuation (2026-09-30)

New combat rendering is bounded: 12 simultaneous impact emitters, 48 reused bullet marks and 8 remote shot sounds. Particle meshes/materials are shared, particles and marks cast no shadows, marks cull at 60 m and emitters stop being created beyond 80 m. Glass shards use particles instead of rigid-body simulation. Runtime asset textures were unchanged.

Sequential, isolated 1920×1080 SubViewport samples on the same GTX 1650 / driver 592.27, Godot 4.7.2 Compatibility, default quality 2, 90 warmup and 240 measured frames:

| Sample | Average FPS | 1% low FPS | Average / p99 ms | Average draw calls | Texture MiB |
|--------|-------------|------------|------------------|--------------------|-------------|
| Exterior | 57.8 | 29.1 | 17.29 / 34.36 | 1124.2 | 106.6 |
| Exterior + synthetic combat effects | 59.2 | 32.1 | 16.88 / 31.20 | 1177.8 | 106.6 |

The combat sample (`performance.gd -- --combat`) repeatedly fills the bounded effects/marks in the same view; it does not simulate a complete firefight. These short runs were on a 60 Hz display, unlike the earlier 120 Hz measurements. Their noise and cap prevent an FPS-improvement claim. The extra effects add about 54 draw calls with no texture-allocation growth at the reported 0.1 MiB precision; both samples still miss the stable-60 target. Logs: `docs/evidence/combat_water_2026-09-30/performance_outside.txt` and `performance_combat.txt`.

A visible fullscreen El Recado route with vsync completes at 59.8 average FPS overall (343.8 s). On foot: 59.7 average / 55.4 FPS 1% low; driving: 59.8 / 60.0; pursuit: 59.9 / 60.0. Maximum frame: 80.49 ms; up to 1493 draw calls and 2.40 million primitives. This demonstrates a completed playable route at the 60 Hz cap for most frames, with spikes still requiring work. It is an automated route, not a human session. The first uncapped route fails its escape while reporting pursuit 75.6 average / 51.9 FPS 1% low; that failed run is retained as evidence, not accepted as a completed route.

Framebuffer verification: the fullscreen GPU image is **1920×1080**. The old monitor's `ViewportTexture.get_size()` reports 2880×1620 because it includes the canvas stretch transform; this is not an actual oversized framebuffer. The monitor now reads the real image size once on startup/resize. `framebuffer.txt` preserves the side-by-side check. PERF-002 remains open for worst-case streets/combat/night, reduced spikes and human acceptance.

### Neighbourhood and physical street contacts (2026-09-30)

21 venues, physical staff/dancers, six beach residents, four skaters, bounded 32 movable chairs and mesh-matched road/curb collision are integrated. Medium is the new default: 85% 3D resolution, 65 m shadow range, 28 m interior visibility. Low/High use 67%/100% 3D; UI remains native. Hidden ambient poses/worker simulation are gated. Physics step sweeps now run only after a wall contact; normal floor movement avoids their additional queries. Shared firearm materials also fix police-despawn renderer errors.

The initial expanded-sector fullscreen route passes gameplay but averages 57.2 FPS, with pursuit 50.4 average / 21.0 1% low and maximum frame 86.86 ms. After the step guard, isolated sequential fullscreen routes on the same GTX 1650/592.27, Ryzen 5600H, Godot 4.7.2 Compatibility and 60 Hz screen produce:

| Mode / context | Avg FPS | 1% low FPS | Average / p99 ms | Max frame ms |
|---|---|---|---|---|
| Vsync · foot | 60.0 | 60.0 | 16.67 / 16.67 | 18.06 |
| Vsync · driving | 59.7 | 55.4 | 16.75 / 18.06 | 33.33 |
| Vsync · pursuit | 56.9 | 34.3 | 17.59 / 29.17 | 37.03 |
| Uncapped · foot | 102.9 | 81.6 | 9.72 / 12.25 | 18.38 |
| Uncapped · driving | 97.0 | 50.2 | 10.31 / 19.93 | 31.50 |
| Uncapped · pursuit | 87.9 | 37.5 | 11.38 / 26.67 | 33.33 |

Both routes complete El Recado with witnessed incident, actual police chase/escape and delivery, at 981/980 vehicle health. Output is verified 1920×1080, quality 1, 85% 3D. Vsync overall: 59.3 average / 40.0 1% low, worst 37.03 ms; uncapped: 96.4 / 45.4, worst 33.33 ms. Maximum visible draw calls 1486; maximum primitives 2.12 million slightly exceeds the initial geometry target. Engine physics monitor means in the capped run: 4.41 ms foot, 6.01 driving, 8.16 pursuit; pursuit max 14.63 ms. These engine monitors can overlap/update at lower cadence, so do not subtract them to infer GPU cost. The routes differ slightly in timing and police behaviour; this is indicative profiling, not identical-frame A/B testing.

Stationary uncapped 1920×1080 diagnostics (90 warmup/240 frames) report High 64.7 average / 43.0 1% low, Medium 65.6 / 42.8, Medium + synthetic combat 62.7 / 41.7. Texture allocation is 106.3 MiB High, 117.8 MiB Medium/combat; render-target allocation changes with scaling and this counter is not total resident VRAM. Render-only CPU/GPU means are 4.48/5.11 ms, 4.45/5.00 ms and 4.72/5.09 ms. The diagnostic uses [Godot viewport render timing](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu); those render times exclude gameplay scripts and should not be equated with total frame time. The short runs and small profile difference do not prove a performance improvement or stable 60 FPS.

Four real F11 transitions between 1280×720 and 1920×1080 pass render-size, mode, quality and HUD checks (`window_modes.gd`). Remaining PERF-002 work: reduce pursuit tail spikes and physics/AI cost, test worst-case armed combat/night/interior transitions and human traversal, then measure a Windows export. Export templates are not installed; current runs use the editor executable. Evidence and raw reports: `docs/evidence/neighborhood_2026-09-30.md` and its data directory.
