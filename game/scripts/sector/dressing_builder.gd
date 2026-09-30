class_name DressingBuilder
extends RefCounted

## Street dressing driven by the real data: palm rows along the Paseos (sea side),
## dense planting in Parque El Majuelo, lamp posts along car roads, benches on the
## promenade, and a terraced Sierra backdrop ring so the horizon is never empty.

const PalmScene = preload("res://assets/procedural/palm.glb")


static func build(parent: Node3D, data: SectorData, network: RoadNetwork, mats: SectorMaterials) -> Dictionary:
	var planned := plan(data, network)
	_scatter_scene(parent, "Palms", PalmScene, planned["palms"], mats)
	_lamp_posts(parent, mats, planned["lamps"])
	_benches(parent, mats, planned["benches"])
	_sierra(parent, mats)
	_colliders(parent, planned)
	return {"palms": (planned["palms"] as Array).size(), "palms_rejected": planned["palms_rejected"]}


## Palms, lamp posts and benches are solid: cars crash into them and people
## stop against them instead of passing through.
static func _colliders(parent: Node3D, planned: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = "StreetFurnitureCollision"
	parent.add_child(body)
	var palm_shape := CylinderShape3D.new()
	palm_shape.radius = 0.3
	palm_shape.height = 4.0
	var lamp_shape := CylinderShape3D.new()
	lamp_shape.radius = 0.13
	lamp_shape.height = 6.0
	var bench_shape := BoxShape3D.new()
	bench_shape.size = Vector3(1.9, 0.9, 0.55)
	for t in planned["palms"]:
		var s := (t as Transform3D).basis.get_scale().x
		_solid(body, palm_shape, Transform3D(Basis.IDENTITY.scaled(Vector3(s, 1.0, s)), (t as Transform3D).origin + Vector3(0, 2.0, 0)))
	for t in planned["lamps"]:
		_solid(body, lamp_shape, Transform3D(Basis.IDENTITY, (t as Transform3D).origin + Vector3(0, 3.0, 0)))
	for t in planned["benches"]:
		_solid(body, bench_shape, Transform3D((t as Transform3D).basis.orthonormalized(), (t as Transform3D).origin + Vector3(0, 0.45, -0.1)))


static func _solid(body: StaticBody3D, shape: Shape3D, at: Transform3D) -> void:
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.transform = at
	body.add_child(collider)


static func plan(data: SectorData, network: RoadNetwork) -> Dictionary:
	var palms: Array[Transform3D] = []
	var lamps: Array[Transform3D] = []
	var benches: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7405
	for road in network.roads:
		var name := str(road["name"])
		var points: PackedVector3Array = road["points"]
		var promenade := name.begins_with("Paseo")
		if road["driveable"]:
			_along(points, 24.0, float(road["width"]) * 0.5 + 1.6, true, lamps, data, rng, false)
		if promenade and road["driveable"]:
			_along(points, 11.0, float(road["width"]) * 0.5 + 3.2, false, palms, data, rng, true)
			_along(points, 26.0, float(road["width"]) * 0.5 + 5.5, false, benches, data, rng, false)
	for park in data.raw["parks"]:
		var polygon := PackedVector2Array()
		for p in park["polygon"]:
			polygon.append(Vector2(float(p[0]), float(p[1])))
		var density := 0.012 if str(park["kind"]) == "park" else 0.004
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for p in polygon:
			bounds = bounds.expand(p)
		var count := int(bounds.get_area() * density)
		for i in range(count):
			var p := Vector2(rng.randf_range(bounds.position.x, bounds.end.x), rng.randf_range(bounds.position.y, bounds.end.y))
			if Geometry2D.is_point_in_polygon(p, polygon) and data.surface_at(p.x, p.y) != "sea":
				palms.append(_upright(Vector3(p.x, data.height_at(p.x, p.y), p.y), rng.randf() * TAU, rng.randf_range(0.8, 1.35)))
	var building_areas := _building_areas(data)
	var safe_palms: Array[Transform3D] = []
	for placement in palms:
		if _clear_of_driveable(placement.origin, network, 1.0) and not _inside_building(placement.origin, building_areas):
			safe_palms.append(placement)
	var safe_lamps: Array[Transform3D] = []
	for placement in lamps:
		if _clear_of_driveable(placement.origin, network, 0.45) and not _inside_building(placement.origin, building_areas):
			safe_lamps.append(placement)
	var safe_benches: Array[Transform3D] = []
	for placement in benches:
		if _clear_of_driveable(placement.origin, network, 1.0) and not _inside_building(placement.origin, building_areas):
			safe_benches.append(placement)
	return {"palms": safe_palms, "palms_rejected": palms.size() - safe_palms.size(), "lamps": safe_lamps, "benches": safe_benches}


static func _clear_of_driveable(at: Vector3, network: RoadNetwork, margin: float) -> bool:
	var p := Vector2(at.x, at.z)
	var cell := Vector2i(floori(at.x / RoadNetwork.BUCKET), floori(at.z / RoadNetwork.BUCKET))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for segment_index in network._buckets.get(cell + Vector2i(dx, dz), []):
				var segment: Array = network._segments[segment_index]
				var road: Dictionary = network.roads[int(segment[2])]
				if not bool(road["driveable"]):
					continue
				var width := float(road["width"]) * 0.5 + margin
				var a := Vector2((segment[0] as Vector3).x, (segment[0] as Vector3).z)
				var b := Vector2((segment[1] as Vector3).x, (segment[1] as Vector3).z)
				var span := b - a
				var t := clampf((p - a).dot(span) / maxf(span.length_squared(), 0.001), 0.0, 1.0)
				if p.distance_to(a + span * t) < width:
					return false
	return true


static func _building_areas(data: SectorData) -> Array:
	var result := []
	for b in data.raw["buildings"]:
		var polygon := PackedVector2Array()
		var bounds := Rect2(Vector2(float(b["footprint"][0][0]), float(b["footprint"][0][1])), Vector2.ZERO)
		for q in b["footprint"]:
			var vertex := Vector2(float(q[0]), float(q[1]))
			polygon.append(vertex)
			bounds = bounds.expand(vertex)
		result.append([bounds, polygon])
	return result


static func _inside_building(at: Vector3, areas: Array) -> bool:
	var p := Vector2(at.x, at.z)
	for area in areas:
		if (area[0] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, area[1]):
			return true
	return false


static func _upright(at: Vector3, yaw: float, scale: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), at)


