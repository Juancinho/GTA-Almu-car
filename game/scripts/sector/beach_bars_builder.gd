class_name BeachBarsBuilder
extends RefCounted

## Five open beach cafés on checked land positions, complementing Jaime Playa.
## Each is a walk-in structure with a counter and shaded seating, not a façade.

const SITES := [
	[-90.0, 110.0, "CHIRINGUITO ARENAS", "5796a4"],
	[110.0, 78.0, "EL ESPETO", "ad7652"],
	[170.0, 90.0, "SAL Y SOL", "6c9c85"],
	[250.0, 130.0, "LA ORILLA", "b88967"],
	[330.0, 110.0, "BRISA MARINA", "6a85a1"],
]


static func build(parent: Node3D, data: SectorData, network: RoadNetwork, mats: SectorMaterials) -> Dictionary:
	var cream := mats.textured("beach_bar_render", "plaster003", Color("eee3ca"), 2.0)
	var deck := mats.textured("beach_bar_deck", "pavingstones046", Color("d9c29a"), 1.8)
	var wood := mats.textured("beach_bar_wood", "roofingtiles006", Color("947251"), 1.1)
	var linen := mats.plain("beach_bar_linen", Color("f1e8d4"), 0.94)
	var count := 0
	var bars: Array[Node3D] = []
	var services: Array[BeachBarService] = []
	var building_areas := DressingBuilder._building_areas(data)
	for index in range(SITES.size()):
		var spec: Array = SITES[index]
		var x := float(spec[0])
		var z := float(spec[1])
		var center := Vector3(x, data.height_at(x, z), z)
		if not _site_clear(center, data, network, building_areas):
			continue
		var bar := Node3D.new()
		bar.name = "Chiringuito_%02d" % index
		parent.add_child(bar)
		bars.append(bar)
		var accent := mats.textured("beach_bar_accent_%d" % index, "tiles040", Color(str(spec[3])), 1.0, 0.65)
		_box(bar, data, "Terrace", Vector3(x, 0.08, z), Vector3(12.4, 0.22, 9.2), deck, true)
		_box(bar, data, "KitchenWall", Vector3(x, 1.45, z - 3.5), Vector3(11.0, 2.9, 0.22), cream, true)
		_box(bar, data, "Counter", Vector3(x, 0.63, z - 0.8), Vector3(8.0, 1.15, 0.9), accent, true)
		_box(bar, data, "CounterTop", Vector3(x, 1.26, z - 0.8), Vector3(8.2, 0.12, 1.1), wood)
		for side in [-1.0, 1.0]:
			for front in [-1.0, 1.0]:
				_box(bar, data, "PergolaPost", Vector3(x + side * 5.7, 1.75, z + front * 4.0), Vector3(0.18, 3.5, 0.18), wood, true)
		for stripe in range(8):
			_box(bar, data, "ShadeStripe", Vector3(x - 5.25 + stripe * 1.5, 3.57, z), Vector3(1.52, 0.12, 8.6), linen if stripe % 2 == 0 else accent)
		for table_x in [-3.3, 0.0, 3.3]:
			_box(bar, data, "TableTop", Vector3(x + table_x, 0.73, z + 2.35), Vector3(0.95, 0.1, 0.95), wood)
			_box(bar, data, "TableLeg", Vector3(x + table_x, 0.37, z + 2.35), Vector3(0.1, 0.7, 0.1), wood)
			for chair_side in [-1.0, 1.0]:
				_box(bar, data, "Chair", Vector3(x + table_x + chair_side * 0.88, 0.45, z + 2.35), Vector3(0.48, 0.13, 0.5), wood)
		var staff := HumanModel.new("female_casual" if index % 2 == 0 else "male_casual")
		staff.name = "BeachBarStaff"
		staff.position = Vector3(x + 3.0, data.height_at(x + 3.0, z - 2.2), z - 2.2)
		bar.add_child(staff)
		var service := BeachBarService.new()
		service.name = "BeachBarService"
		service.bar_name = str(spec[2])
		service.position = Vector3(x, data.height_at(x, z + 0.65) + 0.2, z + 0.65)
		bar.add_child(service)
		services.append(service)
		var menu := Label3D.new()
		menu.name = "Menu"
		menu.text = "MENÚ 35 €  ·  E"
		menu.font_size = 43
		menu.pixel_size = 0.0055
		menu.outline_size = 7
		menu.position = Vector3(x, data.height_at(x, z - 0.8) + 1.95, z - 0.18)
		bar.add_child(menu)
		var letters := Label3D.new()
		letters.name = "BeachBarName"
		letters.text = str(spec[2])
		letters.font_size = 67
		letters.pixel_size = 0.005
		letters.outline_size = 11
		letters.outline_modulate = Color("344654")
		letters.modulate = Color("fff4dc")
		letters.position = Vector3(x, data.height_at(x, z + 4.5) + 3.18, z + 4.5)
		bar.add_child(letters)
		count += 1
	var batches := 0
	for bar in bars:
		batches += _batch_visuals(parent, [bar])
	return {"beach_bars": count, "beach_bar_batches": batches, "services": services}


static func _site_clear(center: Vector3, data: SectorData, network: RoadNetwork, building_areas: Array) -> bool:
	for dx in [-6.2, 0.0, 6.2]:
		for dz in [-4.6, 0.0, 4.6]:
			var at := center + Vector3(dx, 0, dz)
			if data.surface_at(at.x, at.z) != "beach":
				return false
			if not DressingBuilder._clear_of_driveable(at, network, 1.0) or DressingBuilder._inside_building(at, building_areas):
				return false
	return true


static func _batch_visuals(parent: Node3D, bars: Array[Node3D]) -> int:
	var groups := {}
	var visuals: Array[MeshInstance3D] = []
	for bar in bars:
		for child in bar.get_children():
			if child is not MeshInstance3D:
				continue
			var visual := child as MeshInstance3D
			var box := visual.mesh as BoxMesh
			if box == null:
				continue
			var material := visual.material_override as Material
			var key := "%s|%s" % [box.size, material.get_instance_id()]
			if not groups.has(key):
				groups[key] = {"mesh": box, "material": material, "transforms": []}
			(groups[key]["transforms"] as Array).append(visual.global_transform)
			visuals.append(visual)
	for visual in visuals:
		visual.get_parent().remove_child(visual)
		visual.free()
	var index := 0
	for group in groups.values():
		var transforms: Array = group["transforms"]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = group["mesh"]
		multi.instance_count = transforms.size()
		for i in range(transforms.size()):
			multi.set_instance_transform(i, transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = "BeachBarBatch_%d" % index
		instance.multimesh = multi
		instance.material_override = group["material"]
		instance.visibility_range_end = 300.0
		parent.add_child(instance)
		index += 1
	return index


static func _box(parent: Node3D, data: SectorData, label: String, at: Vector3, size: Vector3, material: Material, solid: bool = false) -> void:
	var center := Vector3(at.x, data.height_at(at.x, at.z) + at.y, at.z)
	var visual := MeshInstance3D.new()
	visual.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material
	visual.position = center
	parent.add_child(visual)
	if solid:
		var body := StaticBody3D.new()
		body.name = label + "Collision"
		body.position = center
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		body.add_child(collider)
		parent.add_child(body)
