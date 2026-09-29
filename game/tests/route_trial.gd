extends SceneTree

## Fresh-start El Recado run driven only by simulated movement/interaction input.
## The player follows the road graph, triggers the witnessed incident, is chased by
## road-navigating police, evades them around the west blocks and delivers the package.
## `-- --perf` also writes a PerfMonitor/PlaytestLog report (use a visible window).

const RESTRICTED_ZONE := Rect2(38.0, -96.0, 40.0, 36.0)
const EVASION_LOOP: Array[Vector3] = [
	Vector3(-168, 0, -78), Vector3(-168, 0, 8), Vector3(-55, 0, 8),
	Vector3(-55, 0, -78), Vector3(-55, 0, -158), Vector3(-168, 0, -158),
]

var wanted: WantedSystem
var busted := false
var pursuit_seconds := 0.0
var police_min_distance := INF
var stats_car: DriveableVehicle


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var perf_mode := OS.get_cmdline_user_args().has("--perf")
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	if perf_mode:
		root.playtest_log.mode = "automated_route"
	var world := root.get_node("District_Altillo")
	var network: RoadNetwork = world.road_network
	var player := root.get_node("Player") as PlayerController
	var mission := root.get_node("Mission") as MissionController
	wanted = root.get_node("WantedSystem") as WantedSystem
	wanted.player_busted.connect(func() -> void: busted = true)
	var alba := world.get_node("Alba") as Pedestrian
	var car := world.get_node("FirstCar") as DriveableVehicle
	stats_car = car
	for i in range(20):
		await physics_frame
	var walked_to_alba := await _walk_to(player, alba.global_position, 360)
	await _press_interact()
	var walked_to_car := await _walk_to(player, car.global_position, 540)
	await _press_interact()
	if not walked_to_alba or not walked_to_car or mission.stage != 2:
		push_error("Route trial setup failed: walk=%s stage=%d" % [[walked_to_alba, walked_to_car], mission.stage])
		quit(1)
		return
	var to_old_town := await _drive_path(car, network.find_path(car.global_position, Vector3(58, 0, -78)), 1400)
	var incident := wanted.level > 0 and mission.stage == 3
	var away := await _drive_path(car, network.find_path(car.global_position, Vector3(58, 0, -158)), 900)
	away = away and await _drive_path(car, network.find_path(car.global_position, Vector3(-168, 0, -158)), 1400)
	var escape_frames := 0
	var loop_index := 0
	while wanted.level > 0 and not busted and escape_frames < 7200:
		var target := EVASION_LOOP[loop_index % EVASION_LOOP.size()]
		var result := await _drive_to(car, target, 900, true)
		escape_frames += int(result["frames"])
		loop_index += 1
	var escaped := wanted.level == 0 and not busted and mission.stage == 4
	var delivery_path := network.find_path(car.global_position, Vector3(58, 0, -158), [RESTRICTED_ZONE])
	var delivery := await _drive_path(car, delivery_path, 2400)
	_release_controls()
	Input.action_press("brake")
	for i in range(30):
		await physics_frame
	Input.action_release("brake")
	await process_frame
	var pursued := pursuit_seconds > 1.0 and police_min_distance < 60.0
	var success := walked_to_alba and walked_to_car and to_old_town and incident and away and pursued and escaped and delivery and mission.completed and not busted
	print("ROUTE TRIAL: walk=", [walked_to_alba, walked_to_car], " drive=", [to_old_town, away, delivery],
		" incident=", incident, " pursuit_s=", snappedf(pursuit_seconds, 0.1), " police_min_m=", snappedf(police_min_distance, 0.1),
		" escaped=", escaped, " escape_s=", snappedf(escape_frames / 60.0, 0.1), " busted=", busted,
		" car=", car.global_position, " mission_completed=", mission.completed)
	if perf_mode:
		var path: String = root.playtest_log.write_report("automated_route")
		print("PERF ROUTE: ", JSON.stringify(root.perf_monitor.summary()["contexts"]))
		print("PERF OVERALL: ", JSON.stringify(root.perf_monitor.summary()["overall"]), " report=", path)
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


func _drive_path(car: DriveableVehicle, path: PackedVector3Array, limit: int) -> bool:
	var used := 0
	for i in range(path.size()):
		var next := path[i + 1] if i + 1 < path.size() else Vector3.INF
		var result := await _drive_to(car, path[i], limit - used, false, next)
		used += int(result["frames"])
		if not bool(result["reached"]) or busted:
			return false
	return true


## Steer with simulated keys toward target; brake for sharp turns at the next waypoint.
func _drive_to(car: DriveableVehicle, target: Vector3, limit: int, stop_when_clear: bool = false, next: Vector3 = Vector3.INF) -> Dictionary:
	for i in range(limit):
		var offset := target - car.global_position
		offset.y = 0
		if offset.length() < 8.0 or busted or (stop_when_clear and wanted.level == 0):
			return {"reached": offset.length() < 8.0 or (stop_when_clear and wanted.level == 0), "frames": i}
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
		if (absf(error) > 0.28 and absf(car.speed) > 8.0) or (corner and absf(car.speed) > 11.0):
			Input.action_press("brake")
		else:
			Input.action_release("brake")
		await physics_frame
		_track_police(1.0 / Engine.physics_ticks_per_second)
		if i % 120 == 0:
			var units := []
			for police in wanted.police_cars:
				if is_instance_valid(police):
					units.append("%s(%.0f,%.0f d=%.0f v=%.1f)" % [police.name, police.global_position.x, police.global_position.z, police.global_position.distance_to(car.global_position), police.speed])
			print("ROUTE step=", i, " pos=", car.global_position.snapped(Vector3(0.1, 0.1, 0.1)), " speed=", snappedf(car.speed, 0.1), " wanted=", wanted.level, "/", wanted.phase, " police=", units)
	return {"reached": false, "frames": limit}


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
