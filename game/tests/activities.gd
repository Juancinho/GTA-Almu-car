extends SceneTree

## Side activities: taxi fares (pickup, drop-off, pay, next fare, quit) and the
## street race (start column, checkpoints, finish pay, best time saved).


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(8):
		await physics_frame
	var world := root.get_node("District_Altillo") as SectorWorld
	var player := root.get_node("Player") as PlayerController
	var acts := root.get_node_or_null("Activities")
	if acts == null:
		return _fail("no activity system")
	# Taxi: carjack a traffic taxi.
	var taxi: DriveableVehicle
	for node in get_nodes_in_group("vehicles"):
		if (node as DriveableVehicle).variant == "taxi" and (node as DriveableVehicle).traffic:
			taxi = node
			break
	if taxi == null:
		return _fail("no taxi in traffic")
	taxi.global_position = player.global_position + Vector3(0, 0.5, -8)
	taxi.speed = 0.0
	taxi.traffic = false
	player.global_position = taxi.global_position + taxi.global_transform.basis.x * 2.2
	player._interact()
	await _frames(2)
	acts.call("start_taxi")
	if str(acts.get("active")) != "taxi" or acts.get("fare") == null:
		return _fail("taxi duty did not find a fare")
	var fare := acts.get("fare") as Pedestrian
	taxi.global_position = fare.global_position + Vector3(3, 0.6, 0)
	taxi.speed = 0.0
	await _frames(3)
	if str(acts.get("stage")) != "dropoff" or fare.visible:
		return _fail("the fare did not get in")
	var money := int(root.get("money"))
	taxi.global_position = (acts.get("target") as Vector3) + Vector3(0, 0.6, 0)
	taxi.speed = 0.0
	await _frames(3)
	if int(root.get("money")) <= money or int(acts.get("fares_done")) != 1 or str(acts.get("stage")) != "pickup":
		return _fail("drop-off did not pay and chain the next fare")
	player._interact()
	await _frames(3)
	if str(acts.get("active")) != "":
		return _fail("leaving the cab did not end the shift")
	# Race.
	var car := world.get_node("FirstCar") as DriveableVehicle
	player.global_position = car.global_position + car.global_transform.basis.x * 2.2
	player._interact()
	acts.set("cooldown", 0.0)
	var start := (acts.get("start_column") as Node3D).global_position
	car.global_position = Vector3(start.x, world.height_at(start.x, start.z) + 0.6, start.z)
	await _frames(3)
	if str(acts.get("active")) != "race":
		return _fail("driving into the start column did not start the race")
	money = int(root.get("money"))
	for point in acts.get("race_points"):
		car.global_position = (point as Vector3) + Vector3(0, 0.6, 0)
		car.speed = 0.0
		await _frames(2)
	if str(acts.get("active")) != "" or int(root.get("money")) < money + 600 or float(acts.get("best_race")) <= 0.0:
		return _fail("finishing the race did not pay the par bonus")
	root.set("save_path", "user://test_activities_save.json")
	root.call("_save_game")
	acts.set("best_race", 0.0)
	root.call("_load_game")
	if float(acts.get("best_race")) <= 0.0:
		return _fail("best race time not saved")
	print("ACTIVITIES PASS: taxi pickup/drop-off/pay/next fare/quit, race start/checkpoints/par pay, best time saved")
	root.queue_free()
	await process_frame
	quit(0)


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _fail(reason: String) -> void:
	push_error("ACTIVITIES FAIL: " + reason)
	quit(1)
