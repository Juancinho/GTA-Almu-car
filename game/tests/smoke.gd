extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		_fail("main scene failed to load")
		return
	var root := scene.instantiate()
	get_root().add_child(root)
	for i in range(30):
		await physics_frame
	var world := root.get_node_or_null("District_Altillo")
	var player := root.get_node_or_null("Player") as PlayerController
	var cars := get_nodes_in_group("vehicles")
	if world == null or player == null:
		_fail("world or player missing")
		return
	if cars.size() != 13:
		_fail("expected mission car + 12 traffic cars, found %d" % cars.size())
		return
	if get_nodes_in_group("pedestrians").size() != 15:
		_fail("pedestrian population missing")
		return
	if world.get_child_count() < 150:
		_fail("district geometry unexpectedly sparse: %d children" % world.get_child_count())
		return
	if not player.is_on_floor():
		_fail("player did not land on ground")
		return
	Input.action_press("jump")
	for i in range(2):
		await physics_frame
	Input.action_release("jump")
	if player.velocity.y <= 0.0:
		_fail("jump did not leave ground")
		return
	for i in range(50):
		await physics_frame
	if not player.is_on_floor():
		_fail("player did not land after jump")
		return
	var walk_start := player.global_position
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for i in range(90):
		await physics_frame
	Input.action_release("move_forward")
	Input.action_release("sprint")
	if player.global_position.distance_to(walk_start) < 8.0:
		_fail("sprint movement too slow or blocked")
		return
	if player.nearby_vehicle() != null:
		_fail("car incorrectly near player at spawn")
		return
	var car := world.get_node("FirstCar") as DriveableVehicle
	player.global_position = car.global_position + Vector3(2.0, 0.0, 0.0)
	player._interact()
	if player.driving_vehicle != car or car.driver != player:
		_fail("enter vehicle failed")
		return
	player._interact()
	if player.driving_vehicle != null or car.driver != null:
		_fail("exit vehicle failed")
		return
	var mission := root.get_node("Mission") as MissionController
	var wanted := root.get_node("WantedSystem") as WantedSystem
	var alba := world.get_node("Alba") as Pedestrian
	player.global_position = alba.global_position + Vector3(1, 0, 0)
	player._interact()
	if mission.stage != 1:
		_fail("mission contact did not advance to vehicle objective")
		return
	player.global_position = car.global_position + Vector3(2, 0, 0)
	player._interact()
	if mission.stage != 2:
		_fail("enter vehicle objective did not advance")
		return
	var traffic_starts := {}
	for node in cars:
		var vehicle := node as DriveableVehicle
		if vehicle.traffic:
			traffic_starts[vehicle] = vehicle.global_position
	var start_pos := car.global_position
	var traffic_car := world.get_node("Traffic_00") as DriveableVehicle
	var traffic_start := traffic_car.global_position
	Input.action_press("move_forward")
	for i in range(65):
		await physics_frame
	Input.action_release("move_forward")
	if car.global_position.distance_to(start_pos) < 2.0:
		_fail("driving did not move car")
		return
	if traffic_car.global_position.distance_to(traffic_start) < 1.0:
		_fail("traffic car did not move")
		return
	var moving := 0
	for vehicle in traffic_starts:
		if (vehicle as DriveableVehicle).global_position.distance_to(traffic_starts[vehicle]) > 3.0:
			moving += 1
	if moving < 9:
		_fail("traffic mostly stuck: only %d of %d moved" % [moving, traffic_starts.size()])
		return
	# Carjacking: boarding an occupied traffic car ejects its driver, who flees.
	player._interact()
	var victim := world.get_node("Traffic_03") as DriveableVehicle
	player.global_position = victim.global_position + victim.global_transform.basis.x * 2.0
	player._interact()
	await physics_frame
	var ejected := world.get_node_or_null("Conductor_Traffic_03") as Pedestrian
	if player.driving_vehicle != victim or victim.traffic or ejected == null or ejected.state != Pedestrian.State.FLEE:
		_fail("carjacking failed: driving=%s ejected=%s" % [player.driving_vehicle, ejected])
		return
	player._interact()
	player.global_position = car.global_position + Vector3(2, 0, 0)
	player._interact()
	car.global_position = Vector3(58, 0.1, -78)
	for i in range(3):
		await process_frame
	if wanted.level != 1 or mission.stage != 3 or wanted.police_cars.size() != 1:
		_fail("old town incident did not start pursuit")
		return
	car.global_position = Vector3(-240, 0.1, 8)
	wanted.police_cars[0].global_position = wanted.last_known + Vector3(3, 0, 0)
	wanted.search_timer = WantedSystem.SEARCH_SECONDS - 0.2
	for i in range(30):
		await physics_frame
	if wanted.level != 0:
		_fail("police search did not end")
		return
	await process_frame
	if mission.stage != 4:
		_fail("escape objective did not advance")
		return
	car.global_position = Vector3(58, 0.1, -158)
	for i in range(3):
		await process_frame
	if not mission.completed:
		_fail("mission destination did not complete")
		return
	wanted.incident_cooldown = 0.0
	if not wanted.report_incident(Vector3(58, 0, -78)):
		_fail("first free-roam wanted report failed")
		return
	wanted.incident_cooldown = 0.0
	if not wanted.report_incident(Vector3(58, 0, -78)) or wanted.level != 2 or wanted.police_cars.size() != 2:
		_fail("wanted level 2 failed")
		return
	wanted.unseen_timer = WantedSystem.UNSEEN_SECONDS - 0.2
	car.global_position = Vector3(-240, 0.1, 8)
	for i in range(25):
		await physics_frame
	if wanted.level != 0:
		_fail("unseen escape fallback failed")
		return
	var network: RoadNetwork = world.road_network
	var path := network.find_path(Vector3(112, 0, 8), Vector3(58, 0, -158))
	if path.is_empty() or path[path.size() - 1].distance_to(Vector3(58, 0, -158)) > 0.5 or network.road_name_at(Vector3(58, 0, -100)) != "Calle del Castillo":
		_fail("road network path/name lookup failed: %s" % str(path))
		return
	# Arrest: a stationary player next to a seeing police unit is detained and the
	# mission returns to its checkpoint with the car back at its spawn.
	mission.restore_stage(3)
	player.global_position = car.global_position + Vector3(2, 0, 0)
	if player.driving_vehicle == null:
		player._interact()
	wanted.incident_cooldown = 0.0
	car.global_position = Vector3(58, 0.1, -78)
	for i in range(3):
		await physics_frame
	if wanted.level == 0 or wanted.police_cars.is_empty():
		_fail("arrest setup did not raise wanted level")
		return
	var busted := [false]
	wanted.player_busted.connect(func() -> void: busted[0] = true)
	car.speed = 0.0
	wanted.police_cars[0].global_position = car.global_position + Vector3(5, 0, 0)
	for i in range(240):
		await physics_frame
		if busted[0]:
			break
	await process_frame
	if not busted[0] or mission.stage != 1 or player.driving_vehicle != null or wanted.level != 0:
		_fail("arrest did not reset mission: busted=%s stage=%d" % [busted[0], mission.stage])
		return
	if car.global_position.distance_to(Vector3(112, 0.5, 8)) > 1.0:
		_fail("mission car not returned to spawn after arrest: %s" % str(car.global_position))
		return
	# Exiting next to a façade must not place the player inside the building.
	player.global_position = car.global_position + Vector3(2, 0, 0)
	player._interact()
	# Car parked parallel to the Casa_-16_-54 façade (z = -46.5) with its +X side facing the wall.
	car.global_position = Vector3(-16.0, 0.3, -44.8)
	car.rotation.y = PI * 0.5
	for i in range(2):
		await physics_frame
	player._interact()
	await physics_frame
	var exit_query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	exit_query.shape = capsule
	exit_query.transform = Transform3D(Basis.IDENTITY, player.global_position + Vector3(0, 1.0, 0))
	exit_query.exclude = [player.get_rid(), car.get_rid()]
	if not player.get_world_3d().direct_space_state.intersect_shape(exit_query, 1).is_empty() or player.global_position.z < -46.5 or player.global_position.y > 1.0:
		_fail("vehicle exit placed player inside geometry at %s" % str(player.global_position))
		return
	world.reset_vehicle("FirstCar")
	mission.restore_stage(5)
	root.save_path = "user://smoke_save_v1.json"
	root._save_game()
	player.global_position = Vector3.ZERO
	mission.restore_stage(0)
	root._load_game()
	if not mission.completed or player.global_position == Vector3.ZERO:
		_fail("save/load did not restore state")
		return
	paused = true
	if player.can_process():
		_fail("pause did not stop player")
		return
	paused = false
	print("SMOKE PASS: world=%d objects; walking, car, mission, police, arrest, road graph, safe exit, save/load, pause" % world.get_child_count())
	_stop_audio(root)
	root.queue_free()
	for i in range(3):
		await process_frame
	for bus_name in ["UI", "Ambience", "Music", "SFX"]:
		var bus_index := AudioServer.get_bus_index(bus_name)
		if bus_index > 0:
			AudioServer.remove_bus(bus_index)
	quit(0)


func _fail(message: String) -> void:
	push_error("SMOKE FAIL: " + message)
	quit(1)


func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stop()
		(node as AudioStreamPlayer).stream = null
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stop()
		(node as AudioStreamPlayer3D).stream = null
	for child in node.get_children():
		_stop_audio(child)
