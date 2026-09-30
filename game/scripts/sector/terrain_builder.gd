class_name TerrainBuilder
extends RefCounted

## Heightmap terrain: one indexed mesh with a surface per ground class (sea bed, dark
## gravel beach, urban paving, park, natural hillside, promenade tiles), a
## HeightMapShape3D collider and a large sea plane.


static func build(parent: Node3D, data: SectorData, mats: SectorMaterials) -> void:
	var materials := [
		mats.textured("seabed", "ground080", Color("4a5a5e"), 5.0),
		mats.textured("beach", "ground080", Color("6e6c69"), 2.5, 0.97),
		mats.textured("urban_ground", "pavingstones046", Color("ece5d6"), 2.2),
		mats.textured("park_ground", "ground037", Color("c6cf9e"), 5.0),
		mats.textured("natural_ground", "ground037", Color("c9c08f"), 9.0),
		mats.textured("promenade", "tiles040", Color("eadcc2"), 2.6, 0.8),
	]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.resize(data.cols * data.rows)
	normals.resize(data.cols * data.rows)
	for iz in range(data.rows):
		for ix in range(data.cols):
			var i := iz * data.cols + ix
			var h := data.heights[i]
			vertices[i] = Vector3(data.x0 + ix * data.cell, h, data.z0 + iz * data.cell)
			var hl := data.heights[iz * data.cols + maxi(ix - 1, 0)]
			var hr := data.heights[iz * data.cols + mini(ix + 1, data.cols - 1)]
			var hu := data.heights[maxi(iz - 1, 0) * data.cols + ix]
			var hd := data.heights[mini(iz + 1, data.rows - 1) * data.cols + ix]
			normals[i] = Vector3(hl - hr, 2.0 * data.cell, hu - hd).normalized()
	var indices: Array = []  # plain Arrays are shared references (Packed arrays would copy)
	for s in range(materials.size()):
		indices.append([])
	for iz in range(data.rows - 1):
		for ix in range(data.cols - 1):
			var i := iz * data.cols + ix
			# clockwise seen from above (Godot front face): v00, v10, v01 / v10, v11, v01
			(indices[data.surface[i]] as Array).append_array([i, i + 1, i + data.cols, i + 1, i + data.cols + 1, i + data.cols])
	var mesh := ArrayMesh.new()
	for s in range(materials.size()):
		if (indices[s] as Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(indices[s])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[s])
	var visual := MeshInstance3D.new()
	visual.name = "TerrainMesh"
	visual.mesh = mesh
	parent.add_child(visual)
	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.add_to_group("terrain")
	body.position = Vector3(data.x0 + (data.cols - 1) * data.cell * 0.5, 0.0, data.z0 + (data.rows - 1) * data.cell * 0.5)
	parent.add_child(body)
	var collider := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = data.cols
	shape.map_depth = data.rows
	shape.map_data = data.heights
	collider.shape = shape
	collider.scale = Vector3(data.cell, 1.0, data.cell)
	body.add_child(collider)
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000, 6000)
	sea.mesh = plane
	sea.position = Vector3(0, 0.0, 1800)
	sea.material_override = mats.sea()
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(sea)
