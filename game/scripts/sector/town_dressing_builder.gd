class_name TownDressingBuilder
extends RefCounted

## Everyday clutter that makes the generated town read as lived-in rather than
## extruded: rooftop stair huts, water tanks, solar heaters, antennas and AC units;
## split-AC units, geranium pots, bougainvillea and canvas shop awnings on street
## façades; recycling containers and zebra crossings on the streets; umbrellas,
## loungers and towels on the beaches.
## Everything is deterministic (OSM id / fixed seeds), instanced per 160 m chunk
## with short visibility ranges so small props cost few draw calls far away.
## Façade props replicate BuildingBuilder's bay layout so they line up with windows.

const FLOOR_M := 3.1
const VenueCatalog = preload("res://scripts/venue_catalog.gd")
const AWNING_COLORS := ["2e6f8e", "b8432f", "2f7a4f", "c98a2b", "6b3d6e", "1f4e79", "a33b4f", "3d6b5a", "d0a33a"]
const BOUGAINVILLEA := ["c2185b", "d63384", "a0306e", "e0529c", "b8327a"]
const LEAVES := ["4f7a3a", "5d8a3f", "3f6b34"]
const FLOWERS := ["d7263d", "e85d75", "f4a259", "f7f3e8", "c2185b"]
const CONTAINERS := ["2f6b3a", "e3b72b", "2e5fa3", "6d7270"]
const CANOPIES := ["e8d44d", "d9453b", "2d7fb8", "f2f0e8", "3a9a6b", "f08a24", "1f4e79"]
const TOWELS := ["e0529c", "2d7fb8", "f2c14e", "3a9a6b", "e85d3b", "8e5bc2", "f2f0e8"]

## Item kind -> [mesh, material key, visibility end (m), casts shadow]
var _kinds: Dictionary = {}
## Item kind -> chunk Vector2i -> Array of [Transform3D, Color, Color custom]
var _items: Dictionary = {}


static func build(parent: Node3D, data: SectorData, network: RoadNetwork, mats: SectorMaterials) -> Dictionary:
	# Loaded by path, not class_name, so a stale editor class cache cannot break the build.
	var builder: Object = (load("res://scripts/sector/town_dressing_builder.gd") as GDScript).new()
	return builder.call("_build", parent, data, network, mats)


func _build(parent: Node3D, data: SectorData, network: RoadNetwork, mats: SectorMaterials) -> Dictionary:
	_define_kinds(mats)
	var skip := {}
	for id in VenueCatalog.fronts():
		skip[int(id)] = true
	for shop in CommerceBuilder.SHOPS:
		skip[int(shop[0])] = true
	var stats := {"roof_props": 0, "facade_props": 0, "awnings": 0, "containers": 0, "crossings": 0, "umbrellas": 0}
	for b in data.raw["buildings"]:
		_building(b, data, skip.has(int(b["id"])), stats)
	var areas := DressingBuilder._building_areas(data)
	var bins := _containers(data, network, areas, stats)
	_crossings(data, network, stats)
	_beach(data, network, areas, stats)
	for kind in _items:
		for chunk in _items[kind]:
			_emit(parent, kind, chunk, _items[kind][chunk])
	if not bins.is_empty():
		var body := StaticBody3D.new()
		body.name = "ContainerCollision"
		parent.add_child(body)
		for entry in bins:
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = entry[1]
			shape.shape = box
			shape.transform = entry[0]
			body.add_child(shape)
	return stats


