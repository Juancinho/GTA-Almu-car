extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(game)
	var player := game.get_node("Player") as PlayerController
	var weapons := game.get_node("Weapons") as WeaponSystem
	player.set_physics_process(false)
	await _frames(6)
	var rig := player.human.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var lengths := {}
	for side in ["L", "R"]:
		lengths[side] = [weapons._bone_position("UpperArm." + side).distance_to(weapons._bone_position("LowerArm." + side)), weapons._bone_position("LowerArm." + side).distance_to(weapons._bone_position("Palm." + side))]
	for id in ["pistol", "smg", "shotgun", "rifle"]:
		weapons.give(id, 60)
		weapons.select(id)
		Input.action_press("aim")
		for pitch in [-0.6, 0.0, 0.45]:
			player.camera_pitch = pitch
			await _frames(4)
			if weapons.gun_holder.global_position.distance_to(weapons._bone_position("MiddleHand.R")) > 0.012:
				return _fail("%s grip detached from the right hand" % id)
			for side in ["L", "R"]:
				var a := weapons._bone_position("UpperArm." + side)
				var b := weapons._bone_position("LowerArm." + side)
				var c := weapons._bone_position("Palm." + side)
				if absf(a.distance_to(b) - lengths[side][0]) > 0.003 or absf(b.distance_to(c) - lengths[side][1]) > 0.003:
					return _fail("%s stretched the %s arm" % [id, side])
			if bool(weapons.definition().get("long", false)):
				var point: Array = weapons.definition()["support_grip"]
				var support := weapons.gun_holder.to_global(Vector3(point[0], point[1], point[2]))
				if support.distance_to(weapons._bone_position("MiddleHand.L")) > 0.08:
					return _fail("%s support hand cannot reach the fore-end" % id)
		Input.action_release("aim")
		await _frames(4)
		if weapons.gun_holder.global_position.distance_to(weapons._bone_position("MiddleHand.R")) > 0.012:
			return _fail("%s did not release the aim pose into the carrying grip" % id)
	weapons.select("fists")
	await _frames(3)
	for model in weapons.gun_models.values():
		if model.visible:
			return _fail("weapon mesh left visible with fists selected")
	if player.human.grip_active or rig.get_bone_count() < 10:
		return _fail("arm overrides were not cleared")
	print("WEAPON GRIPS PASS: four weapons, raised/lowered grips, three aim pitches, preserved arm lengths, support-hand reach and clean unequip")
	game.queue_free()
	await process_frame
	quit()

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame
		await physics_frame

func _fail(reason: String) -> void:
	Input.action_release("aim")
	push_error("WEAPON GRIPS FAIL: " + reason)
	quit(1)
