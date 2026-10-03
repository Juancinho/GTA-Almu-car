extends SceneTree

## Vigilante: in a patrol car T starts a pursuit; the suspect's car flees along
## the roads; wrecking it ejects an armed driver; taking him down pays and
## brings the next, faster suspect.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(8):
		await physics_frame
	var world := root.get_node("District_Altillo") as SectorWorld
	var player := root.get_node("Player") as PlayerController
	var activities: Node = root.get("activities")
	var patrol := (load("res://scripts/vehicle.gd") as GDScript).new() as DriveableVehicle
	patrol.variant = "police_local"
	var spot: Vector3 = (world.get_node("FirstCar") as Node3D).global_position
	patrol.position = spot + Vector3(0, 0.2, 0)
	(world.get_node("FirstCar") as Node3D).global_position += Vector3(0, 0, 30)
	world.add_child(patrol)
	await physics_frame
	player.global_position = patrol.global_position + patrol.global_transform.basis.x * 2.0
	player._interact()
	if player.driving_vehicle != patrol:
		return _fail("could not board the patrol car")
	var press := InputEventAction.new()
	press.action = "activity"
	press.pressed = true
	activities.call("_unhandled_input", press)
	if str(activities.get("active")) != "vigilante":
		return _fail("T in a patrol car did not start vigilante")
	var suspect: DriveableVehicle = activities.get("suspect")
	if suspect == null:
		return _fail("no suspect spawned")
	var start := suspect.global_position
	for i in range(240):
		await physics_frame
	if suspect.global_position.distance_to(start) < 15.0:
		return _fail("the suspect did not drive off")
	suspect.apply_damage(suspect.health - 200.0)
	for i in range(5):
		await physics_frame
	var driver: Pedestrian = activities.get("suspect_driver")
	if str(activities.get("stage")) != "takedown" or driver == null or not driver.armed:
		return _fail("wrecked suspect did not bail out armed")
	var money := int(root.get("money"))
	driver.take_damage(500.0, driver.global_position + Vector3(1, 0, 0))
	for i in range(5):
		await physics_frame
	if int(root.get("money")) <= money or int(activities.get("vigilante_level")) != 2:
		return _fail("takedown did not pay or bring the next suspect")
	print("VIGILANTE PASS: patrol car T, fleeing suspect (%.0f m in 4 s), wreck -> armed driver, takedown pays, level 2" % suspect.global_position.distance_to(start))
	root.queue_free()
	await process_frame
	quit(0)


func _fail(reason: String) -> void:
	push_error("VIGILANTE FAIL: " + reason)
	quit(1)
