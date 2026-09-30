class_name LandmarkBuilder
extends RefCounted

## Hero landmarks placed on their real footprints/positions:
## Castillo de San Miguel (curtain walls, merlons, four round towers on the north
## front facing Barrio de San Miguel, gate, courtyard, museum), Peñón del Santo
## (rock, mirador, railing and white cross) with the two offshore peñones, the
## Iglesia de la Encarnación bell tower, the Phoenician monument on Paseo del Altillo
## and the Roman fish-salting vats in Parque El Majuelo.

const WALL_HEIGHT := 9.5
const WALL_THICKNESS := 2.2
const TOWER_RADIUS := 4.2


static func build(parent: Node3D, data: SectorData, mats: SectorMaterials) -> Dictionary:
	var info := {}
	var stone := mats.textured("castle_stone", "plaster003", Color("c9b18c"), 2.6, 0.95)
	var landmarks: Dictionary = data.raw["landmarks"]
	if landmarks.has("castle"):
		info["castle_gate"] = _castle(parent, data, mats, stone, landmarks["castle"])
	if landmarks.has("penon_del_santo"):
		_penon(parent, data, mats, landmarks["penon_del_santo"])
	for b in data.raw["buildings"]:
		if str(b.get("landmark", "")) == "church":
			_church_tower(parent, data, mats, b)
	if landmarks.has("phoenician_monument"):
		var p: Array = landmarks["phoenician_monument"]
		_monument(parent, mats, Vector3(float(p[0]), float(p[1]), float(p[2])))
	if landmarks.has("jaime_playa"):
		_jaime_playa(parent, data, mats, landmarks["jaime_playa"])
	for park in data.raw["parks"]:
		if str(park["name"]) == "Parque El Majuelo":
			_salting_vats(parent, data, stone, park["polygon"])
	return info


