extends SceneTree

## Chapter two after the bank job (docs/CHAPTER_2.md): Rocío and Curro only offer
## work once Poniente is done; every spawn and marker is on land/road (or at sea for
## boats); La sombra (tail with a timed failure reset, on-foot stake-out, wanted),
## Oro verde (armed farm raid, loaded vehicle, police), Mar de fondo (car chase with
## escape failure, then boat chase); rewards, no replay and save/load of completion.

const CHAPTER_ONE := ["el_recado", "proteccion", "la_cuota", "coche_concejal", "ajuste_de_cuentas", "el_furgon", "golpe_joyeria", "pescadores", "emboscada", "la_copia", "el_atico", "poniente"]
const CHAPTER_TWO := ["la_sombra", "la_finca", "mar_de_fondo"]
const REWARDS := {"la_sombra": 1800, "la_finca": 2500, "mar_de_fondo": 4000}

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
	var weapons := root.get_node("Weapons") as WeaponSystem
	mission.mission_failed.connect(func(reason: String) -> void: failed_reasons.append(reason))
	# --- Contacts and data sanity ----------------------------------------------------
	var rocio := world.get_node_or_null("Rocio") as Pedestrian
	var curro := world.get_node_or_null("Curro") as Pedestrian
	if rocio == null or curro == null or not rocio.mission_contact or not curro.mission_contact:
		return _fail("chapter-two contacts Rocío and Curro were not placed")
	for person: Pedestrian in [rocio, curro]:
		var p := person.global_position
		if world.data.surface_at(p.x, p.z) == "sea" or absf(p.y - world.height_at(p.x, p.z)) > 1.0:
			return _fail("%s is not standing on land (%s)" % [person.name, str(p)])
		if person.display_name.find(" · ") < 0:
			return _fail("%s has no display title" % person.name)
	var problem := _check_positions(world)
	if problem != "":
		return _fail(problem)
	if mission.offer_of("Rocio") != "" or mission.offer_of("Curro") != "":
		return _fail("chapter two offered before chapter one is finished")
	mission.restore_stage(mission.objectives.size())  # El Recado done
	for id in CHAPTER_ONE:
		if id != "poniente":
			mission.completed_missions[id] = true
	if mission.offer_of("Rocio") != "":
		return _fail("La sombra offered before the Poniente finale")
	mission.completed_missions["poniente"] = true
	if mission.offer_of("Rocio") != "la_sombra" or mission.offer_of("Curro") != "" or mission.offer_of("Alba") != "":
		return _fail("after Poniente only Rocío should offer La sombra (Rocío '%s', Curro '%s')" % [mission.offer_of("Rocio"), mission.offer_of("Curro")])
	if not mission.offers().any(func(o: Dictionary) -> bool: return o["letter"] == "R" and o["id"] == "la_sombra"):
		return _fail("Rocío's R blip is not offered")
	var money := int(root.get("money"))
	# --- La sombra (tail, stake-out) --------------------------------------------------
	player.global_position = rocio.global_position + Vector3(0.8, 0.3, 0)
	player._interact()
	if mission.mission_id != "la_sombra" or mission.stage != 1 or mission.suspended_id != "":
		return _fail("talking to Rocío did not start La sombra (%s %d)" % [mission.mission_id, mission.stage])
	var rocio_car := mission.spawned.get("rocio_car") as DriveableVehicle
	await _board(player, rocio_car)
	var lledo := mission.spawned.get("lledo_car") as DriveableVehicle
	if mission.stage != 2 or lledo == null or not lledo.traffic or lledo.occupant_name == "":
		return _fail("La sombra: the accountant's car did not spawn driving (stage %d)" % mission.stage)
	if mission.objective_time_left <= 0.0:
		return _fail("La sombra: the tail has no time limit")
	mission.objective_time_left = 0.001  # lose him: back to the checkpoint
	await _frames(3)
	if mission.stage != 1 or failed_reasons.is_empty() or player.driving_vehicle != null:
		return _fail("La sombra: a lost tail did not fail back to the checkpoint (stage %d)" % mission.stage)
	rocio_car = mission.spawned.get("rocio_car") as DriveableVehicle
	await _board(player, rocio_car)
	lledo = mission.spawned.get("lledo_car") as DriveableVehicle
	if mission.stage != 2 or lledo == null:
		return _fail("La sombra: retry did not restart the tail")
	await _drive_to(rocio_car, lledo.global_position + lledo.global_transform.basis.z * 25.0)
	if mission.stage != 3:
		return _fail("La sombra: catching up with Lledó did not advance (stage %d)" % mission.stage)
	await _drive_to(rocio_car, lledo.global_position + lledo.global_transform.basis.z * 8.0)
	if mission.stage != 4:
		return _fail("La sombra: reading the plate did not advance (stage %d)" % mission.stage)
	wanted.raise_to(1, player.global_position)
	await _drive_to(rocio_car, mission.marker_position())
	if mission.stage != 4:
		return _fail("La sombra: arrived at the meeting with police behind")
	wanted.clear_wanted()
	await _frames(3)
	if mission.stage != 5 or mission.spawned.get("meet_suv") == null or mission.spawned.get("meet_sports") == null:
		return _fail("La sombra: arriving at San Cristóbal did not set up the meeting (stage %d)" % mission.stage)
	await _drive_to(rocio_car, mission.marker_position())
	if mission.stage != 5:
		return _fail("La sombra: the stake-out point was reached by car")
	player._interact()
	await _frames(3)
	await _walk_to(player, mission.marker_position())
	if mission.stage != 6:
		return _fail("La sombra: reaching the Peñón steps on foot did not advance (stage %d)" % mission.stage)
	for i in range(60 * 14):
		await physics_frame
		if mission.stage != 6:
			break
	if mission.stage != 7 or wanted.level < 2:
		return _fail("La sombra: the photos did not get the sergeant's attention (stage %d level %d)" % [mission.stage, wanted.level])
	wanted.clear_wanted()
	await _frames(3)
	player.heal_full()
	await _walk_to(player, rocio.global_position + Vector3(1.5, 0, 0))
	money += REWARDS["la_sombra"]
	if not mission.completed_missions.has("la_sombra") or int(root.get("money")) != money:
		return _fail("La sombra did not pay out (stage %d money %d)" % [mission.stage, int(root.get("money"))])
	# --- Oro verde (farm raid) ---------------------------------------------------------
	if mission.offer_of("Curro") != "la_finca" or mission.offer_of("Rocio") != "":
		return _fail("Oro verde not offered by Curro after La sombra")
	player.global_position = curro.global_position + Vector3(0.8, 0.3, 0)
	player._interact()
	if mission.mission_id != "la_finca" or mission.stage != 1:
		return _fail("talking to Curro did not start Oro verde")
	await _walk_to(player, mission.marker_position())
	if mission.stage != 2 or not weapons.owned.has("smg"):
		return _fail("Oro verde: reaching the farm did not arm the player (stage %d)" % mission.stage)
	var guards: Array[Pedestrian] = []
	for id in ["capataz", "guarda_1", "guarda_2", "guarda_3", "guarda_4", "guarda_5"]:
		var guard := mission.spawned.get(id) as Pedestrian
		if guard == null or not guard.armed or guard.state != Pedestrian.State.FIGHT:
			return _fail("Oro verde: farm guard %s missing or passive" % id)
		var g := guard.global_position
		if absf(g.y - world.height_at(g.x, g.z)) > 1.5:
			return _fail("Oro verde: guard %s spawned off the ground" % id)
		guards.append(guard)
	for guard in guards:
		guard.take_damage(500.0, guard.global_position + Vector3(1, 0, 0))
	await _frames(3)
	if mission.stage != 3:
		return _fail("Oro verde: clearing the farm did not advance (stage %d)" % mission.stage)
	wanted.clear_wanted()
	player.heal_full()
	await _walk_to(player, mission.marker_position())
	if mission.stage != 4:
		return _fail("Oro verde: searching the crates did not advance (stage %d)" % mission.stage)
	var van := mission.spawned.get("farm_van") as DriveableVehicle
	await _board(player, van)
	if mission.stage != 5 or wanted.level < 2:
		return _fail("Oro verde: taking the loaded 4x4 did not bring the sergeant's patrol (stage %d level %d)" % [mission.stage, wanted.level])
	wanted.clear_wanted()
	await _frames(3)
	if mission.stage != 6:
		return _fail("Oro verde: losing the patrol did not advance")
	await _drive_to(van, curro.global_position + Vector3(6.0, 0, 0))
	money += REWARDS["la_finca"]
	if not mission.completed_missions.has("la_finca") or int(root.get("money")) != money:
		return _fail("Oro verde did not pay out (stage %d money %d)" % [mission.stage, int(root.get("money"))])
	player._interact()
	await _frames(3)
	# --- Mar de fondo (car chase + boat chase) -----------------------------------------
	if mission.offer_of("Rocio") != "mar_de_fondo" or mission.offer_of("Curro") != "":
		return _fail("Mar de fondo not offered by Rocío after Oro verde")
	player.global_position = rocio.global_position + Vector3(0.8, 0.3, 0)
	player._interact()
	if mission.mission_id != "mar_de_fondo" or mission.stage != 1:
		return _fail("talking to Rocío did not start Mar de fondo")
	var sports := mission.spawned.get("alba_sports") as DriveableVehicle
	for leftover: DriveableVehicle in [rocio_car, van]:
		if is_instance_valid(leftover) and leftover.global_position.distance_to(sports.global_position) < 4.0:
			return _fail("Mar de fondo: Alba's car spawned on top of an earlier mission car")
	await _board(player, sports)
	var robles := mission.spawned.get("robles_suv") as DriveableVehicle
	if mission.stage != 2 or robles == null or not robles.traffic or robles.health < 1600.0 or not weapons.owned.has("smg"):
		return _fail("Mar de fondo: the sergeant's 4x4 is missing, parked or soft (stage %d)" % mission.stage)
	var fails_before := failed_reasons.size()
	robles.global_position = player.global_position + Vector3(0, 0, 600)  # he gets away
	await _frames(3)
	if mission.stage != 1 or failed_reasons.size() == fails_before or player.driving_vehicle != null:
		return _fail("Mar de fondo: an escaped sergeant did not fail back to the checkpoint (stage %d)" % mission.stage)
	sports = mission.spawned.get("alba_sports") as DriveableVehicle
	await _board(player, sports)
	robles = mission.spawned.get("robles_suv") as DriveableVehicle
	robles.apply_damage(1300.0)
	await _frames(3)
	if mission.stage != 3 or wanted.level < 2:
		return _fail("Mar de fondo: wrecking the sergeant's 4x4 did not advance with two stars (stage %d level %d)" % [mission.stage, wanted.level])
	await _drive_to(sports, mission.marker_position())
	if mission.stage != 4:
		return _fail("Mar de fondo: reaching San Cristóbal beach did not advance (stage %d)" % mission.stage)
	player._interact()
	await _frames(3)
	var rib := mission.spawned.get("paco_rib") as DriveableVehicle
	if rib == null or not rib.boat or absf(rib.global_position.y - DriveableVehicle.WATER_Y) > 0.3:
		return _fail("Mar de fondo: Paco's RIB missing or not afloat")
	player.global_position = rib.global_position + Vector3(2.0, 0.0, 0)
	player._interact()
	await _frames(3)
	var target := mission.spawned.get("cifuentes_rib") as DriveableVehicle
	if mission.stage != 5 or player.driving_vehicle != rib or target == null or target.boat_route.size() < 3:
		return _fail("Mar de fondo: boarding the RIB did not start the boat chase (stage %d)" % mission.stage)
	var start := target.global_position
	for i in range(60 * 3):
		await physics_frame
	if target.global_position.distance_to(start) < 10.0:
		return _fail("Mar de fondo: Cifuentes's boat is not moving")
	target.apply_damage(700.0)
	await _frames(3)
	if mission.stage != 6:
		return _fail("Mar de fondo: stopping Cifuentes's boat did not advance (stage %d)" % mission.stage)
	rib.global_position = target.global_position + Vector3(4, 0, 0)
	await _frames(4)
	if mission.stage < 7:
		return _fail("Mar de fondo: taking the briefcase did not advance (stage %d)" % mission.stage)
	wanted.clear_wanted()
	await _frames(3)
	if mission.stage != 8:
		return _fail("Mar de fondo: losing the police did not advance (stage %d)" % mission.stage)
	player._interact()
	await _frames(3)
	player.heal_full()
	await _walk_to(player, mission.marker_position())
	money += REWARDS["mar_de_fondo"]
	if not mission.completed_missions.has("mar_de_fondo") or int(root.get("money")) != money:
		return _fail("Mar de fondo did not pay out (stage %d money %d)" % [mission.stage, int(root.get("money"))])
	if mission.offer_of("Rocio") != "" or mission.offer_of("Curro") != "":
		return _fail("chapter-two contacts still offer work after Mar de fondo")
	# --- Save/load and no replay --------------------------------------------------------
	root.set("save_path", "user://test_chapter2_save.json")
	root.call("_save_game")
	mission.completed_missions.clear()
	root.call("_load_game")
	for id in CHAPTER_ONE + CHAPTER_TWO:
		if not mission.completed_missions.has(id):
			return _fail("completed mission %s lost on load" % id)
	if mission.offer_of("Rocio") != "" or mission.offer_of("Curro") != "" or int(root.get("money")) != money:
		return _fail("offers or money wrong after load")
	player.global_position = rocio.global_position + Vector3(0.8, 0.3, 0)
	player._interact()
	await _frames(2)
	if mission.mission_id != "mar_de_fondo" or not mission.completed or int(root.get("money")) != money or not mission.dialogue.begins_with("Rocío:"):
		return _fail("talking to Rocío after the chapter replayed a mission or said nothing")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_chapter2_save.json"))
	print("CHAPTER2 PASS: Rocío/Curro unlock after Poniente, positions on land/road/sea, La sombra (tail, timeout reset, stake-out, 2★), Oro verde (6 armed guards, loaded 4x4, patrol), Mar de fondo (4x4 chase + escape reset, RIB chase), rewards %d €, save/load, no replay" % (REWARDS["la_sombra"] + REWARDS["la_finca"] + REWARDS["mar_de_fondo"]))
	root.queue_free()
	await process_frame
	quit(0)


