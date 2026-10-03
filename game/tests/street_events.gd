extends SceneTree

## Random street events: a bag snatcher runs from the player and drops the bag
## when taken down, a stolen car flees and the thief bails out when it is
## stopped, and a wrecked cash van spills cash bags, armed guards and stars.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(10):
		await physics_frame
	var player := root.get_node("Player") as PlayerController
	var events: Node = root.get("street_events")
	var wanted := root.get_node("WantedSystem") as WantedSystem
	if events == null:
		return _fail("no street events system")
	if bool(events.call("busy")):
		return _fail("free roam reported as busy")
	# --- Bag snatch ---
	if not bool(events.call("start", "mugging")):
		return _fail("no spot for a mugging")
	var thief := events.get("thief") as Pedestrian
	if thief == null or events.get("blip_target") != thief:
		return _fail("mugging has no thief / blip")
	var gap_before := thief.global_position.distance_to(player.global_position)
	for i in range(150):
		await physics_frame
	var gap_after := thief.global_position.distance_to(player.global_position)
	if gap_after < gap_before + 4.0:
		return _fail("thief did not run away (%.1f -> %.1f m)" % [gap_before, gap_after])
	thief.take_damage(200.0, player.global_position)
	await _frames(3)
	if str(events.get("active")) != "" or events.get("loot") == null:
		return _fail("taking the thief down did not drop the bag")
	var money_before := int(root.get("money"))
	player.global_position = (events.get("loot") as Node3D).global_position + Vector3(0, 0.3, 0)
	await _frames(4)
	if int(root.get("money")) <= money_before:
		return _fail("bag not collected")
	# --- Stolen car ---
	if not bool(events.call("start", "car_theft")):
		return _fail("no road for a car theft")
	var stolen := events.get("car") as DriveableVehicle
	var car_start := stolen.global_position
	for i in range(180):
		await physics_frame
	if stolen.global_position.distance_to(car_start) < 8.0:
		return _fail("stolen car did not drive off")
	money_before = int(root.get("money"))
	stolen.apply_damage(600.0)
	await _frames(3)
	if str(events.get("active")) != "" or int(root.get("money")) != money_before + 250:
		return _fail("stopping the stolen car did not pay (%d -> %d)" % [money_before, int(root.get("money"))])
	if stolen.occupant_name != "":
		return _fail("thief still in the stopped car")
	# --- Cash van ---
	if not bool(events.call("start", "cash_van")):
		return _fail("no road for the cash van")
	var van := events.get("car") as DriveableVehicle
	van.apply_damage(600.0)
	await _frames(3)
	var bags := events.get("loot") as Node3D
	if bags == null or int(events.get("loot_value")) < 1500:
		return _fail("cash van did not spill the bags")
	var stars := wanted.level
	if stars < 1:
		return _fail("cash van robbery gave no stars")
	var guards := 0
	for node in root.get_tree().get_nodes_in_group("pedestrians"):
		if str(node.name).begins_with("Vigilante") and (node as Pedestrian).armed:
			guards += 1
	if guards < 2:
		return _fail("no armed guards")
	money_before = int(root.get("money"))
	player.global_position = bags.global_position + Vector3(0, 0.3, 0)
	await _frames(4)
	if int(root.get("money")) < money_before + 1500:
		return _fail("cash bags not collected")
	if not bool(events.call("busy")):
		return _fail("events should pause while wanted")
	root.set("save_path", "user://test_events_save.json")
	root.call("_save_game")
	events.set("done_count", 0)
	root.call("_load_game")
	if int(events.get("done_count")) != 3:
		return _fail("event count not saved (%d)" % int(events.get("done_count")))
	print("STREET EVENTS PASS: thief ran %.0f -> %.0f m and dropped the bag, stolen car stopped (+250, thief out), cash van -> bags, %d guards, %d stars, saved" % [gap_before, gap_after, guards, stars])
	root.queue_free()
	await process_frame
	quit(0)


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _fail(reason: String) -> void:
	push_error("STREET EVENTS FAIL: " + reason)
	quit(1)
