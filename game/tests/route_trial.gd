extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	var world := root.get_node("District_Altillo")
	var player := root.get_node("Player") as PlayerController
	var mission := root.get_node("Mission") as MissionController
	var alba := world.get_node("Alba") as Pedestrian
	var car := world.get_node("FirstCar") as DriveableVehicle
	for i in range(20):
		await physics_frame
	var walked_to_alba := await _walk_to(player, alba.global_position, 360)
	await _press_interact()
	var walked_to_car := await _walk_to(player, car.global_position, 540)
	await _press_interact()
	if not walked_to_alba or not walked_to_car or mission.stage != 2:
		push_error("Route trial setup failed")
		quit(1)
		return
	var first := await _drive_to(car, Vector3(58, 0, 8), 500)
	var second := await _drive_to(car, Vector3(58, 0, -78), 900)
	var third := await _drive_to(car, Vector3(58, 0, -158), 900)
	var fourth := await _drive_to(car, Vector3(-168, 0, -158), 1400)
	_release_controls()
	var wanted := root.get_node("WantedSystem") as WantedSystem
	Input.action_press("brake")
	var escaped := false
	for i in range(1500):
		await physics_frame
		if wanted.level == 0:
			escaped = true
			break
	Input.action_release("brake")
	var delivery := await _drive_to(car, Vector3(58, 0, -158), 1600)
	_release_controls()
	await process_frame
	var success := walked_to_alba and walked_to_car and first and second and third and fourth and escaped and delivery and mission.completed
	print("ROUTE TRIAL: walk=", [walked_to_alba, walked_to_car], " drive=", [first, second, third, fourth, delivery], " escaped=", escaped, " car=", car.global_position, " mission_completed=", mission.completed)
	root.queue_free()
	for i in range(3):
		await process_frame
	quit(0 if success else 1)


func _drive_to(car: DriveableVehicle, target: Vector3, limit: int) -> bool:
	for i in range(limit):
		var offset := target - car.global_position
		offset.y = 0
		if offset.length() < 8.0:
			return true
		var desired := atan2(-offset.x, -offset.z)
		var error := wrapf(desired - car.rotation.y, -PI, PI)
		Input.action_press("move_forward")
		Input.action_release("move_left")
		Input.action_release("move_right")
		if error < -0.07:
			Input.action_press("move_right")
		elif error > 0.07:
			Input.action_press("move_left")
		if absf(error) > 0.28 and absf(car.speed) > 8.0:
			Input.action_press("brake")
		else:
			Input.action_release("brake")
		await physics_frame
		if i % 120 == 0:
			print("ROUTE step=", i, " pos=", car.global_position, " speed=", car.speed, " yaw=", car.rotation.y)
	return false


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
