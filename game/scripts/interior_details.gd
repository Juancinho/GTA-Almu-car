class_name InteriorDetails
extends RefCounted

## Batch repeated opaque furniture within each room. Architectural surfaces stay
## visible at street distance; small furnishings and people stop drawing at 120 m.
const DETAIL_DISTANCE := 120.0
const STRUCTURE := ["Floor", "Ceiling", "LeftWall", "RightWall", "BackWall", "FrontWall",
	"StorefrontHeader", "StorefrontSill", "StorefrontMullion", "ShopWindow", "GlassDoor", "DoorHandle",
	"StoneLintel", "StonePlinth", "StonePier", "StoneMullion", "StainedWindow", "ChurchDoor", "PortalBeam"]


static func optimize(room: Node3D) -> void:
	var groups := {}
	for node in room.get_children():
		if node is HumanModel:
			for geometry in node.find_children("*", "GeometryInstance3D", true, false):
				(geometry as GeometryInstance3D).visibility_range_end = DETAIL_DISTANCE
		if node is not MeshInstance3D:
			continue
		var visual := node as MeshInstance3D
		var label := str(visual.get_meta("detail_kind", visual.name))
		if label in STRUCTURE:
			continue
		visual.visibility_range_end = DETAIL_DISTANCE
		# Robbery changes these objects individually; preserve their identities.
		if label.begins_with("Gemstone") or label.begins_with("GoldSetting") or label.begins_with("GoldDisplay"):
			continue
		var material := visual.material_override as StandardMaterial3D
		if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var shape := _signature(visual.mesh)
		if shape.is_empty():
			continue
		var key := "%s:%d" % [shape, material.get_instance_id()]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(visual)
	var batch_index := 0
	for members in groups.values():
		if members.size() < 2:
			continue
		var first := members[0] as MeshInstance3D
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = first.mesh
		multi.instance_count = members.size()
		for i in range(members.size()):
			multi.set_instance_transform(i, (members[i] as MeshInstance3D).transform)
		var batch := MultiMeshInstance3D.new()
		batch.name = "FurnitureBatch_%d" % batch_index
		batch.multimesh = multi
		batch.material_override = first.material_override
		batch.visibility_range_end = DETAIL_DISTANCE
		room.add_child(batch)
		for visual in members:
			room.remove_child(visual)
			visual.free()
		batch_index += 1


static func _signature(mesh: Mesh) -> String:
	if mesh is BoxMesh:
		return "box:%s" % (mesh as BoxMesh).size
	if mesh is CylinderMesh:
		var cylinder := mesh as CylinderMesh
		return "cylinder:%s:%s:%s:%d" % [cylinder.top_radius, cylinder.bottom_radius, cylinder.height, cylinder.radial_segments]
	if mesh is SphereMesh:
		var sphere := mesh as SphereMesh
		return "sphere:%s:%s:%d:%d" % [sphere.radius, sphere.height, sphere.radial_segments, sphere.rings]
	return ""
