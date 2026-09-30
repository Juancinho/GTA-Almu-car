extends RefCounted

## Original procedural poses on the CC0 adult rig, updated only for nearby people.
static func update(human: HumanModel, activity: String, phase: float) -> void:
	if human.grip_skeleton == null:
		var rigs := human.find_children("*", "Skeleton3D", true, false)
		if rigs.is_empty():
			return
		human.grip_skeleton = rigs[0] as Skeleton3D
	var rig := human.grip_skeleton
	human.play_state("idle")
	for side in ["L", "R"]:
		var swing := sin(phase + (PI if side == "R" else 0.0))
		for limb in ["UpperArm", "LowerArm", "UpperLeg", "LowerLeg"]:
			var bone := rig.find_bone(limb + "." + side)
			if bone < 0:
				continue
			var angle := 0.0
			match activity:
				"dance": angle = swing * 0.75 if limb == "UpperArm" else 0.55 if limb == "LowerArm" else swing * 0.18 if limb == "UpperLeg" else 0.2
				"work": angle = -0.55 + swing * 0.18 if limb == "UpperArm" else -0.65 if limb == "LowerArm" else 0.0
				"skate": angle = swing * 0.35 if limb == "UpperArm" else 0.25 if limb == "LowerArm" else swing * 0.3 if limb == "UpperLeg" else 0.18
			var pose := rig.get_bone_pose(bone)
			pose.basis = Basis(Vector3.RIGHT, angle) * pose.basis
			rig.set_bone_global_pose_override(bone, rig.get_bone_global_pose(rig.get_bone_parent(bone)) * pose, 1.0, true)
	human.swim_pose_active = true  # shared cleanup before fighting/fleeing/swimming

static func skates(human: HumanModel) -> void:
	var rigs := human.find_children("*", "Skeleton3D", true, false)
	if rigs.is_empty():
		return
	var rig := rigs[0] as Skeleton3D
	var mats := SectorMaterials.new()
	var material := mats.textured("skate_boot", "asphalt010", Color("374d68"), 0.2)
	var rubber := mats.textured("skate_wheels", "asphalt010", Color("29262d"), 0.08)
	for side in ["L", "R"]:
		var attachment := Node3D.new()
		attachment.name = "InlineSkate_" + side
		rig.add_child(attachment)
		# The imported rig's units are converted by its model/FBX transforms.
		attachment.set_as_top_level(true)
		var boot := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.13, 0.08, 0.32)
		boot.mesh = box
		boot.material_override = material
		boot.visibility_range_end = 70.0
		boot.position.y = -0.01
		attachment.add_child(boot)
		for i in range(4):
			var wheel := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.042
			mesh.bottom_radius = 0.042
			mesh.height = 0.04
			mesh.radial_segments = 8
			wheel.mesh = mesh
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(0, -0.065, -0.115 + i * 0.075)
			wheel.material_override = rubber
			wheel.visibility_range_end = 70.0
			wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			attachment.add_child(wheel)

static func place_skates(human: HumanModel) -> void:
	if human.grip_skeleton == null:
		return
	var rig := human.grip_skeleton
	for side in ["L", "R"]:
		var attachment := rig.get_node_or_null("InlineSkate_" + side) as Node3D
		var bone := rig.find_bone("Foot." + side)
		if attachment != null and bone >= 0:
			var at := rig.to_global(rig.get_bone_global_pose(bone).origin)
			attachment.global_transform = Transform3D(human.global_basis.orthonormalized(), at)
