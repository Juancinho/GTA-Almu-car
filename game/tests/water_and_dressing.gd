extends SceneTree

## Swim/dive/shore exit, car water boundary and palm placement in the live sector.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(25):
		await physics_frame
	var world := root.get_node("District_Altillo") as SectorWorld
	var player := root.get_node("Player") as PlayerController
	var car := world.get_node("FirstCar") as DriveableVehicle
	var planned := DressingBuilder.plan(world.data, world.road_network)
	var building_areas := DressingBuilder._building_areas(world.data)
	if (planned["palms"] as Array).size() < 15:
		return _fail("palm population unexpectedly low")
	for t in planned["palms"]:
		if not DressingBuilder._clear_of_driveable(t.origin, world.road_network, 1.0):
			return _fail("palm trunk inside a driveable lane")
		if DressingBuilder._inside_building(t.origin, building_areas):
			return _fail("palm trunk inside a building")
	for kind in ["lamps", "benches"]:
		for t in planned[kind]:
			if not DressingBuilder._clear_of_driveable(t.origin, world.road_network, 0.45 if kind == "lamps" else 1.0):
				return _fail("%s inside a driveable lane" % kind)
			if DressingBuilder._inside_building(t.origin, building_areas):
				return _fail("%s inside a building" % kind)
	# Walk into the water and swim back to a reachable beach without teleporting.
	player.global_position = Vector3(20.0, world.height_at(20.0, 85.0) + 0.5, 85.0)
	player.camera_yaw = PI
	player._update_camera_orientation()
	Input.action_press("move_forward")
	for i in range(360):
		await physics_frame
	Input.action_release("move_forward")
	if not player.swimming or player.global_position.z < 100.0:
		return _fail("walking from beach did not enter swimmable sea")
	Input.action_press("move_back")
	for i in range(480):
		await physics_frame
	Input.action_release("move_back")
	if player.swimming or player.global_position.z > 97.0:
		return _fail("swimming toward beach did not return to shore")
	var dry_car := car.global_position
	car.global_position = Vector3(20.0, -1.0, 200.0)
	await physics_frame
	if car.global_position.distance_to(dry_car) > 3.0 or absf(car.speed) > 0.1:
		return _fail("car remained in deep water")
	player.global_position = Vector3(20.0, -0.65, 200.0)
	for i in range(20):
		await physics_frame
	if not player.swimming or player.diving or player.breath < PlayerController.MAX_BREATH - 0.1:
		return _fail("surface swim did not stabilize")
	Input.action_press("dive")
	for i in range(100):
		await physics_frame
	Input.action_release("dive")
	if not player.diving or player.global_position.y >= -1.1 or player.breath >= PlayerController.MAX_BREATH - 0.5:
		return _fail("diving did not consume breath")
	Input.action_press("jump")
	for i in range(80):
		await physics_frame
	Input.action_release("jump")
	if player.breath <= 0.0:
		return _fail("player could not surface for air")
	player.global_position = world.anchor("player_spawn") + Vector3(0, 0.3, 0)
	for i in range(4):
		await physics_frame
	if player.swimming:
		return _fail("player could not leave the water")
	print("WATER AND DRESSING PASS: %d palms clear of roads, car boundary, swim, dive, shore exit" % (planned["palms"] as Array).size())
	root.queue_free()
	await process_frame
	quit(0)


func _fail(reason: String) -> void:
	push_error("WATER AND DRESSING FAIL: " + reason)
	quit(1)
