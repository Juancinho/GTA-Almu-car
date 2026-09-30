extends SceneTree

## Fresh-start El Recado run on the real 1:1 street network, driven only by simulated
## movement/interaction input: walk to Alba and the car, drive the one-way streets up
## to the old-town pedestrian zone, evade the road-following police through distant
## streets and deliver below the castle. `-- --perf` also writes a PerfMonitor report
## (fullscreen; `--uncapped` disables vsync). Run with --fixed-fps 60 for speed.

var wanted: WantedSystem
var busted := false
var pursuit_seconds := 0.0
var police_min_distance := INF
var stats_car: DriveableVehicle
var roads: RoadNetwork


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var perf_mode := OS.get_cmdline_user_args().has("--perf")
	var uncapped := OS.get_cmdline_user_args().has("--uncapped")
	if perf_mode and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		if uncapped:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	if perf_mode:
		root.playtest_log.mode = "automated_route_uncapped" if uncapped else "automated_route_vsync"
	var world := root.get_node("District_Altillo") as SectorWorld
	var network: RoadNetwork = world.road_network
	roads = network
	var player := root.get_node("Player") as PlayerController
	var mission := root.get_node("Mission") as MissionController
	wanted = root.get_node("WantedSystem") as WantedSystem
	wanted.player_busted.connect(func() -> void: busted = true)
	var alba := world.get_node("Alba") as Pedestrian
	var car := world.get_node("FirstCar") as DriveableVehicle
	stats_car = car
	var avoid: Array[Rect2] = []
	for zone in world.restricted_zones:
		var r := float(zone["radius"])
		avoid.append(Rect2(float(zone["x"]) - r, float(zone["z"]) - r, r * 2.0, r * 2.0))
	for i in range(20):
		await physics_frame
	var walked_to_alba := await _walk_to(player, alba.global_position, 600)
	await _press_interact()
	var walked_to_car := await _walk_to(player, car.global_position, 1500)
	await _press_interact()
	if not walked_to_alba or not walked_to_car or mission.stage != 2:
		push_error("Route trial setup failed: walk=%s stage=%d" % [[walked_to_alba, walked_to_car], mission.stage])
		quit(1)
		return
	var to_old_town := await _drive_path(car, network.find_path(car.global_position, world.anchor("old_town_target")), 15000, true)
	var incident := wanted.level > 0 and mission.stage == 3
	var escape_frames := 0
	var targets := ["hospital", "player_spawn", "castle_drop", "hospital"]
	var leg := 0
	while wanted.level > 0 and not busted and escape_frames < 12000:
		var path := network.find_path(car.global_position, world.anchor(targets[leg % targets.size()]), avoid)
		var before := Engine.get_physics_frames()
		await _drive_path(car, path, 5000, false, true)
		escape_frames += Engine.get_physics_frames() - before
		leg += 1
	var escaped := wanted.level == 0 and not busted and mission.stage == 4
	var delivery := await _drive_path(car, network.find_path(car.global_position, world.anchor("castle_drop"), avoid), 15000)
	_release_controls()
	Input.action_press("brake")
	for i in range(40):
		await physics_frame
	Input.action_release("brake")
	await process_frame
	var pursued := pursuit_seconds > 1.0 and police_min_distance < 80.0
	var success := walked_to_alba and walked_to_car and to_old_town and incident and pursued and escaped and delivery and mission.completed and not busted
	print("ROUTE TRIAL: walk=", [walked_to_alba, walked_to_car], " drive=", [to_old_town, delivery],
		" incident=", incident, " pursuit_s=", snappedf(pursuit_seconds, 0.1), " police_min_m=", snappedf(police_min_distance, 0.1),
		" escaped=", escaped, " escape_s=", snappedf(escape_frames / 60.0, 0.1), " busted=", busted, " health=", int(car.health),
		" car=", car.global_position.snapped(Vector3.ONE * 0.1), " mission_completed=", mission.completed)
	if perf_mode:
		var report_path: String = root.playtest_log.write_report(root.playtest_log.mode)
		print("PERF ROUTE: ", JSON.stringify(root.perf_monitor.summary()["contexts"]))
		print("PERF OVERALL: ", JSON.stringify(root.perf_monitor.summary()["overall"]), " report=", report_path)
	root.queue_free()
	for i in range(3):
		await process_frame
	quit(0 if success else 1)


func _track_police(delta: float) -> void:
	if wanted.phase == "pursuit":
		pursuit_seconds += delta
	for police in wanted.police_cars:
		if is_instance_valid(police):
			police_min_distance = minf(police_min_distance, police.global_position.distance_to(stats_car.global_position))


func _drive_path(car: DriveableVehicle, path: PackedVector3Array, limit: int, stop_on_incident: bool = false, stop_when_clear: bool = false) -> bool:
	var used := 0
	var i := 0
	while i < path.size():
		# Skip waypoints already behind us (dense OSM nodes on curves).
		while i + 1 < path.size() and Vector2(path[i].x - car.global_position.x, path[i].z - car.global_position.z).length() < 4.0:
			i += 1
		var next := path[i + 1] if i + 1 < path.size() else Vector3.INF
		var result := await _drive_to(car, path[i], limit - used, stop_when_clear, next)
		used += int(result["frames"])
		if busted or (stop_when_clear and wanted.level == 0):
			return not busted
		if stop_on_incident and wanted.level > 0 and i >= path.size() - 1:
			return true
		if not bool(result["reached"]):
			print("DRIVE STALLED at ", car.global_position, " waypoint ", i, "/", path.size(), " -> ", path[i])
			return false
		i += 1
	return true


