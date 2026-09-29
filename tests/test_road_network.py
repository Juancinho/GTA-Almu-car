"""Road network data checks: schema, connectivity and mission markers on streets."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NETWORK = ROOT / "game/data/world/road_network.json"
MISSION = ROOT / "game/data/missions/el_recado.json"


def load_roads() -> list[dict]:
    return json.loads(NETWORK.read_text(encoding="utf-8"))["roads"]


def distance_to_road(road: dict, x: float, z: float) -> float:
    along, across = (x, z) if road["axis"] == "x" else (z, x)
    clamped = min(max(along, road["from"]), road["to"])
    return ((along - clamped) ** 2 + (across - road["fixed"]) ** 2) ** 0.5


class RoadNetworkTests(unittest.TestCase):
    def test_schema_and_unique_ids(self) -> None:
        roads = load_roads()
        self.assertGreaterEqual(len(roads), 7)
        self.assertEqual(len({road["id"] for road in roads}), len(roads))
        for road in roads:
            self.assertIn(road["axis"], ("x", "z"), road["id"])
            self.assertLess(road["from"], road["to"], road["id"])
            self.assertGreater(road["width"], 6.0, road["id"])

    def test_network_is_connected(self) -> None:
        roads = load_roads()
        linked = {roads[0]["id"]}
        changed = True
        while changed:
            changed = False
            for road in roads:
                if road["id"] in linked:
                    continue
                for other in roads:
                    if other["id"] not in linked or other["axis"] == road["axis"]:
                        continue
                    if other["from"] <= road["fixed"] <= other["to"] and road["from"] <= other["fixed"] <= road["to"]:
                        linked.add(road["id"])
                        changed = True
                        break
        self.assertEqual(linked, {road["id"] for road in roads})

    def test_driving_objectives_are_on_roads(self) -> None:
        roads = load_roads()
        mission = json.loads(MISSION.read_text(encoding="utf-8"))
        for objective in mission["objectives"]:
            if objective["type"] in ("enter_vehicle", "reach_area", "escape_police"):
                x, z = objective["marker"]
                nearest = min(distance_to_road(road, x, z) for road in roads)
                self.assertLess(nearest, 8.0, f"{objective['text']} marker {objective['marker']} is off-road")


if __name__ == "__main__":
    unittest.main()
