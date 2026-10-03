extends SceneTree

## Stunt jumps: ramps are placed on clear beach runs; driving fast up one flies
## the car over 14 m, slows time in the air, pays the first time and is saved.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(10):
		await physics_frame
	var jumps: Node = root.get("stunt_jumps")
	var ramps: Array = jumps.get("ramps")
	if ramps.size() < 3:
		return _fail("only %d stunt ramps placed" % ramps.size())
	var player := root.get_node("Player") as PlayerController
	var car := root.get_node("District_Altillo/FirstCar") as DriveableVehicle
	player.global_position = car.global_position + car.global_transform.basis.x * 2.0
	player._interact()
	var ramp: Dictionary = ramps[0]
	var dir: Vector3 = ramp["dir"]
	var start: Vector3 = (ramp["top"] as Vector3) - dir * 30.0
	car.global_position = Vector3(start.x, player.sector_data.height_at(start.x, start.z) + 0.6, start.z)
	car.rotation = Vector3(0, atan2(-dir.x, -dir.z), 0)
	car.speed = 21.0
	var money := int(root.get("money"))
	var slowed := false
	Input.action_press("move_forward")
	for i in range(300):
		await physics_frame
		slowed = slowed or Engine.time_scale < 1.0
		if (jumps.get("done") as Dictionary).size() > 0:
			break
	Input.action_release("move_forward")
	if (jumps.get("done") as Dictionary).is_empty():
		return _fail("jump not completed (car at %s, speed %.1f)" % [car.global_position, car.speed])
	if not slowed or Engine.time_scale != 1.0:
		return _fail("slow motion not applied/restored")
	if int(root.get("money")) < money + 250:
		return _fail("no reward")
	var flown: float = (jumps.get("done") as Dictionary).values()[0]
	print("STUNT JUMPS PASS: %d beach ramps, jump of %.0f m with slow motion, 250 € reward" % [ramps.size(), flown])
	root.queue_free()
	await process_frame
	quit(0)


func _fail(reason: String) -> void:
	Engine.time_scale = 1.0
	push_error("STUNT JUMPS FAIL: " + reason)
	quit(1)
