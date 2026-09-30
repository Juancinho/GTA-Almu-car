extends SceneTree

## Smoke test of the real 1:1 sector: movement, car, traffic, carjacking, the full El
## Recado state machine, police incident/search/escape, road graph, arrest, safe exit
## next to a real façade, save/load and pause. Positions come from sector anchors.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		return _fail("main scene failed to load")
	var root := scene.instantiate()
	get_root().add_child(root)
	for i in range(30):
		await physics_frame
	var world := root.get_node_or_null("District_Altillo") as SectorWorld
	var player := root.get_node_or_null("Player") as PlayerController
	if world == null or player == null:
		return _fail("world or player missing")
	var cars := get_nodes_in_group("vehicles").filter(func(v: Node) -> bool: return not (v as DriveableVehicle).boat)
	if cars.size() != 1 + SectorWorld.TRAFFIC_COUNT:
		return _fail("expected mission car + %d traffic cars, found %d" % [SectorWorld.TRAFFIC_COUNT, cars.size()])
	if get_nodes_in_group("pedestrians").size() < 30:
		return _fail("pedestrian population missing")
	if int(world.build_stats.get("buildings", 0)) < 1000 or int(world.build_stats.get("details", 0)) < 20000:
		return _fail("sector unexpectedly sparse: %s" % world.build_stats)
	if not player.is_on_floor():
		return _fail("player did not land on ground")
	Input.action_press("jump")
	for i in range(2):
		await physics_frame
	Input.action_release("jump")
	if player.velocity.y <= 0.0:
		return _fail("jump did not leave ground")
	for i in range(50):
		await physics_frame
	if not player.is_on_floor():
		return _fail("player did not land after jump")
	var walk_start := player.global_position
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for i in range(90):
		await physics_frame
	Input.action_release("move_forward")
	Input.action_release("sprint")
	if player.global_position.distance_to(walk_start) < 8.0:
		return _fail("sprint movement too slow or blocked")
	var car := world.get_node("FirstCar") as DriveableVehicle
	if player.global_position.distance_to(car.global_position) < 4.0:
		return _fail("car incorrectly near player at spawn")
	player.global_position = car.global_position + car.global_transform.basis.x * 2.2
	player._interact()
	if player.driving_vehicle != car or car.driver != player:
		return _fail("enter vehicle failed")
	player._interact()
	if player.driving_vehicle != null or car.driver != null:
		return _fail("exit vehicle failed")
	var mission := root.get_node("Mission") as MissionController
	var wanted := root.get_node("WantedSystem") as WantedSystem
	var alba := world.get_node("Alba") as Pedestrian
	player.global_position = alba.global_position + Vector3(1, 0, 0)
	player._interact()
	if mission.stage != 1:
		return _fail("mission contact did not advance to vehicle objective")
	player.global_position = car.global_position + car.global_transform.basis.x * 2.2
	player._interact()
	if mission.stage != 2:
		return _fail("enter vehicle objective did not advance")
	var traffic_starts := {}
	for node in cars:
		var vehicle := node as DriveableVehicle
		if vehicle.traffic:
			traffic_starts[vehicle] = vehicle.global_position
	var start_pos := car.global_position
	Input.action_press("move_forward")
	for i in range(65):
		await physics_frame
	Input.action_release("move_forward")
	if car.global_position.distance_to(start_pos) < 2.0:
		return _fail("driving did not move car")
	var moving := 0
	for vehicle in traffic_starts:
		if (vehicle as DriveableVehicle).global_position.distance_to(traffic_starts[vehicle]) > 3.0:
			moving += 1
	if moving < traffic_starts.size() * 0.6:
		return _fail("traffic mostly stuck: only %d of %d moved" % [moving, traffic_starts.size()])
	# Carjacking: boarding an occupied traffic car ejects its driver, who flees.
	player._interact()
	var victim := world.get_node("Traffic_03") as DriveableVehicle
	player.global_position = victim.global_position + victim.global_transform.basis.x * 2.0
	player._interact()
	await physics_frame
	var ejected := world.get_node_or_null("Conductor_Traffic_03") as Pedestrian
	if player.driving_vehicle != victim or victim.traffic or ejected == null or ejected.state != Pedestrian.State.FLEE:
		return _fail("carjacking failed: driving=%s ejected=%s" % [player.driving_vehicle, ejected])
	player._interact()
	player.global_position = car.global_position + car.global_transform.basis.x * 2.2
	player._interact()
	# Driving into the old town pedestrian zone in front of residents starts the pursuit.
	car.global_position = world.anchor("old_town_target") + Vector3(0, 0.6, 0)
	for i in range(3):
		await physics_frame
	if wanted.level != 1 or mission.stage != 3 or wanted.police_cars.size() != 1:
		return _fail("old town incident did not start pursuit (level %d stage %d police %d)" % [wanted.level, mission.stage, wanted.police_cars.size()])
	car.global_position = world.anchor("hospital") + Vector3(0, 0.6, 0)
	wanted.police_cars[0].global_position = wanted.last_known + Vector3(3, 0.6, 0)
	wanted.search_timer = WantedSystem.SEARCH_SECONDS - 0.2
	for i in range(30):
		await physics_frame
	if wanted.level != 0:
		return _fail("police search did not end")
	await process_frame
	if mission.stage != 4:
		return _fail("escape objective did not advance")
	car.global_position = world.anchor("castle_drop") + Vector3(0, 0.6, 0)
	for i in range(3):
		await process_frame
	if not mission.completed:
		return _fail("mission destination did not complete")
	wanted.incident_cooldown = 0.0
	if not wanted.report_incident(world.anchor("old_town_target")):
		return _fail("first free-roam wanted report failed")
	wanted.incident_cooldown = 0.0
	if not wanted.report_incident(world.anchor("old_town_target")) or wanted.level != 2 or wanted.police_cars.size() != 2:
		return _fail("wanted level 2 failed")
	wanted.unseen_timer = WantedSystem.UNSEEN_SECONDS - 0.2
	car.global_position = world.anchor("hospital") + Vector3(0, 0.6, 0)
	for i in range(25):
		await physics_frame
	if wanted.level != 0:
		return _fail("unseen escape fallback failed")
	var network: RoadNetwork = world.road_network
	var path := network.find_path(world.anchor("first_car"), world.anchor("castle_drop"))
	if path.size() < 5 or path[path.size() - 1].distance_to(world.anchor("castle_drop")) > 6.0 or network.road_name_at(world.anchor("player_spawn")) == "":
		return _fail("road graph path/name lookup failed (%d nodes)" % path.size())
	# Arrest: slow next to a seeing unit -> detained, mission back to its checkpoint.
	mission.restore_stage(3)
	if player.driving_vehicle == null:
		player.global_position = car.global_position + car.global_transform.basis.x * 2.2
		player._interact()
	wanted.incident_cooldown = 0.0
	car.global_position = world.anchor("old_town_target") + Vector3(0, 0.6, 0)
	for i in range(3):
		await physics_frame
	if wanted.level == 0 or wanted.police_cars.is_empty():
		return _fail("arrest setup did not raise wanted level")
	var busted := [false]
	wanted.player_busted.connect(func() -> void: busted[0] = true)
	car.speed = 0.0
	wanted.police_cars[0].global_position = car.global_position + car.global_transform.basis.z * 6.0 + Vector3(0, 0.3, 0)
	for i in range(240):
		await physics_frame
		if busted[0]:
			break
	await process_frame
	if not busted[0] or mission.stage != 1 or player.driving_vehicle != null or wanted.level != 0:
		return _fail("arrest did not reset mission: busted=%s stage=%d" % [busted[0], mission.stage])
	if car.global_position.distance_to(world.vehicle_spawns["FirstCar"].origin) > 1.5:
		return _fail("mission car not returned to spawn after arrest: %s" % str(car.global_position))
	# Exit next to a real façade: the player must never end up inside the building.
	var facade := _street_facade(world)
	player.global_position = car.global_position + car.global_transform.basis.x * 2.2
	player._interact()
	var yaw := atan2(-facade["dir"].x, -facade["dir"].z)
	car.rotation.y = yaw
	if car.global_transform.basis.x.dot(-facade["normal"]) < 0.0:
		car.rotation.y = yaw + PI
	var spot: Vector3 = facade["mid"] + facade["normal"] * 1.9
	car.global_position = Vector3(spot.x, world.height_at(spot.x, spot.z) + 0.6, spot.z)
	for i in range(2):
		await physics_frame
	player._interact()
	await physics_frame
	var footprint: PackedVector2Array = facade["footprint"]
	if Geometry2D.is_point_in_polygon(Vector2(player.global_position.x, player.global_position.z), footprint):
		return _fail("vehicle exit placed player inside a building at %s" % str(player.global_position))
	world.reset_vehicle("FirstCar")
	mission.restore_stage(5)
	root.save_path = "user://smoke_save_v1.json"
	root._save_game()
	var saved_position := player.global_position
	player.global_position = Vector3.ZERO
	mission.restore_stage(0)
	root._load_game()
	if not mission.completed or player.global_position.distance_to(saved_position) > 0.5:
		return _fail("save/load did not restore state")
	paused = true
	if player.can_process():
		return _fail("pause did not stop player")
	paused = false
	print("SMOKE PASS: %d buildings, %d façade details; walking, car, traffic, carjacking, mission, police, arrest, road graph, safe exit, save/load, pause" % [world.build_stats["buildings"], world.build_stats["details"]])
	_stop_audio(root)
	root.queue_free()
	for i in range(3):
		await process_frame
	for bus_name in ["UI", "Ambience", "Music", "SFX"]:
		var bus_index := AudioServer.get_bus_index(bus_name)
		if bus_index > 0:
			AudioServer.remove_bus(bus_index)
	quit(0)


## A long street-facing seafront wall edge: {mid, dir, normal, footprint}.
func _street_facade(world: SectorWorld) -> Dictionary:
	for b in world.data.raw["buildings"]:
		if str(b["zone"]) != "seafront":
			continue
		var fp: Array = b["footprint"]
		for i in range(fp.size()):
			if int(b["street_edges"][i]) != 1:
				continue
			var a := Vector2(float(fp[i][0]), float(fp[i][1]))
			var c := Vector2(float(fp[(i + 1) % fp.size()][0]), float(fp[(i + 1) % fp.size()][1]))
			if a.distance_to(c) < 10.0:
				continue
			var polygon := PackedVector2Array()
			for p in fp:
				polygon.append(Vector2(float(p[0]), float(p[1])))
			var edge := (c - a).normalized()
			return {"mid": Vector3((a.x + c.x) * 0.5, 0, (a.y + c.y) * 0.5), "dir": Vector3(edge.x, 0, edge.y),
				"normal": Vector3(edge.y, 0, -edge.x), "footprint": polygon}
	return {}


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