# ------------------------------------------------------------------ castle
static func _castle(parent: Node3D, data: SectorData, mats: SectorMaterials, stone: Material, castle: Dictionary) -> Vector3:
	var pts: Array[Vector2] = []
	for p in castle["footprint"]:
		pts.append(Vector2(float(p[0]), float(p[1])))
	var crest := float(castle["base"])
	var top := crest + WALL_HEIGHT
	# Four round towers on the northern (town-facing) front, spread at least 12 m apart.
	var order := range(pts.size())
	order.sort_custom(func(i: int, j: int) -> bool: return pts[i].y < pts[j].y)
	var towers: Array[int] = []
	for i in order:
		var ok := true
		for t in towers:
			if pts[t].distance_to(pts[i]) < 12.0:
				ok = false
		if ok:
			towers.append(i)
		if towers.size() == 4:
			break
	towers.sort_custom(func(i: int, j: int) -> bool: return pts[i].x < pts[j].x)
	var gate_edge := towers[1]  # opening after the second tower from the west
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces: Array = []
	var merlons: Array[Transform3D] = []
	var gate_point := Vector3.ZERO
	for i in range(pts.size()):
		var a := pts[i]
		var c := pts[(i + 1) % pts.size()]
		var length := a.distance_to(c)
		if length < 0.1:
			continue
		var dir := Vector3(c.x - a.x, 0, c.y - a.y) / length
		var normal := Vector3(dir.z, 0, -dir.x)
		var bottom := minf(data.height_at(a.x, a.y), data.height_at(c.x, c.y)) - 2.0
		if i == gate_edge and length > 6.0:
			var mid := (a + c) * 0.5
			gate_point = Vector3(mid.x, data.height_at(mid.x, mid.y), mid.y) + normal * 3.0
			_gate(st, faces, a, c, bottom, top, normal)
			continue
		_thick_wall(st, faces, a, c, bottom, top, normal)
		var steps := int(length / 2.3)
		for k in range(steps):
			var p := Vector3(a.x, top + 0.55, a.y) + dir * (2.3 * (k + 0.5))
			merlons.append(Transform3D(Basis(dir * 1.1, Vector3.UP * 1.1, dir.cross(Vector3.UP) * 0.7), p))
	for t in towers:
		var center := Vector3(pts[t].x, 0, pts[t].y)
		var ground := data.height_at(center.x, center.z) - 2.0
		_cylinder(st, faces, center, TOWER_RADIUS, ground, top + 3.0, 14)
		_cylinder(st, faces, center, TOWER_RADIUS + 0.45, top + 2.6, top + 3.2, 14)  # corbel ring
		for k in range(9):
			var angle := TAU * k / 9.0
			var offset := Vector3(cos(angle), 0, sin(angle)) * (TOWER_RADIUS + 0.2)
			merlons.append(Transform3D(Basis(Vector3.UP, -angle).scaled(Vector3(0.7, 1.1, 1.3)), center + offset + Vector3(0, top + 3.75, 0)))
	# Square towers at the far southern corners.
	var south := range(pts.size())
	south.sort_custom(func(i: int, j: int) -> bool: return pts[i].y > pts[j].y)
	for i in [south[0], south[3]]:
		var cpos := Vector3(pts[i].x, 0, pts[i].y)
		_box_tower(st, faces, cpos, 7.0, data.height_at(cpos.x, cpos.z) - 2.0, top + 2.5)
	var mesh := st.commit()
	var visual := MeshInstance3D.new()
	visual.name = "CastilloDeSanMiguel"
	visual.mesh = mesh
	visual.material_override = stone
	parent.add_child(visual)
	_static_faces(parent, "CastleCollision", faces)
	_multibox(parent, "CastleMerlons", merlons, stone)
	# Courtyard floor and the small whitewashed museum building inside.
	var courtyard := SurfaceTool.new()
	courtyard.begin(Mesh.PRIMITIVE_TRIANGLES)
	var polygon := PackedVector2Array(pts)
	var tris := Geometry2D.triangulate_polygon(polygon)
	var cfaces: Array = []
	for k in range(0, tris.size(), 3):
		var p0 := Vector3(polygon[tris[k]].x, crest + 0.1, polygon[tris[k]].y)
		var p1 := Vector3(polygon[tris[k + 1]].x, crest + 0.1, polygon[tris[k + 1]].y)
		var p2 := Vector3(polygon[tris[k + 2]].x, crest + 0.1, polygon[tris[k + 2]].y)
		Geo.add_tri(courtyard, p0, p1, p2, Vector3.UP)
		cfaces.append_array([p0, p1, p2])
	var yard := MeshInstance3D.new()
	yard.name = "CastleCourtyard"
	yard.mesh = courtyard.commit()
	yard.material_override = mats.textured("castle_yard", "pavingstones046", Color("d8cdb6"), 2.0)
	parent.add_child(yard)
	_static_faces(parent, "CastleCourtyardCollision", cfaces)
	var sum := Vector2.ZERO
	for p in pts:
		sum += p
	var centroid := sum / pts.size()
	var museum := MeshInstance3D.new()
	museum.name = "CastleMuseum"
	var box := BoxMesh.new()
	box.size = Vector3(16, 5.0, 9)
	museum.mesh = box
	museum.position = Vector3(centroid.x, crest + 2.6, centroid.y + 12.0)
	museum.material_override = mats.textured("museum_plaster", "plaster003", Color("f3efe7"), 3.0)
	parent.add_child(museum)
	return gate_point


static func _thick_wall(st: SurfaceTool, faces: Array, a: Vector2, c: Vector2, bottom: float, top: float, normal: Vector3) -> void:
	var inner := -normal * WALL_THICKNESS
	var a0 := Vector3(a.x, bottom, a.y)
	var c0 := Vector3(c.x, bottom, c.y)
	var a1 := Vector3(a.x, top, a.y)
	var c1 := Vector3(c.x, top, c.y)
	Geo.add_quad(st, a0, c0, c1, a1, normal)
	Geo.add_quad(st, a0 + inner, c0 + inner, c1 + inner, a1 + inner, -normal)
	Geo.add_quad(st, a1, c1, c1 + inner, a1 + inner, Vector3.UP)
	faces.append_array([a0, c0, c1, a0, c1, a1, a0 + inner, c0 + inner, c1 + inner, a0 + inner, c1 + inner, a1 + inner])


static func _gate(st: SurfaceTool, faces: Array, a: Vector2, c: Vector2, bottom: float, top: float, normal: Vector3) -> void:
	var dir := Vector2(c - a).normalized()
	var length := a.distance_to(c)
	var gap := 4.5
	var left_end := a + dir * (length - gap) * 0.5
	var right_start := c - dir * (length - gap) * 0.5
	_thick_wall(st, faces, a, left_end, bottom, top, normal)
	_thick_wall(st, faces, right_start, c, bottom, top, normal)
	var lintel_bottom := top - 3.0
	_thick_wall(st, faces, left_end, right_start, lintel_bottom, top, normal)


