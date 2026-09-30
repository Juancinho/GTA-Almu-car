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
	var world := root.get_node("District_Altillo") as SectorWorld
	var player := root.get_node("Player") as PlayerController
	var wanted := root.get_node("WantedSystem") as WantedSystem
	var mission := root.get_node("Mission") as MissionController
	var car := world.get_node("FirstCar") as DriveableVehicle
	root.money = 150

	# 1. Punch knocks a pedestrian down and a witnessed assault raises the wanted level.
	var victim := world.get_node("Paseante_05") as Pedestrian
	var spawn := world.anchor("player_spawn")
	victim.global_position = spawn + Vector3(6, 0.1, 0)
	player.global_position = victim.global_position + Vector3(0, 0, 1.2)
	player.visual.rotation.y = 0.0  # facing -Z, toward the victim
	await physics_frame
	victim.temperament = 0.2  # a timid victim stays put long enough for three punches
	victim.set_physics_process(false)
	player.punch()
	for i in range(45):
		await physics_frame
	if victim.state == Pedestrian.State.DOWN or victim.health >= 100.0:
		return _fail("one punch should hurt but not floor a pedestrian")
	for k in range(2):
		player.global_position = victim.global_position + Vector3(0, 0, 1.2)
		player.punch()
		for i in range(45):
			await physics_frame
	victim.set_physics_process(true)
	for i in range(3):
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
	var straight := _straight_segment(world.road_network, 34.0)
	var heading: Vector3 = (straight[1] - straight[0]).normalized()
	car.global_position = straight[0] + Vector3(0, 0.6, 0)
	car.rotation.y = atan2(-heading.x, -heading.z)
	var walker_at: Vector3 = straight[0] + heading * 14.0
	walker.global_position = Vector3(walker_at.x, world.height_at(walker_at.x, walker_at.z) + 0.1, walker_at.z)
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
	var facade := await _street_facade(world)
	var start: Vector3 = facade["mid"] + facade["normal"] * 26.0
	car.global_position = Vector3(start.x, world.height_at(start.x, start.z) + 0.6, start.z)
	car.rotation.y = atan2(facade["normal"].x, facade["normal"].z)  # facing the wall (-normal)
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
	print("DAMAGE PASS: three-punch knockdown, knockdown recovery, run-over report, crash damage, explosion, wasted respawn (money %d)" % root.money)
	root.queue_free()
	for i in range(3):
		await process_frame
	quit(0)


## First graph edge with a clear straight run of at least `length` m: [a, b].
func _straight_segment(network: RoadNetwork, length: float) -> Array[Vector3]:
	for a in network.edges:
		for b in network.edges[a]:
			var pa := network.nodes[a]
			var pb := network.nodes[b]
			if Vector2(pb.x - pa.x, pb.z - pa.z).length() >= length and absf(pb.y - pa.y) < 1.5:
				return [pa, pb]
	return [network.nodes[0], network.nodes[1]]


## A street-facing seafront wall with a clear 26 m run-up (ray hits it first): {mid, normal}.
func _street_facade(world: SectorWorld) -> Dictionary:
	await physics_frame
	var space := world.get_world_3d().direct_space_state
	for b in world.data.raw["buildings"]:
		if str(b["zone"]) != "seafront":
			continue
		var fp: Array = b["footprint"]
		for i in range(fp.size()):
			var a := Vector2(float(fp[i][0]), float(fp[i][1]))
			var c := Vector2(float(fp[(i + 1) % fp.size()][0]), float(fp[(i + 1) % fp.size()][1]))
			if int(b["street_edges"][i]) != 1 or a.distance_to(c) < 12.0:
				continue
			var edge := (c - a).normalized()
			var mid := Vector3((a.x + c.x) * 0.5, 0, (a.y + c.y) * 0.5)
			var normal := Vector3(edge.y, 0, -edge.x)
			var start := mid + normal * 26.0
			var ground := world.height_at(start.x, start.z)
			if absf(ground - world.height_at(mid.x, mid.z)) > 1.5:
				continue
			var query := PhysicsRayQueryParameters3D.create(Vector3(start.x, ground + 1.0, start.z), Vector3(mid.x, ground + 1.0, mid.z) - normal * 0.5)
			var exclusions: Array[RID] = []
			for node in world.get_tree().get_nodes_in_group("terrain"):
				exclusions.append((node as CollisionObject3D).get_rid())
			query.exclude = exclusions
			var hit := space.intersect_ray(query)
			if not hit.is_empty() and (hit["position"] as Vector3).distance_to(Vector3(mid.x, ground + 1.0, mid.z)) < 1.0:
				return {"mid": mid, "normal": normal}
	return {}


func _fail(message: String) -> void:
	push_error("DAMAGE FAIL: " + message)
	quit(1)
