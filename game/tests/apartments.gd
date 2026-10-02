extends SceneTree

## Walk-in residential blocks: the player walks through the street portal into
## the lobby, climbs the real stair (flight, half landing, flight) to the first
## floor, takes the lift, sleeps in the safehouse (save + heal), opens the stash,
## and plays "El ático de Ferrer" up to the safe (guards stand on the top floor).


func _initialize() -> void:
	call_deferred("_run")


var player: PlayerController


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(8):
		await physics_frame
	var world := root.get_node("District_Altillo") as SectorWorld
	player = root.get_node("Player") as PlayerController
	var mission := root.get_node("Mission") as MissionController
	var wanted := root.get_node("WantedSystem") as WantedSystem
	if not ("apartments" in world) or world.apartments.size() != 3:
		return _fail("residential blocks missing")
	var home: Node3D = world.apartments["residencial_poniente"]
	var tower: Node3D = world.apartments["torre_mediterraneo"]
	var fh := 3.1
	# 1. Walk in from the pavement through the portal (no teleport).
	player.global_position = home.exterior_entry + Vector3(0, 0.3, 0)
	await _frames(4)
	await _walk(-home.exterior_normal, 150)
	if not home.contains_player(player.global_position) or home.level_at(player.global_position) != 0:
		return _fail("could not walk into the portal (at %s)" % home.to_local(player.global_position))
	# 2. Climb: up flight A to the half landing, across, up flight B to floor 1.
	player.global_position = home.to_global(Vector3(1.5, 0.15, -7.6))
	await _frames(3)
	await _walk(home.global_transform.basis * Vector3(0, 0, -1), 110)
	var local := home.to_local(player.global_position)
	if absf(local.y - fh * 0.5) > 0.35 or local.z > -12.6:
		return _fail("flight A did not lead to the half landing (local %s)" % local)
	await _walk(home.global_transform.basis * Vector3(1, 0, 0), 40)
	await _walk(home.global_transform.basis * Vector3(0, 0, 1), 110)
	local = home.to_local(player.global_position)
	if home.level_at(player.global_position) != 1 or absf(local.y - fh) > 0.3:
		return _fail("flight B did not reach the first floor (local %s)" % local)
	# 3. Lift from the portal to the key floor and back.
	player.global_position = home.point("lift_0") + Vector3(0, 0.15, 0)
	await _frames(2)
	player._interact()
	await _frames(3)
	if home.level_at(player.global_position) != 1:
		return _fail("lift did not go up")
	player.global_position = tower.point("lift_0") + Vector3(0, 0.15, 0)
	await _frames(2)
	player._interact()
	await _frames(20)
	if tower.level_at(player.global_position) != 5 or absf(tower.to_local(player.global_position).y - 5 * fh) > 0.3:
		return _fail("tower lift did not reach the penthouse floor")
	# 4. Safehouse: bed saves and heals, stash gives a pistol.
	root.set("save_path", "user://test_apartments_save.json")
	var before_hours := float(root.day_night.hours)
	player.health = 40.0
	player.global_position = home.point("bed") + Vector3(0, 0.15, 0)
	await _frames(3)
	if home.prompt_text(player) == "":
		return _fail("no prompt at the bed")
	player._interact()
	if player.health < PlayerController.MAX_HEALTH or absf(fposmod(float(root.day_night.hours) - before_hours, 24.0) - 8.0) > 0.1:
		return _fail("sleeping did not heal / pass the night")
	if not FileAccess.file_exists("user://test_apartments_save.json"):
		return _fail("sleeping did not save")
	player.global_position = home.point("stash") + Vector3(0, 0.15, 0)
	await _frames(2)
	player._interact()
	if not root.weapons.owned.has("pistol"):
		return _fail("stash gave nothing")
	# 4b. Burglary: force a neighbour's door on the second floor, once.
	var money_before := int(root.get("money"))
	player.global_position = home.point("door:2ºA") + Vector3(0, 0.15, 0)
	await _frames(2)
	if not home.prompt_text(player).begins_with("E · Forzar"):
		return _fail("no burglary prompt at a neighbour's door")
	player._interact()
	if int(root.get("money")) <= money_before or home.can_burgle("2ºA"):
		return _fail("burglary gave no loot or no cooldown")
	wanted.clear_wanted()
	# 4c. Garage: a car left in the bay is kept by the save and comes back on load.
	var car := world.get_node("FirstCar") as DriveableVehicle
	car.global_position = home.garage_spot + Vector3(0, 0.5, 0)
	car.rotation.y = home.garage_yaw
	car.speed = 0.0
	await _frames(30)
	if home.garage_variant != car.variant:
		return _fail("car left in the garage bay was not stored")
	root.call("_save_game")
	car.global_position += Vector3(0, 0, 60.0)
	await _frames(30)
	if home.garage_variant != "":
		return _fail("driving away did not free the garage")
	root.call("_load_game")
	await _frames(10)
	if home.garage_car == null or home.garage_car.global_position.distance_to(home.garage_spot) > 2.0:
		return _fail("garage car not restored on load")
	# 4d. Mar Azul: the builder's safe pays out black money and trips the alarm.
	var office: Node3D = world.apartments["edificio_mar_azul"]
	player.global_position = office.point("office_safe") + Vector3(0, 0.15, 0)
	await _frames(2)
	var cash := int(root.get("money"))
	player._interact()
	if int(root.get("money")) < cash + 900 or wanted.level < 2 or office.can_burgle("office_safe"):
		return _fail("Mar Azul safe heist did not pay / raise the alarm")
	wanted.clear_wanted()
	# 5. The mission: portal, penthouse, guards, safe.
	if not mission.load_mission("el_atico", false):
		return _fail("el_atico mission missing")
	mission.restore_stage(1)
	player.global_position = tower.exterior_entry + Vector3(0, 0.2, 0)
	await _frames(4)
	if mission.stage != 2:
		return _fail("reaching the portal did not advance (stage %d)" % mission.stage)
	var guard := mission.spawned.get("guard_1") as Pedestrian
	if guard == null:
		return _fail("guards not spawned")
	player.global_position = tower.point("flat_door") + Vector3(0, 0.15, 0)
	await _frames(40)
	if mission.stage != 3:
		return _fail("reaching the penthouse door did not advance (stage %d)" % mission.stage)
	var guard_level: int = tower.level_at(guard.global_position)
	if guard_level != 5 or not tower.contains_player(guard.global_position):
		return _fail("guard is not on the penthouse floor (level %d, %s)" % [guard_level, tower.to_local(guard.global_position)])
	for id in ["guard_1", "guard_2", "guard_3"]:
		var person := mission.spawned.get(id) as Pedestrian
		person.take_damage(500.0, person.global_position + Vector3(1, 0, 0))
	await _frames(4)
	if mission.stage != 4:
		return _fail("beating the guards did not advance (stage %d)" % mission.stage)
	player.global_position = tower.point("safe") + Vector3(0, 0.15, 0)
	await _frames(3)
	player._interact()
	if mission.stage != 5 or wanted.level < 2:
		return _fail("opening the safe did not advance / raise the alarm (stage %d, wanted %d)" % [mission.stage, wanted.level])
	print("APARTMENTS PASS: walked in through the portal, stair to floor 1, lifts, safehouse bed saved + healed, stash, burglary, garage kept in the save, Mar Azul safe, El ático up to the safe with guards upstairs")
	root.queue_free()
	await process_frame
	quit(0)


## Walks the player with the real controls in a world direction.
func _walk(direction: Vector3, frames: int) -> void:
	var flat := Vector3(direction.x, 0, direction.z).normalized()
	player.camera_yaw = atan2(-flat.x, -flat.z)
	player._update_camera_orientation()
	var forward := -player.camera.global_transform.basis.z
	if Vector2(forward.x, forward.z).normalized().dot(Vector2(flat.x, flat.z)) < 0.9:
		player.camera_yaw = atan2(flat.x, flat.z)
		player._update_camera_orientation()
	Input.action_press("move_forward")
	for i in range(frames):
		await physics_frame
	Input.action_release("move_forward")
	for i in range(8):
		await physics_frame


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _fail(reason: String) -> void:
	push_error("APARTMENTS FAIL: " + reason)
	quit(1)
