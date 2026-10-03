extends SceneTree

## Four-star roadblocks lay a spike strip on the approach. Driving over it
## bursts the tyres: the car cannot go past the limp speed until repaired.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(8):
		await physics_frame
	var wanted := root.get_node("WantedSystem") as WantedSystem
	var player := root.get_node("Player") as PlayerController
	var car := root.get_node("District_Altillo/FirstCar") as DriveableVehicle
	player.global_position = car.global_position + car.global_transform.basis.x * 2.0
	player._interact()
	await _frames(3)
	if player.driving_vehicle != car:
		return _fail("could not board the car")
	var escalation: Node = wanted.escalation
	wanted.raise_to(4, player.global_position)
	var point: Vector3 = escalation.call("_point_ahead", car.global_position)
	if point == Vector3.INF:
		escalation.set("roadblock_timer", 0.0)
		await _frames(2)
	else:
		(escalation.get("roadblocks") as Array).append(escalation.call("_place_roadblock", point))
	var blocks: Array = escalation.get("roadblocks")
	if blocks.is_empty() or not (blocks[0] as Dictionary).has("strip"):
		return _fail("four-star roadblock without a spike strip")
	var strip := (blocks[0] as Dictionary)["strip"] as Node3D
	var to_block := (blocks[0]["at"] as Vector3) - strip.global_position
	if to_block.length() < 10.0:
		return _fail("strip not in front of the roadblock")
	# Drive over it.
	var start := strip.global_position - to_block.normalized() * 10.0
	car.global_position = Vector3(start.x, strip.global_position.y + 0.6, start.z)
	car.look_at(Vector3(strip.global_position.x, car.global_position.y, strip.global_position.z), Vector3.UP)
	car.reset_physics_interpolation()
	car.speed = 14.0
	Input.action_press("move_forward")
	for i in range(90):
		await physics_frame
		if car.tyres_burst:
			break
	if not car.tyres_burst:
		Input.action_release("move_forward")
		return _fail("driving over the strip did not burst the tyres (car %.1f m from strip)" % car.global_position.distance_to(strip.global_position))
	var top := 0.0
	for i in range(180):
		await physics_frame
		top = maxf(top, absf(car.speed))
	Input.action_release("move_forward")
	if top > DriveableVehicle.BURST_MAX_SPEED + 0.1:
		return _fail("burst car still reached %.1f m/s" % top)
	car.repair()
	if car.tyres_burst:
		return _fail("repair did not fix the tyres")
	wanted.clear_wanted()
	await _frames(2)
	if is_instance_valid(strip) and not strip.is_queued_for_deletion():
		return _fail("strip not removed with the stars")
	print("SPIKE STRIPS PASS: 4-star roadblock lays a strip %.0f m ahead of it, tyres burst, top speed %.1f m/s, repaired, cleared" % [to_block.length(), top])
	root.queue_free()
	await process_frame
	quit(0)


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _fail(reason: String) -> void:
	push_error("SPIKE STRIPS FAIL: " + reason)
	quit(1)