## Points every `spacing` m along a polyline, offset to one side (+right, the sea side
## for east-west Paseos) or alternating sides.
static func _along(points: PackedVector3Array, spacing: float, offset: float, alternate: bool, out: Array[Transform3D], data: SectorData, rng: RandomNumberGenerator, jitter: bool) -> void:
	var carry := spacing * 0.5
	var side := 1.0
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var length := Vector2(b.x - a.x, b.z - a.z).length()
		if length < 0.01:
			continue
		var dir := Vector3(b.x - a.x, 0, b.z - a.z) / length
		var right := Vector3(-dir.z, 0, dir.x)
		if right.z < 0.0 and not alternate:
			right = -right  # keep palms/benches on the southern (sea) side
		var t := carry
		while t < length:
			var p := a + (b - a) * (t / length) + right * offset * side
			if data.surface_at(p.x, p.z) != "sea":
				p.y = data.height_at(p.x, p.z)
				out.append(_upright(p, atan2(dir.x, dir.z) + (rng.randf() * TAU if jitter else 0.0), rng.randf_range(0.9, 1.2) if jitter else 1.0))
			if alternate:
				side = -side
			t += spacing
		carry = t - length


static func _scatter_scene(parent: Node3D, label: String, scene: PackedScene, transforms: Array[Transform3D], mats: SectorMaterials) -> void:
	if transforms.is_empty():
		return
	var template := scene.instantiate() as Node3D
	for node in template.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var local := mesh_instance.transform
		var parent_node := mesh_instance.get_parent()
		while parent_node != template and parent_node is Node3D:
			local = (parent_node as Node3D).transform * local
			parent_node = parent_node.get_parent()
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh_instance.mesh
		multi.instance_count = transforms.size()
		for i in range(transforms.size()):
			multi.set_instance_transform(i, transforms[i] * local)
		var instance := MultiMeshInstance3D.new()
		instance.name = "%s_%s" % [label, mesh_instance.name]
		instance.multimesh = multi
		if mesh_instance.name == "PalmTrunk":
			instance.material_override = mats.palm_bark()
		instance.visibility_range_end = 600.0
		parent.add_child(instance)
	template.free()


static func _lamp_posts(parent: Node3D, mats: SectorMaterials, transforms: Array[Transform3D]) -> void:
	var metal := mats.plain("lamp_metal", Color("3a3f3f"), 0.45, 0.7)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.07
	pole.bottom_radius = 0.1
	pole.height = 6.0
	pole.radial_segments = 6
	var head := BoxMesh.new()
	head.size = Vector3(0.35, 0.22, 0.9)
	var poles: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	for t in transforms:
		poles.append(t.translated_local(Vector3(0, 3.0, 0)))
		heads.append(t.translated_local(Vector3(0, 6.0, -0.35)))
	_multimesh(parent, "LampPoles", pole, poles, metal)
	_multimesh(parent, "LampHeads", head, heads, mats.plain("lamp_head", Color("d8d2bf"), 0.4))


