class_name BuildingBuilder
extends RefCounted

## Extrudes every OSM footprint with its zone rules (whitewashed old town, seafront
## apartment blocks, modern centre): plastered walls tinted per building with a
## coloured plinth, terrace roofs with parapets or terracotta hip roofs, and façade
## details (windows/shutters/rejas/doors/shops) as atlas quads plus 3D balconies.
## Meshes and colliders are merged per 160 m chunk.

const FLOOR_M := 3.1
const PLINTH_M := 0.9
const PARAPET_M := 0.8
const BAY_M := 3.3
const WHITES := ["f4f1ea", "efebe2", "f2eee6", "ebe6da", "f6f3ee"]
const SEAFRONT := ["f1ede4", "ece2cf", "e9d2ae", "efc9a6", "e4b894", "f4e3b8", "f3efe8", "dfe5e2", "f6f3ee", "e8c6a8"]
const MODERN := ["e9e1d0", "dfd2bb", "e8dccb", "d9c3a0", "cfae8c", "efe9dc", "e7cfa5", "d6dcd6", "ecd2b8", "c9b79a"]
const PLINTHS := ["c99a52", "3e6e9e", "8a8a86", "a65a3a", "4f6a4f", "6f5d4f"]
const CELL := {"shutter_green": 0, "shutter_blue": 1, "shutter_brown": 2, "reja": 3, "balcony_door": 4, "shop": 5,
	"door": 6, "modern": 7, "garage": 8, "shop_awning": 9, "small_reja": 10, "door_arched": 11,
	"modern_blind": 12, "balcony_shutters": 13, "railing": 14}
const VenueCatalog = preload("res://scripts/venue_catalog.gd")


