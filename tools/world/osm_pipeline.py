"""Fetch and normalize a small, cached OSM reference extract for the Altillo district.

Network access is used only by `fetch`. The game reads no live geographic service.
Coordinates remain in raw provenance and a separate local Cartesian layer.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import urllib.parse
import urllib.request

EARTH_RADIUS_M = 6_378_137.0
ORIGIN_LAT = 36.7314508
ORIGIN_LON = -3.6902315
BBOX = (36.7285, -3.6970, 36.7355, -3.6840)  # south, west, north, east
OVERPASS_URL = "https://overpass-api.de/api/interpreter"


def to_local(lat: float, lon: float, origin_lat: float = ORIGIN_LAT, origin_lon: float = ORIGIN_LON) -> tuple[float, float]:
    """Return Godot horizontal coordinates (x east, z south), in metres."""
    phi = math.radians(lat)
    lam = math.radians(lon)
    phi0 = math.radians(origin_lat)
    lam0 = math.radians(origin_lon)
    return (EARTH_RADIUS_M * math.cos(phi0) * (lam - lam0), -EARTH_RADIUS_M * (phi - phi0))


def to_geo(x: float, z: float, origin_lat: float = ORIGIN_LAT, origin_lon: float = ORIGIN_LON) -> tuple[float, float]:
    phi0 = math.radians(origin_lat)
    return (origin_lat - math.degrees(z / EARTH_RADIUS_M),
            origin_lon + math.degrees(x / (EARTH_RADIUS_M * math.cos(phi0))))


def perpendicular_distance(point: tuple[float, float], start: tuple[float, float], end: tuple[float, float]) -> float:
    dx, dy = end[0] - start[0], end[1] - start[1]
    if dx == 0 and dy == 0:
        return math.dist(point, start)
    projection = max(0.0, min(1.0, ((point[0] - start[0]) * dx + (point[1] - start[1]) * dy) / (dx * dx + dy * dy)))
    return math.dist(point, (start[0] + projection * dx, start[1] + projection * dy))


def simplify(points: list[tuple[float, float]], tolerance: float = 1.8) -> list[tuple[float, float]]:
    if len(points) <= 2:
        return points
    farthest_index = max(range(1, len(points) - 1), key=lambda i: perpendicular_distance(points[i], points[0], points[-1]))
    distance = perpendicular_distance(points[farthest_index], points[0], points[-1])
    if distance <= tolerance:
        return [points[0], points[-1]]
    return simplify(points[:farthest_index + 1], tolerance)[:-1] + simplify(points[farthest_index:], tolerance)


def classify(tags: dict[str, str]) -> str | None:
    if "highway" in tags:
        return "path" if tags["highway"] in {"footway", "pedestrian", "path", "steps"} else "road"
    if "building" in tags:
        return "building"
    if tags.get("natural") == "coastline":
        return "coastline"
    if tags.get("leisure") in {"park", "garden"} or tags.get("landuse") in {"grass", "forest"}:
        return "park"
    return None


def convert(raw: dict, raw_hash: str) -> dict:
    features = []
    counts: dict[str, int] = {}
    for item in raw.get("elements", []):
        if item.get("type") != "way" or "geometry" not in item:
            continue
        tags = item.get("tags", {})
        category = classify(tags)
        if category is None:
            continue
        points = [to_local(float(node["lat"]), float(node["lon"])) for node in item["geometry"]]
        if len(points) < 2:
            continue
        closed = category in {"building", "park"} and math.dist(points[0], points[-1]) < 0.25
        if closed:
            points = points[:-1]
            if len(points) < 3:
                continue
            # Simplify a ring without collapsing its closure to a single endpoint.
            simplified = simplify(points + [points[0]])
            points = simplified[:-1] if len(simplified) >= 4 else points
        else:
            points = simplify(points)
        counts[category] = counts.get(category, 0) + 1
        features.append({"source_id": f"way/{item['id']}", "category": category,
                         "tags": {key: value for key, value in tags.items() if key in ("name", "highway", "building", "leisure", "landuse", "natural")},
                         "closed": closed, "points_xz_m": [[round(x, 2), round(z, 2)] for x, z in points]})
    return {"schema": 1, "license": "ODbL-1.0", "attribution": "Map data © OpenStreetMap contributors",
            "attribution_url": "https://www.openstreetmap.org/copyright",
            "raw_sha256": raw_hash, "origin_wgs84": [ORIGIN_LAT, ORIGIN_LON],
            "axis": "Godot x east, z south; metres", "design_transform": "none; reference data only",
            "source_timestamp": raw.get("osm3s", {}).get("timestamp_osm_base"),
            "counts": counts, "features": features}


def fetch(output: Path) -> None:
    if output.exists():
        print(f"OSM cache exists; leaving unchanged: {output}")
        return
    south, west, north, east = BBOX
    bbox = f"{south},{west},{north},{east}"
    query = f'''[out:json][timeout:25];(way["highway"]({bbox});way["building"]({bbox});way["natural"="coastline"]({bbox});way["leisure"~"park|garden"]({bbox});way["landuse"~"grass|forest"]({bbox}););out body geom;'''
    request = urllib.request.Request(OVERPASS_URL, data=urllib.parse.urlencode({"data": query}).encode(),
                                     headers={"User-Agent": "BrisaDePoniente/0.1 (offline OSM prototype)"})
    print(f"Requesting one bounded OSM extract: {bbox}")
    with urllib.request.urlopen(request, timeout=90) as response:
        payload = response.read(15_000_001)
    if len(payload) > 15_000_000:
        raise RuntimeError("OSM extract exceeds 15 MB safety limit; narrow the bounding box")
    raw = json.loads(payload)
    if "elements" not in raw:
        raise RuntimeError("Overpass response has no elements")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(payload)
    metadata = {"url": OVERPASS_URL, "query": query, "fetched_utc": datetime.now(timezone.utc).isoformat(),
                "sha256": hashlib.sha256(payload).hexdigest(), "license": "ODbL-1.0",
                "attribution": "Map data © OpenStreetMap contributors",
                "attribution_url": "https://www.openstreetmap.org/copyright"}
    output.with_suffix(".metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(f"OSM FETCH PASS: {len(raw['elements'])} elements, {len(payload)} bytes -> {output}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    command = parser.add_subparsers(dest="command", required=True)
    command.add_parser("fetch").add_argument("--out", type=Path, required=True)
    converter = command.add_parser("convert")
    converter.add_argument("--input", type=Path, required=True)
    converter.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "fetch":
        fetch(args.out)
    else:
        payload = args.input.read_bytes()
        result = convert(json.loads(payload), hashlib.sha256(payload).hexdigest())
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"OSM CONVERT PASS: {result['counts']} -> {args.out}")


if __name__ == "__main__":
    main()
