extends SceneTree

## GAME-007 checks: punch, run-over, crash damage, burning/explosion, player death
## and hospital respawn with fee. Uses the real main scene and public APIs.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(30):
		await physics_frame
	var world := root.get_node("District_Altillo")
	var player := root.get_node("Player") as PlayerController
	var wanted := root.get_node("WantedSystem") as WantedSystem
	var mission := root.get_node("Mission") as MissionController
	var car := world.get_node("FirstCar") as DriveableVehicle
	root.money = 150

	# 1. Punch knocks a pedestrian down and a witnessed assault raises the wanted level.
	var victim := world.get_node("Paseante_05") as Pedestrian
	victim.global_position = Vector3(-30, 0.1, 24)
	player.global_position = victim.global_position + Vector3(0, 0, 1.2)
	player.visual.rotation.y = 0.0  # facing -Z, toward the victim
	await physics_frame
	player.punch()
	for i in range(30):
		await physics_frame
	if victim.state != Pedestrian.State.DOWN or wanted.level < 1:
		return _fail("punch: state=%d wanted=%d" % [victim.state, wanted.level])
	for i in range(int(7.5 * 60)):
		await physics_frame
	if victim.state == Pedestrian.State.DOWN:
		return _fail("knocked pedestrian never got up")
	wanted.clear_wanted()
	wanted.incident_cooldown = 0.0

	# 2. Running someone over knocks them down and is reported.
	var walker := world.get_node("Paseante_07") as Pedestrian
	player.global_position = car.global_position + Vector3(2, 0, 0)
	player._interact()
	car.global_position = Vector3(-60, 0.2, 8)
	car.rotation.y = PI * 0.5  # heading west (-X)
	walker.global_position = Vector3(-72, 0.1, 8)
	walker.state = Pedestrian.State.IDLE
	walker.destination = walker.global_position
	await physics_frame
	var crimes := []
	wanted.crime_reported.connect(func(kind: String, _w: bool) -> void: crimes.append(kind))
	Input.action_press("move_forward")
	for i in range(90):
		await physics_frame
		if walker.state == Pedestrian.State.DOWN:
			break
	Input.action_release("move_forward")
	if walker.state != Pedestrian.State.DOWN or not crimes.has("atropello"):
		return _fail("run over: state=%d crimes=%s" % [walker.state, crimes])
	wanted.clear_wanted()

	# 3. A hard crash into a façade damages the car.
	car.speed = 0.0
	car.rotation.y = 0.0  # heading -Z toward the Casa_-16_-33 façade at z = -25.5
	car.global_position = Vector3(-16.0, 0.3, -2.0)
	var health_before := car.health
	Input.action_press("move_forward")
	for i in range(150):
		await physics_frame
	Input.action_release("move_forward")
	if car.health >= health_before:
		return _fail("crash did not damage the car (health %.0f)" % car.health)

	# 4. A wrecked car burns, explodes, knocks people down and kills its driver.
	var bystander := world.get_node("Paseante_08") as Pedestrian
	var money_before: int = root.money
	car.apply_damage(DriveableVehicle.MAX_HEALTH)
	if car.damage_fx.fire.emitting != true:
		return _fail("burning car shows no fire")
	while car.burn_timer > 0.1:
		await physics_frame
	bystander.global_position = car.global_position + Vector3(0, 0, 4)  # street side, away from the façade
	bystander.state = Pedestrian.State.IDLE
	bystander.destination = bystander.global_position
	for i in range(30):
		await physics_frame
	if not car.destroyed or bystander.state != Pedestrian.State.DOWN or not player.dead:
		return _fail("explosion: destroyed=%s bystander=%d player_dead=%s" % [car.destroyed, bystander.state, player.dead])

	# 5. Death respawns at the health centre with full health and a fee.
	for i in range(int(3.5 * 60)):
		await physics_frame
	if player.dead or player.health < PlayerController.MAX_HEALTH or player.global_position.distance_to(root.HOSPITAL_RESPAWN) > 3.0:
		return _fail("respawn: dead=%s health=%.0f pos=%s" % [player.dead, player.health, player.global_position])
	if root.money != maxi(0, money_before - root.HOSPITAL_FEE):
		return _fail("hospital fee not charged: %d -> %d" % [money_before, root.money])
	if car.destroyed:
		return _fail("mission car not restored after respawn")
	print("DAMAGE PASS: punch, knockdown recovery, run-over report, crash damage, explosion, wasted respawn (money %d)" % root.money)
	root.queue_free()
	for i in range(3):
		await process_frame
	quit(0)


func _fail(message: String) -> void:
	push_error("DAMAGE FAIL: " + message)
	quit(1)