static func _benches(parent: Node3D, mats: SectorMaterials, transforms: Array[Transform3D]) -> void:
	var seat := BoxMesh.new()
	seat.size = Vector3(1.9, 0.08, 0.5)
	var back := BoxMesh.new()
	back.size = Vector3(1.9, 0.5, 0.06)
	var seats: Array[Transform3D] = []
	var backs: Array[Transform3D] = []
	for t in transforms:
		seats.append(t.translated_local(Vector3(0, 0.45, 0)))
		backs.append(t.translated_local(Vector3(0, 0.75, -0.24)))
	var wood := mats.textured("bench_wood", "roofingtiles006", Color("8a6a4c"), 1.0)
	_multimesh(parent, "BenchSeats", seat, seats, wood)
	_multimesh(parent, "BenchBacks", back, backs, wood)


static func _multimesh(parent: Node3D, label: String, mesh: Mesh, transforms: Array[Transform3D], material: Material) -> void:
	if transforms.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in range(transforms.size()):
		multi.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = label
	instance.multimesh = multi
	instance.material_override = material
	instance.visibility_range_end = 500.0
	parent.add_child(instance)


## Terraced Sierra backdrop north of the sector: three rolling ridgelines of
## subtropical orchards (dark olive/avocado greens), lower near town, darker far away.
static func _sierra(parent: Node3D, mats: SectorMaterials) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7406
	var columns := 140
	var rings := [[650.0, 25.0, 45.0], [1000.0, 90.0, 150.0], [1500.0, 190.0, 330.0], [2300.0, 260.0, 520.0]]
	var profile: Array = []
	for r in range(rings.size()):
		var row: Array[Vector3] = []
		for i in range(columns + 1):
			var angle := lerpf(PI * 0.96, TAU * 1.04, float(i) / columns)
			var ridge: float = lerpf(rings[r][1], rings[r][2], 0.5 + 0.5 * sin(i * 0.37 + r * 1.3) * cos(i * 0.11 + r))
			ridge += rng.randf_range(-12.0, 12.0) * (r + 1)
			var radius: float = rings[r][0] + rng.randf_range(-40.0, 40.0)
			row.append(Vector3(cos(angle) * radius, ridge, sin(angle) * radius - 150.0))
		profile.append(row)
	# Orchard-green lower slopes fading to hazy blue-grey ridges. Colours vary smoothly
	# along the range and normals are smoothed, so the backdrop reads as mountains
	# instead of radial stripes (a stretched ground texture did exactly that).
	var tints := [Color("4f6034"), Color("5d6c43"), Color("74827a"), Color("93a3aa")]
	var shade := StandardMaterial3D.new()
	shade.vertex_color_use_as_albedo = true
	shade.roughness = 1.0
	shade.disable_fog = true  # depth fog washed the range out to white; haze is in the colours
	var colors: Array = []
	for r in range(rings.size()):
		var row: Array[Color] = []
		for i in range(columns + 1):
			var tint: Color = tints[r]
			var dry := 0.5 + 0.5 * sin(i * 0.21 + r * 0.8) * cos(i * 0.057 + r * 1.7)
			tint = tint.lerp(Color("8f8458"), clampf(dry - 0.45, 0.0, 0.5) * (0.9 if r < 2 else 0.35))
			row.append(tint)
		colors.append(row)
	for r in range(rings.size() - 1):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(columns):
			var quad := [[r, i], [r, i + 1], [r + 1, i + 1], [r + 1, i]]
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var p0: Vector3 = profile[quad[tri[0]][0]][quad[tri[0]][1]]
				var p1: Vector3 = profile[quad[tri[1]][0]][quad[tri[1]][1]]
				var p2: Vector3 = profile[quad[tri[2]][0]][quad[tri[2]][1]]
				var order := [tri[0], tri[1], tri[2]]
				if (p1 - p0).cross(p2 - p0).y > 0.0:  # Godot front faces are clockwise from above
					order = [tri[0], tri[2], tri[1]]
				for k in order:
					st.set_color(colors[quad[k][0]][quad[k][1]])
					st.add_vertex(profile[quad[k][0]][quad[k][1]])
		st.index()
		st.generate_normals()
		var hills := MeshInstance3D.new()
		hills.name = "SierraBackdrop_%d" % r
		hills.mesh = st.commit()
		hills.material_override = shade
		hills.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(hills)