static func build(parent: Node3D, data: SectorData, mats: SectorMaterials) -> Dictionary:
	var venue_fronts := VenueCatalog.fronts()
	var wall_mats := {
		"walls": mats.textured("building_plaster", "plaster003", Color.WHITE, 3.0, 0.92, true),
		"stone": mats.textured("building_stone", "rock020", Color("e1d8c6"), 2.2, 0.91, true),
		"ceramic": mats.textured("building_ceramic", "tiles040", Color("e9e4da"), 1.9, 0.87, true),
	}
	var terrace_mat := mats.textured("roof_terrace", "plaster003", Color("b9b5ad"), 3.0, 0.95)
	var tile_mat := mats.textured("roof_tiles", "roofingtiles006", Color("e8c4a8"), 2.4, 0.85)
	var slab_mat := mats.textured("balcony_slab", "plaster003", Color("f2efe8"), 2.0)
	var chunks: Dictionary = {}
	var details: Dictionary = {}  # chunk -> Array of [Transform3D, cell, glass_bias]
	var boxes: Dictionary = {"slab": [], "rail": []}
	var stats := {"buildings": 0, "details": 0}
	for b in data.raw["buildings"]:
		var fp: Array = b["footprint"]
		var pts: Array[Vector2] = []
		for p in fp:
			pts.append(Vector2(float(p[0]), float(p[1])))
		var cx := 0.0
		var cz := 0.0
		for p in pts:
			cx += p.x
			cz += p.y
		cx /= pts.size()
		cz /= pts.size()
		var key := Geo.chunk_key(cx, cz)
		if not chunks.has(key):
			chunks[key] = _new_chunk()
			details[key] = []
		var chunk: Dictionary = chunks[key]
		var base := float(b["base"])
		var top := base + float(b["height"])
		var zone := str(b["zone"])
		var id := int(b["id"])
		var wall_key := "walls"
		var finish := Geo.hash01(id, 217)
		if finish < (0.12 if zone == "old_town" or zone == "san_miguel" else 0.20):
			wall_key = "stone"
		elif finish > 0.84 and (zone == "seafront" or zone == "modern"):
			wall_key = "ceramic"
		var wall_color := Color(_pick(zone, int(b["tint"])))
		var plinth_color := Color(PLINTHS[int(b["plinth"]) % PLINTHS.size()])
		if zone == "modern" or zone == "seafront":
			plinth_color = wall_color.darkened(0.25)
		var tiled := str(b["roof"]) == "tile" and pts.size() <= 9 and Geometry2D.is_point_in_polygon(Vector2(cx, cz), PackedVector2Array(pts))
		var wall_top := top if tiled else top + PARAPET_M
		var street: Array = b["street_edges"]
		for i in range(pts.size()):
			var a := pts[i]
			var c := pts[(i + 1) % pts.size()]
			var edge := c - a
			var length := edge.length()
			if length < 0.05:
				continue
			var normal := Vector3(edge.y, 0, -edge.x) / length
			var a0 := Vector3(a.x, base, a.y)
			var c0 := Vector3(c.x, base, c.y)
			var venue_front := venue_fronts.has(id) and i == int(venue_fronts[id][0])
			var aperture_half := minf(length * 0.5 - 0.25, 7.0 * float(venue_fronts[id][1])) if venue_front else 0.0
			# A single ground height buries the uphill half of a long façade.
			# Sample the actual terrain along each wall and step the plinth with it.
			var segments := maxi(1, int(ceil(length / 2.0)))
			for segment in range(segments):
				var t0 := float(segment) / segments
				var t1 := float(segment + 1) / segments
				var cuts := [t0, t1]
				if venue_front:
					for cut in [0.5 - aperture_half / length, 0.5 + aperture_half / length]:
						if cut > t0 and cut < t1:
							cuts.append(cut)
					cuts.sort()
				for piece in range(cuts.size() - 1):
					var q0: float = cuts[piece]
					var q1: float = cuts[piece + 1]
					var p0 := a.lerp(c, q0)
					var p1 := a.lerp(c, q1)
					var open_ground := venue_front and absf((q0 + q1) * 0.5 - 0.5) < aperture_half / length
					var face_color := wall_color
					if (zone == "seafront" or zone == "modern") and float(b["area"]) > 450.0:
						# Large OSM polygons can cover several attached apartment blocks.
						# Subtle 24 m façade sections break the continuous colour band.
						var section := floori((p0.x + p1.x + p0.y + p1.y) / 48.0)
						face_color = wall_color.lightened(0.065) if posmod(section, 3) == 0 else wall_color.darkened(0.045) if posmod(section, 3) == 2 else wall_color
					var h0 := data.height_at(p0.x, p0.y) + PLINTH_M
					var h1 := data.height_at(p1.x, p1.y) + PLINTH_M
					var f0 := Vector3(p0.x, base, p0.y)
					var f1 := Vector3(p1.x, base, p1.y)
					var s0 := Vector3(p0.x, h0, p0.y)
					var s1 := Vector3(p1.x, h1, p1.y)
					if not open_ground:
						Geo.add_quad(chunk[wall_key], f0, f1, s1, s0, normal, plinth_color)
						Geo.add_quad(chunk[wall_key], s0, s1, Vector3(p1.x, wall_top, p1.y), Vector3(p0.x, wall_top, p0.y), normal, face_color)
						(chunk["faces"] as Array).append_array([f0, f1, Vector3(p1.x, wall_top, p1.y), f0, Vector3(p1.x, wall_top, p1.y), Vector3(p0.x, wall_top, p0.y)])
					else:
						var lintel_y := data.height_at((p0.x + p1.x) * 0.5, (p0.y + p1.y) * 0.5) + 4.5
						var high0 := Vector3(p0.x, lintel_y, p0.y)
						var high1 := Vector3(p1.x, lintel_y, p1.y)
						Geo.add_quad(chunk[wall_key], high0, high1, Vector3(p1.x, wall_top, p1.y), Vector3(p0.x, wall_top, p0.y), normal, face_color)
						(chunk["faces"] as Array).append_array([high0, high1, Vector3(p1.x, wall_top, p1.y), high0, Vector3(p1.x, wall_top, p1.y), Vector3(p0.x, wall_top, p0.y)])
			if not tiled:  # parapet inner face
				Geo.add_quad(chunk[wall_key], Vector3(a.x, top, a.y), Vector3(c.x, top, c.y), Vector3(c.x, wall_top, c.y), Vector3(a.x, wall_top, a.y), -normal, wall_color)
			if Geo.hash01(id, 121) < 0.48:
				var trim_color := wall_color.lightened(0.16)
				Geo.add_quad(chunk[wall_key], Vector3(a.x, top - 0.30, a.y) + normal * 0.05, Vector3(c.x, top - 0.30, c.y) + normal * 0.05, Vector3(c.x, top, c.y) + normal * 0.05, Vector3(a.x, top, a.y) + normal * 0.05, normal, trim_color)
			if not venue_front:
				stats["details"] += _facade(details[key], boxes, b, zone, a, c, normal, data, top, int(street[i]) == 1, id * 31 + i)
		_roof(chunk, pts, top, tiled, Vector2(cx, cz))
		stats["buildings"] += 1
	for key in chunks:
		var chunk: Dictionary = chunks[key]
		for finish_name in wall_mats:
			_emit(parent, "Buildings_%s_%s_%s" % [key.x, key.y, finish_name], chunk[finish_name], wall_mats[finish_name])
		_emit(parent, "Terraces_%s_%s" % [key.x, key.y], chunk["terrace"], terrace_mat)
		_emit(parent, "TileRoofs_%s_%s" % [key.x, key.y], chunk["tiles"], tile_mat)
		var body := StaticBody3D.new()
		body.name = "BuildingCollision_%s_%s" % [key.x, key.y]
		parent.add_child(body)
		var collider := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true  # nothing may slip inside a façade shell
		shape.set_faces(PackedVector3Array(chunk["faces"]))
		collider.shape = shape
		body.add_child(collider)
		_emit_details(parent, "Facade_%s_%s" % [key.x, key.y], details[key], mats.facade_detail())
	_emit_boxes(parent, "BalconySlabs", boxes["slab"], slab_mat)
	return stats


