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
