class_name Geo
extends RefCounted

## Geometry helpers. Godot front faces are clockwise as seen by the camera, i.e. the
## cross product (p1-p0)x(p2-p0) points away from the viewer; add_tri enforces that
## for the requested outward normal so faces never end up inside-out.


static func add_tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, normal: Vector3, color: Color = Color.WHITE) -> void:
	if (p1 - p0).cross(p2 - p0).dot(normal) > 0.0:
		var swap := p1
		p1 = p2
		p2 = swap
	for p in [p0, p1, p2]:
		st.set_color(color)
		st.set_normal(normal)
		st.add_vertex(p)


static func add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color = Color.WHITE) -> void:
	add_tri(st, a, b, c, normal, color)
	add_tri(st, a, c, d, normal, color)


static func add_uv_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, meters_per_repeat: float, color: Color = Color.WHITE) -> void:
	_add_uv_tri(st, a, b, c, normal, meters_per_repeat, color)
	_add_uv_tri(st, a, c, d, normal, meters_per_repeat, color)


static func _add_uv_tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, normal: Vector3, meters_per_repeat: float, color: Color) -> void:
	if (p1 - p0).cross(p2 - p0).dot(normal) > 0.0:
		var swap := p1
		p1 = p2
		p2 = swap
	for p in [p0, p1, p2]:
		st.set_color(color)
		st.set_normal(normal)
		st.set_uv(Vector2(p.x, p.z) / meters_per_repeat)
		st.add_vertex(p)


## Faces-only list (for ConcavePolygonShape3D) from triangles already added.
static func faces_of(mesh: ArrayMesh, surface: int) -> PackedVector3Array:
	var arrays := mesh.surface_get_arrays(surface)
	return arrays[Mesh.ARRAY_VERTEX]


static func chunk_key(x: float, z: float, size: float = 160.0) -> Vector2i:
	return Vector2i(floori(x / size), floori(z / size))


## Deterministic 0..1 value from an integer (OSM id) and a salt.
static func hash01(value: int, salt: int) -> float:
	var h := hash(str(value) + ":" + str(salt))
	return float(h & 0xFFFFFF) / float(0xFFFFFF)
