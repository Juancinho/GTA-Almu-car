# Decision log

| ID | Date | Decision | Reason / revisit condition |
|----|------|----------|----------------------------|
| D-001 | 2026-09-29 | Working title **Brisa de Poniente**. | Original coastal identity; avoids the proprietary title implied by the folder name. Revisit after a playable art/mission prototype. |
| D-002 | 2026-09-29 | Use Godot 4.7.x standard and Blender 5.2 LTS portable project-local tools. | Meets requested stack without changing machine configuration. Pin patch versions in setup for reproducibility. |
| D-003 | 2026-09-29 | First district around 600 × 600 m, compressed. | Short routes and density matter more than survey accuracy. Expand only after mission works. |
| D-004 | 2026-09-29 | Source OSM coordinates and authored design offsets are separate. | Preserves provenance, repeatability and clear licensing boundaries. |
| D-005 | 2026-09-29 | Start with a nonviolent witnessed traffic incident for wanted level 1. | Enables full police loop before combat systems exist. |
| D-006 | 2026-09-29 | First district loads all at once; sector scenes define future streaming seam. | Avoids premature complexity while retaining expansion path. |
| D-007 | 2026-09-29 | Use OpenStreetMap as cached reference while the first playable roads remain authored. | Allows a complete loop before reconciling dense source geometry with lane and mission design. The OSM-derived layer retains IDs and license metadata. |
| D-008 | 2026-09-29 | Start with Godot Compatibility renderer and simple shared materials. | Gives a robust baseline on the detected GTX 1650; revisit after profiling Forward+ and lighting quality. |
| D-009 | 2026-09-29 | Authored roads live in `game/data/world/road_network.json`; geometry, minimap, HUD street names, AI paths and tests read it. | One source for visuals and navigation, as required by the technical design. WORLD-003 will generate it from the edited OSM reference. |
| D-010 | 2026-09-29 | Police act only on sightings: road-graph pursuit to the last seen position, a search sweep toward the last seen heading, arrest after 2.5 s slow within 8.5 m of a seeing unit; arrest returns the mission to `fail_checkpoint`. | Makes pursuit a real threat that can be escaped by breaking line of sight, with no omniscience. Retune after more human sessions. |
| D-011 | 2026-09-29 | Playtests and performance are recorded in-game (PerfMonitor + PlaytestLog JSON) rather than by manual notes. | Reproducible evidence for task status; offscreen samples alone cannot prove gameplay frame rate. |
