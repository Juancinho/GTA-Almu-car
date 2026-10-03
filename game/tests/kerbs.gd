extends SceneTree

## No invisible walls at surface edges: the real car drives off the road over
## the kerb onto open ground and back, and the real player walks across paving
## and road edges (paseo included), without stalling or hopping.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(6):
		await physics_frame
	var world := root.get_node("District_Altillo") as SectorWorld
	var player := root.get_node("Player") as PlayerController
	var car := world.get_node("FirstCar") as DriveableVehicle
	for node in get_nodes_in_group("pedestrians"):
		(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(node as Node3D).position.y -= 500.0
	for node in get_nodes_in_group("vehicles"):
		if node != car:
			(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
			(node as Node3D).position.y -= 500.0
	await physics_frame
	var drive_spots := _edges(world, true, 6)
	var walk_spots := _edges(world, false, 6)
	if drive_spots.size() < 4 or walk_spots.size() < 4:
		return _fail("not enough open edges to test (%d road, %d paving)" % [drive_spots.size(), walk_spots.size()])
	# --- Car: off the road across the kerb at 90° and 35°, then back on ---
	player.global_position = car.global_position + car.global_transform.basis.x * 2.0
	player._interact()
	await physics_frame
	var crossed := 0
	var tries := 0
	var worst_air := 0
	var stalls := []
	for spot in drive_spots:
		for angle: float in [90.0, 35.0]:
			for direction: float in [1.0, -1.0]:
				tries += 1
				var edge: Vector3 = spot[0]
				var out: Vector3 = spot[1] * direction
				var along: Vector3 = spot[2]
				var heading := (out * sin(deg_to_rad(angle)) + along * cos(deg_to_rad(angle))).normalized()
				var start := edge - heading * 6.0
				if not _clear_path(world, start, edge + heading * 4.0):
					tries -= 1
					continue  # a palm or lamp post in the way: not a kerb question
				car.global_position = Vector3(start.x, world.height_at(start.x, start.z) + 0.7, start.z)
				car.rotation = Vector3(0, atan2(-heading.x, -heading.z), 0)
				car.reset_physics_interpolation()
				car.repair()
				car.speed = 0.0
				car.fall_speed = 0.0
				for i in range(12):
					await physics_frame
				Input.action_press("move_forward")
				var air := 0
				for i in range(110):
					await physics_frame
					air = 0 if car.is_on_floor() else air + 1
					worst_air = maxi(worst_air, air)
				Input.action_release("move_forward")
				var progressed := (car.global_position - edge).dot(heading)
				if progressed > 3.0:
					crossed += 1
				else:
					var hits := []
					for c in range(car.get_slide_collision_count()):
						var col := car.get_slide_collision(c)
						hits.append("%s n=%s" % [(col.get_collider() as Node).name, col.get_normal().snapped(Vector3(0.1, 0.1, 0.1))])
					stalls.append("car %s %.0f° at (%.0f, %.0f) got %.1f m past, speed %.1f, hits %s" % ["out" if direction > 0 else "in", angle, edge.x, edge.z, progressed, car.speed, str(hits)])
	player._interact()  # out of the car
	for i in range(30):
		await physics_frame
	car.global_position.y -= 500.0
	# --- On foot: across paving edges both ways ---
	var walked := 0
	var walk_tries := 0
	for spot in walk_spots + drive_spots.slice(0, 3):
		for direction: float in [1.0, -1.0]:
			walk_tries += 1
			var edge: Vector3 = spot[0]
			var out: Vector3 = spot[1] * direction
			var start := edge - out * 2.5
			player.global_position = Vector3(start.x, world.height_at(start.x, start.z) + 0.6, start.z)
			player.velocity = Vector3.ZERO
			player.reset_physics_interpolation()
			player.camera_yaw = atan2(-out.x, -out.z)
			player._update_camera_orientation()
			for i in range(10):
				await physics_frame
			Input.action_press("move_forward")
			for i in range(75):
				await physics_frame
			Input.action_release("move_forward")
			var progressed := (player.global_position - edge).dot(out)
			if progressed > 1.5:
				walked += 1
			else:
				stalls.append("walk %s at (%.0f, %.0f) got %.1f m past" % ["out" if direction > 0 else "in", edge.x, edge.z, progressed])
	for line in stalls:
		print("  ", line)
	if tries < 12 or crossed < tries - 1 or walked < walk_tries - 1 or worst_air > 18:
		return _fail("car %d/%d, walk %d/%d, worst airtime %d ticks" % [crossed, tries, walked, walk_tries, worst_air])
	print("KERBS PASS: car crossed %d/%d kerbs (worst airtime %d ticks), walked across %d/%d paving/road edges" % [crossed, tries, worst_air, walked, walk_tries])
	root.queue_free()
	await process_frame
	quit(0)


func _clear_path(world: SectorWorld, from: Vector3, to: Vector3) -> bool:
	var space := world.get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 1.2, 2.6)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	for k in range(9):
		var p := from.lerp(to, k / 8.0)
		query.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, world.height_at(p.x, p.z) + 1.1, p.z))
		for h in space.intersect_shape(query, 6):
			var label := str((h["collider"] as Node).name)
			if not (label == "Terrain" or label.begins_with("RoadSurface") or h["collider"] is DriveableVehicle or h["collider"] is PlayerController):
				return false
	return true


## Ribbon edges with open ground (no building, wall or prop) 4 m beyond.
func _edges(world: SectorWorld, driveable: bool, count: int) -> Array:
	var data := world.data
	var space := world.get_world_3d().direct_space_state
	var spots := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 if driveable else 78
	var roads: Array = world.road_network.roads.filter(func(r: Dictionary) -> bool: return bool(r["driveable"]) == driveable and str(r["class"]) != "steps")
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 1.6, 2.4)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	for attempt in range(3000):
		if spots.size() >= count:
			break
		var road: Dictionary = roads[rng.randi() % roads.size()]
		var pts: PackedVector3Array = road["points"]
		if pts.size() < 2:
			continue
		var i := rng.randi() % (pts.size() - 1)
		var a := pts[i]
		var b := pts[i + 1]
		if Vector2(b.x - a.x, b.z - a.z).length() < 4.0:
			continue
		var along := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var side := Vector3(-along.z, 0, along.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var edge := (a + b) * 0.5 + side * float(road["width"]) * 0.5
		edge.y = data.height_at(edge.x, edge.z)
		var open := true
		for d: float in [1.5, 3.0, 4.5]:
			var p := edge + side * d
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, data.height_at(p.x, p.z) + 3.0, p.z), Vector3(p.x, data.height_at(p.x, p.z) - 3.0, p.z)))
			if hit.is_empty() or str((hit["collider"] as Node).name) != "Terrain" or absf(data.height_at(p.x, p.z) - edge.y) > 1.2:
				open = false
		for d: float in [-3.0, -1.0, 1.0, 3.0, 5.0]:
			var p := edge + side * d
			query.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, data.height_at(p.x, p.z) + 1.3, p.z))
			for h in space.intersect_shape(query, 6):
				var label := str((h["collider"] as Node).name)
				if not (label == "Terrain" or label.begins_with("RoadSurface")):
					open = false
		if open:
			spots.append([edge, side, along])
	return spots


func _fail(reason: String) -> void:
	push_error("KERBS FAIL: " + reason)
	quit(1)
