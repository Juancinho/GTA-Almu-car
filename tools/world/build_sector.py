"""Build the playable 1:1 Almuñécar sector data from the cached OSM extract.

Reads source_assets/osm/altillo_2026-09-29.json (raw Overpass, ODbL) and
source_assets/world/design_layer.json, writes game/data/world/sector_center.json:
terrain heightmap (int16 cm, base64) with surface classes, driveable road network
(OSM node graph, one-way aware), pedestrian paths/steps, building footprints with
zone/storeys/colour/roof decisions and street-facing edges, parks, coastline,
landmarks and gameplay anchors. Deterministic: same inputs -> same bytes.

Usage: python tools/world/build_sector.py [--out game/data/world/sector_center.json]
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import heapq
import json
import math
from pathlib import Path
import sys

import numpy as np
from shapely.geometry import LineString, Polygon
from shapely.geometry.polygon import orient
from shapely.ops import unary_union

sys.path.insert(0, str(Path(__file__).resolve().parent))
from osm_pipeline import to_local  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "source_assets/osm/altillo_2026-09-29.json"
DESIGN = ROOT / "source_assets/world/design_layer.json"
OUT = ROOT / "game/data/world/sector_center.json"

DRIVE_WIDTH = {"tertiary": 9.0, "residential": 7.0, "living_street": 5.5, "service": 4.5}
WALK_WIDTH = {"pedestrian": 5.0, "footway": 2.6, "steps": 2.6}
FLOOR_M = 3.1
SURFACES = ["sea", "beach", "urban", "park", "natural", "promenade"]


class BuildError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def seeded(value: int, salt: int) -> float:
    """Stable pseudo-random in [0, 1) from an OSM id."""
    digest = hashlib.sha256(f"{value}:{salt}".encode()).digest()
    return int.from_bytes(digest[:4], "little") / 2**32


def point_in_polygon(px: np.ndarray, pz: np.ndarray, poly: np.ndarray) -> np.ndarray:
    inside = np.zeros(px.shape, dtype=bool)
    x0, z0 = poly[:, 0], poly[:, 1]
    x1, z1 = np.roll(x0, -1), np.roll(z0, -1)
    for a, b, c, d in zip(x0, z0, x1, z1):
        crosses = ((b > pz) != (d > pz))
        with np.errstate(divide="ignore", invalid="ignore"):
            xint = a + (pz - b) * (c - a) / (d - b)
        inside ^= crosses & (px < xint)
    return inside


def segment_distance(px: np.ndarray, pz: np.ndarray, segs: np.ndarray, chunk: int = 256) -> np.ndarray:
    """Min distance from points to a set of segments [[x0,z0,x1,z1],...]."""
    best = np.full(px.shape, np.inf)
    flat_x, flat_z = px.ravel(), pz.ravel()
    out = best.ravel()
    for start in range(0, len(segs), chunk):
        s = segs[start:start + chunk]
        ax, az, bx, bz = s[:, 0][:, None], s[:, 1][:, None], s[:, 2][:, None], s[:, 3][:, None]
        dx, dz = bx - ax, bz - az
        length2 = np.maximum(dx * dx + dz * dz, 1e-9)
        t = np.clip(((flat_x[None, :] - ax) * dx + (flat_z[None, :] - az) * dz) / length2, 0.0, 1.0)
        qx, qz = ax + t * dx, az + t * dz
        d = np.sqrt((flat_x[None, :] - qx) ** 2 + (flat_z[None, :] - qz) ** 2).min(axis=0)
        out = np.minimum(out, d)
    return out.reshape(px.shape)


def polyline_segments(lines: list[list[tuple[float, float]]]) -> np.ndarray:
    segs = [(a[0], a[1], b[0], b[1]) for line in lines for a, b in zip(line, line[1:])]
    return np.array(segs, dtype=float) if segs else np.zeros((0, 4))


def densify(points: list[tuple[float, float]], step: float) -> list[tuple[float, float]]:
    out = [points[0]]
    for a, b in zip(points, points[1:]):
        n = max(1, int(math.dist(a, b) / step))
        for i in range(1, n + 1):
            out.append((a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n))
    return out


class Terrain:
    def __init__(self, design: dict, land_poly: np.ndarray, coast_segs: np.ndarray) -> None:
        cfg = design["terrain"]
        xmin, zmin, xmax, zmax = design["bounds"]
        self.cell = float(cfg["cell_m"])
        self.x0, self.z0 = xmin, zmin
        self.cols = int(round((xmax - xmin) / self.cell)) + 1
        self.rows = int(round((zmax - zmin) / self.cell)) + 1
        xs = xmin + np.arange(self.cols) * self.cell
        zs = zmin + np.arange(self.rows) * self.cell
        self.gx, self.gz = np.meshgrid(xs, zs)
        self.land = point_in_polygon(self.gx, self.gz, land_poly)
        self.coast_distance = segment_distance(self.gx, self.gz, coast_segs)
        height = cfg["shore_height_m"] + cfg["inland_gradient"] * self.coast_distance
        for bump in cfg["bumps"]:
            d2 = (self.gx - bump["x"]) ** 2 + (self.gz - bump["z"]) ** 2
            height += bump["height"] * np.exp(-d2 / (2 * bump["sigma"] ** 2))
        # Beach profile: ease down to the shoreline over 40 m; sea floor slopes out.
        shore = np.clip(self.coast_distance / 40.0, 0.0, 1.0)
        land_h = 0.35 + (height - 0.35) * (shore * shore * (3 - 2 * shore))
        sea_h = -np.minimum(cfg["sea_depth_m"] * -1.0, 0.8 + self.coast_distance * 0.06)
        self.h = np.where(self.land, land_h, sea_h)
        self.natural = self.h.copy()
        self.road_distance = np.full(self.h.shape, np.inf)

    def sample(self, x: float, z: float) -> float:
        fx = min(max((x - self.x0) / self.cell, 0.0), self.cols - 1.001)
        fz = min(max((z - self.z0) / self.cell, 0.0), self.rows - 1.001)
        ix, iz = int(fx), int(fz)
        tx, tz = fx - ix, fz - iz
        h = self.h
        return float((h[iz, ix] * (1 - tx) + h[iz, ix + 1] * tx) * (1 - tz) + (h[iz + 1, ix] * (1 - tx) + h[iz + 1, ix + 1] * tx) * tz)

    def burn(self, points: list[tuple[float, float, float]], half_width: float, blend: float = 6.0) -> None:
        """Flatten the heightmap across a road and blend back to the natural ground over
        `blend` metres so roads never leave vertical cut/fill steps beside them."""
        reach = half_width + blend + self.cell
        for (ax, ay, az), (bx, by, bz) in zip(points, points[1:]):
            minx, maxx = min(ax, bx) - reach, max(ax, bx) + reach
            minz, maxz = min(az, bz) - reach, max(az, bz) + reach
            c0, c1 = int((minx - self.x0) / self.cell), int((maxx - self.x0) / self.cell) + 1
            r0, r1 = int((minz - self.z0) / self.cell), int((maxz - self.z0) / self.cell) + 1
            c0, r0 = max(c0, 0), max(r0, 0)
            c1, r1 = min(c1, self.cols - 1), min(r1, self.rows - 1)
            if c1 < c0 or r1 < r0:
                continue
            px, pz = self.gx[r0:r1 + 1, c0:c1 + 1], self.gz[r0:r1 + 1, c0:c1 + 1]
            dx, dz = bx - ax, bz - az
            length2 = max(dx * dx + dz * dz, 1e-9)
            t = np.clip(((px - ax) * dx + (pz - az) * dz) / length2, 0, 1)
            d = np.hypot(px - (ax + t * dx), pz - (az + t * dz))
            target = ay + t * (by - ay)
            land = self.land[r0:r1 + 1, c0:c1 + 1]
            block = self.h[r0:r1 + 1, c0:c1 + 1]
            natural = self.natural[r0:r1 + 1, c0:c1 + 1]
            core = (d <= half_width + self.cell * 0.75) & land
            weight = np.clip((d - half_width) / blend, 0.0, 1.0)
            blended = target + (natural - target) * weight * weight * (3 - 2 * weight)
            # nearest road wins: keep whichever candidate stays closest to its own road
            closer = (d < self.road_distance[r0:r1 + 1, c0:c1 + 1]) & land & (d <= half_width + blend)
            block[closer] = np.where(core[closer], target[closer], blended[closer])
            self.road_distance[r0:r1 + 1, c0:c1 + 1] = np.where(closer, d, self.road_distance[r0:r1 + 1, c0:c1 + 1])


def build(out: Path) -> dict:
    raw = json.loads(RAW.read_text(encoding="utf-8"))
    design = json.loads(DESIGN.read_text(encoding="utf-8"))
    xmin, zmin, xmax, zmax = design["bounds"]
    nodes_xz: dict[int, tuple[float, float]] = {}
    ways = []
    for element in raw["elements"]:
        if element.get("type") != "way" or "geometry" not in element:
            continue
        pts = []
        for node_id, geo in zip(element["nodes"], element["geometry"]):
            x, z = to_local(geo["lat"], geo["lon"])
            nodes_xz[node_id] = (round(x, 2), round(z, 2))
            pts.append(nodes_xz[node_id])
        ways.append((element, pts))

    def inside(pts: list[tuple[float, float]], margin: float = 0.0) -> bool:
        return any(xmin - margin <= x <= xmax + margin and zmin - margin <= z <= zmax + margin for x, z in pts)

    coast = [pts for el, pts in ways if el["tags"].get("natural") == "coastline"]
    if not coast:
        raise BuildError("stage coastline: no natural=coastline way in raw extract")
    coast_line = max(coast, key=len)
    far = zmin - 2000.0
    land_poly = np.array(coast_line + [(coast_line[-1][0], far), (coast_line[0][0], far)], dtype=float)
    coast_segs = polyline_segments([coast_line])
    terrain = Terrain(design, land_poly, coast_segs)

    # --- roads and paths
    drive_ways, walk_ways = [], []
    for el, pts in ways:
        hw = el["tags"].get("highway")
        if hw in DRIVE_WIDTH and inside(pts, 30) and el["tags"].get("access") not in ("private", "no"):
            drive_ways.append((el, pts))
        elif hw in WALK_WIDTH and inside(pts, 30):
            walk_ways.append((el, pts))
    roads = []
    for el, pts in drive_ways + walk_ways:
        hw = el["tags"]["highway"]
        width = DRIVE_WIDTH.get(hw, WALK_WIDTH.get(hw, 3.0))
        dense = densify(pts, 3.0)
        heights = np.array([terrain.sample(x, z) for x, z in dense])
        if len(heights) > 4:  # smooth the profile along the road (running mean)
            kernel = np.ones(5) / 5.0
            padded = np.pad(heights, 2, mode="edge")
            heights = np.convolve(padded, kernel, mode="valid")
        points3 = [(round(x, 2), round(float(y), 2), round(z, 2)) for (x, z), y in zip(dense, heights)]
        roads.append({"id": el["id"], "name": el["tags"].get("name", ""), "class": hw, "width": width,
                      "driveable": hw in DRIVE_WIDTH, "oneway": el["tags"].get("oneway") == "yes",
                      "points": points3})
    for road in sorted(roads, key=lambda r: r["driveable"]):  # driveable last: they win
        terrain.burn(road["points"], road["width"] * 0.5 + (1.5 if road["driveable"] else 0.3))
    for road in roads:  # re-sample after burning so ribbons match the ground exactly
        road["points"] = [(x, round(terrain.sample(x, z), 2), z) for x, _, z in road["points"]]

    # --- driveable graph on OSM nodes (intersections survive, curves kept as nodes)
    usage: dict[int, int] = {}
    for el, _ in drive_ways:
        for n in el["nodes"]:
            usage[n] = usage.get(n, 0) + 1
    index: dict[int, int] = {}
    graph_nodes: list[tuple[float, float, float]] = []
    edges: dict[int, set[int]] = {}
    edge_names: dict[str, str] = {}
    for el, _ in drive_ways:
        ids = el["nodes"]
        for n in ids:
            if n not in index:
                x, z = nodes_xz[n]
                index[n] = len(graph_nodes)
                graph_nodes.append((x, round(terrain.sample(x, z), 2), z))
                edges[index[n]] = set()
        oneway = el["tags"].get("oneway") == "yes"
        for a, b in zip(ids, ids[1:]):
            ia, ib = index[a], index[b]
            if ia == ib:
                continue
            # Cars only drive where terrain collision exists (10 m inside the bounds).
            if not all(xmin + 10 <= nodes_xz[n][0] <= xmax - 10 and zmin + 10 <= nodes_xz[n][1] <= zmax - 10 for n in (a, b)):
                continue
            edges[ia].add(ib)
            if not oneway:
                edges[ib].add(ia)
            edge_names[f"{ia}:{ib}"] = el["tags"].get("name", "")
    # keep the largest strongly usable component (undirected connectivity)
    undirected: dict[int, set[int]] = {i: set() for i in edges}
    for a, targets in edges.items():
        for b in targets:
            undirected[a].add(b)
            undirected[b].add(a)
    seen, components = set(), []
    for start in undirected:
        if start in seen:
            continue
        stack, comp = [start], []
        seen.add(start)
        while stack:
            n = stack.pop()
            comp.append(n)
            for m in undirected[n]:
                if m not in seen:
                    seen.add(m)
                    stack.append(m)
        components.append(comp)
    keep = set(max(components, key=len))
    # Strongly connected core (Kosaraju): every kept node can reach every other one,
    # so traffic and police can never be trapped by one-way streets.
    def reach(start: int, forward: bool) -> set[int]:
        reverse: dict[int, set[int]] = {}
        if not forward:
            for a, targets in edges.items():
                for b in targets:
                    reverse.setdefault(b, set()).add(a)
        seen_nodes, stack = {start}, [start]
        while stack:
            n = stack.pop()
            for m in (edges[n] if forward else reverse.get(n, set())):
                if m in keep and m not in seen_nodes:
                    seen_nodes.add(m)
                    stack.append(m)
        return seen_nodes
    best_core: set[int] = set()
    remaining = set(keep)
    while remaining and len(remaining) > len(best_core):
        start = next(iter(sorted(remaining)))
        core = reach(start, True) & reach(start, False)
        if len(core) > len(best_core):
            best_core = core
        remaining -= core
    keep = best_core
    remap = {old: new for new, old in enumerate(sorted(keep))}
    graph = {
        "nodes": [graph_nodes[old] for old in sorted(keep)],
        "edges": [[remap[a], remap[b]] for a in sorted(keep) for b in sorted(edges[a]) if b in keep],
        "names": {f"{remap[int(k.split(':')[0])]}:{remap[int(k.split(':')[1])]}": v for k, v in edge_names.items()
                  if int(k.split(":")[0]) in keep and int(k.split(":")[1]) in keep and v},
    }

    # --- surfaces
    road_segs = polyline_segments([[(p[0], p[2]) for p in r["points"]] for r in roads])
    road_distance = segment_distance(terrain.gx, terrain.gz, road_segs)
    building_polys = []
    for el, pts in ways:
        if "building" in el["tags"] and len(pts) >= 4 and inside(pts):
            building_polys.append((el, pts[:-1] if pts[0] == pts[-1] else pts))
    building_segs = polyline_segments([p + [p[0]] for _, p in building_polys])
    building_distance = segment_distance(terrain.gx, terrain.gz, building_segs)
    surface = np.full(terrain.gx.shape, SURFACES.index("natural"), dtype=np.int8)
    urban = (road_distance < 22) | (building_distance < 25)
    surface[urban] = SURFACES.index("urban")
    parks = []
    for el, pts in ways:
        if el["tags"].get("leisure") in ("park", "garden") and inside(pts) and len(pts) >= 4:
            name = el["tags"].get("name", "")
            poly = np.array(pts, dtype=float)
            mask = point_in_polygon(terrain.gx, terrain.gz, poly)
            kind = "promenade" if name.startswith("Paseo") else "park"
            surface[mask] = SURFACES.index(kind)
            parks.append({"id": el["id"], "name": name, "kind": kind, "polygon": [list(p) for p in pts]})
    beach = terrain.land & (terrain.coast_distance < 46) & (road_distance > 7) & (building_distance > 4) & (terrain.h < 3.0)
    surface[beach & (surface != SURFACES.index("promenade"))] = SURFACES.index("beach")
    surface[~terrain.land] = SURFACES.index("sea")

    # --- buildings
    zones = design["zones"]
    zone_polys = {z["name"]: np.array(z["polygon"], dtype=float) for z in zones if "polygon" in z}
    seafront_dist = next(z["coast_distance_m"] for z in zones if z["name"] == "seafront")
    buildings = []
    landmarks = dict(design["landmarks"])
    for el, pts in building_polys:
        tags = el["tags"]
        name = tags.get("name", "")
        cx = sum(p[0] for p in pts) / len(pts)
        cz = sum(p[1] for p in pts) / len(pts)
        area = 0.5 * sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(pts, pts[1:] + pts[:1]))
        if area < 0:  # store counter-clockwise in (x, z)
            pts = list(reversed(pts))
            area = -area
        if area < 12:
            continue
        coast_d = float(segment_distance(np.array([cx]), np.array([cz]), coast_segs)[0])
        zone = "modern"
        if coast_d < seafront_dist:
            zone = "seafront"
        for zname, zpoly in zone_polys.items():
            if point_in_polygon(np.array([cx]), np.array([cz]), zpoly)[0]:
                zone = zname
        rnd = seeded(el["id"], 1)
        levels_rule = {"old_town": (2, 3), "san_miguel": (1, 3), "seafront": (5, 9), "modern": (3, 6)}[zone]
        levels = int(tags["building:levels"]) if tags.get("building:levels", "").isdigit() else levels_rule[0] + int(rnd * (levels_rule[1] - levels_rule[0] + 1))
        if area < 40:
            levels = min(levels, 2)
        base = min(terrain.sample(x, z) for x, z in pts)
        top_ground = max(terrain.sample(x, z) for x, z in pts)
        edge_street = []
        for a, b in zip(pts, pts[1:] + pts[:1]):
            mx, mz = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
            ex, ez = b[0] - a[0], b[1] - a[1]
            length = math.hypot(ex, ez) or 1.0
            nx, nz = ez / length, -ex / length  # outward normal for CCW in (x,z) with z south
            probe_x, probe_z = mx + nx * 6.0, mz + nz * 6.0
            d = float(segment_distance(np.array([probe_x]), np.array([probe_z]), road_segs)[0]) if len(road_segs) else 99
            edge_street.append(1 if d < 9.0 else 0)
        entry = {"id": el["id"], "footprint": [[round(x, 2), round(z, 2)] for x, z in pts],
                 "base": round(base - 0.4, 2), "height": round(top_ground - base + 0.4 + levels * FLOOR_M, 2),
                 "levels": levels, "zone": zone, "area": round(area, 1), "street_edges": edge_street,
                 "tint": int(seeded(el["id"], 2) * 1000), "plinth": int(seeded(el["id"], 3) * 1000),
                 "roof": "tile" if (zone in ("old_town", "san_miguel") and area < 220 and seeded(el["id"], 4) < 0.55) else "terrace"}
        if name == "Castillo de San Miguel":
            landmarks["castle"] = {"id": el["id"], "footprint": entry["footprint"], "base": round(top_ground, 2)}
            continue
        if name == "Iglesia de la Encarnación":
            entry["landmark"] = "church"
            entry["levels"] = 4
            entry["height"] = round(top_ground - base + 13.0, 2)
            entry["roof"] = "tile"
        buildings.append(entry)

    # OSM centre lines and inferred carriageway widths sometimes cut through
    # source building footprints, especially in the old town. Keep the largest
    # usable part of each footprint outside the driveable road envelope.
    road_envelope = unary_union([
        LineString([(p[0], p[2]) for p in road["points"]]).buffer(
            road["width"] * 0.5 + 0.45, quad_segs=2, cap_style="round", join_style="round")
        for road in roads if road["driveable"] and len(road["points"]) >= 2
    ])
    clipped_buildings = []
    clipped_count = 0
    setback_count = 0
    removed_count = 0
    # Preserve the hand-placed business entrances: their front-edge indices and
    # footprints are used by the physical interiors and the garage.
    fixed_entrances = {1388939169, 1388635018, 1388940272, 1388635559, 1389157377, 1388629764}
    for entry in buildings:
        footprint = Polygon(entry["footprint"]).buffer(0)
        usable = footprint.difference(road_envelope)
        pieces = [usable] if usable.geom_type == "Polygon" else [g for g in getattr(usable, "geoms", []) if g.geom_type == "Polygon"]
        if not pieces:
            removed_count += 1
            continue
        candidate = max(pieces, key=lambda shape: shape.area).simplify(0.12, preserve_topology=True)
        if candidate.area < 22.0 or candidate.area < footprint.area * 0.22:
            removed_count += 1
            continue
        # A small, varied recess gives newer blocks daylight and readable gaps.
        # Historic attached houses retain the surveyed street wall.
        if (entry["zone"] in ("modern", "seafront") and entry["id"] not in fixed_entrances
                and candidate.area >= 130.0 and entry.get("landmark") is None):
            setback = 0.35 + seeded(entry["id"], 208) * 0.55
            inset = candidate.buffer(-setback, join_style="mitre")
            if inset.geom_type == "Polygon" and inset.area >= candidate.area * 0.72:
                candidate = inset
                setback_count += 1
        if candidate.area < footprint.area - 0.1:
            clipped_count += 1
            candidate = orient(candidate, sign=1.0)
            pts = [(round(x, 2), round(z, 2)) for x, z in list(candidate.exterior.coords)[:-1]]
            if len(pts) < 3:
                removed_count += 1
                continue
            base = min(terrain.sample(x, z) for x, z in pts)
            top_ground = max(terrain.sample(x, z) for x, z in pts)
            entry["footprint"] = [[x, z] for x, z in pts]
            entry["base"] = round(base - 0.4, 2)
            entry["height"] = round(top_ground - base + (13.0 if entry.get("landmark") == "church" else 0.4 + entry["levels"] * FLOOR_M), 2)
            entry["area"] = round(candidate.area, 1)
            street_edges = []
            for a, b in zip(pts, pts[1:] + pts[:1]):
                mx, mz = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
                ex, ez = b[0] - a[0], b[1] - a[1]
                length = math.hypot(ex, ez) or 1.0
                probe_x, probe_z = mx + ez / length * 6.0, mz - ex / length * 6.0
                d = float(segment_distance(np.array([probe_x]), np.array([probe_z]), road_segs)[0]) if len(road_segs) else 99
                street_edges.append(1 if d < 9.0 else 0)
            entry["street_edges"] = street_edges
        clipped_buildings.append(entry)
    buildings = clipped_buildings
    print(f"BUILDING CLEARANCE: {clipped_count} footprints trimmed (including {setback_count} modern setbacks), {removed_count} unusable footprints omitted")

    # --- gameplay anchors (nearest driveable graph node to named places)
    def nearest_node(x: float, z: float) -> list[float]:
        best = min(graph["nodes"], key=lambda n: (n[0] - x) ** 2 + (n[2] - z) ** 2)
        return [best[0], best[1], best[2]]

    def ground(x: float, z: float) -> list[float]:
        return [x, round(terrain.sample(x, z), 2), z]

    node_list = graph["nodes"]
    adjacency: dict[int, list[int]] = {i: [] for i in range(len(node_list))}
    for a, b in graph["edges"]:
        adjacency[a].append(b)

    def route_lengths(start: int) -> dict[int, float]:
        dist = {start: 0.0}
        queue = [(0.0, start)]
        while queue:
            d, u = heapq.heappop(queue)
            if d > dist[u]:
                continue
            for v in adjacency[u]:
                nd = d + math.dist((node_list[u][0], node_list[u][2]), (node_list[v][0], node_list[v][2]))
                if nd < dist.get(v, math.inf):
                    dist[v] = nd
                    heapq.heappush(queue, (nd, v))
        return dist

    def index_of(p: list[float]) -> int:
        return min(range(len(node_list)), key=lambda i: (node_list[i][0] - p[0]) ** 2 + (node_list[i][2] - p[2]) ** 2)

    def closest_by_road(start: list[float], cx: float, cz: float, radius: float) -> list[float]:
        dist = route_lengths(index_of(start))
        options = [i for i in dist if math.hypot(node_list[i][0] - cx, node_list[i][2] - cz) < radius]
        if not options:
            raise BuildError(f"stage anchors: no driveable node within {radius} m of ({cx}, {cz})")
        return list(node_list[min(options, key=lambda i: dist[i])])

    first_car = nearest_node(-40.0, 26.0)
    old_town_target = closest_by_road(first_car, -94.0, -240.0, 70.0)
    castle_drop = closest_by_road(old_town_target, -214.0, 60.0, 110.0)
    anchors = {
        "player_spawn": ground(-5.0, 34.0),
        "alba": ground(12.0, 36.0),
        "first_car": first_car,
        "old_town_target": old_town_target,
        "castle_drop": castle_drop,
        "hospital": nearest_node(design["landmarks"]["hospital"]["x"], design["landmarks"]["hospital"]["z"]),
        "arrest_release": ground(-5.0, 34.0),
    }
    jaime = design["landmarks"]["jaime_playa"]
    anchors["jaime_playa"] = ground(jaime["x"], jaime["z"])
    anchors["jaime_staff"] = ground(jaime["x"] - 5.0, jaime["z"] + 7.0)
    phoenician = design["landmarks"]["phoenician_monument"]
    anchors["jaime_equipment"] = ground(phoenician["x"] + 1.0, phoenician["z"] + 17.0)
    legs = {"first_car->old_town_target": round(route_lengths(index_of(first_car))[index_of(old_town_target)], 1),
            "old_town_target->castle_drop": round(route_lengths(index_of(old_town_target))[index_of(castle_drop)], 1)}
    restricted = [{"name": "Plaza de la Constitución", "x": -94.0, "z": -240.0, "radius": 70.0},
                  {"name": "Calle Real", "x": -52.0, "z": -195.0, "radius": 45.0}]
    landmarks["phoenician_monument"] = ground(phoenician["x"], phoenician["z"])
    landmarks["jaime_playa"] = ground(jaime["x"], jaime["z"])

    heights_cm = np.clip(np.round(terrain.h * 100.0), -32768, 32767).astype("<i2")
    data = {
        "schema": "brisa.sector.v1",
        "name": "Almuñécar centro (Puerta del Mar, casco antiguo, San Miguel, San Cristóbal)",
        "license": "Derived from OpenStreetMap (ODbL). Terrain PROVISIONAL (design control points) until CNIG MDT05 (WORLD-004).",
        "inputs": {"osm_raw_sha256": sha256(RAW), "design_layer_sha256": sha256(DESIGN), "builder_sha256": sha256(Path(__file__))},
        "bounds": design["bounds"],
        "terrain": {"x0": terrain.x0, "z0": terrain.z0, "cell": terrain.cell, "cols": terrain.cols, "rows": terrain.rows,
                    "heights_cm_b64": base64.b64encode(heights_cm.tobytes()).decode(),
                    "surface_b64": base64.b64encode(surface.astype(np.int8).tobytes()).decode(), "surfaces": SURFACES},
        "coast": [[round(x, 2), round(z, 2)] for x, z in coast_line if xmin - 200 <= x <= xmax + 200],
        "roads": roads,
        "graph": graph,
        "buildings": buildings,
        "parks": parks,
        "landmarks": landmarks,
        "anchors": anchors,
        "mission_legs_m": legs,
        "restricted_zones": restricted,
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    return data


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path, default=OUT)
    args = parser.parse_args()
    try:
        data = build(args.out)
    except BuildError as error:
        print(f"SECTOR FAIL: {error}", file=sys.stderr)
        return 1
    drive = sum(1 for r in data["roads"] if r["driveable"])
    print(f"SECTOR PASS: {len(data['buildings'])} buildings, {drive} driveable + {len(data['roads']) - drive} walkable ways, "
          f"{len(data['graph']['nodes'])} graph nodes, {len(data['graph']['edges'])} directed edges, "
          f"terrain {data['terrain']['cols']}x{data['terrain']['rows']} -> {args.out.relative_to(ROOT)} "
          f"({args.out.stat().st_size // 1024} KiB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
