extends SceneTree

## Mission system v2: contact offers and unlocks, the three chapter-one missions
## after El Recado (Hielo para el chiringuito, La cuota, El coche del concejal),
## spawned vehicles/enemies, timed objectives and failure reset, a vehicle chase
## target, wanted-level objectives, rewards and save/load of completed missions.

var failed_reasons: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(10):
		await physics_frame
	var world := root.get_node("District_Altillo") as SectorWorld
	var player := root.get_node("Player") as PlayerController
	var mission := root.get_node("Mission") as MissionController
	var wanted := root.get_node("WantedSystem") as WantedSystem
	mission.mission_failed.connect(func(reason: String) -> void: failed_reasons.append(reason))
	if root.get_node_or_null("MissionMarkers") == null:
		return _fail("mission markers missing")
	if mission.offer_of("Paco") != "" or world.get_node_or_null("Paco") == null:
		return _fail("Paco must exist but offer nothing before El Recado")
	var letters := mission.offers().map(func(o: Dictionary) -> String: return str(o["letter"]))
	if not ("A" in letters and "J" in letters):
		return _fail("start offers should be Alba and Marina, got %s" % str(letters))
	mission.restore_stage(mission.objectives.size())  # El Recado done
	if mission.offer_of("Paco") != "hielo" or not mission.offers().any(func(o: Dictionary) -> bool: return o["letter"] == "P"):
		return _fail("Paco's mission not offered after El Recado: %s" % mission.objective_label())
	# --- Hielo para el chiringuito ---------------------------------------------
	var paco := world.get_node("Paco") as Pedestrian
	player.global_position = paco.global_position + Vector3(0.8, 0.3, 0)
	player._interact()
	if mission.mission_id != "hielo" or mission.stage != 1:
		return _fail("talking to Paco did not start Hielo (%s %d)" % [mission.mission_id, mission.stage])
	var suv := mission.spawned.get("paco_suv") as DriveableVehicle
	if suv == null:
		return _fail("Paco's SUV not spawned")
	await _board(player, suv)
	if mission.stage != 2 or mission.objective_time_left <= 0.0:
		return _fail("entering the SUV did not start the timed run (stage %d)" % mission.stage)
	var minimap := (root.get("hud") as GameHud).minimap
	minimap._update_gps()
	if minimap.gps_path.size() < 3:
		return _fail("GPS found no road route to Mercado Azul")
	mission.objective_time_left = 0.01  # the ice melts: failure resets to the SUV
	await _frames(3)
	if mission.stage != 1 or failed_reasons.is_empty() or player.driving_vehicle != null:
		return _fail("timeout did not fail back to the checkpoint")
	suv = mission.spawned.get("paco_suv") as DriveableVehicle
	await _board(player, suv)
	await _drive_to(suv, mission.marker_position())
	if mission.stage != 3:
		return _fail("reaching Mercado Azul did not advance (stage %d)" % mission.stage)
	await _drive_to(suv, mission.marker_position())
	if mission.stage != 4:
		return _fail("returning to the paseo did not advance (stage %d)" % mission.stage)
	player._interact()
	await _walk_to(player, mission.marker_position())
	if mission.stage != 5:
		return _fail("carrying the ice to the bar did not advance (stage %d)" % mission.stage)
	var gorrones := [mission.spawned.get("gorron_1"), mission.spawned.get("gorron_2")]
	for enemy in gorrones:
		if enemy == null or (enemy as Pedestrian).state != Pedestrian.State.FIGHT:
			return _fail("gorrones did not spawn and attack")
	(gorrones[0] as Pedestrian).take_hit(player.global_position, 4.0)
	if (gorrones[0] as Pedestrian).defeated:
		return _fail("a tough enemy went down with one punch")
	for enemy in gorrones:
		for k in range(3):
			(enemy as Pedestrian).take_hit(player.global_position, 4.0)
	await _frames(3)
	if not mission.completed or not mission.completed_missions.has("hielo") or int(root.get("money")) != 300:
		return _fail("Hielo did not complete with its reward (money %d)" % int(root.get("money")))
	# --- La cuota ----------------------------------------------------------------
	var alba := world.get_node("Alba") as Pedestrian
	if mission.offer_of("Alba") != "la_cuota":
		return _fail("La cuota not offered after Hielo")
	player.global_position = alba.global_position + Vector3(0.8, 0.3, 0)
	player._interact()
	if mission.mission_id != "la_cuota" or mission.stage != 1:
		return _fail("La cuota did not start")
	for k in range(3):
		await _walk_to(player, mission.marker_position())
	if mission.stage != 4:
		return _fail("collecting the three envelopes did not advance (stage %d)" % mission.stage)
	var thief := mission.spawned.get("thief_car") as DriveableVehicle
	if thief == null or not thief.traffic or thief.occupant_name == "":
		return _fail("the thief's car did not spawn driving")
	thief.apply_damage(750.0)
	await _frames(3)
	if mission.stage != 5 or thief.traffic:
		return _fail("wrecking the thief's car did not advance (stage %d)" % mission.stage)
	await _walk_to(player, mission.marker_position())
	if mission.stage != 6:
		return _fail("picking up the money did not advance")
	await _walk_to(player, alba.global_position + Vector3(1.5, 0, 0))
	if not mission.completed_missions.has("la_cuota") or int(root.get("money")) != 900:
		return _fail("La cuota did not pay out (money %d)" % int(root.get("money")))
	# --- El coche del concejal -------------------------------------------------------
	player.global_position = alba.global_position + Vector3(0.8, 0.3, 0)
	player._interact()
	if mission.mission_id != "coche_concejal" or mission.stage != 1:
		return _fail("El coche del concejal did not start")
	var sports := mission.spawned.get("councillor_car") as DriveableVehicle
	await _board(player, sports)
	if mission.stage != 2 or wanted.level < 1:
		return _fail("stealing the car did not raise the wanted level (stage %d level %d)" % [mission.stage, wanted.level])
	wanted.clear_wanted()
	await _frames(3)
	if mission.stage != 3:
		return _fail("losing the police did not advance")
	await _drive_to(sports, mission.marker_position())
	if not mission.completed_missions.has("coche_concejal") or int(root.get("money")) != 1700:
		return _fail("El coche del concejal did not pay out (money %d)" % int(root.get("money")))
	# --- Save/load and offers after the chapter --------------------------------
	player._interact()
	root.set("save_path", "user://test_missions_save.json")
	root.call("_save_game")
	mission.completed_missions.clear()
	root.call("_load_game")
	for id in ["el_recado", "hielo", "la_cuota", "coche_concejal"]:
		if not mission.completed_missions.has(id):
			return _fail("completed mission %s lost on load" % id)
	if mission.offer_of("Alba") != "" or mission.offer_of("Marina") != "jaime_playa":
		return _fail("offers after the chapter are wrong")
	# --- Full map and waypoint ------------------------------------------------------
	root.call("_toggle_map")
	var hud := root.get("hud") as GameHud
	if not hud.world_map.visible or not paused:
		return _fail("map did not open and pause")
	var destination := (world.venues["supermarket"] as VenueInterior).exterior_entry
	hud.minimap.set_waypoint(destination)
	if hud.minimap.waypoint_path.size() < 3:
		return _fail("waypoint has no road route")
	root.call("_toggle_map")
	if hud.world_map.visible or paused:
		return _fail("map did not close")
	player.global_position = destination + Vector3(0, 0.4, 0)
	hud.minimap._update_gps()
	if hud.minimap.waypoint != Vector3.INF:
		return _fail("waypoint not cleared on arrival")
	print("MISSIONS PASS: offers/unlocks, Hielo (timed run, fail reset, fight), La cuota (collection, chase target), El coche del concejal (theft, wanted, workshop), rewards 1700 €, save/load, map + waypoint")
	root.queue_free()
	await process_frame
	quit(0)


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _board(player: PlayerController, car: DriveableVehicle) -> void:
	player.global_position = car.global_position + car.global_transform.basis.x * 2.2 + Vector3(0, 0.3, 0)
	player._interact()
	await _frames(3)


func _drive_to(car: DriveableVehicle, target: Vector3) -> void:
	car.global_position = target + Vector3(0, 0.6, 0)
	car.speed = 0.0
	await _frames(4)


func _walk_to(player: PlayerController, target: Vector3) -> void:
	player.global_position = target + Vector3(0, 0.4, 0)
	player.velocity = Vector3.ZERO
	await _frames(4)


func _fail(reason: String) -> void:
	push_error("MISSIONS FAIL: " + reason)
	quit(1)
