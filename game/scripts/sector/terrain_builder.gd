class_name TerrainBuilder
extends RefCounted

## Heightmap terrain: one indexed mesh with a surface per ground class (sea bed, dark
## gravel beach, urban paving, park, natural hillside, promenade tiles), a
## HeightMapShape3D collider and a large sea plane.


static func build(parent: Node3D, data: SectorData, mats: SectorMaterials) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var weights_b := PackedVector2Array()
	var count := data.cols * data.rows
	vertices.resize(count)
	normals.resize(count)
	colors.resize(count)
	weights_b.resize(count)
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
			# Surface weights: the share of each class in the 3×3 neighbourhood,
			# so classes fade over ~8 m instead of stepping along the grid.
			var share := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var jx := clampi(ix + dx, 0, data.cols - 1)
					var jz := clampi(iz + dz, 0, data.rows - 1)
					var weight := 2.0 if dx == 0 and dz == 0 else 1.0
					share[data.surface[jz * data.cols + jx]] += weight
			# SURFACES: sea, beach, urban, park, natural, promenade
			colors[i] = Color(share[1] / 10.0, share[2] / 10.0, share[3] / 10.0, share[4] / 10.0)
			weights_b[i] = Vector2(share[5] / 10.0, share[0] / 10.0)
	# 32×32-cell tiles (128 m): the camera culls what it cannot see, and the flat
	# ground casts no shadows (it was the largest single cost of the frame).
	var material := _ground_material()
	var tile := 32
	for tz in range(0, data.rows - 1, tile):
		for tx in range(0, data.cols - 1, tile):
			var x1 := mini(tx + tile, data.cols - 1)
			var z1 := mini(tz + tile, data.rows - 1)
			var w := x1 - tx + 1
			var tv := PackedVector3Array()
			var tn := PackedVector3Array()
			var tc := PackedColorArray()
			var tw := PackedVector2Array()
			for iz in range(tz, z1 + 1):
				for ix in range(tx, x1 + 1):
					var i := iz * data.cols + ix
					tv.append(vertices[i])
					tn.append(normals[i])
					tc.append(colors[i])
					tw.append(weights_b[i])
			var indices := PackedInt32Array()
			for iz in range(z1 - tz):
				for ix in range(x1 - tx):
					var i := iz * w + ix
					# clockwise seen from above (Godot front face): v00, v10, v01 / v10, v11, v01
					indices.append_array([i, i + 1, i + w, i + 1, i + w + 1, i + w])
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = tv
			arrays[Mesh.ARRAY_NORMAL] = tn
			arrays[Mesh.ARRAY_COLOR] = tc
			arrays[Mesh.ARRAY_TEX_UV2] = tw
			arrays[Mesh.ARRAY_INDEX] = indices
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, material)
			var visual := MeshInstance3D.new()
			visual.name = "TerrainMesh_%d_%d" % [tx / tile, tz / tile]
			visual.mesh = mesh
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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


static func _ground_material() -> ShaderMaterial:
	var dir := SectorMaterials.TEXTURE_DIR
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain_blend.gdshader") as Shader
	for pair in [["gravel", "ground080"], ["paving", "pavingstones046"], ["grass", "ground037"], ["tiles", "tiles040"]]:
		mat.set_shader_parameter(pair[0] + "_albedo", load(dir + pair[1] + "_color.png") as Texture2D)
		mat.set_shader_parameter(pair[0] + "_normal", load(dir + pair[1] + "_normal.png") as Texture2D)
	return mat