func _define_kinds(mats: SectorMaterials) -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.5
	cylinder.bottom_radius = 0.5
	cylinder.height = 1.0
	cylinder.radial_segments = 8
	cylinder.rings = 1
	var thin := CylinderMesh.new()
	thin.top_radius = 0.5
	thin.bottom_radius = 0.5
	thin.height = 1.0
	thin.radial_segments = 4
	thin.rings = 1
	var cone := CylinderMesh.new()
	cone.top_radius = 0.04
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 10
	cone.rings = 1
	var blob := SphereMesh.new()
	blob.radius = 0.5
	blob.height = 1.0
	blob.radial_segments = 7
	blob.rings = 4
	var plaster := mats.textured("rooftop_plaster", "plaster003", Color.WHITE, 3.0, 0.92, true)
	var awning := ShaderMaterial.new()
	awning.shader = load("res://shaders/awning.gdshader") as Shader
	_kinds = {
		"RoofHut": [box, plaster, 420.0, true],
		"RoofTank": [cylinder, _tinted(mats, "prop_paint", 0.55), 320.0, true],
		"RoofSolar": [box, _tinted(mats, "prop_glass", 0.2, 0.35), 320.0, false],
		"RoofAntenna": [thin, _tinted(mats, "prop_metal", 0.5, 0.6), 220.0, false],
		"WallAC": [box, _tinted(mats, "prop_paint", 0.55), 190.0, false],
		"Awning": [_awning_mesh(), awning, 300.0, true],
		"Pot": [box, _tinted(mats, "prop_clay", 0.9), 150.0, false],
		"Foliage": [blob, _tinted(mats, "prop_foliage", 0.95), 260.0, false],
		"Container": [box, _tinted(mats, "prop_plastic", 0.6), 260.0, true],
		"Zebra": [box, _tinted(mats, "prop_road_paint", 0.7), 170.0, false],
		"UmbrellaPole": [thin, _tinted(mats, "prop_metal", 0.5, 0.6), 260.0, false],
		"UmbrellaCanopy": [cone, _tinted(mats, "prop_canvas", 0.9), 320.0, true],
		"Lounger": [box, _tinted(mats, "prop_plastic", 0.6), 220.0, false],
		"Towel": [box, _tinted(mats, "prop_canvas", 0.9), 160.0, false],
	}
	for kind in _kinds:
		_items[kind] = {}


