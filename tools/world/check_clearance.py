"""Report footprint and driveable-road overlap in the generated sector."""

from __future__ import annotations

from collections import defaultdict
import argparse
import json
import math
import sys
from pathlib import Path
from shapely.geometry import LineString, Polygon
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
SECTOR = ROOT / "game/data/world/sector_center.json"
CELL = 8.0


def key(x: float, z: float) -> tuple[int, int]:
    return math.floor(x / CELL), math.floor(z / CELL)


def samples(a: tuple[float, float], b: tuple[float, float], step: float = 1.5):
    count = max(1, math.ceil(math.dist(a, b) / step))
    for i in range(count + 1):
        t = i / count
        yield a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--road-width-scale", type=float, default=1.0)
    args = parser.parse_args()
    data = json.loads(SECTOR.read_text(encoding="utf-8"))
    cells: dict[tuple[int, int], list[tuple[float, float, float, int]]] = defaultdict(list)
    for road in data["roads"]:
        if not road["driveable"]:
            continue
        points = [(float(p[0]), float(p[2])) for p in road["points"]]
        for a, b in zip(points, points[1:]):
            for x, z in samples(a, b):
                cells[key(x, z)].append((x, z, float(road["width"]) * args.road_width_scale * 0.5, int(road["id"])))
    conflicts: list[tuple[int, int, float]] = []
    for building in data["buildings"]:
        footprint = [(float(p[0]), float(p[1])) for p in building["footprint"]]
        worst = (0, math.inf)
        for a, b in zip(footprint, footprint[1:] + footprint[:1]):
            for x, z in samples(a, b):
                cx, cz = key(x, z)
                for dx in (-1, 0, 1):
                    for dz in (-1, 0, 1):
                        for rx, rz, half, road_id in cells.get((cx + dx, cz + dz), []):
                            clearance = math.hypot(x - rx, z - rz) - half
                            if clearance < worst[1]:
                                worst = road_id, clearance
        if worst[1] < -0.2:
            conflicts.append((int(building["id"]), worst[0], round(worst[1], 2)))
    print(f"CLEARANCE REPORT: {len(conflicts)} of {len(data['buildings'])} buildings overlap driveable lanes")
    print("Worst overlaps (building, road, metres):", sorted(conflicts, key=lambda c: c[2])[:20])
    road_lookup = {int(road["id"]): road for road in data["roads"]}
    by_class: dict[str, int] = defaultdict(int)
    for _, road_id, _ in conflicts:
        by_class[str(road_lookup[road_id]["class"])] += 1
    print("By road class:", dict(by_class))
    carriageway = unary_union([
        LineString([(float(p[0]), float(p[2])) for p in road["points"]]).buffer(
            float(road["width"]) * args.road_width_scale * 0.5)
        for road in data["roads"] if road["driveable"] and len(road["points"]) >= 2
    ])
    area_conflicts = [(int(building["id"]), round(Polygon(building["footprint"]).intersection(carriageway).area, 2))
                      for building in data["buildings"]]
    area_conflicts = [(bid, area) for bid, area in area_conflicts if area > 0.25]
    print(f"Exact polygon intersection: {len(area_conflicts)} buildings", area_conflicts[:20])
    return 1 if conflicts or area_conflicts else 0


if __name__ == "__main__":
    sys.exit(main())
