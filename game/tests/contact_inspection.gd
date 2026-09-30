extends SceneTree

func _initialize() -> void:
	call_deferred("inspect")

func inspect() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	for key in ["mission_red", "sedan_teal", "suv_sand", "sports_orange", "compact_generated"]:
		var car := DriveableVehicle.new()
		car.variant = key
		holder.add_child(car)
		car.set_physics_process(false)
		var visual := car.get_node("CarVisual") as Node3D
		var bounds := AABB()
		var first := true
		for mesh in visual.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = (car.global_transform.affine_inverse() * mesh.global_transform) * mesh.mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
			if key == "mission_red":
				for surface in range(mesh.mesh.get_surface_count()):
					print("CAR_MATERIAL ",mesh.mesh.surface_get_material(surface).resource_name)
		car.set_occupant("male_casual")
		car.occupant.player.seek(0.8, true)
		car.occupant.player.advance(0.0)
		await process_frame
		await process_frame
		var rig := car.occupant.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var bones := {}
		for bone in ["Hip", "Hips", "Pelvis", "Spine", "Head", "Foot.L", "Foot.R", "LowerLeg.L", "UpperLeg.L"]:
			var index := rig.find_bone(bone)
			if index >= 0:
				bones[bone] = car.to_local(rig.to_global(rig.get_bone_global_pose(index).origin))
		print("CONTACT_INSPECT ", key, " bounds=", bounds, " seated=", bones, " names=", rig.get_bone_name(0))
	for choice in ["female_tanktop", "female_casual"]:
		var human := HumanModel.new(choice)
		holder.add_child(human)
		for item in human.find_children("*", "MeshInstance3D", true, false):
			var mesh := item as MeshInstance3D
			for surface in range(mesh.mesh.get_surface_count()):
				var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				var box := AABB(vertices[0], Vector3.ZERO)
				for vertex in vertices:
					box = box.expand(vertex)
				print("OUTFIT_INSPECT ", choice, " mesh=", mesh.name, " material=", mesh.mesh.surface_get_material(surface).resource_name, " bounds=", box, " transform=", mesh.transform)
	quit()
