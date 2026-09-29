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
	if cars.size() != 4:
		_fail("expected four vehicles, found %d" % cars.size())
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
	car.global_position = Vector3(58, 0.1, -78)
	for i in range(3):
		await process_frame
	if wanted.level != 1 or mission.stage != 3 or wanted.police_cars.size() != 1:
		_fail("old town incident did not start pursuit")
		return
	car.global_position = Vector3(-240, 0.1, 8)
	wanted.police_cars[0].global_position = wanted.last_known + Vector3(3, 0, 0)
	wanted.search_timer = 9.8
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
	wanted.unseen_timer = 17.8
	car.global_position = Vector3(-240, 0.1, 8)
	for i in range(25):
		await physics_frame
	if wanted.level != 0:
		_fail("unseen escape fallback failed")
		return
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
	print("SMOKE PASS: world=%d objects; walking, car, mission, police, save/load, pause" % world.get_child_count())
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
