"""Deterministic first-pass low-poly assets for Brisa de Poniente.

Usage: blender --background --python tools/blender/generate.py -- \
    --kind palm --seed 7401 --out game/assets/procedural/palm_a.glb
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import sys

import bpy


def parse_args() -> argparse.Namespace:
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kind", choices=("palm", "building", "compact_car"), required=True)
    parser.add_argument("--seed", type=int, default=7401)
    parser.add_argument("--floors", type=int, default=3)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    return parser.parse_args(arguments)


def material(name: str, rgba: tuple[float, float, float, float], roughness: float = 0.85) -> bpy.types.Material:
    item = bpy.data.materials.new(name)
    item.diffuse_color = rgba
    item.use_nodes = True
    principled = item.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = rgba
    principled.inputs["Roughness"].default_value = roughness
    return item


def cube(name: str, xyz: tuple[float, float, float], size: tuple[float, float, float], mat: bpy.types.Material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=xyz)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return obj


def leaf(index: int, angle: float, length: float, mat: bpy.types.Material) -> None:
    direction = (math.cos(angle), math.sin(angle))
    side = (-direction[1], direction[0])
    rings = ((0.0, 0.05, 7.55), (0.28, 0.48, 7.70), (0.62, 0.55, 7.05), (1.0, 0.03, 6.08))
    vertices: list[tuple[float, float, float]] = []
    for along, half_width, height in rings:
        for sign in (-1.0, 1.0):
            vertices.append((direction[0] * length * along + side[0] * half_width * sign,
                             direction[1] * length * along + side[1] * half_width * sign,
                             height))
    faces = []
    for segment in range(len(rings) - 1):
        a = segment * 2
        faces.extend(((a, a + 1, a + 2), (a + 1, a + 3, a + 2)))
    mesh = bpy.data.meshes.new(f"PalmLeafMesh_{index}")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    uv = mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        for loop_index in polygon.loop_indices:
            vertex_index = mesh.loops[loop_index].vertex_index
            uv.data[loop_index].uv = ((vertex_index // 2) / (len(rings) - 1), vertex_index % 2)
    obj = bpy.data.objects.new(f"PalmLeaf_{index}", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)


def make_palm(rng: random.Random) -> None:
    bark = material("M_palm_bark", (0.34, 0.27, 0.18, 1.0))
    green = material("M_palm_frond", (0.12, 0.32, 0.22, 1.0))
    bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=0.35, radius2=0.18, depth=7.5, location=(0, 0, 3.75))
    bpy.context.object.name = "PalmTrunk"
    bpy.context.object.data.materials.append(bark)
    for index in range(9):
        leaf(index, index * math.tau / 9.0 + rng.uniform(-0.08, 0.08), rng.uniform(3.3, 4.5), green)


def make_building(rng: random.Random, floors: int) -> None:
    if not 2 <= floors <= 5:
        raise ValueError("building floors must be 2–5")
    plaster = material("M_plaster_warm", (0.82, 0.77, 0.64, 1.0))
    tile = material("M_roof_terracotta", (0.48, 0.24, 0.16, 1.0))
    glass = material("M_glass_teal", (0.18, 0.36, 0.42, 1.0), 0.3)
    shutter = material("M_shutter_sage", (0.23, 0.32, 0.28, 1.0))
    awning = material("M_awning_coral", (0.65, 0.31, 0.24, 1.0))
    width = rng.uniform(11.5, 15.5)
    depth = rng.uniform(11.0, 15.0)
    height = floors * 3.2
    cube("BuildingShell", (0, 0, height / 2), (width, depth, height), plaster)
    cube("RoofTrim", (0, 0, height + 0.13), (width + 0.4, depth + 0.4, 0.26), tile)
    for floor in range(floors):
        for side in (-1, 1):
            x = side * width * 0.26
            y = -depth / 2 - 0.06
            z = floor * 3.2 + 1.75
            cube(f"Window_{floor}_{side}", (x, y, z), (1.45, 0.09, 1.55), glass)
            cube(f"Shutter_{floor}_{side}_L", (x - 0.91, y - 0.06, z), (0.3, 0.12, 1.6), shutter)
            cube(f"Shutter_{floor}_{side}_R", (x + 0.91, y - 0.06, z), (0.3, 0.12, 1.6), shutter)
    if rng.random() < 0.6:
        cube("ShopAwning", (0, -depth / 2 - 0.72, 2.68), (width * 0.76, 1.35, 0.14), awning)
    marker = bpy.data.objects.new("CollisionProxy_Box", None)
    marker.empty_display_type = "CUBE"
    marker.empty_display_size = 0.3
    marker["collision_dimensions"] = [width, depth, height]
    bpy.context.collection.objects.link(marker)


def make_car(rng: random.Random) -> None:
    paint = material("M_car_paint", (rng.uniform(0.45, 0.75), 0.24, 0.18, 1.0), 0.45)
    glass = material("M_car_glass", (0.18, 0.32, 0.36, 1.0), 0.25)
    rubber = material("M_tyre", (0.055, 0.065, 0.07, 1.0))
    light = material("M_lamp", (0.92, 0.78, 0.51, 1.0))
    rear_light = material("M_rear_lamp", (0.66, 0.07, 0.055, 1.0))
    cube("Body", (0, 0, 0.72), (1.85, 3.75, 0.78), paint)
    cube("Cabin", (0, 0.1, 1.28), (1.55, 1.95, 0.58), glass)
    cube("Roof", (0, 0.1, 1.61), (1.63, 2.1, 0.12), paint)
    for side in (-1, 1):
        for axle in (-1.15, 1.15):
            bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.33, depth=0.18,
                                                location=(side * 0.98, axle, 0.36), rotation=(0, math.pi / 2, 0))
            wheel = bpy.context.object
            wheel.name = f"Wheel_{side}_{axle}"
            wheel.data.materials.append(rubber)
        cube(f"Headlight_{side}", (side * 0.65, 1.91, 0.79), (0.3, 0.07, 0.18), light)
        cube(f"Taillight_{side}", (side * 0.65, -1.91, 0.79), (0.3, 0.07, 0.18), rear_light)
    seat = bpy.data.objects.new("DriverSeat", None)
    seat.location = (-0.35, -0.2, 0.85)
    bpy.context.collection.objects.link(seat)
    marker = bpy.data.objects.new("CollisionProxy_Box", None)
    marker["collision_dimensions"] = [1.85, 3.75, 1.15]
    bpy.context.collection.objects.link(marker)


def validate_and_export(args: argparse.Namespace) -> dict:
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError(f"{args.kind}: no mesh objects generated")
    total_triangles = 0
    objects = []
    for obj in meshes:
        dimensions = [round(float(value), 4) for value in obj.dimensions]
        if min(dimensions) <= 0.0001:
            raise RuntimeError(f"{args.kind}: zero-size mesh {obj.name}: {dimensions}")
        if not obj.data.materials:
            raise RuntimeError(f"{args.kind}: material missing on {obj.name}")
        if not obj.data.uv_layers:
            raise RuntimeError(f"{args.kind}: UV missing on {obj.name}")
        triangles = sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
        total_triangles += triangles
        objects.append({"name": obj.name, "dimensions_m": dimensions, "triangles": triangles,
                        "materials": [item.name for item in obj.data.materials], "uv_layers": len(obj.data.uv_layers)})
    if total_triangles > 5000:
        raise RuntimeError(f"{args.kind}: polygon budget exceeded ({total_triangles} triangles)")
    if args.kind in ("building", "compact_car") and "CollisionProxy_Box" not in bpy.data.objects:
        raise RuntimeError(f"{args.kind}: collision proxy marker missing")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=str(args.out.resolve()), export_format="GLB", use_selection=True)
    if not args.out.exists() or args.out.stat().st_size < 512:
        raise RuntimeError(f"{args.kind}: GLB export failed: {args.out}")
    return {"kind": args.kind, "seed": args.seed, "blender": bpy.app.version_string,
            "source_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "output": str(args.out), "output_sha256": hashlib.sha256(args.out.read_bytes()).hexdigest(),
            "mesh_count": len(meshes), "triangles": total_triangles, "objects": objects}


def main() -> None:
    args = parse_args()
    randomizer = random.Random(args.seed)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    if args.kind == "palm":
        make_palm(randomizer)
    elif args.kind == "building":
        make_building(randomizer, args.floors)
    elif args.kind == "compact_car":
        make_car(randomizer)
    report = validate_and_export(args)
    report_path = args.report or args.out.with_suffix(".json")
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"ASSET PASS: {args.kind}: {report['mesh_count']} meshes, {report['triangles']} triangles -> {args.out}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ASSET FAIL: {exc}", file=sys.stderr)
        raise
