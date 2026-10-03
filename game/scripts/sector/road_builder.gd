class_name RoadBuilder
extends RefCounted

## Ribbon meshes for every OSM way: asphalt with curbs and centre dashes for car
## roads, stone paving for pedestrian lanes, stone for steps. Heights follow the
## (road-flattened) terrain. Meshes are grouped per 160 m chunk and material.

const LIFT_DRIVE := 0.16
const LIFT_WALK := 0.11
const CURB_WIDTH := 0.6
const SKIRT_WALK := 0.5

## No lips anywhere. Every ribbon floats 11–16 cm above the heightmap, and its
## bare edge used to be a lip that a capsule or a tyre met at ~30°: an invisible
## wall wherever the ground texture changed (road → pavement, paseo paving →
## tiles). Each ribbon now ends in a sloping skirt down into the ground (in the
## visible mesh and in the collision), and the kerb is a sloped stone band
## instead of a step, so feet and wheels roll on and off everywhere.
static var _skirts := {}  # ribbon key -> collision faces of its skirts


static func build(parent: Node3D, data: SectorData, network: RoadNetwork, mats: SectorMaterials) -> void:
	var asphalt := mats.road_asphalt()
	var paving := mats.textured("lane_paving", "pavingstones046", Color("d9d0bf"), 1.8)
	var steps := mats.textured("steps_stone", "rock020", Color("cfc6b4"), 1.2)
	var curb := mats.plain("curb", Color("cfc8b8"), 0.85)
	var paint := mats.plain("road_paint", Color("eeeae0"), 0.7)
	var tools: Dictionary = {}  # "chunk|kind" -> SurfaceTool
	_skirts = {}
	var dashes: Array[Transform3D] = []
	for road in network.roads:
		var points := _densify(road["points"] as PackedVector3Array, data)
		if points.size() < 2:
			continue
		# Old-town living streets are cobbled in reality; only through roads are asphalt.
		var kind := "asphalt" if road["driveable"] and road["class"] != "living_street" else ("steps" if road["class"] == "steps" else "paving")
		var key := "%s|%s" % [Geo.chunk_key(points[0].x, points[0].z), kind]
		if not tools.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[key] = st
		var lift := LIFT_DRIVE if road["driveable"] else LIFT_WALK
		var half := float(road["width"]) * 0.5
		var left := PackedVector3Array()
		var right := PackedVector3Array()
		for i in range(points.size()):
			var prev := points[maxi(i - 1, 0)]
			var next := points[mini(i + 1, points.size() - 1)]
			var dir := Vector3(next.x - prev.x, 0, next.z - prev.z).normalized()
			var side := Vector3(-dir.z, 0, dir.x)
			var l := points[i] + side * half
			var r := points[i] - side * half
			l.y = data.height_at(l.x, l.z) + lift
			r.y = data.height_at(r.x, r.z) + lift
			left.append(l)
			right.append(r)
		var st: SurfaceTool = tools[key]
		var road_tint := Color.WHITE
		if kind == "asphalt":
			var wear := Geo.hash01(int(road["id"]), 91)
			road_tint = Color.from_hsv(0.11, 0.025, 0.85 + wear * 0.13)
		for i in range(points.size() - 1):
			# The terrain also bends across the road width. A single wide quad
			# cuts through the heightmap and exposes patches of paving.
			var strips := maxi(2, int(ceil(float(road["width"]) / 2.0)))
			for strip in range(strips):
				var u0 := float(strip) / strips
				var u1 := float(strip + 1) / strips
				var v0 := _road_vertex(left[i], right[i], u0, data, lift)
				var v1 := _road_vertex(left[i + 1], right[i + 1], u0, data, lift)
				var v2 := _road_vertex(left[i + 1], right[i + 1], u1, data, lift)
				var v3 := _road_vertex(left[i], right[i], u1, data, lift)
				if kind == "asphalt":
					Geo.add_uv_quad(st, v0, v1, v2, v3, Vector3.UP, 2.1, road_tint)
				else:
					Geo.add_quad(st, v0, v1, v2, v3, Vector3.UP)
		_collision_skirts(key, left, right, points, data, CURB_WIDTH if kind == "asphalt" else SKIRT_WALK)
		if kind != "asphalt":
			_walk_skirts(st, left, right, data)
		else:
			_curbs(tools, key.replace("asphalt", "curb"), left, right, points, network, int(road["id"]), data)
			if str(road["class"]) == "tertiary":
				_edge_lines(tools, key.replace("asphalt", "paint"), left, right, data, lift, network, int(road["id"]))
			# Wide one-way streets have two lanes too, so retain their painted
			# lane divider instead of leaving a broad blank asphalt ribbon.
			if road["driveable"] and float(road["width"]) >= (7.0 if road["oneway"] else 6.0):
				_dashes(dashes, points, lift + 0.012)
	for key in tools:
		var kind: String = key.split("|")[1]
		var mesh := (tools[key] as SurfaceTool).commit()
		var instance := MeshInstance3D.new()
		instance.name = "Roads_" + str(key).replace("|", "_")
		instance.mesh = mesh
		instance.material_override = {"asphalt": asphalt, "paving": paving, "steps": steps, "curb": curb, "paint": paint}[kind]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(instance)
		if kind in ["asphalt", "paving", "steps"]:
			# Use exactly the rendered triangles: the heightmap lies 11–16 cm below
			# the road and cannot support feet or tyres on its visible surface.
			var body := StaticBody3D.new()
			body.name = "RoadSurface_" + str(key).replace("|", "_")
			body.add_to_group("terrain")
			body.add_to_group("road_surfaces")
			var shape := ConcavePolygonShape3D.new()
			var faces := mesh.get_faces()
			faces.append_array(_skirts.get(key, PackedVector3Array()))
			shape.set_faces(faces)
			shape.backface_collision = true
			var collision := CollisionShape3D.new()
			collision.shape = shape
			body.add_child(collision)
			parent.add_child(body)
	var dash_mesh := QuadMesh.new()
	dash_mesh.size = Vector2(0.14, 2.6)
	dash_mesh.orientation = PlaneMesh.FACE_Y
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = dash_mesh
	multi.instance_count = dashes.size()
	for i in range(dashes.size()):
		multi.set_instance_transform(i, dashes[i])
	var dash_instance := MultiMeshInstance3D.new()
	dash_instance.name = "RoadDashes"
	dash_instance.multimesh = multi
	dash_instance.material_override = paint
	dash_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(dash_instance)