## Every chapter-two spawn and marker must be somewhere the player can reach:
## cars near a driveable road, people on land, boats and their routes in deep water.
func _check_positions(world: SectorWorld) -> String:
	var data := world.data
	for id in CHAPTER_TWO:
		var parsed: Variant = MissionController._read_json("res://data/missions/%s.json" % id)
		if not parsed is Dictionary:
			return "%s.json missing or invalid" % id
		var m: Dictionary = parsed
		if int(m.get("reward", 0)) != int(REWARDS[id]):
			return "%s reward is %d" % [id, int(m.get("reward", 0))]
		var boats := {}
		for spec: Dictionary in m.get("spawns", []):
			var at: Array = spec["at"]
			var x := float(at[0])
			var z := float(at[1])
			if not _in_bounds(x, z):
				return "%s/%s spawns out of bounds" % [id, spec["id"]]
			if str(spec.get("kind", "vehicle")) == "vehicle":
				if bool(DriveableVehicle.variant_spec(str(spec.get("variant", ""))).get("boat", false)):
					boats[str(spec["id"])] = true
					var points: Array = [at] + (spec.get("route", []) as Array)
					for p: Array in points:
						if data.surface_at(float(p[0]), float(p[1])) != "sea" or data.height_at(float(p[0]), float(p[1])) > -0.6:
							return "%s/%s boat point %s is not deep water" % [id, spec["id"], str(p)]
					continue
				var road := world.road_network.nearest(Vector3(x, data.height_at(x, z), z))
				if road.is_empty() or float(road["distance"]) > 25.0:
					return "%s/%s car spawn is far from any road" % [id, spec["id"]]
			if data.surface_at(x, z) == "sea":
				return "%s/%s spawns in the sea" % [id, spec["id"]]
		for objective: Dictionary in m["objectives"]:
			if not objective.has("marker"):
				continue
			var mk: Array = objective["marker"]
			var x := float(mk[0])
			var z := float(mk[1])
			var at_sea := boats.has(str(objective.get("vehicle", "")))
			if not _in_bounds(x, z) or (data.surface_at(x, z) == "sea") != at_sea:
				return "%s marker %s ('%s') is not on %s" % [id, str(mk), objective.get("text", ""), "the sea" if at_sea else "land"]
			if not at_sea and (bool(objective.get("requires_vehicle", false)) or str(objective.get("type", "")) == "reach_area" and not bool(objective.get("requires_on_foot", false))):
				var road := world.road_network.nearest(Vector3(x, data.height_at(x, z), z), false)
				if road.is_empty() or float(road["distance"]) > 40.0:
					return "%s marker %s is far from any street" % [id, str(mk)]
	return ""


func _in_bounds(x: float, z: float) -> bool:
	return x > -620.0 and x < 620.0 and z > -600.0 and z < 470.0


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
	push_error("CHAPTER2 FAIL: " + reason)
	quit(1)
