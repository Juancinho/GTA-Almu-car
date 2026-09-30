extends SceneTree

## Weapons: pickups, aiming camera, pistol hits and kills, ammo and reload,
## vehicle damage, gunfire panic/police report, bat swing and save/load.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(10):
		await physics_frame
	var world := root.get_node("District_Altillo") as SectorWorld
	var player := root.get_node("Player") as PlayerController
	var weapons := root.get_node_or_null("Weapons") as WeaponSystem
	var wanted := root.get_node("WantedSystem") as WantedSystem
	if weapons == null or weapons.pickups.size() < 6 or weapons.current != "fists":
		return _fail("weapon system or pickups missing")
	var pistol_pickup: Dictionary = weapons.pickups.filter(func(p: Dictionary) -> bool: return p["weapon"] == "pistol")[0]
	player.global_position = (pistol_pickup["node"] as Node3D).global_position + Vector3(0, 0.3, 0)
	await _frames(3)
	if weapons.current != "pistol" or int(weapons.clip["pistol"]) != 12 or int(weapons.reserve["pistol"]) != 24 or (pistol_pickup["node"] as Node3D).visible:
		return _fail("pistol pickup did not arm the player (%s %s)" % [weapons.current, weapons.ammo_text()])
	# A civilian 9 m ahead on open ground.
	var person := _victim(world, player)
	if person == null:
		return _fail("no civilian to test with")
	Input.action_press("aim")
	await _frames(12)
	if not weapons.aiming or player.camera_arm.spring_length > 3.0:
		return _fail("aiming did not tighten the camera")
	var shots := 0
	while not person.dead and shots < 6:
		_aim_at(player, person.global_position + Vector3(0, 1.1, 0))
		await _frames(2)
		weapons.cooldown = 0.0
		weapons.fire()
		shots += 1
		await _frames(2)
	Input.action_release("aim")
	if not person.dead:
		return _fail("three pistol hits did not kill (health %.0f after %d shots)" % [person.health, shots])
	if int(weapons.clip["pistol"]) != 12 - shots:
		return _fail("ammo not spent")
	weapons.clip["pistol"] = 0
	weapons.cooldown = 0.0
	weapons.fire()
	if weapons.reload_timer <= 0.0:
		return _fail("empty clip did not start a reload")
	for i in range(100):
		await physics_frame
	if int(weapons.clip["pistol"]) != 12 or int(weapons.reserve["pistol"]) != 12:
		return _fail("reload did not refill (%s)" % weapons.ammo_text())
	var car := world.get_node("FirstCar") as DriveableVehicle
	player.global_position = car.global_position + car.global_transform.basis.z * 7.0 + Vector3(0, 0.3, 0)
	await _frames(2)
	_aim_at(player, car.global_position + Vector3(0, 0.7, 0))
	await _frames(2)
	weapons.cooldown = 0.0
	var hit := weapons.fire()
	if hit != car or car.health >= DriveableVehicle.MAX_HEALTH:
		return _fail("shooting the car did not damage it (hit %s)" % str(hit))
	weapons.give("bat", 0)
	weapons.select("bat")
	var target := _victim(world, player)
	player.global_position = target.global_position + Vector3(0, 0.3, 1.5)
	player.visual.rotation.y = 0.0  # facing -Z, towards the target
	weapons.cooldown = 0.0
	weapons.swing()
	for i in range(30):
		await physics_frame
	if target.state != Pedestrian.State.DOWN:
		return _fail("bat swing did not knock the civilian down")
	# Holdup: aim at the Mercado Azul counter for four seconds.
	wanted.clear_wanted()
	weapons.select("pistol")
	var shop := world.venues["supermarket"] as VenueInterior
	player.global_position = shop.inside_entry
	await _frames(2)
	var money_before := int(root.get("money"))
	Input.action_press("aim")
	for i in range(60 * 5):
		_aim_at(player, shop.service_point + Vector3(0, 1.0, 0))
		await physics_frame
		if int(root.get("money")) > money_before:
			break
	Input.action_release("aim")
	if int(root.get("money")) <= money_before or wanted.level < 2:
		return _fail("aiming at the shop counter did not complete a holdup (money %d, level %d)" % [int(root.get("money")), wanted.level])
	root.set("save_path", "user://test_weapons_save.json")
	root.call("_save_game")
	weapons.from_save({})
	root.call("_load_game")
	if not weapons.owned.has("pistol") or not weapons.owned.has("bat") or int(weapons.reserve["pistol"]) != 12:
		return _fail("weapons not restored from the save")
	print("WEAPONS PASS: pickup, aim camera, shop holdup, %d-shot kill, ammo/reload, vehicle damage, bat, save/load (wanted %d)" % [shots, wanted.level])
	root.queue_free()
	await process_frame
	quit(0)


func _victim(world: SectorWorld, player: PlayerController) -> Pedestrian:
	var best: Pedestrian
	var best_d := INF
	for node in world.get_tree().get_nodes_in_group("pedestrians"):
		var p := node as Pedestrian
		if p == null or p.mission_contact or p.dead or p.state == Pedestrian.State.DOWN:
			continue
		var d := p.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = p
	if best == null:
		return null
	best.set_physics_process(false)  # hold still for the test
	var toward := (player.global_position - best.global_position)
	toward.y = 0.0
	player.global_position = best.global_position + toward.normalized() * 9.0 + Vector3(0, 0.3, 0)
	return best


func _aim_at(player: PlayerController, point: Vector3) -> void:
	for k in range(3):
		var from := player.camera_arm.global_position  # the view line runs through the arm origin
		var flat := Vector2(point.x - from.x, point.z - from.z)
		player.camera_yaw = atan2(-(point.x - from.x), -(point.z - from.z))
		player.camera_pitch = -atan2(from.y - point.y, flat.length())
		player._update_camera_orientation()
		player.camera.force_update_transform()


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _fail(reason: String) -> void:
	Input.action_release("aim")
	push_error("WEAPONS FAIL: " + reason)
	quit(1)