static func _densify(points: PackedVector3Array, data: SectorData) -> PackedVector3Array:
	var result := PackedVector3Array()
	if points.is_empty():
		return result
	result.append(Vector3(points[0].x, data.height_at(points[0].x, points[0].z), points[0].z))
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var steps := maxi(1, int(ceil(Vector2(b.x - a.x, b.z - a.z).length() / 1.5)))
		for j in range(1, steps + 1):
			var p := a.lerp(b, float(j) / steps)
			result.append(Vector3(p.x, data.height_at(p.x, p.z), p.z))
	return result


static func _road_vertex(left: Vector3, right: Vector3, t: float, data: SectorData, lift: float) -> Vector3:
	var p := left.lerp(right, t)
	p.y = data.height_at(p.x, p.z) + lift
	return p


## Kerb: a light stone band sloping from the road edge down to the pavement
## (a dropped kerb all along), so it reads as a kerb but is never a step.
static func _curbs(tools: Dictionary, key: String, left: PackedVector3Array, right: PackedVector3Array, center: PackedVector3Array, network: RoadNetwork, own_id: int, data: SectorData) -> void:
	if not tools.has(key):
		var st_new := SurfaceTool.new()
		st_new.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[key] = st_new
	var st: SurfaceTool = tools[key]
	for edge in [left, right]:
		for i in range(edge.size() - 1):
			var a: Vector3 = edge[i]
			var b: Vector3 = edge[i + 1]
			# At junctions, the kerb of a side street ends before it reaches the
			# carriageway of the crossing road.
			if _inside_other_carriageway((a + b) * 0.5, network, own_id):
				continue
			var out_a := _outward(a, center[i])
			var out_b := _outward(b, center[i + 1])
			var a_out := _skirt_end(a, out_a, CURB_WIDTH, data, 0.012)
			var b_out := _skirt_end(b, out_b, CURB_WIDTH, data, 0.012)
			var lift := Vector3(0, 0.012, 0)
			Geo.add_quad(st, a + lift, b + lift, b_out, a_out, Vector3.UP)


## Paving and steps: the same sloping edge in their own stone.
static func _walk_skirts(st: SurfaceTool, left: PackedVector3Array, right: PackedVector3Array, data: SectorData) -> void:
	for pair in [[left, right], [right, left]]:
		var edge: PackedVector3Array = pair[0]
		var other: PackedVector3Array = pair[1]
		for i in range(edge.size() - 1):
			var a: Vector3 = edge[i]
			var b: Vector3 = edge[i + 1]
			var a_out := _skirt_end(a, _outward(a, (a + other[i]) * 0.5), SKIRT_WALK, data, 0.005)
			var b_out := _skirt_end(b, _outward(b, (b + other[i + 1]) * 0.5), SKIRT_WALK, data, 0.005)
			if edge == left:
				Geo.add_quad(st, a, b, b_out, a_out, Vector3.UP)
			else:
				Geo.add_quad(st, b, a, a_out, b_out, Vector3.UP)


