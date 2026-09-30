extends SceneTree

## Live physics checks: penetration, solid cover, remote fire, save and effect budgets.
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(scene)
	await _frames(10)
	var player := scene.get_node("Player") as PlayerController
	var weapons := scene.get_node("Weapons") as WeaponSystem
	var wanted := scene.get_node("WantedSystem") as WantedSystem
	wanted.clear_wanted()
	wanted.set_physics_process(false)
	player.set_physics_process(false)
	player.global_position = Vector3(20, 80, 20)
	var origin := player.global_position + Vector3.UP * 1.1
	var pane_a := _pane(scene, origin + Vector3(0, 0, -3))
	var pane_b := _pane(scene, origin + Vector3(0, 0, -5))
	var victim := Pedestrian.new()
	victim.position = player.global_position + Vector3(0, 0, -8)
	scene.add_child(victim)
	victim.set_physics_process(false)
	var wall := _wall(scene, origin + Vector3(0, 0, -12), Vector3(6, 4, 0.5))
	await _frames(3)
	var hit := weapons.ballistics.shoot(origin, Vector3.FORWARD, 20, 30, 50, player)
	if not pane_a.broken or pane_a.visual.visible or not pane_b.broken or int(hit["glass_hits"]) != 2:
		return _fail("two glass panes did not shatter in the same shot")
	if hit["collider"] != victim or not is_equal_approx(victim.health, 80.8) or victim.state != Pedestrian.State.FLEE:
		return _fail("penetration failed to hit/react behind glass (%.2f)" % victim.health)
	hit = weapons.ballistics.shoot(origin, Vector3.FORWARD, 20, 10, 50, player)
	if int(hit["glass_hits"]) != 0 or not is_equal_approx(victim.health, 70.8):
		return _fail("broken glass still blocked/attenuated the next bullet")
	# Save/load real scene panes as well as the test fixture; old saves reset glass.
	var venue_pane := (get_nodes_in_group("breakable_glass")[0] as BreakableGlass)
	venue_pane.shatter()
	scene.set("save_path", "user://test_ballistics_save.json")
	scene.call("_save_game")
	weapons.ballistics.glass_from_save([])
	if pane_a.broken or venue_pane.broken:
		return _fail("old-save glass defaults failed")
	scene.call("_load_game")
	if not pane_a.broken or not venue_pane.broken:
		return _fail("broken glass was not restored from save")
	player.set_physics_process(false)
	wanted.set_physics_process(false)
	# Cover blocks both player and NPC rounds. Move the wall between shooter/target.
	wall.position = origin + Vector3(0, 0, -6)
	await _frames(3)
	var before := victim.health
	hit = weapons.ballistics.shoot(origin, Vector3.FORWARD, 20, 30, 50, player)
	if hit["collider"] != wall or victim.health != before or weapons.ballistics.marks.is_empty():
		return _fail("masonry did not stop the player's bullet/leave a mark")
	victim.position.x += 10.0
	var gunman := Pedestrian.new()
	gunman.enemy = true
	gunman.armed = true
	gunman.position = player.global_position + Vector3(0, 0, -10)
	scene.add_child(gunman)
	gunman.set_physics_process(false)
	gunman.take_damage(10.0, player.global_position)
	if gunman.state != Pedestrian.State.FIGHT:
		return _fail("wounded armed enemy stopped fighting")
	await _frames(3)
	var seeded := RandomNumberGenerator.new()
	seeded.seed = 7401
	var health_before := player.health
	hit = weapons.fire_remote(gunman, origin, 9.0, 35.0, 0.0, seeded, "gunman")
	if hit["collider"] != wall or player.health != health_before:
		return _fail("remote bullet cover: hit %s player %s gunman %s wall %s health %.1f/%.1f" % [str(hit["collider"]), player.global_position, gunman.global_position, wall.global_position, player.health, health_before])
	wall.position.x += 10.0
	# Move the civilian away so it does not intercept the NPC's returning fire.
	await _frames(3)
	hit = weapons.fire_remote(gunman, origin, 9.0, 35.0, 0.0, seeded, "gunman")
	if hit["collider"] != player or not is_equal_approx(player.health, health_before - 9.0):
		return _fail("unobstructed NPC round did not actually strike the player")
	# A muzzle that clips through a wall still cannot shoot through it.
	weapons.give("pistol", 60)
	weapons.select("pistol")
	Input.action_press("aim")
	player.camera_yaw = 0.0
	player.camera_pitch = 0.0
	player._update_camera_orientation()
	await _frames(4)
	weapons._pose_gun(0.0)
	var body_origin := player.global_position + Vector3.UP * 1.3
	var muzzle := weapons.muzzle_position()
	wall.position = body_origin.lerp(muzzle, 0.5)
	(wall.get_child(0) as CollisionShape3D).shape = _box(Vector3(0.08, 4, 4))
	await _frames(3)
	weapons.cooldown = 0.0
	hit = {"collider": weapons.fire()}
	Input.action_release("aim")
	if hit["collider"] != wall:
		return _fail("barrel clipping allowed a shot through the wall")
	# A nearby target behind cover must also be safe from a bat swing.
	player.global_position = origin - Vector3.UP * 1.1
	player.visual.rotation.y = 0.0
	victim.global_position = player.global_position + Vector3.FORWARD * 1.5
	victim.health = 100.0
	victim.dead = false
	victim.state = Pedestrian.State.WANDER
	wall.position = player.global_position + Vector3(0,1,-0.75)
	(wall.get_child(0) as CollisionShape3D).shape = _box(Vector3(3,3,0.1))
	weapons.give("bat",0)
	weapons.select("bat")
	await _frames(3)
	weapons._land_swing()
	if victim.health != 100.0:
		return _fail("bat damaged a civilian through solid cover")
	wall.position.x += 10.0
	await _frames(3)
	weapons._land_swing()
	if victim.health >= 100.0:
		return _fail("unobstructed bat swing missed its nearby target")
	# Bounded allocations under a sustained synthetic firefight.
	wall.position = origin + Vector3(10, 0, -6)
	(wall.get_child(0) as CollisionShape3D).shape = _box(Vector3(6, 4, 0.5))
	await _frames(3)
	for i in range(180):
		weapons.ballistics.shoot(origin + Vector3(10, 0, 0), Vector3.FORWARD, 20, 1, 1, player)
	if weapons.ballistics.marks.size() != Ballistics.MAX_MARKS or weapons.active_impacts > WeaponSystem.MAX_IMPACT_EFFECTS:
		return _fail("combat allocations exceeded their budgets")
	# Exercise mid-session police despawn, including rendered gun overrides/caps,
	# before world shutdown (resource teardown errors must fail the validator).
	for i in range(2):
		var patrol := DriveableVehicle.new()
		patrol.variant = "police_local"
		scene.add_child(patrol)
		patrol.set_physics_process(false)
		patrol.global_position = player.global_position + Vector3(5,0,5 + i * 5)
		patrol.set_headlights(true)
		wanted.police_cars.append(patrol)
		var officer := PoliceOfficer.new()
		officer.wanted = wanted
		officer.player = player
		scene.add_child(officer)
		officer.set_physics_process(false)
		officer.global_position = player.global_position + Vector3(3,0,-3 - i * 3)
		officer.firearm.pose()
		wanted.officers.append(officer)
	await _frames(3)
	wanted.clear_wanted()
	await _frames(3)
	print("BALLISTICS PASS: glass penetration/attenuation, reactions, saved destruction, solid cover, remote hits, muzzle obstruction, melee cover, 180-shot bounded effects")
	scene.queue_free()
	await process_frame
	quit(0)


func _pane(parent: Node, at: Vector3) -> BreakableGlass:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.position = at
	parent.add_child(mesh)
	var pane := BreakableGlass.new()
	pane.configure(mesh, Vector3(3, 3, 0.08))
	parent.add_child(pane, true)
	return pane


func _box(size: Vector3) -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return shape


func _wall(parent: Node, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	var collider := CollisionShape3D.new()
	collider.shape = _box(size)
	body.add_child(collider)
	parent.add_child(body)
	return body


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _fail(reason: String) -> void:
	Input.action_release("aim")
	push_error("BALLISTICS FAIL: " + reason)
	quit(1)
