extends SceneTree

## Motorbikes and scooters: a parked bike near the start is boarded with E, out-
## accelerates the mission car over the same time on the same open straight, leans
## into a turn while the body stays upright and grounded, can be left again, and a
## head-on crash into a façade throws the player off (hurt, knocked down). A car
## ploughing into a bike unseats its NPC rider.

const ACCEL_SECONDS := 1.6


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(20):
		await physics_frame
	var world := root.get_node("District_Altillo") as SectorWorld
	var player := root.get_node("Player") as PlayerController
	var car := world.get_node("FirstCar") as DriveableVehicle
	var bike: DriveableVehicle
	var parked := 0
	for node in get_nodes_in_group("vehicles"):
		var vehicle := node as DriveableVehicle
		if vehicle.bike and not vehicle.traffic:
			parked += 1
			if vehicle.variant == "moto_naked" and bike == null:
				bike = vehicle
	if bike == null or parked < 2:
		return _fail("no parked motorbike near the start (%d parked bikes)" % parked)
	if bike.global_position.distance_to(world.anchor("player_spawn")) > 40.0:
		return _fail("parked bike is far from the start: %s" % str(bike.global_position))
	var traffic_bikes := get_nodes_in_group("vehicles").filter(func(v: Node) -> bool: return (v as DriveableVehicle).bike and (v as DriveableVehicle).traffic)
	if traffic_bikes.is_empty():
		return _fail("no bikes in the traffic mix")
	# Board the parked bike like a car (E next to it).
	player.global_position = bike.global_position + bike.global_transform.basis.z * 1.7
	await physics_frame
	player._interact()
	if player.driving_vehicle != bike or bike.driver != player or bike.occupant == null or not bike.occupant.visible:
		return _fail("boarding the parked bike failed")
	# Rider astride: hands near the bars, hips on the seat.
	await physics_frame
	var rig := bike.occupant.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var grip: Vector3 = DriveableVehicle.BikeModel.geometry(bike.bike_kind)["grip"]
	for side in ["L", "R"]:
		var palm := bike.to_local(rig.to_global(rig.get_bone_global_pose(rig.find_bone("Palm." + side)).origin))
		var target := Vector3(grip.x * (-1.0 if side == "L" else 1.0), grip.y, grip.z)
		if palm.distance_to(target) > 0.3:
			return _fail("rider hand %s far from the grip: %s vs %s" % [side, str(palm), str(target)])
	player._interact()
	# Quiet world: no traffic or people wandering into the test straights.
	for node in get_nodes_in_group("pedestrians"):
		(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(node as Node3D).position.y -= 500.0
	for node in get_nodes_in_group("vehicles"):
		if node != car and node != bike:
			(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
			(node as Node3D).position.y -= 500.0
	await physics_frame
	var lane := _open_straight(world)
	if lane.is_empty():
		return _fail("no open straight found for the acceleration run")
	var start: Vector3 = lane[0]
	var heading: Vector3 = lane[1]
	# Mission car over ACCEL_SECONDS.
	var car_speed: float = await _accelerate(player, car, world, start, heading)
	player._interact()
	car.global_position.y -= 500.0
	car.process_mode = Node.PROCESS_MODE_DISABLED
	# The bike over the same time, then a right-hand turn: it must lean.
	var stats := {"frames": 0, "floor": 0, "max_air": 0.0, "max_body_tilt": 0.0}
	var bike_speed: float = await _accelerate(player, bike, world, start, heading, stats)
	if bike_speed < car_speed + 4.0 or bike_speed < 26.0:
		return _fail("bike accelerates no better than a car: bike %.1f m/s vs car %.1f m/s after %.1f s" % [bike_speed, car_speed, ACCEL_SECONDS])
	var lean_node := bike.get_node("CarVisual/Lean") as Node3D
	var max_roll := 0.0
	Input.action_press("move_forward")
	Input.action_press("move_right")
	for i in range(24):
		await physics_frame
		_sample(bike, world, stats)
		max_roll = maxf(max_roll, -lean_node.rotation.z)
	Input.action_release("move_right")
	Input.action_release("move_forward")
	Input.action_press("brake")
	for i in range(60):
		await physics_frame
		_sample(bike, world, stats)
	Input.action_release("brake")
	if max_roll < 0.12:
		return _fail("bike did not lean into the right turn (max roll %.2f rad)" % max_roll)
	if absf(lean_node.rotation.z) > 0.2:
		return _fail("bike stayed leaned after the turn (%.2f rad)" % lean_node.rotation.z)
	var on_floor := float(stats["floor"]) / maxf(1.0, float(stats["frames"]))
	if on_floor < 0.85 or float(stats["max_air"]) > 1.0 or float(stats["max_body_tilt"]) > 0.01:
		return _fail("bike not upright/grounded: on floor %.0f%%, max height %.2f m, body tilt %.3f" % [on_floor * 100.0, stats["max_air"], stats["max_body_tilt"]])
	# Get off.
	player._interact()
	await physics_frame
	if player.driving_vehicle != null or bike.driver != null or bike.occupant.visible or player.global_position.distance_to(bike.global_position) > 3.0:
		return _fail("exiting the bike failed")
	# Head-on into a façade at speed: thrown off, hurt and knocked down.
	var wall := _wall_run(world)
	if wall.is_empty():
		return _fail("no façade found for the crash run")
	bike.global_position = wall[0]
	bike.rotation = Vector3(0.0, atan2(-(wall[1] as Vector3).x, -(wall[1] as Vector3).z), 0.0)
	bike.reset_physics_interpolation()
	bike.fall_speed = 0.0
	await physics_frame
	player.global_position = bike.global_position + bike.global_transform.basis.x * 1.4
	player._interact()
	if player.driving_vehicle != bike:
		return _fail("could not re-board the bike for the crash run")
	var health_before := player.health
	bike.speed = 24.0
	Input.action_press("move_forward")
	var thrown := false
	for i in range(90):
		await physics_frame
		if player.driving_vehicle == null:
			thrown = true
			break
	Input.action_release("move_forward")
	if not thrown:
		return _fail("crash into the wall did not throw the rider (bike speed %.1f, at %s)" % [bike.speed, str(bike.global_position)])
	if player.health >= health_before or player.knocked_timer <= 0.0 or not bike.fallen or player.global_position.distance_to(bike.global_position) > 4.0:
		return _fail("crash ejection incomplete: health %.0f->%.0f knocked %.2f fallen %s distance %.1f" % [health_before, player.health, player.knocked_timer, bike.fallen, player.global_position.distance_to(bike.global_position)])
	for i in range(110):
		await physics_frame
	if player.knocked_timer > 0.0 or bike.driver != null:
		return _fail("player did not get up after the fall")
	var lying := absf(lean_node.rotation.z)
	# A car hitting a bike at speed unseats its NPC rider.
	var npc_bike := traffic_bikes[0] as DriveableVehicle
	npc_bike.process_mode = Node.PROCESS_MODE_INHERIT
	npc_bike.traffic = false
	npc_bike.global_position = start + heading * 20.0 + Vector3(0, 0.3, 0)
	npc_bike.rotation = Vector3(0.0, atan2(-heading.x, -heading.z), 0.0)
	npc_bike.reset_physics_interpolation()
	npc_bike.speed = 0.0
	car.process_mode = Node.PROCESS_MODE_INHERIT
	car.repair()
	car.global_position = start + heading * 8.0 + Vector3(0, 0.4, 0)
	car.rotation = npc_bike.rotation
	car.reset_physics_interpolation()
	for i in range(10):
		await physics_frame
	var rider_name := npc_bike.occupant_name
	if rider_name == "":
		return _fail("traffic bike has no rider")
	var unseated := false
	for i in range(80):
		car.speed = 16.0
		await physics_frame
		if npc_bike.occupant_name == "":
			unseated = true
			break
	var ejected := world.get_node_or_null("Conductor_" + str(npc_bike.name)) as Pedestrian
	if not unseated or ejected == null or ejected.state != Pedestrian.State.DOWN:
		return _fail("car hitting the bike did not throw its rider (unseated %s, ejected %s)" % [unseated, ejected])
	print("MOTORBIKE PASS: %d parked + %d traffic bikes; car %.1f m/s vs bike %.1f m/s after %.1f s; lean %.2f rad in a right turn, on floor %.0f%%, max height %.2f m; exit ok; wall crash threw rider (health %.0f->%.0f, bike lying %.2f rad); car unseated NPC rider" % [parked, traffic_bikes.size(), car_speed, bike_speed, ACCEL_SECONDS, max_roll, on_floor * 100.0, stats["max_air"], health_before, player.health, lying])
	root.queue_free()
	for i in range(3):
		await process_frame
	quit(0)


## Board `vehicle` at the start of the straight and hold the throttle; returns the speed reached.
func _accelerate(player: PlayerController, vehicle: DriveableVehicle, world: SectorWorld, start: Vector3, heading: Vector3, stats: Dictionary = {}) -> float:
	vehicle.global_position = Vector3(start.x, world.height_at(start.x, start.z) + 0.4, start.z)
	vehicle.rotation = Vector3(0.0, atan2(-heading.x, -heading.z), 0.0)
	vehicle.reset_physics_interpolation()
	vehicle.speed = 0.0
	vehicle.fall_speed = 0.0
	player.global_position = vehicle.global_position + vehicle.global_transform.basis.x * 1.6
	player.board_vehicle(vehicle)
	for i in range(15):
		await physics_frame
	Input.action_press("move_forward")
	for i in range(int(ACCEL_SECONDS * Engine.physics_ticks_per_second)):
		await physics_frame
		if not stats.is_empty():
			_sample(vehicle, world, stats)
	Input.action_release("move_forward")
	return vehicle.speed


func _sample(vehicle: DriveableVehicle, world: SectorWorld, stats: Dictionary) -> void:
	stats["frames"] += 1
	if vehicle.is_on_floor():
		stats["floor"] += 1
	var p := vehicle.global_position
	stats["max_air"] = maxf(stats["max_air"], p.y - world.height_at(p.x, p.z))
	stats["max_body_tilt"] = maxf(stats["max_body_tilt"], maxf(absf(vehicle.rotation.x), absf(vehicle.rotation.z)))


## A clear, fairly flat 80 m line on dry land near the start: [start, heading].
func _open_straight(world: SectorWorld) -> Array:
	var space := world.get_world_3d().direct_space_state
	var spawn := world.anchor("player_spawn")
	for radius: float in [0.0, 25.0, 50.0, 80.0]:
		for k in range(8 if radius > 0.0 else 1):
			var origin := spawn + Vector3(cos(k * TAU / 8.0), 0.0, sin(k * TAU / 8.0)) * radius
			for step in range(24):
				var angle := step * TAU / 24.0
				var heading := Vector3(sin(angle), 0.0, cos(angle))
				if _line_clear(world, space, origin, heading, 80.0):
					return [origin, heading]
	return []


func _line_clear(world: SectorWorld, space: PhysicsDirectSpaceState3D, origin: Vector3, heading: Vector3, length: float) -> bool:
	var h0 := world.height_at(origin.x, origin.z)
	for d in range(0, int(length) + 1, 4):
		var p := origin + heading * d
		if world.data.surface_at(p.x, p.z) == "sea" or absf(world.height_at(p.x, p.z) - h0 - d * 0.0) > 2.5:
			return false
	for side: float in [-0.8, 0.0, 0.8]:
		for height: float in [0.45, 1.0, 1.6]:
			var a := origin + heading.cross(Vector3.UP) * side
			var from := Vector3(a.x, world.height_at(a.x, a.z) + height, a.z)
			var end := a + heading * length
			var to := Vector3(end.x, world.height_at(end.x, end.z) + height, end.z)
			var ray := PhysicsRayQueryParameters3D.create(from, to)
			ray.collide_with_areas = false
			if not space.intersect_ray(ray).is_empty():
				return false
	return true


## A façade 14–60 m away across open ground: [start 12 m before it, heading].
func _wall_run(world: SectorWorld) -> Array:
	var space := world.get_world_3d().direct_space_state
	var spawn := world.anchor("player_spawn")
	for radius: float in [0.0, 30.0, 60.0]:
		for k in range(8 if radius > 0.0 else 1):
			var origin := spawn + Vector3(cos(k * TAU / 8.0), 0.0, sin(k * TAU / 8.0)) * radius
			for step in range(36):
				var angle := step * TAU / 36.0
				var heading := Vector3(sin(angle), 0.0, cos(angle))
				var from := Vector3(origin.x, world.height_at(origin.x, origin.z) + 0.9, origin.z)
				var ray := PhysicsRayQueryParameters3D.create(from, from + heading * 60.0)
				var hit := space.intersect_ray(ray)
				if hit.is_empty() or (hit["collider"] as Node).is_in_group("terrain") or not hit["collider"] is StaticBody3D:
					continue
				var distance := from.distance_to(hit["position"])
				var normal: Vector3 = hit["normal"]
				if distance < 14.0 or normal.y > 0.2 or -normal.dot(heading) < 0.85:
					continue
				var start := from + heading * (distance - 12.0)
				if not _line_clear(world, space, start - heading * 0.5, heading, 10.0):
					continue
				return [Vector3(start.x, world.height_at(start.x, start.z) + 0.35, start.z), heading]
	return []


func _fail(message: String) -> void:
	push_error("MOTORBIKE FAIL: " + message)
	quit(1)