static func _new_chunk() -> Dictionary:
	var chunk := {"faces": []}  # plain Array: shared reference while filling
	for name in ["walls", "stone", "ceramic", "terrace", "tiles"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		chunk[name] = st
	return chunk


static func _pick(zone: String, seed_value: int) -> String:
	var palette: Array = WHITES
	if zone == "seafront":
		palette = SEAFRONT
	elif zone == "modern":
		palette = MODERN
	elif seed_value % 6 == 0:  # the odd ochre, cream or almagra-washed house in the old town
		palette = ["e8d3a8", "efe0bf", "e6c9a1", "f0cfb0", "e9bf8f", "f3e3a8"]
	return palette[seed_value % palette.size()]


static func _roof(chunk: Dictionary, pts: Array[Vector2], top: float, tiled: bool, center: Vector2) -> void:
	if tiled:
		var span := 1e9
		for p in pts:
			span = minf(span, p.distance_to(center))
		var apex := Vector3(center.x, top + clampf(span * 0.45, 0.8, 2.6), center.y)
		for i in range(pts.size()):
			var a := Vector3(pts[i].x, top, pts[i].y)
			var c := Vector3(pts[(i + 1) % pts.size()].x, top, pts[(i + 1) % pts.size()].y)
			var normal := (c - a).cross(apex - a).normalized()
			if normal.y < 0.0:
				normal = -normal
			Geo.add_tri(chunk["tiles"], a, c, apex, normal)
		return
	var polygon := PackedVector2Array(pts)
	var tris := Geometry2D.triangulate_polygon(polygon)
	for i in range(0, tris.size(), 3):
		var p0 := Vector3(polygon[tris[i]].x, top, polygon[tris[i]].y)
		var p1 := Vector3(polygon[tris[i + 1]].x, top, polygon[tris[i + 1]].y)
		var p2 := Vector3(polygon[tris[i + 2]].x, top, polygon[tris[i + 2]].y)
		Geo.add_tri(chunk["terrace"], p0, p1, p2, Vector3.UP)


## Places façade detail quads for one wall edge; returns how many were placed.
static func _facade(list: Array, boxes: Dictionary, b: Dictionary, zone: String, a: Vector2, c: Vector2, normal: Vector3, data: SectorData, top: float, street: bool, seed_value: int) -> int:
	var length := a.distance_to(c)
	if length < 2.4:
		return 0
	var bay_width := 2.7 + Geo.hash01(seed_value, 301) * 1.35
	var bays := maxi(1, int(length / bay_width))
	var spacing := length / bays
	var dir := Vector3(c.x - a.x, 0, c.y - a.y) / length
	var basis := Basis(Vector3.UP.cross(normal), Vector3.UP, normal)
	var levels := int(b["levels"])
	var old := zone == "old_town" or zone == "san_miguel"
	var shutter_cell: int = [CELL["shutter_green"], CELL["shutter_blue"], CELL["shutter_brown"], CELL["shutter_green"]][int(b["tint"]) % 4]
	var door_bay := int(Geo.hash01(seed_value, 5) * bays)
	var placed := 0
	var landmark := str(b.get("landmark", ""))
	for bay in range(bays):
		var along := spacing * (bay + 0.5)
		var base_point := Vector3(a.x, 0, a.y) + dir * along + normal * 0.03
		var ground := data.height_at(base_point.x, base_point.z)
		for floor_index in range(levels):
			var y := ground + floor_index * FLOOR_M
			if y + 2.4 > top:
				break
			var cell := -1
			var size := Vector2(1.5, 1.9)
			var center_y := y + 1.55
			var r := Geo.hash01(seed_value * 13 + bay, floor_index)
			if landmark == "church":
				if floor_index == 0 and street and bay == door_bay:
					cell = CELL["door_arched"]
					size = Vector2(2.4, 3.4)
					center_y = y + 1.7
				elif floor_index == 2 and r < 0.5:
					cell = CELL["small_reja"]
			elif floor_index == 0 and street:
				if bay == door_bay:
					cell = CELL["door_arched"] if old and r < 0.3 else CELL["door"]
					size = Vector2(1.5, 2.5)
					center_y = y + 1.25
				elif not old or r < 0.35:
					cell = CELL["shop_awning"] if r < 0.45 else CELL["shop"]
					size = Vector2(minf(spacing - 0.4, 3.0), 2.7)
					center_y = y + 1.4
				else:
					cell = CELL["reja"]
			elif floor_index == 0:
				cell = CELL["small_reja"] if old else CELL["modern_blind"]
				if r < 0.3:
					cell = -1
			else:
				if old:
					cell = shutter_cell if r < 0.7 else CELL["balcony_shutters"]
					if cell == CELL["balcony_shutters"]:
						size = Vector2(1.5, 2.4)
						center_y = y + 1.25
						_balcony(list, boxes, base_point, dir, normal, y + 0.05, 1.7, 0.55)
				elif zone == "seafront":
					cell = CELL["balcony_door"] if r < 0.6 else CELL["modern_blind"]
					size = Vector2(1.6, 2.4)
					center_y = y + 1.25
				else:
					cell = CELL["modern"] if r < 0.55 else CELL["modern_blind"]
			if cell < 0:
				continue
			var t := Transform3D(_scaled(basis, Vector3(size.x, size.y, 1.0)), base_point + Vector3(0, center_y, 0))
			list.append([t, cell, Geo.hash01(seed_value, bay * 7 + floor_index)])
			placed += 1
	if zone == "seafront" and street and levels > 2 and Geo.hash01(seed_value, 304) < 0.68:
		# Individual bays follow the street grade; a single long balcony crosses
		# the hillside and its uphill railing disappears into the terrain.
		for bay in range(bays):
			var at := Vector3(a.x, 0, a.y) + dir * (spacing * (bay + 0.5))
			var ground := data.height_at(at.x, at.z)
			for floor_index in range(1, levels):
				var y := ground + floor_index * FLOOR_M
				if y + 1.0 > top:
					break
				_balcony(list, boxes, at, dir, normal, y + 0.05, spacing - 0.15, 0.75 + Geo.hash01(seed_value, 305) * 0.45)
	return placed


static func _balcony(list: Array, boxes: Dictionary, at: Vector3, dir: Vector3, normal: Vector3, y: float, width: float, depth: float) -> void:
	var basis := Basis(dir, Vector3.UP, dir.cross(Vector3.UP))
	var slab_center := Vector3(at.x, y, at.z) + normal * (depth * 0.5)
	(boxes["slab"] as Array).append(Transform3D(_scaled(basis, Vector3(width, 0.16, depth)), slab_center))
	# Wrought-iron railing: atlas quads (transparent between bars) in ~2 m panels.
	var panels := maxi(1, int(round(width / 2.0)))
	var panel := width / panels
	var face := Basis(Vector3.UP.cross(normal), Vector3.UP, normal)
	for k in range(panels):
		var offset := -width * 0.5 + panel * (k + 0.5)
		var center := Vector3(at.x, y + 0.6, at.z) + dir * offset + normal * depth
		list.append([Transform3D(_scaled(face, Vector3(panel, 1.05, 1.0)), center), CELL["railing"], 0.0])
	for side: float in [-1.0, 1.0]:  # short side panels
		var side_center := Vector3(at.x, y + 0.6, at.z) + dir * (width * 0.5 * side) + normal * (depth * 0.5)
		var side_normal := dir * side
		list.append([Transform3D(_scaled(Basis(Vector3.UP.cross(side_normal), Vector3.UP, side_normal), Vector3(depth, 1.05, 1.0)), side_center), CELL["railing"], 0.0])


## Scale along the basis' own axes (column-wise).
static func _scaled(basis: Basis, scale: Vector3) -> Basis:
	return Basis(basis.x * scale.x, basis.y * scale.y, basis.z * scale.z)


static func _emit(parent: Node3D, label: String, st: SurfaceTool, material: Material) -> void:
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)


static func _emit_details(parent: Node3D, label: String, list: Array, material: Material) -> void:
	if list.is_empty():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = quad
	multi.instance_count = list.size()
	for i in range(list.size()):
		multi.set_instance_transform(i, list[i][0])
		multi.set_instance_custom_data(i, Color(float(list[i][1]) / 16.0, float(list[i][2]), 0, 0))
	var instance := MultiMeshInstance3D.new()
	instance.name = label
	instance.multimesh = multi
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = 420.0
	parent.add_child(instance)


static func _emit_boxes(parent: Node3D, label: String, transforms: Array, material: Material) -> void:
	if transforms.is_empty():
		return
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = box
	multi.instance_count = transforms.size()
	for i in range(transforms.size()):
		multi.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = label
	instance.multimesh = multi
	instance.material_override = material
	parent.add_child(instance)
