extends SceneTree

## Grenades and Molotovs: the stash and pickups fill the inventory, a thrown
## grenade flies, goes off after its fuse and hurts people and cars nearby, a
## Molotov leaves a burning pool that hurts whoever stands in it, both are
## crimes, and the inventory is saved.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(8):
		await physics_frame
	var player := root.get_node("Player") as PlayerController
	var thrown: Node = root.get("throwables")
	var wanted: Node = root.get("wanted")
	if thrown == null:
		return _fail("no throwables system")
	# Pickup: walk onto the grenade crate.
	var crate: Dictionary
	for pickup in root.get("weapons").get("pickups"):
		if pickup["weapon"] == "grenade":
			crate = pickup
			break
	if crate.is_empty():
		return _fail("no grenade pickup in the world")
	player.global_position = (crate["node"] as Node3D).global_position + Vector3(0, 0.2, 0)
	await _frames(4)
	if int(thrown.get("counts")["grenade"]) != 3 or (crate["node"] as Node3D).visible:
		return _fail("grenade pickup not collected (%s)" % str(thrown.get("counts")))
	thrown.call("add", "molotov", 2)
	if not str(thrown.call("hud_text")).contains("Granada ×3"):
		return _fail("hud text: " + str(thrown.call("hud_text")))
	# Throw: a projectile leaves the hand along the aim and lands ahead.
	var start := player.global_position
	var projectile: RigidBody3D = thrown.call("throw")
	if projectile == null or int(thrown.get("counts")["grenade"]) != 2:
		return _fail("throw did not spawn a grenade")
	await _frames(20)
	if not is_instance_valid(projectile) or projectile.global_position.distance_to(start) < 3.0:
		return _fail("grenade did not fly")
	var level_before := int(wanted.get("level"))
	for i in range(170):  # past the 2.2 s fuse
		await physics_frame
	if is_instance_valid(projectile) and not projectile.is_queued_for_deletion():
		return _fail("grenade did not go off")
	if int(wanted.get("level")) <= level_before and int(wanted.get("level")) == 0:
		return _fail("explosion not reported to the police")
	# Blast: a pedestrian and a car near the blast are hurt.
	var person: Pedestrian = null
	for node in root.get_tree().get_nodes_in_group("pedestrians"):
		if node is Pedestrian and not (node as Pedestrian).dead and not node is PoliceOfficer:
			person = node
			break
	var car: DriveableVehicle = null
	for node in root.get_tree().get_nodes_in_group("vehicles"):
		if node is DriveableVehicle and not (node as DriveableVehicle).destroyed and node != player.driving_vehicle:
			car = node
			break
	if person == null or car == null:
		return _fail("no pedestrian/car to test the blast")
	var car_health := car.health
	var blast := car.global_position + Vector3(2.0, 0.3, 0)
	player.global_position = blast + Vector3(40, 0, 0)
	thrown.call("explode", blast)
	if car.health > car_health - 300.0:
		return _fail("car barely damaged by the blast (%.0f -> %.0f)" % [car_health, car.health])
	var at := person.global_position
	var ped_health := person.health
	thrown.call("explode", at + Vector3(1.0, 0, 0))
	if person.health >= ped_health and not person.dead:
		return _fail("pedestrian unhurt by the blast")
	# Molotov: a pool of fire that burns for seconds and hurts whoever is in it.
	var victim: Pedestrian = null
	for node in root.get_tree().get_nodes_in_group("pedestrians"):
		if node is Pedestrian and not (node as Pedestrian).dead and not node is PoliceOfficer and node != person:
			victim = node
			break
	var pool := victim.global_position
	var victim_health := victim.health
	thrown.call("ignite", pool)
	if (thrown.get("fires") as Array).size() != 1:
		return _fail("molotov left no fire")
	for i in range(40):
		victim.global_position = pool
		await physics_frame
	if victim.health >= victim_health and not victim.dead:
		return _fail("fire did not hurt someone standing in it")
	for i in range(int(7.5 * 60)):
		await physics_frame
	if not (thrown.get("fires") as Array).is_empty():
		return _fail("fire never went out")
	# Save / load the inventory.
	root.set("save_path", "user://test_throwables_save.json")
	root.call("_save_game")
	thrown.call("from_save", {})
	root.call("_load_game")
	if int(thrown.get("counts")["grenade"]) != 2 or int(thrown.get("counts")["molotov"]) != 2:
		return _fail("inventory not saved (%s)" % str(thrown.get("counts")))
	print("THROWABLES PASS: grenade pickup, throw arc, fuse, blast hurts car/pedestrian, wanted, molotov fire pool burns then dies out, saved")
	root.queue_free()
	await process_frame
	quit(0)


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _fail(reason: String) -> void:
	push_error("THROWABLES FAIL: " + reason)
	quit(1)
