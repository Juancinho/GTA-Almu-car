extends SceneTree

var game: Node3D
var player: PlayerController
var venue: VenueInterior
var mission: MissionController
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(game)
	player = game.get_node("Player") as PlayerController
	mission = game.get_node("Mission") as MissionController
	venue = game.world.venues["casino"] as VenueInterior
	await _frames(10)
	for x in range(-6, 7, 3):
		for z in range(-8, 9, 2):
			var floor_at := venue.room.to_global(VenueInterior.SPECS["casino"]["origin"] + Vector3(x, 0, z))
			if game.world.height_at(floor_at.x, floor_at.z) > floor_at.y:
				return _fail("terrain protrudes through the casino floor")
	var contact := game.world.get_node("Ines") as Pedestrian
	player.global_position = contact.global_position
	player._interact()
	if mission.mission_id != "cuentas_pendientes" or mission.stage != 1:
		return _fail("contact did not offer the new mission")
	player.global_position = venue.exterior_entry
	player._interact()
	await _frames(8)
	# Walking under the upper objective must not complete it from the ground floor.
	mission.set_process(false)
	var landing := venue.point_position("landing")
	player.global_position = Vector3(landing.x, venue.inside_entry.y, landing.z)
	mission._process(0.01)
	if mission.stage != 1:
		return _fail("upper objective completed from the wrong floor")
	player.global_position = venue.inside_entry
	mission.set_process(true)
	await _frames(8)
	for point in [Vector3(2, 0, 6), Vector3(5.25, 0, 7.5), Vector3(5.25, 4.5, -2.8)]:
		await _walk(point)
		if failed:
			return
	if mission.stage != 2 or venue.floor_number(player.global_position) != 1:
		return _fail("stair ascent did not reach the first floor and objective")
	for point in [Vector3(0, 4.5, -2.8), Vector3(-5.7, 4.5, -2.8), Vector3(-5.7, 4.5, 7.1)]:
		await _walk(point)
		if failed:
			return
	var secret_cash: int = game.money
	player._interact()
	player._interact()
	if game.money != secret_cash + 125 or not venue.stash_collected:
		return _fail("hidden archive did not pay exactly once")
	game.save_path = "user://casino_route_test.json"
	game._save_game()
	game.discoveries.clear()
	venue.restore_discoveries({})
	game._load_game()
	player._interact()
	if game.money != secret_cash + 125 or not venue.stash_collected:
		return _fail("discovered secret was not persisted")
	await _walk(Vector3(-5.7, 4.5, -2.8))
	if failed:
		return
	for point in [Vector3(0, 4.5, -2.8), Vector3(0, 4.5, -5.3), Vector3(-3.6, 4.5, -5.3)]:
		await _walk(point)
		if failed:
			return
	game.save_path = "user://casino_route_test.json"
	game._save_game()
	var saved := player.global_position
	player.global_position = venue.exterior_entry
	game._load_game()
	await _frames(8)
	if player.global_position.distance_to(saved) > 0.5 or not venue.room.visible or not venue.contains_player(player.global_position):
		return _fail("upper-floor save did not restore position and visibility")
	player._interact()
	if mission.stage != 3:
		return _fail("examining the ledger did not advance the mission")
	for point in [Vector3(0, 4.5, -5.3), Vector3(0, 4.5, -2.8), Vector3(5.25, 4.5, -2.8), Vector3(5.25, 4.5, -1.3), Vector3(5.25, 0, 7.5), Vector3(2, 0, 6), Vector3(0, 0, 3)]:
		await _walk(point)
		if failed:
			return
	player._interact()
	await _frames(8)
	if mission.stage != 4 or venue.contains_player(player.global_position):
		return _fail("descending and exiting did not reach the handoff")
	player.global_position = contact.global_position
	var money_before: int = game.money
	player._interact()
	if not mission.completed_missions.has("cuentas_pendientes") or game.money != money_before + 650 or mission.mission_id != "el_recado":
		return _fail("reward/completion/resuming the previous mission failed")
	player._interact()
	if game.money != money_before + 650:
		return _fail("contact paid twice")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path))
	print("CASINO ROUTE PASS: contact, wrong-floor rejection, physical stair ascent/descent, hidden archive and saved discovery, office interaction, upper-floor save/load, exit, reward once and mission resume")
	game.queue_free()
	await process_frame
	quit()

func _walk(local: Vector3) -> void:
	var target := venue.room.to_global(VenueInterior.SPECS["casino"]["origin"] + local)
	for i in range(600):
		var direction := target - player.global_position
		direction.y = 0.0
		if direction.length() < 0.22:
			Input.action_release("move_forward")
			await _frames(8)
			if absf(player.global_position.y - target.y) > 0.45:
				_fail("wrong stair height at %s: %s" % [local, venue.room.to_local(player.global_position) - VenueInterior.SPECS["casino"]["origin"]])
			return
		player.camera_yaw = atan2(-direction.x, -direction.z)
		player._update_camera_orientation()
		Input.action_press("move_forward")
		await physics_frame
		await process_frame
	Input.action_release("move_forward")
	_fail("blocked walking to %s at %s" % [local, venue.room.to_local(player.global_position) - VenueInterior.SPECS["casino"]["origin"]])

func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func _fail(reason: String) -> void:
	failed = true
	Input.action_release("move_forward")
	push_error("CASINO ROUTE FAIL: " + reason)
	quit(1)