func _tinted(mats: SectorMaterials, key: String, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	if mats.cache.has(key):
		return mats.cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.roughness = roughness
	mat.metallic = metallic
	mats.cache[key] = mat
	return mat


## Unit awning: 1 m wide (x -0.5..0.5), projecting 1 m (+z) and dropping 0.45 m,
## with a 0.25 m valance and closed side cheeks. UV.x runs across the width.
static func _awning_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall_l := Vector3(-0.5, 0, 0)
	var wall_r := Vector3(0.5, 0, 0)
	var front_l := Vector3(-0.5, -0.45, 1)
	var front_r := Vector3(0.5, -0.45, 1)
	var hem_l := Vector3(-0.5, -0.7, 1)
	var hem_r := Vector3(0.5, -0.7, 1)
	var slope_n := Vector3(0, 1, 0.45).normalized()
	_uv_quad(st, wall_l, wall_r, front_r, front_l, slope_n)
	_uv_quad(st, front_l, front_r, hem_r, hem_l, Vector3(0, 0, 1))
	for side: float in [-1.0, 1.0]:
		var n := Vector3(side, 0, 0)
		var a := Vector3(0.5 * side, 0, 0)
		var b := Vector3(0.5 * side, -0.45, 1)
		var c := Vector3(0.5 * side, -0.7, 1)
		for p in [a, b, c]:
			st.set_color(Color.WHITE)
			st.set_normal(n)
			st.set_uv(Vector2(0.0, 0.0))
			st.add_vertex(p)
	return st.commit()


static func _uv_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_color(Color.WHITE)
		st.set_normal(n)
		st.set_uv(Vector2(p.x + 0.5, p.z))
		st.add_vertex(p)


func _add(kind: String, t: Transform3D, color: Color, custom: Color = Color(0, 0, 0, 0)) -> void:
	var key := Geo.chunk_key(t.origin.x, t.origin.z)
	var by_chunk: Dictionary = _items[kind]
	if not by_chunk.has(key):
		by_chunk[key] = []
	(by_chunk[key] as Array).append([t, color, custom])


static func _box(basis: Basis, size: Vector3, at: Vector3) -> Transform3D:
	return Transform3D(Basis(basis.x * size.x, basis.y * size.y, basis.z * size.z), at)


# --- Buildings -------------------------------------------------------------------

func _building(b: Dictionary, data: SectorData, skip_facade: bool, stats: Dictionary) -> void:
	var pts: Array[Vector2] = []
	for p in b["footprint"]:
		pts.append(Vector2(float(p[0]), float(p[1])))
	if pts.size() < 3:
		return
	var center := Vector2.ZERO
	for p in pts:
		center += p
	center /= pts.size()
	var top := float(b["base"]) + float(b["height"])
	var zone := str(b["zone"])
	var id := int(b["id"])
	var tiled := str(b["roof"]) == "tile" and pts.size() <= 9 and Geometry2D.is_point_in_polygon(center, PackedVector2Array(pts))
	var wall_color := Color(BuildingBuilder._pick(zone, int(b["tint"])))
	if not tiled:
		stats["roof_props"] += _roof(pts, top, id, int(b["levels"]), float(b["area"]), wall_color)
	if skip_facade:
		return
	var street: Array = b["street_edges"]
	for i in range(pts.size()):
		if i >= street.size() or int(street[i]) != 1:
			continue
		var a := pts[i]
		var c := pts[(i + 1) % pts.size()]
		var length := a.distance_to(c)
		if length < 2.4:
			continue
		var edge := c - a
		var normal := Vector3(edge.y, 0, -edge.x) / length
		_facade(stats, b, zone, a, c, normal, data, top, id * 31 + i)


func _roof(pts: Array[Vector2], top: float, id: int, levels: int, area: float, wall_color: Color) -> int:
	if area < 25.0:
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = id * 7 + 3
	var polygon := PackedVector2Array(pts)
	var bounds := Rect2(pts[0], Vector2.ZERO)
	var longest := Vector2.RIGHT
	var longest_length := 0.0
	for i in range(pts.size()):
		bounds = bounds.expand(pts[i])
		var e := pts[(i + 1) % pts.size()] - pts[i]
		if e.length() > longest_length:
			longest_length = e.length()
			longest = e.normalized()
	var yaw := atan2(longest.x, longest.y)
	var basis := Basis(Vector3.UP, yaw)
	var placed := 0
	if levels >= 2 and area > 70.0 and rng.randf() < 0.65:
		var spot := _roof_spot(polygon, bounds, 2.0, rng)
		if spot != Vector2.INF:
			_add("RoofHut", _box(basis, Vector3(rng.randf_range(2.4, 3.2), 2.3, rng.randf_range(2.4, 3.0)), Vector3(spot.x, top + 1.15, spot.y)), wall_color)
			placed += 1
	for k in range(rng.randi_range(0, clampi(int(area / 150.0), 1, 4))):
		var spot := _roof_spot(polygon, bounds, 1.0, rng)
		if spot == Vector2.INF:
			continue
		var s := rng.randf_range(0.8, 1.1)
		var tank_color := Color("2b2b2b") if rng.randf() < 0.25 else Color("ecebe6") if rng.randf() < 0.7 else Color("b9bcb8")
		_add("RoofTank", _box(basis, Vector3(0.95 * s, 1.2 * s, 0.95 * s), Vector3(spot.x, top + 0.6 * s, spot.y)), tank_color)
		placed += 1
	if area > 60.0 and rng.randf() < 0.3:
		for k in range(rng.randi_range(1, 2)):
			var spot := _roof_spot(polygon, bounds, 1.4, rng)
			if spot == Vector2.INF:
				continue
			# Thermal panels face south (+z) with the tank on top, as on every Costa roof.
			var tilt := Basis(Vector3.RIGHT, deg_to_rad(35.0))
			_add("RoofSolar", _box(tilt, Vector3(2.0, 0.06, 1.1), Vector3(spot.x, top + 0.75, spot.y)), Color("1c2a3d"))
			var tank_basis := Basis(Vector3.FORWARD, PI * 0.5)
			_add("RoofTank", _box(tank_basis, Vector3(0.5, 1.9, 0.5), Vector3(spot.x, top + 1.25, spot.y - 0.5)), Color("ecebe6"))
			placed += 2
	for k in range(rng.randi_range(0, 3)):
		var spot := _roof_spot(polygon, bounds, 0.8, rng)
		if spot != Vector2.INF:
			_add("WallAC", _box(basis, Vector3(0.9, 0.65, 0.45), Vector3(spot.x, top + 0.33, spot.y)), Color("dcdcd6"))
			placed += 1
	if rng.randf() < 0.5:
		var spot := _roof_spot(polygon, bounds, 0.6, rng)
		if spot != Vector2.INF:
			var h := rng.randf_range(2.6, 3.8)
			_add("RoofAntenna", _box(Basis.IDENTITY, Vector3(0.05, h, 0.05), Vector3(spot.x, top + h * 0.5, spot.y)), Color("9a9a96"))
			_add("RoofAntenna", _box(Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.035, 1.3, 0.035), Vector3(spot.x, top + h - 0.35, spot.y)), Color("9a9a96"))
			placed += 1
	return placed