## Steer with simulated keys toward target; brake for sharp turns at the next waypoint.
func _drive_to(car: DriveableVehicle, target: Vector3, limit: int, stop_when_clear: bool = false, next: Vector3 = Vector3.INF) -> Dictionary:
	var stalled := 0
	for i in range(limit):
		if stalled > 50:
			# Like a human driver: wedged against traffic, back up with opposite lock.
			stalled = 0
			await _reverse_out(car)
		var offset := target - car.global_position
		offset.y = 0
		if offset.length() < 4.5 or busted or (stop_when_clear and wanted.level == 0):
			return {"reached": offset.length() < 8.0 or (stop_when_clear and wanted.level == 0), "frames": i}
		var avoid := _traffic_ahead(car)
		if avoid["distance"] < 18.0:
			# Swerve toward the free side, as a driver overtaking or dodging would.
			offset += car.global_transform.basis.x * 4.5 * float(avoid["side"])
		var desired := atan2(-offset.x, -offset.z)
		var error := wrapf(desired - car.rotation.y, -PI, PI)
		Input.action_press("move_forward")
		Input.action_release("move_left")
		Input.action_release("move_right")
		if error < -0.07:
			Input.action_press("move_right")
		elif error > 0.07:
			Input.action_press("move_left")
		var corner := false
		if next != Vector3.INF and offset.length() < 20.0:
			var outgoing := next - target
			outgoing.y = 0
			corner = outgoing.length() > 1.0 and offset.normalized().dot(outgoing.normalized()) < 0.6
		# A careful human: 15 m/s in town, 8 m/s in the old-town living streets.
		var limit_speed := 15.0
		if i % 20 == 0:
			var hit: Dictionary = roads.nearest(car.global_position)
			car.set_meta("lane_class", str((hit["road"] as Dictionary)["class"]) if not hit.is_empty() else "")
		if str(car.get_meta("lane_class", "")) == "living_street":
			limit_speed = 8.0
		if (absf(error) > 0.28 and absf(car.speed) > 8.0) or (corner and absf(car.speed) > 10.0) or (avoid["distance"] < 9.0 and absf(car.speed) > 6.0) or (offset.length() < 25.0 and absf(car.speed) > 12.0) or absf(car.speed) > limit_speed:
			Input.action_press("brake")
		else:
			Input.action_release("brake")
		await physics_frame
		stalled = stalled + 1 if absf(car.speed) < 1.0 else 0
		_track_police(1.0 / Engine.physics_ticks_per_second)
		if i % 120 == 0:
			var units := []
			for police in wanted.police_cars:
				if is_instance_valid(police):
					units.append("%s(%.0f,%.0f d=%.0f v=%.1f)" % [police.name, police.global_position.x, police.global_position.z, police.global_position.distance_to(car.global_position), police.speed])
			print("ROUTE step=", i, " pos=", car.global_position.snapped(Vector3(0.1, 0.1, 0.1)), " speed=", snappedf(car.speed, 0.1), " hp=", int(car.health), " wanted=", wanted.level, "/", wanted.phase, " police=", units)
	return {"reached": false, "frames": limit}


## Nearest vehicle in a 3-ray fan ahead and which side (+1 right, -1 left) is freer.
func _traffic_ahead(car: DriveableVehicle) -> Dictionary:
	var space := car.get_world_3d().direct_space_state
	var forward := -car.global_transform.basis.z
	var right := car.global_transform.basis.x
	var origin := car.global_position + Vector3.UP * 0.7
	var hits := {}
	for side in [-1.0, 0.0, 1.0]:
		var query := PhysicsRayQueryParameters3D.create(origin + right * side * 1.0, origin + right * side * 1.0 + forward * 18.0)
		query.exclude = [car.get_rid()]
		var hit := space.intersect_ray(query)
		hits[side] = origin.distance_to(hit["position"]) if not hit.is_empty() and hit["collider"] is DriveableVehicle else INF
	var nearest := minf(hits[-1.0], minf(hits[0.0], hits[1.0]))
	return {"distance": nearest, "side": -1.0 if hits[-1.0] > hits[1.0] else 1.0}


func _reverse_out(car: DriveableVehicle) -> void:
	_release_controls()
	Input.action_press("move_back")
	Input.action_press("move_left" if randf() < 0.5 else "move_right")
	for j in range(60):
		await physics_frame
		_track_police(1.0 / Engine.physics_ticks_per_second)
	_release_controls()


func _walk_to(player: PlayerController, target: Vector3, limit: int) -> bool:
	for i in range(limit):
		var offset := target - player.global_position
		offset.y = 0
		if offset.length() < 2.9:
			_release_controls()
			for j in range(7):
				await physics_frame
			return true
		var direction := offset.normalized()
		var right := player.camera.global_transform.basis.x
		var forward := -player.camera.global_transform.basis.z
		right.y = 0
		forward.y = 0
		_set_axis("move_right", "move_left", direction.dot(right.normalized()))
		_set_axis("move_back", "move_forward", -direction.dot(forward.normalized()))
		await physics_frame
	_release_controls()
	print("WALK FAILED at ", player.global_position, " target ", target)
	return false


func _set_axis(positive: StringName, negative: StringName, value: float) -> void:
	Input.action_release(positive)
	Input.action_release(negative)
	if value > 0.03:
		Input.action_press(positive, value)
	elif value < -0.03:
		Input.action_press(negative, -value)


func _press_interact() -> void:
	var press := InputEventAction.new()
	press.action = "interact"
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release := InputEventAction.new()
	release.action = "interact"
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame


func _release_controls() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "brake"]:
		Input.action_release(action)
