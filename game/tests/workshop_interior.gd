extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(8):
		await physics_frame
	var world := root.get_node("District_Altillo") as SectorWorld
	var player := root.get_node("Player") as PlayerController
	var car := world.get_node("FirstCar") as DriveableVehicle
	var workshop := world.workshop
	if workshop == null or workshop.source_building_id != WorkshopInterior.BUILDING_ID:
		return _fail("workshop not attached to its selected building")
	if not DressingBuilder._clear_of_driveable(workshop.exterior_entry, world.road_network, 0.0):
		return _fail("workshop door is in a driveable lane")
	car.global_position = workshop.exterior_entry + workshop.exterior_normal * 3.5
	car.health = 400.0
	root.money = 50
	player.global_position = workshop.exterior_entry
	player._interact()
	if player.global_position.distance_to(workshop.inside_entry) > 0.2 or player.driving_vehicle != null:
		return _fail("could not enter workshop")
	for i in range(8):
		await physics_frame
	if player.global_position.y < 999.5:
		return _fail("workshop floor did not support the player")
	player.global_position = workshop.service_point
	player._interact()
	if car.health != 400.0 or root.money != 50:
		return _fail("repair ignored insufficient funds")
	root.money = 100
	player._interact()
	if car.health < DriveableVehicle.MAX_HEALTH or root.money != 25:
		return _fail("paid repair did not work")
	player.global_position = workshop.inside_entry
	player._interact()
	if player.global_position.distance_to(workshop.exterior_entry) > 1.0:
		return _fail("could not leave workshop")
	print("WORKSHOP PASS: enter, solid furnished room, paid repair, exit")
	root.queue_free()
	await process_frame
	quit(0)


func _fail(reason: String) -> void:
	push_error("WORKSHOP FAIL: " + reason)
	quit(1)
