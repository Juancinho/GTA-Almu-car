extends Node3D

## The Compatibility renderer compiles each material/mesh-format/light combination
## the first time it is drawn: walking into a shop, the first night lamp, the first
## police car or a venue room becoming visible each froze the game for a moment
## ("tirones"). During loading this node draws one tiny copy of every material in
## the world, in every mesh format it is used with (plain, MultiMesh, skinned),
## lit by an omni and a spot light and casting shadows, right in front of the
## camera for a few frames, then frees itself.

const FRAMES := 4

var _frames_left := FRAMES


static func attach(camera: Camera3D, world: Node, extra_scenes: Array) -> Node3D:
	var warmup: Node3D = (load("res://scripts/shader_warmup.gd") as GDScript).new()
	warmup.name = "ShaderWarmup"
	camera.add_child(warmup)
	warmup.position = Vector3(0, 0, -2.0)
	warmup.call("_build", world, extra_scenes)
	return warmup


func _build(world: Node, extra_scenes: Array) -> void:
	var seen := {}
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.02)
	var index := 0
	for node in world.find_children("*", "GeometryInstance3D", true, false):
		if node is MultiMeshInstance3D:
			var source := (node as MultiMeshInstance3D).multimesh
			if source == null or source.mesh == null:
				continue
			var key := "mm:%d:%d:%s:%s:%d" % [source.mesh.get_rid().get_id(), _material_id(node as GeometryInstance3D), source.use_colors, source.use_custom_data, source.transform_format]
			if seen.has(key):
				continue
			seen[key] = true
			var multi := MultiMesh.new()
			multi.transform_format = source.transform_format
			multi.use_colors = source.use_colors
			multi.use_custom_data = source.use_custom_data
			multi.mesh = source.mesh
			multi.instance_count = 1
			multi.set_instance_transform(0, Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3.ZERO))
			var copy := MultiMeshInstance3D.new()
			copy.multimesh = multi
			copy.material_override = (node as GeometryInstance3D).material_override
			_place(copy, index)
			index += 1
		elif node is MeshInstance3D:
			var mesh_node := node as MeshInstance3D
			if mesh_node.mesh == null:
				continue
			var skinned := mesh_node.skin != null or mesh_node.get_node_or_null(mesh_node.skeleton) is Skeleton3D
			for surface in range(mesh_node.mesh.get_surface_count()):
				var material := mesh_node.get_active_material(surface)
				if material == null:
					continue
				var format := (mesh_node.mesh as ArrayMesh).surface_get_format(surface) & 0xFF if mesh_node.mesh is ArrayMesh else 0
				var key := "m:%d:%s:%d" % [material.get_instance_id(), skinned, format]
				if seen.has(key):
					continue
				seen[key] = true
				if skinned:
					continue  # skinned variants come from the character scenes below
				var copy := MeshInstance3D.new()
				copy.mesh = quad
				copy.material_override = material
				_place(copy, index)
				index += 1
	# Characters (skinned) and vehicles in their real formats.
	for scene in extra_scenes:
		if scene is PackedScene:
			var instance := (scene as PackedScene).instantiate()
			if instance is Node3D:
				_place(instance as Node3D, index, 0.01)
				index += 1
			else:
				instance.free()
	var omni := OmniLight3D.new()
	omni.omni_range = 6.0
	omni.light_energy = 0.01
	add_child(omni)
	var spot := SpotLight3D.new()
	spot.spot_range = 6.0
	spot.light_energy = 0.01
	spot.position = Vector3(0, 0, 1.0)
	add_child(spot)


func _material_id(node: GeometryInstance3D) -> int:
	return node.material_override.get_instance_id() if node.material_override != null else 0


func _place(node: Node3D, index: int, scale_value: float = 1.0) -> void:
	node.position = Vector3((index % 20) * 0.025 - 0.25, (index / 20 % 20) * 0.025 - 0.25, 0.0)
	node.scale = Vector3.ONE * scale_value
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(node)


func _process(_delta: float) -> void:
	_frames_left -= 1
	if _frames_left <= 0:
		queue_free()
