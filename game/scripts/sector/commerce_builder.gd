class_name CommerceBuilder
extends RefCounted

## Street-level businesses on surveyed building edges. Open terraces are kept
## clear of the carriageway; all placements are deterministic by OSM id.

const SHOPS := [
	[1427155245, "LA MAR DE SAL", "bar"],
	[448349662, "BAR LA CALETA", "bar"],
	[1056656678, "CASA DEL PUERTO", "restaurant"],
	[1056656686, "CAFÉ DEL ALTILLO", "bar"],
	[1388941224, "LA BAHÍA", "restaurant"],
	[467627875, "BRISA Y LIMÓN", "bar"],
	[467627870, "EL FARO", "restaurant"],
	[1388942450, "PESCADORES", "bar"],
	[1154823706, "LA PALMERA", "restaurant"],
	[1388940273, "CAFÉ DE LA PLAYA", "bar"],
	[1388940275, "ALMUÑÉCAR TAPAS", "bar"],
	[1388943443, "ESTANCO DEL PASEO", "estanco"],
]
static var chair_mesh: ArrayMesh


static func build(parent: Node3D, data: SectorData, network: RoadNetwork, mats: SectorMaterials) -> Dictionary:
	var physical_fronts: Dictionary = preload("res://scripts/venue_catalog.gd").fronts()
	physical_fronts.merge(preload("res://scripts/apartment_catalog.gd").fronts())
	var by_id := {}
	for building in data.raw["buildings"]:
		by_id[int(building["id"])] = building
	var areas := DressingBuilder._building_areas(data)
	var count := 0
	var terraces := 0
	for shop in SHOPS:
		var id: int = shop[0]
		if not by_id.has(id) or physical_fronts.has(id):
			continue
		var building: Dictionary = by_id[id]
		var fp: Array = building["footprint"]
		var best_edge := -1
		var best_length := 0.0
		for i in range(fp.size()):
			if int(building["street_edges"][i]) == 0:
				continue
			var a := Vector2(float(fp[i][0]), float(fp[i][1]))
			var b := Vector2(float(fp[(i + 1) % fp.size()][0]), float(fp[(i + 1) % fp.size()][1]))
			var length := a.distance_to(b)
			if length > best_length:
				best_length = length
				best_edge = i
		if best_edge < 0 or best_length < 4.0:
			continue
		var a := Vector2(float(fp[best_edge][0]), float(fp[best_edge][1]))
		var b := Vector2(float(fp[(best_edge + 1) % fp.size()][0]), float(fp[(best_edge + 1) % fp.size()][1]))
		var mid := (a + b) * 0.5
		var edge := (b - a).normalized()
		var normal := Vector3(edge.y, 0, -edge.x)
		var base := Vector3(mid.x, data.height_at(mid.x, mid.y), mid.y)
		var yaw := atan2(normal.x, normal.z)
		var business := Node3D.new()
		business.name = "Commerce_%s" % id
		parent.add_child(business)
		var color := Color("246a73") if shop[2] == "bar" else Color("a35338") if shop[2] == "restaurant" else Color("694d44")
		var panel := mats.plain("commerce_panel_%s" % id, color, 0.72)
		var shade := mats.plain("commerce_shade_%s" % id, color.lightened(0.33), 0.92)
		var wood := mats.textured("commerce_wood", "roofingtiles006", Color("ab8a64"), 1.1)
		var width := minf(7.2, best_length - 0.35)
		_box(business, "SignPanel", base + Vector3.UP * 2.95 + normal * 0.16, Vector3(width, 0.72, 0.15), yaw, panel)
		var sign := Label3D.new()
		sign.name = "BusinessName"
		sign.text = str(shop[1])
		sign.font_size = 64
		sign.pixel_size = 0.005
		sign.outline_size = 7
		sign.modulate = Color("fff3df")
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.position = base + Vector3.UP * 2.96 + normal * 0.29
		business.add_child(sign)
		_box(business, "Awning", base + Vector3.UP * 2.47 + normal * 0.92, Vector3(width - 0.25, 0.12, 1.8), yaw, shade)
		count += 1
		if shop[2] == "estanco":
			continue
		for side in [-1.0, 1.0]:
			var spot: Vector3 = base + Vector3(edge.x, 0, edge.y) * side * minf(2.0, width * 0.27) + normal * 3.0
			spot.y = data.height_at(spot.x, spot.z)
			if not DressingBuilder._clear_of_driveable(spot, network, 1.25) or DressingBuilder._inside_building(spot, areas):
				continue
			_box(business, "TerraceTable", spot + Vector3.UP * 0.76, Vector3(0.9, 0.09, 0.9), yaw, wood)
			_box(business, "TableLeg", spot + Vector3.UP * 0.37, Vector3(0.1, 0.7, 0.1), yaw, wood)
			for chair_side in [-1.0, 1.0]:
				var chair_at: Vector3 = spot + Vector3(edge.x, 0, edge.y) * chair_side * 0.88
				_box(business, "Chair", chair_at + Vector3.UP * 0.46, Vector3(0.46, 0.13, 0.46), yaw, wood)
			terraces += 1
	return {"businesses": count, "terrace_tables": terraces}


static func _box(parent: Node3D, label: String, at: Vector3, size: Vector3, yaw: float, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	if label == "Chair":
		if chair_mesh == null:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.append_from(mesh, 0, Transform3D.IDENTITY)
			for x in [-0.19, 0.19]:
				for z in [-0.19, 0.19]:
					var leg := BoxMesh.new()
					leg.size = Vector3(0.055, 0.4, 0.055)
					st.append_from(leg, 0, Transform3D(Basis.IDENTITY, Vector3(x, -0.26, z)))
			var back := BoxMesh.new()
			back.size = Vector3(0.46, 0.5, 0.06)
			st.append_from(back, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0.2)))
			chair_mesh = st.commit()
		instance.mesh = chair_mesh
	instance.material_override = material
	instance.position = at
	instance.rotation.y = yaw
	if label == "Chair" and parent.get_tree().get_nodes_in_group("interactive_props").size() < 32:
		var body := InteractiveProp.new()
		body.name = "MovableChair"
		body.position = at
		body.rotation.y = yaw
		parent.add_child(body)
		instance.position = Vector3.ZERO
		instance.rotation = Vector3.ZERO
		body.add_child(instance)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(size.x, 1.05, size.z)
		collision.shape = shape
		collision.position.y = 0.065
		body.add_child(collision)
	elif label in ["Chair", "TerraceTable"]:
		parent.add_child(instance)
		var body := StaticBody3D.new()
		body.position = at
		body.rotation.y = yaw
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(size.x, 1.05 if label == "Chair" else 0.8, size.z)
		collision.shape = shape
		collision.position.y = 0.065 if label == "Chair" else -0.35
		body.add_child(collision)
		parent.add_child(body)
	else:
		parent.add_child(instance)
