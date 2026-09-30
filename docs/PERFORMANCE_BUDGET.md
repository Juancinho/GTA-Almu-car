# Performance budget

Target 1920×1080 at stable 60 FPS on a mid-range Windows gaming PC, with GTX 1650 as the detected local test GPU. Frame budget: 16.7 ms total. Sustained gameplay performance still needs a visible-window playtest.

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