static func _cylinder(st: SurfaceTool, faces: Array, center: Vector3, radius: float, bottom: float, top: float, sides: int) -> void:
	for k in range(sides):
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var pa := center + Vector3(cos(a0), 0, sin(a0)) * radius
		var pc := center + Vector3(cos(a1), 0, sin(a1)) * radius
		var n := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		var q := [Vector3(pa.x, bottom, pa.z), Vector3(pc.x, bottom, pc.z), Vector3(pc.x, top, pc.z), Vector3(pa.x, top, pa.z)]
		Geo.add_quad(st, q[0], q[1], q[2], q[3], n)
		Geo.add_tri(st, Vector3(center.x, top, center.z), q[3], q[2], Vector3.UP)
		faces.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])


static func _box_tower(st: SurfaceTool, faces: Array, center: Vector3, size: float, bottom: float, top: float) -> void:
	var h := size * 0.5
	var corners := [Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]
	for k in range(4):
		var a: Vector2 = corners[k]
		var c: Vector2 = corners[(k + 1) % 4]
		var mid := (a + c) * 0.5
		var n := Vector3(mid.x, 0, mid.y).normalized()
		var q := [center + Vector3(a.x, bottom, a.y), center + Vector3(c.x, bottom, c.y), center + Vector3(c.x, top, c.y), center + Vector3(a.x, top, a.y)]
		Geo.add_quad(st, q[0], q[1], q[2], q[3], n)
		faces.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])
	Geo.add_quad(st, center + Vector3(-h, top, -h), center + Vector3(h, top, -h), center + Vector3(h, top, h), center + Vector3(-h, top, h), Vector3.UP)


# ------------------------------------------------------------------ Peñón del Santo
static func _penon(parent: Node3D, data: SectorData, mats: SectorMaterials, spec: Dictionary) -> void:
	var rock := mats.textured("penon_rock", "rock020", Color("b9b8b0"), 5.0, 0.95)
	var center := Vector3(float(spec["x"]), -3.0, float(spec["z"]))
	var height := float(spec["height"])
	var top := _rock(parent, "PenonDelSanto", center, float(spec["radius"]), height, 0.82, 7401, rock, 7.0)
	for i in range(spec.get("offshore", []).size()):
		var o: Array = spec["offshore"][i]
		_rock(parent, "Penon_%d" % (i + 1), Vector3(float(o[0]), -4.0, float(o[1])), float(o[2]), float(o[3]), 1.0, 7500 + i, rock, 1.5)
	var white := mats.plain("cross_white", Color("f4f2ec"), 0.6)
	var platform := MeshInstance3D.new()
	platform.name = "PenonMirador"
	var disc := CylinderMesh.new()
	disc.top_radius = 6.5
	disc.bottom_radius = 6.8
	disc.height = 0.5
	platform.mesh = disc
	platform.position = top + Vector3(0, 0.25, 0)
	platform.material_override = mats.textured("mirador_paving", "pavingstones046", Color("e6ddcb"), 1.6)
	parent.add_child(platform)
	var body := StaticBody3D.new()
	body.name = "PenonMiradorCollision"
	body.position = platform.position
	parent.add_child(body)
	var collider := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 6.5
	cyl.height = 0.5
	collider.shape = cyl
	body.add_child(collider)
	var post := BoxMesh.new()
	post.size = Vector3(0.6, 7.5, 0.6)
	var beam := BoxMesh.new()
	beam.size = Vector3(3.6, 0.6, 0.6)
	for part in [[post, Vector3(0, 4.0, 0)], [beam, Vector3(0, 5.6, 0)]]:
		var m := MeshInstance3D.new()
		m.name = "PenonCross"
		m.mesh = part[0]
		m.position = top + part[1]
		m.material_override = white
		parent.add_child(m)
	var rail: Array[Transform3D] = []
	for k in range(24):
		var angle := TAU * k / 24.0
		rail.append(Transform3D(Basis().scaled(Vector3(0.08, 1.0, 0.08)), top + Vector3(cos(angle) * 6.3, 1.0, sin(angle) * 6.3)))
	_multibox(parent, "PenonRailing", rail, mats.plain("iron_rail", Color("2b2d2f"), 0.5, 0.6))