## Collision skirts on both sides and both ends of a ribbon, tucked a few
## centimetres under the ground so there is no edge left to catch on.
static func _collision_skirts(key: String, left: PackedVector3Array, right: PackedVector3Array, center: PackedVector3Array, data: SectorData, width: float) -> void:
	if not _skirts.has(key):
		_skirts[key] = PackedVector3Array()
	var faces: PackedVector3Array = _skirts[key]
	for edge in [left, right]:
		for i in range(edge.size() - 1):
			var a: Vector3 = edge[i]
			var b: Vector3 = edge[i + 1]
			_tri_quad(faces, a, b, _skirt_end(b, _outward(b, center[i + 1]), width, data, -0.04), _skirt_end(a, _outward(a, center[i]), width, data, -0.04))
	var last := center.size() - 1
	for end in [[0, 1], [last, last - 1]]:
		var here: Vector3 = center[end[0]]
		var away := Vector3(here.x - center[end[1]].x, 0, here.z - center[end[1]].z).normalized()
		var l: Vector3 = left[end[0]]
		var r: Vector3 = right[end[0]]
		_tri_quad(faces, l, r, _skirt_end(r, away, width, data, -0.04), _skirt_end(l, away, width, data, -0.04))
	_skirts[key] = faces


static func _outward(edge_point: Vector3, centre: Vector3) -> Vector3:
	var out := Vector3(edge_point.x - centre.x, 0, edge_point.z - centre.z)
	return out.normalized() if out.length() > 0.001 else Vector3.RIGHT


## Where a skirt meets the ground, `width` metres out from `edge_point`; never
## above the edge itself (on a downhill side the ground may be higher).
static func _skirt_end(edge_point: Vector3, outward: Vector3, width: float, data: SectorData, offset: float) -> Vector3:
	var p := edge_point + outward * width
	p.y = minf(data.height_at(p.x, p.z) + offset, edge_point.y)
	return p


static func _tri_quad(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	faces.append_array([a, b, c, a, c, d])


static func _edge_lines(tools: Dictionary, key: String, left: PackedVector3Array, right: PackedVector3Array, data: SectorData, lift: float, network: RoadNetwork, own_id: int) -> void:
	if not tools.has(key):
		var created := SurfaceTool.new()
		created.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[key] = created
	var st: SurfaceTool = tools[key]
	for i in range(left.size() - 1):
		for near_left in [true, false]:
			var edge := left if near_left else right
			var opposite := right if near_left else left
			var midpoint := (edge[i] + edge[i + 1]) * 0.5
			if _inside_other_carriageway(midpoint, network, own_id):
				continue
			var a := _road_vertex(edge[i], opposite[i], 0.055, data, lift + 0.018)
			var b := _road_vertex(edge[i + 1], opposite[i + 1], 0.055, data, lift + 0.018)
			var c := _road_vertex(edge[i + 1], opposite[i + 1], 0.071, data, lift + 0.018)
			var d := _road_vertex(edge[i], opposite[i], 0.071, data, lift + 0.018)
			Geo.add_quad(st, a, b, c, d, Vector3.UP, Color("d9d6cc"))


static func _inside_other_carriageway(at: Vector3, network: RoadNetwork, own_id: int) -> bool:
	var cell := Vector2i(floori(at.x / RoadNetwork.BUCKET), floori(at.z / RoadNetwork.BUCKET))
	var p := Vector2(at.x, at.z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for segment_index in network._buckets.get(cell + Vector2i(dx, dz), []):
				var segment: Array = network._segments[segment_index]
				var road: Dictionary = network.roads[int(segment[2])]
				if int(road["id"]) == own_id or not bool(road["driveable"]):
					continue
				var a := Vector2((segment[0] as Vector3).x, (segment[0] as Vector3).z)
				var b := Vector2((segment[1] as Vector3).x, (segment[1] as Vector3).z)
				var span := b - a
				var t := clampf((p - a).dot(span) / maxf(span.length_squared(), 0.001), 0.0, 1.0)
				if p.distance_to(a + span * t) < float(road["width"]) * 0.5 + 0.45:
					return true
	return false


static func _dashes(dashes: Array[Transform3D], points: PackedVector3Array, lift: float) -> void:
	var travelled := 0.0
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var length := Vector2(b.x - a.x, b.z - a.z).length()
		var dir := (b - a).normalized()
		var t := fmod(6.0 - fmod(travelled, 6.0), 6.0)
		while t < length:
			var p := a + (b - a) * (t / maxf(length, 0.001))
			var basis := Basis(Vector3.UP, atan2(dir.x, dir.z))
			dashes.append(Transform3D(basis, p + Vector3(0, lift, 0)))
			t += 6.0
		travelled += length