static func _roof_spot(polygon: PackedVector2Array, bounds: Rect2, margin: float, rng: RandomNumberGenerator) -> Vector2:
	for attempt in range(12):
		var p := Vector2(rng.randf_range(bounds.position.x, bounds.end.x), rng.randf_range(bounds.position.y, bounds.end.y))
		var ok := Geometry2D.is_point_in_polygon(p, polygon)
		for offset in [Vector2(margin, 0), Vector2(-margin, 0), Vector2(0, margin), Vector2(0, -margin)]:
			ok = ok and Geometry2D.is_point_in_polygon(p + offset, polygon)
		if ok:
			return p
	return Vector2.INF


## Mirrors BuildingBuilder._facade's bays, door bay and per-floor random values.
func _facade(stats: Dictionary, b: Dictionary, zone: String, a: Vector2, c: Vector2, normal: Vector3, data: SectorData, top: float, seed_value: int) -> void:
	var length := a.distance_to(c)
	var bay_width := 2.7 + Geo.hash01(seed_value, 301) * 1.35
	var bays := maxi(1, int(length / bay_width))
	var spacing := length / bays
	var dir := Vector3(c.x - a.x, 0, c.y - a.y) / length
	var face := Basis(Vector3.UP.cross(normal), Vector3.UP, normal)
	var levels := int(b["levels"])
	var old := zone == "old_town" or zone == "san_miguel"
	var landmark := str(b.get("landmark", ""))
	if landmark != "":
		return
	var door_bay := int(Geo.hash01(seed_value, 5) * bays)
	var seafront_balconies := zone == "seafront" and levels > 2 and Geo.hash01(seed_value, 304) < 0.68
	var balcony_depth := 0.75 + Geo.hash01(seed_value, 305) * 0.45
	var awning_color := Color(AWNING_COLORS[int(Geo.hash01(seed_value, 71) * AWNING_COLORS.size()) % AWNING_COLORS.size()])
	var striped := 1.0 if Geo.hash01(seed_value, 72) < 0.6 else 0.0
	for bay in range(bays):
		var along := spacing * (bay + 0.5)
		var at := Vector3(a.x, 0, a.y) + dir * along
		var ground := data.height_at(at.x, at.z)
		for floor_index in range(levels):
			var y := ground + floor_index * FLOOR_M
			if y + 2.4 > top:
				break
			var r := Geo.hash01(seed_value * 13 + bay, floor_index)
			var roll := Geo.hash01(seed_value * 7 + bay, floor_index + 40)
			if floor_index == 0:
				var shop := bay != door_bay and (not old or r < 0.35)
				if shop and (r < 0.3 or Geo.hash01(seed_value + bay, 77) < 0.3):
					var width := minf(spacing - 0.4, 3.0) + 0.3
					_add("Awning", _box(face, Vector3(width, 1.0, 1.15), at + normal * 0.05 + Vector3(0, ground + 2.95, 0)), awning_color, Color(width / 10.0, striped, 0, 0))
					stats["awnings"] += 1
				continue
			if old:
				if r >= 0.7 and roll < 0.6:  # pots along the old-town balcony
					_pots(face, at + normal * 0.42 + Vector3(0, y + 0.05 + 0.19, 0), 1.2, seed_value + bay * 17 + floor_index)
					stats["facade_props"] += 1
				elif r < 0.7 and roll < 0.38:  # geraniums on the window sill
					_pots(face, at + normal * 0.16 + Vector3(0, y + 0.7, 0), 0.9, seed_value + bay * 17 + floor_index)
					stats["facade_props"] += 1
			elif seafront_balconies and roll < 0.28:
				_pots(face, at + normal * (balcony_depth - 0.22) + Vector3(0, y + 0.05 + 0.19, 0), 0.7, seed_value + bay * 17 + floor_index)
				stats["facade_props"] += 1
			if bay < bays - 1 and Geo.hash01(seed_value * 5 + bay, floor_index + 90) < (0.06 if old else 0.22):
				var ac_at := Vector3(a.x, 0, a.y) + dir * (spacing * (bay + 1)) + normal * 0.2
				_add("WallAC", _box(face, Vector3(0.8, 0.55, 0.3), ac_at + Vector3(0, y + 2.05, 0)), Color("e2e1dc"))
				stats["facade_props"] += 1
	if Geo.hash01(seed_value, 410) < (0.16 if old else 0.07):
		var k := int(Geo.hash01(seed_value, 411) * bays)
		var along := spacing * k if bays > 1 and k > 0 else spacing * 0.5
		var at := Vector3(a.x, 0, a.y) + dir * along
		var ground := data.height_at(at.x, at.z)
		var height := minf(top - ground - 0.4, FLOOR_M * (2.0 if old else 1.4) + 0.8)
		if height > 2.0:
			_bougainvillea(face, at + normal * 0.28, ground, height, seed_value)
			stats["facade_props"] += 1