## Noisy rock dome; returns the centre of its flat summit.
static func _rock(parent: Node3D, label: String, center: Vector3, radius: float, height: float, squash: float, seed_value: int, material: Material, summit: float) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rings := 7
	var sides := 18
	var noise: Array[float] = []
	for k in range(sides * (rings + 1)):
		noise.append(rng.randf_range(0.82, 1.12))
	var ring_points: Array = []
	for r in range(rings + 1):
		var t := float(r) / rings
		var y := center.y + height * t
		var rad := lerpf(radius, summit, pow(t, 0.8))
		var ring: Array[Vector3] = []
		for s in range(sides):
			var angle := TAU * s / sides
			var jitter := noise[r * sides + s] if r < rings else 1.0
			ring.append(Vector3(center.x + cos(angle) * rad * jitter, y + (rng.randf_range(-0.8, 0.8) if 0 < r and r < rings else 0.0), center.z + sin(angle) * rad * jitter * squash))
		ring_points.append(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hull := PackedVector3Array()
	for r in range(rings):
		for s in range(sides):
			var a: Vector3 = ring_points[r][s]
			var b: Vector3 = ring_points[r][(s + 1) % sides]
			var c: Vector3 = ring_points[r + 1][(s + 1) % sides]
			var d: Vector3 = ring_points[r + 1][s]
			var outward := ((a + b + c + d) * 0.25 - Vector3(center.x, (a.y + c.y) * 0.5, center.z)).normalized()
			var n1 := (b - a).cross(d - a).normalized()
			if n1.dot(outward) < 0:
				n1 = -n1
			Geo.add_tri(st, a, b, d, n1)
			var n2 := (c - b).cross(d - b).normalized()
			if n2.dot(outward) < 0:
				n2 = -n2
			Geo.add_tri(st, b, c, d, n2)
		for p in ring_points[r]:
			hull.append(p)
	var summit_center := Vector3(center.x, center.y + height, center.z)
	for s in range(sides):
		Geo.add_tri(st, summit_center, ring_points[rings][s], ring_points[rings][(s + 1) % sides], Vector3.UP)
	for p in ring_points[rings]:
		hull.append(p)
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = st.commit()
	visual.material_override = material
	parent.add_child(visual)
	var body := StaticBody3D.new()
	body.name = label + "Collision"
	parent.add_child(body)
	var collider := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = hull
	collider.shape = shape
	body.add_child(collider)
	return summit_center


# ------------------------------------------------------------------ church tower
static func _church_tower(parent: Node3D, data: SectorData, mats: SectorMaterials, church: Dictionary) -> void:
	var fp: Array = church["footprint"]
	var best := Vector2(float(fp[0][0]), float(fp[0][1]))
	for p in fp:  # corner facing the town (southern-most)
		if float(p[1]) > best.y:
			best = Vector2(float(p[0]), float(p[1]))
	var ground := data.height_at(best.x, best.y)
	var plaster := mats.textured("church_plaster", "plaster003", Color("ecdcbf"), 3.0)
	var shaft := MeshInstance3D.new()
	shaft.name = "EncarnacionTower"
	var box := BoxMesh.new()
	box.size = Vector3(5.6, 27.0, 5.6)
	shaft.mesh = box
	shaft.position = Vector3(best.x, ground + 13.5, best.y)
	shaft.material_override = plaster
	parent.add_child(shaft)
	var cornice := MeshInstance3D.new()
	var cbox := BoxMesh.new()
	cbox.size = Vector3(6.4, 0.6, 6.4)
	cornice.mesh = cbox
	cornice.position = shaft.position + Vector3(0, 13.8, 0)
	cornice.material_override = mats.textured("church_stone", "rock020", Color("d9ccb4"), 2.0)
	parent.add_child(cornice)
	var spire := MeshInstance3D.new()
	spire.name = "EncarnacionSpire"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = 3.3
	cone.height = 7.0
	cone.radial_segments = 8
	spire.mesh = cone
	spire.position = shaft.position + Vector3(0, 17.6, 0)
	spire.material_override = mats.textured("spire_tiles", "roofingtiles006", Color("b9d0cc"), 1.5)
	parent.add_child(spire)
	var belfry := mats.plain("belfry_dark", Color("2a2622"), 0.9)
	for side in range(4):
		var angle := PI * 0.5 * side
		var n := Vector3(cos(angle), 0, sin(angle))
		var opening := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1.6, 3.0)
		opening.mesh = quad
		opening.material_override = belfry
		parent.add_child(opening)
		opening.global_transform = Transform3D(Basis(Vector3.UP.cross(n), Vector3.UP, n), shaft.position + n * 2.82 + Vector3(0, 10.5, 0))
	var body := StaticBody3D.new()
	body.name = "EncarnacionTowerCollision"
	body.position = shaft.position
	parent.add_child(body)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	collider.shape = shape
	body.add_child(collider)


