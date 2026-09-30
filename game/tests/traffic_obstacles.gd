extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	get_root().add_child(scene)
	var ground := _solid(scene, Vector3(0, -0.2, -35), Vector3(12, 0.4, 100))
	ground.add_to_group("terrain")
	var barrier := _solid(scene, Vector3(0, 1.5, -15), Vector3(6, 3, 0.5))
	var car := DriveableVehicle.new()
	car.position = Vector3(0, 0.2, 0)
	scene.add_child(car)
	car.pursuing = true
	car.pursuit_target = Vector3(0, 0, -60)
	car.pursuit_speed = 22.0
	car.speed = 22.0
	var nearest := INF
	for i in range(100):
		await physics_frame
		nearest = minf(nearest, car.global_position.distance_to(barrier.global_position))
	if car.health < DriveableVehicle.MAX_HEALTH or car.global_position.z < -12.6:
		return _fail("fast AI crashed into the roadblock (z %.2f health %.1f)" % [car.global_position.z, car.health])
	barrier.queue_free()
	for i in range(300):
		await physics_frame
	if car.global_position.z > -20.0:
		return _fail("AI did not continue after the obstacle was cleared (pos %s speed %.1f)" % [car.global_position, car.speed])
	print("TRAFFIC OBSTACLES PASS: 22 m/s approach brakes without damage, continues after roadblock removed (min gap %.2f m)" % nearest)
	scene.queue_free()
	await process_frame
	quit(0)


func _solid(parent: Node, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body


func _fail(reason: String) -> void:
	push_error("TRAFFIC OBSTACLES FAIL: " + reason)
	quit(1)