func _pots(face: Basis, center: Vector3, width: float, seed_value: int) -> void:
	_add("Pot", _box(face, Vector3(width, 0.22, 0.24), center), Color("b5603a"))
	var count := maxi(2, int(width / 0.3))
	for k in range(count):
		var h := Geo.hash01(seed_value, 500 + k)
		var offset := face.x * ((float(k) + 0.5) / count - 0.5) * width
		var leaf := h < 0.45
		var color := Color(LEAVES[k % LEAVES.size()]) if leaf else Color(FLOWERS[int(h * 97.0) % FLOWERS.size()])
		_add("Foliage", _box(face, Vector3(0.34, 0.3 + h * 0.12, 0.28), center + offset + Vector3(0, 0.22, 0)), color)


func _bougainvillea(face: Basis, at: Vector3, ground: float, height: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 3 + 11
	for k in range(rng.randi_range(10, 16)):
		var t := sqrt(rng.randf())
		var r := rng.randf_range(0.35, 0.75)
		var spread := rng.randf_range(-1.0, 1.0) * (0.5 + t * 1.1)
		var color := Color(LEAVES[k % LEAVES.size()]) if rng.randf() < 0.25 else Color(BOUGAINVILLEA[rng.randi() % BOUGAINVILLEA.size()])
		var p := at + face.x * spread + face.z * rng.randf_range(0.0, 0.25) + Vector3(0, ground + 0.3 + t * height, 0)
		_add("Foliage", _box(face, Vector3(r * 1.7, r, r * 0.8), p), color)


# --- Streets ---------------------------------------------------------------------

## Groups of recycling containers at the kerb every ~90 m on car streets.
func _containers(data: SectorData, network: RoadNetwork, areas: Array, stats: Dictionary) -> Array:
	var shapes: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7412
	var placed: Array[Vector3] = []
	for road in network.roads:
		if not road["driveable"] or str(road["class"]) == "living_street":
			continue
		var points: PackedVector3Array = road["points"]
		var half := float(road["width"]) * 0.5
		var carry := rng.randf_range(20.0, 60.0)
		for i in range(points.size() - 1):
			var a := points[i]
			var b := points[i + 1]
			var length := Vector2(b.x - a.x, b.z - a.z).length()
			if length < 0.01:
				continue
			var dir := Vector3(b.x - a.x, 0, b.z - a.z) / length
			var right := Vector3(-dir.z, 0, dir.x)
			var t := carry
			while t < length:
				var side := 1.0 if Geo.hash01(int(road["id"]), int(t * 10.0) + i) < 0.5 else -1.0
				var p := a.lerp(b, t / length) + right * side * (half + 1.05)
				var count := rng.randi_range(3, 4)
				var span := count * 1.6
				var ends := [p - dir * span * 0.5, p + dir * span * 0.5, p + right * side * 0.9]
				var ok := data.surface_at(p.x, p.z) in ["urban", "promenade", "park"]
				for e in ends:
					ok = ok and DressingBuilder._clear_of_driveable(e, network, 0.62) and not DressingBuilder._inside_building(e, areas)
				for other in placed:
					ok = ok and other.distance_to(p) > 45.0
				if ok:
					placed.append(p)
					var basis := Basis(dir, Vector3.UP, dir.cross(Vector3.UP))
					var ground := data.height_at(p.x, p.z)
					var start := rng.randi_range(0, CONTAINERS.size() - 1)
					for k in range(count):
						var at := p + dir * ((k + 0.5) * 1.6 - span * 0.5)
						_add("Container", _box(basis, Vector3(1.45, 1.35, 1.2), Vector3(at.x, ground + 0.68, at.z)), Color(CONTAINERS[(start + k) % CONTAINERS.size()]))
					shapes.append([Transform3D(basis, Vector3(p.x, ground + 0.68, p.z)), Vector3(span, 1.35, 1.25)])
					stats["containers"] += count
				t += rng.randf_range(80.0, 110.0)
			carry = t - length
	return shapes


## Zebra crossings on every arm of a junction of asphalt streets.
func _crossings(data: SectorData, network: RoadNetwork, stats: Dictionary) -> void:
	var neighbours: Dictionary = {}
	for from in network.edges:
		for to in network.edges[from]:
			if not neighbours.has(from):
				neighbours[from] = {}
			if not neighbours.has(to):
				neighbours[to] = {}
			neighbours[from][to] = true
			neighbours[to][from] = true
	for node in neighbours:
		var arms: Dictionary = neighbours[node]
		if arms.size() < 3:
			continue
		var center: Vector3 = network.nodes[int(node)]
		for other_index in arms:
			var other: Vector3 = network.nodes[int(other_index)]
			var flat := Vector2(other.x - center.x, other.z - center.z)
			if flat.length() < 18.0:
				continue
			var hit := network.nearest(center.lerp(other, 0.5), true, 1)
			if hit.is_empty():
				continue
			var road: Dictionary = hit["road"]
			var width := float(road["width"])
			if str(road["class"]) == "living_street" or width < 5.0:
				continue
			var dir := Vector3(flat.x, 0, flat.y).normalized()
			var right := Vector3(-dir.z, 0, dir.x)
			var mid := center + dir * (maxf(width, 7.0) * 0.5 + 3.2)
			var h0 := data.height_at(mid.x - dir.x * 1.3, mid.z - dir.z * 1.3)
			var h1 := data.height_at(mid.x + dir.x * 1.3, mid.z + dir.z * 1.3)
			var along := (dir * 2.6 + Vector3(0, h1 - h0, 0)).normalized()
			var across := Vector3.UP.cross(along).normalized()
			var basis := Basis(across, along.cross(across).normalized(), along)
			var offset := -width * 0.5 + 0.7
			while offset < width * 0.5 - 0.5:
				var p := mid + right * offset
				var y := data.height_at(p.x, p.z) + RoadBuilder.LIFT_DRIVE + 0.025
				_add("Zebra", _box(basis, Vector3(0.5, 0.02, 2.6), Vector3(p.x, y, p.z)), Color("f1eee6"))
				offset += 1.0
			stats["crossings"] += 1


# --- Beach -----------------------------------------------------------------------

## Rows of umbrellas with loungers, and towels, on the sand a few metres from the
## water. Some stretches stay empty; the chiringuitos keep a clear apron.
func _beach(data: SectorData, network: RoadNetwork, areas: Array, stats: Dictionary) -> void:
	var bounds: Array = data.raw["bounds"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7413
	var keep_clear: Array[Vector2] = [Vector2(36, 52)]
	for site in BeachBarsBuilder.SITES:
		keep_clear.append(Vector2(float(site[0]), float(site[1])))
	var x := float(bounds[0])
	while x < float(bounds[2]):
		var z := float(bounds[1])
		while z < float(bounds[3]):
			var px := x + rng.randf_range(-0.8, 0.8)
			var pz := z + rng.randf_range(-0.8, 0.8)
			z += 5.5
			if data.surface_at(px, pz) != "beach":
				continue
			if Geo.hash01(floori(px / 55.0), 88) < 0.3:
				continue
			var seaward := _seaward(data, px, pz)
			if seaward == Vector3.ZERO:
				continue
			var near_bar := false
			for site in keep_clear:
				near_bar = near_bar or site.distance_to(Vector2(px, pz)) < 11.0
			var at := Vector3(px, data.height_at(px, pz), pz)
			if near_bar or not DressingBuilder._clear_of_driveable(at, network, 2.0) or DressingBuilder._inside_building(at, areas):
				continue
			var roll := rng.randf()
			if roll < 0.28:
				continue
			var yaw := atan2(seaward.x, seaward.z)
			var basis := Basis(Vector3.UP, yaw)
			if roll < 0.8:
				_umbrella(at, basis, rng)
				stats["umbrellas"] += 1
			else:
				for k in range(rng.randi_range(1, 2)):
					var offset := basis.x * (k * 1.1 - 0.5)
					_add("Towel", _box(basis, Vector3(0.9, 0.015, 1.8), at + offset + Vector3(0, 0.02, 0)), Color(TOWELS[rng.randi() % TOWELS.size()]))
		x += 4.5


## Direction to the nearest sea within 6–30 m, or zero if too close or too far.
static func _seaward(data: SectorData, x: float, z: float) -> Vector3:
	for radius in [3.0, 6.0, 12.0, 18.0, 24.0, 30.0]:
		for k in range(8):
			var angle := k * TAU / 8.0
			var dir := Vector3(cos(angle), 0, sin(angle))
			if data.surface_at(x + dir.x * radius, z + dir.z * radius) == "sea":
				return Vector3.ZERO if radius < 6.0 else dir
	return Vector3.ZERO


func _umbrella(at: Vector3, basis: Basis, rng: RandomNumberGenerator) -> void:
	var tilt := Basis(basis.x, rng.randf_range(-0.08, 0.08)) * basis
	_add("UmbrellaPole", _box(tilt, Vector3(0.05, 2.3, 0.05), at + Vector3(0, 1.15, 0)), Color("d9d6cc"))
	_add("UmbrellaCanopy", _box(tilt, Vector3(1.15, 0.42, 1.15), at + tilt.y * 2.12 + Vector3(0, 0.04, 0)), Color(CANOPIES[rng.randi() % CANOPIES.size()]))
	var lounger_color := Color("f3f1ea") if rng.randf() < 0.6 else Color("2e6f9e")
	for side: float in [-1.0, 1.0]:
		if rng.randf() < 0.2:
			continue
		var p := at + basis.x * side * 0.75 + basis.z * 0.3
		_add("Lounger", _box(basis, Vector3(0.62, 0.1, 1.85), p + Vector3(0, 0.32, 0)), lounger_color)
		var back := Basis(basis.x, deg_to_rad(50.0)) * basis
		_add("Lounger", _box(back, Vector3(0.62, 0.08, 0.65), p - basis.z * 0.8 + Vector3(0, 0.55, 0)), lounger_color)


func _emit(parent: Node3D, kind: String, chunk: Vector2i, list: Array) -> void:
	var spec: Array = _kinds[kind]
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.use_custom_data = kind == "Awning"
	multi.mesh = spec[0]
	multi.instance_count = list.size()
	for i in range(list.size()):
		multi.set_instance_transform(i, list[i][0])
		multi.set_instance_color(i, list[i][1])
		if multi.use_custom_data:
			multi.set_instance_custom_data(i, list[i][2])
	var instance := MultiMeshInstance3D.new()
	instance.name = "Life_%s_%s_%s" % [kind, chunk.x, chunk.y]
	instance.multimesh = multi
	instance.material_override = spec[1]
	instance.visibility_range_end = spec[2]
	instance.visibility_range_end_margin = 20.0
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if spec[3] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