# ------------------------------------------------------------------ Phoenician monument
static func _monument(parent: Node3D, mats: SectorMaterials, at: Vector3) -> void:
	var pedestal := MeshInstance3D.new()
	pedestal.name = "MonumentoFenicioPedestal"
	var box := BoxMesh.new()
	box.size = Vector3(2.8, 2.6, 2.8)
	pedestal.mesh = box
	pedestal.position = at + Vector3(0, 1.3, 0)
	pedestal.material_override = mats.textured("monument_stone", "rock020", Color("e0d6c4"), 1.5)
	parent.add_child(pedestal)
	var body := StaticBody3D.new()
	body.name = "MonumentoFenicioCollision"
	body.position = pedestal.position
	parent.add_child(body)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	collider.shape = shape
	body.add_child(collider)
	var bronze := mats.plain("bronze", Color("6e4b2c"), 0.38, 0.85)
	var statue := HumanModel.new("male_shirt")
	statue.name = "MonumentoFenicio"
	statue.scale = Vector3.ONE * 1.35
	statue.position = at + Vector3(0, 2.6, 0)
	statue.rotation.y = PI  # facing the sea (south)
	parent.add_child(statue)
	statue.play_state("idle")
	statue.set_animation_active(false)
	for mesh in statue.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = bronze


# ------------------------------------------------------------------ Majuelo salting vats
static func _jaime_playa(parent: Node3D, data: SectorData, mats: SectorMaterials, spec: Array) -> void:
	var x := float(spec[0])
	var z := float(spec[2])
	var venue := Node3D.new()
	venue.name = "JaimePlaya"
	parent.add_child(venue)
	var cream := mats.textured("jaime_plaster", "plaster003", Color("f4e7ca"), 2.0)
	var tile := mats.textured("jaime_tile", "pavingstones046", Color("c8b996"), 2.0)
	var wood := mats.plain("jaime_wood", Color("775239"), 0.7)
	var blue := mats.textured("jaime_blue_tile", "tiles040", Color("4d9cb0"), 1.0, 0.55)
	var white := mats.plain("jaime_awning_white", Color("f2e9d4"), 0.85)
	var sand := mats.plain("jaime_awning_sand", Color("d2a778"), 0.85)
	var bottle := mats.plain("jaime_bottles", Color("3b685b"), 0.2, 0.1)
	# Open beachfront bar: counter, shaded pergola and terrace visible from the promenade.
	_jaime_box(venue, data, "RaisedTerrace", Vector3(x, 0, z), Vector3(17, 0.28, 12), tile, true)
	_jaime_box(venue, data, "BackWall", Vector3(x, 1.55, z - 4.2), Vector3(14.5, 3.1, 0.35), cream, true)
	_jaime_box(venue, data, "Counter", Vector3(x, 0.65, z + 0.1), Vector3(12.5, 1.3, 1.25), blue, true)
	_jaime_box(venue, data, "CounterTop", Vector3(x, 1.38, z + 0.1), Vector3(12.8, 0.15, 1.55), wood, false)
	for shelf_y in [1.05, 1.9]:
		_jaime_box(venue, data, "BackShelf", Vector3(x, shelf_y, z - 3.85), Vector3(10.4, 0.13, 0.48), wood, false)
	for k in range(12):
		_jaime_box(venue, data, "Bottle", Vector3(x - 4.4 + k * 0.8, 1.36, z - 3.85), Vector3(0.16, 0.48, 0.16), bottle, false)
	for dx in [-7.6, 7.6]:
		for dz in [-5.1, 5.1]:
			_jaime_box(venue, data, "PergolaPost", Vector3(x + dx, 1.9, z + dz), Vector3(0.28, 3.8, 0.28), wood, true)
	for k in range(10):
		var stripe_x := x - 7.2 + k * 1.6
		_jaime_box(venue, data, "StripedAwning", Vector3(stripe_x, 3.85, z), Vector3(1.6, 0.14, 10.5), white if k % 2 == 0 else sand, false)
	for dx in [-4.7, 0.0, 4.7]:
		_jaime_box(venue, data, "TerraceTable", Vector3(x + dx, 0.85, z + 3.35), Vector3(1.4, 0.12, 1.4), wood, false)
		_jaime_box(venue, data, "TableLeg", Vector3(x + dx, 0.44, z + 3.35), Vector3(0.13, 0.8, 0.13), wood, false)
		for side in [-1.0, 1.0]:
			_jaime_box(venue, data, "ChairSeat", Vector3(x + dx + side * 1.2, 0.52, z + 3.35), Vector3(0.65, 0.11, 0.65), wood, false)
			_jaime_box(venue, data, "ChairBack", Vector3(x + dx + side * 1.5, 0.95, z + 3.35), Vector3(0.12, 0.9, 0.65), wood, false)
	for dx in [-7.1, 7.1]:
		_jaime_box(venue, data, "Planter", Vector3(x + dx, 0.42, z + 3.3), Vector3(0.8, 0.84, 0.8), blue, false)
		var shrub := MeshInstance3D.new()
		shrub.name = "TerraceShrub"
		var canopy := SphereMesh.new()
		canopy.radius = 0.58
		canopy.height = 1.0
		shrub.mesh = canopy
		shrub.material_override = mats.plain("jaime_shrub", Color("527b54"), 0.95)
		shrub.position = Vector3(x + dx, data.height_at(x + dx, z + 3.3) + 1.1, z + 3.3)
		venue.add_child(shrub)
	var sign := Label3D.new()
	sign.name = "JaimePlayaSign"
	sign.text = "JAIME PLAYA"
	sign.font_size = 90
	sign.pixel_size = 0.006
	sign.modulate = Color("f6f0e0")
	sign.outline_modulate = Color("174761")
	sign.outline_size = 20
	sign.position = Vector3(x, data.height_at(x, z + 5.2) + 3.55, z + 5.25)
	venue.add_child(sign)
	# A visible equipment case supports the mission pickup by the monument.
	_jaime_box(venue, data, "SoundEquipment", Vector3(19.0, 0.45, 47.0), Vector3(0.85, 0.9, 0.6), blue, false)


