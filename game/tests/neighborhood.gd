extends SceneTree

var game: Node3D
var player: PlayerController
var venue: VenueInterior
var failed := false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	player = game.player
	await frames(12)
	var world: SectorWorld = game.world
	for kind in ["bakery", "pharmacy", "barber", "gym", "record_shop", "clothing", "residence_altillo", "residence_centro", "residence_mirador"]:
		venue = world.venues[kind]
		var polygon := PackedVector2Array()
		for building in world.data.raw["buildings"]:
			if int(building["id"]) == venue.source_building_id:
				for p in building["footprint"]:
					polygon.append(Vector2(p[0], p[1]))
		var origin: Vector3 = VenueInterior.SPECS[kind]["origin"]
		for x in [-6.8, 0.0, 6.8]:
			for z in [-8.8, 0.0, 8.8]:
				var at := venue.room.to_global(origin + Vector3(x, 0.1, z))
				if not Geometry2D.is_point_in_polygon(Vector2(at.x, at.z), polygon) or world.height_at(at.x, at.z) > at.y:
					return fail(kind + " floor outside footprint/below terrain at %s ground=%.2f inside=%s" % [at, world.height_at(at.x, at.z), Geometry2D.is_point_in_polygon(Vector2(at.x, at.z), polygon)])
		player.global_position = venue.exterior_entry
		player._interact()
		if not venue.contains_player(player.global_position):
			return fail(kind + " entry unavailable")
		await frames(8)
		if player.global_position.y < venue.inside_entry.y - 0.5:
			return fail(kind + " floor not supporting player")
		if bool(VenueInterior.SPECS[kind].get("residential", false)):
			for point in [Vector3(2,0,6), Vector3(5.25,0,7.5), Vector3(5.25,4.5,-2.8), Vector3(0,4.5,-2.8), Vector3(0,4.5,-6), Vector3(-2.3,4.5,-6)]:
				await walk(point)
				if failed:
					return
			player.health = 25.0
			player._interact()
			if player.health != PlayerController.MAX_HEALTH:
				return fail(kind + " bed interaction failed")
			for point in [Vector3(0,4.5,-6), Vector3(0,4.5,2.8), Vector3(0,4.5,6.4), Vector3(-2.3,4.5,6.4)]:
				await walk(point)
				if failed:
					return
			player.health = 30.0
			player._interact()
			if player.health != PlayerController.MAX_HEALTH:
				return fail(kind + " second apartment bed unavailable")
			for point in [Vector3(0,4.5,6.4), Vector3(0,4.5,-2.8), Vector3(5.25,4.5,-2.8), Vector3(5.25,0,7.5), Vector3(2,0,6), Vector3(0,0,3)]:
				await walk(point)
				if failed:
					return
		else:
			game.money = 200
			player.health = 30.0
			player.global_position = venue.service_point
			var model_before := player.human.model_name
			player._interact()
			if kind in ["barber", "clothing"] and (player.human.model_name == model_before or game.money >= 200):
				return fail(kind + " style transaction failed")
			if kind in ["bakery", "pharmacy", "gym"] and (player.health <= 30.0 or game.money >= 200):
				return fail(kind + " health transaction failed")
			if kind == "record_shop" and not (venue.room.get_node("ListeningStation") as AudioStreamPlayer3D).playing:
				return fail("original listening session unavailable")
			player.global_position = venue.inside_entry
		player._interact()
		if venue.contains_player(player.global_position):
			return fail(kind + " exit unavailable")
	var skaters := 0
	var bathers := 0
	var workers := 0
	var dancers := 0
	for person in get_nodes_in_group("pedestrians"):
		skaters += int(person.activity == "skate")
		bathers += int(person.outfit == "adult_swimwear")
		workers += int(person.activity == "work")
		dancers += int(person.activity == "dance")
	if skaters < 4 or bathers < 4 or workers < 12 or dancers != 4:
		return fail("ambient population missing %s" % [Vector4(skaters,bathers,workers,dancers)])
	game.save_path = "user://neighborhood_test.json"
	var style := player.human.model_name
	game._save_game()
	player.human.change_model("male_casual")
	game._load_game()
	game.weapons.give("pistol",24)
	game.weapons.select("pistol")
	game.weapons._pose_gun(0.0)
	if player.human.model_name != style:
		return fail("outfit not saved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path))
	print("NEIGHBORHOOD PASS: nine fitted interiors, real entry/exit, six services, three stair/apartment routes, recovery, style save, skaters=%d bathers=%d workers=%d dancers=%d" % [skaters,bathers,workers,dancers])
	game.queue_free()
	await process_frame
	quit()

func walk(local: Vector3) -> void:
	var target := venue.room.to_global(VenueInterior.SPECS[venue.kind]["origin"] + local)
	for i in range(500):
		var offset := target - player.global_position
		offset.y = 0
		if offset.length() < 0.23:
			Input.action_release("move_forward")
			await frames(8)
			if absf(player.global_position.y - target.y) > 0.45:
				fail("wrong floor " + venue.kind + str(local))
			return
		player.camera_yaw = atan2(-offset.x,-offset.z)
		player._update_camera_orientation()
		Input.action_press("move_forward")
		await frames(1)
	var contacts := []
	for index in range(player.get_slide_collision_count()):
		var body := player.get_slide_collision(index).get_collider() as Node3D
		contacts.append(str(body.get_path()) + " local=" + str(body.position - VenueInterior.SPECS[venue.kind]["origin"]))
	fail("blocked " + venue.kind + str(local) + " at " + str(venue.room.to_local(player.global_position)-VenueInterior.SPECS[venue.kind]["origin"]) + str(contacts))

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func fail(reason: String) -> void:
	failed = true
	Input.action_release("move_forward")
	push_error("NEIGHBORHOOD FAIL: " + reason)
	quit(1)