static func _jaime_box(parent: Node3D, data: SectorData, label: String, at: Vector3, size: Vector3, material: Material, solid: bool) -> void:
	var center := Vector3(at.x, data.height_at(at.x, at.z) + at.y, at.z)
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.material_override = material
	visual.position = center
	parent.add_child(visual)
	if solid:
		var body := StaticBody3D.new()
		body.name = label + "Collision"
		body.position = center
		parent.add_child(body)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)


# ------------------------------------------------------------------ Majuelo salting vats
static func _salting_vats(parent: Node3D, data: SectorData, stone: Material, polygon: Array) -> void:
	var sum := Vector2.ZERO
	for p in polygon:
		sum += Vector2(float(p[0]), float(p[1]))
	var center := sum / polygon.size() + Vector2(10, 25)
	var walls: Array[Transform3D] = []
	for row in range(2):
		for col in range(4):
			var origin := center + Vector2(col * 4.2, row * 3.4)
			var y := data.height_at(origin.x, origin.y)
			for side in [[Vector2(0, -1.5), Vector3(3.6, 1.0, 0.45)], [Vector2(0, 1.5), Vector3(3.6, 1.0, 0.45)], [Vector2(-1.8, 0), Vector3(0.45, 1.0, 3.0)], [Vector2(1.8, 0), Vector3(0.45, 1.0, 3.0)]]:
				var o: Vector2 = side[0]
				walls.append(Transform3D(Basis().scaled(side[1]), Vector3(origin.x + o.x, y + 0.3, origin.y + o.y)))
	_multibox(parent, "SalazonesRomanos", walls, stone)


# ------------------------------------------------------------------ helpers
static func _static_faces(parent: Node3D, label: String, faces: Array) -> void:
	var body := StaticBody3D.new()
	body.name = label
	parent.add_child(body)
	var collider := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(PackedVector3Array(faces))
	collider.shape = shape
	body.add_child(collider)


static func _multibox(parent: Node3D, label: String, transforms: Array, material: Material) -> void:
	if transforms.is_empty():
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
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
	parent.add_child(instance)
