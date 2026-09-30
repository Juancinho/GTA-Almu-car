extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	var world: SectorWorld = game.world
	var player: PlayerController = game.player
	for person in get_nodes_in_group("pedestrians"):
		person.set_physics_process(false)
	for car in get_nodes_in_group("vehicles"):
		car.set_physics_process(false)
	var near: Dictionary = world.road_network.nearest(world.anchor("first_car"))
	var at: Vector3 = near["point"]
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 3.0)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or not hit["collider"].is_in_group("road_surfaces"):
		return fail("visible road has no matching collision")
	var road_y: float = hit["position"].y
	if absf(road_y - world.height_at(at.x, at.z) - RoadBuilder.LIFT_DRIVE) > 0.03:
		return fail("road collision differs from visible road height")
	player.global_position = Vector3(at.x, road_y + 0.8, at.z)
	await frames(70)
	if not player.is_on_floor() or player.global_position.y < road_y - 0.02:
		return fail("player feet sink below the actual road")
	for variant in DriveableVehicle.traffic_variants() + ["mission_red", "police_local", "police_suv", "compact_generated"]:
		var car := DriveableVehicle.new()
		car.variant = str(variant)
		game.add_child(car)
		car.set_physics_process(false)
		car.global_position = Vector3(1000,80,1000)
		car.set_occupant("male_casual")
		await frames(2)
		var visual := car.get_node("CarVisual") as Node3D
		var lower := INF
		var upper := -INF
		for item in visual.find_children("*", "MeshInstance3D", true, false):
			var mesh := item as MeshInstance3D
			var bounds: AABB = (car.global_transform.affine_inverse() * mesh.global_transform) * mesh.mesh.get_aabb()
			lower = minf(lower,bounds.position.y)
			upper = maxf(upper,bounds.end.y)
		if absf(lower) > 0.001:
			return fail(str(variant) + " tyre datum is not grounded")
		var rig := car.occupant.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		for bone in ["Foot.L", "Foot.R", "Head"]:
			var point := car.to_local(rig.to_global(rig.get_bone_global_pose(rig.find_bone(bone)).origin))
			if point.y < 0.04 or (bone == "Head" and point.y > upper - 0.05):
				return fail(str(variant) + " occupant outside floor/roof: " + bone + str(point))
		car.free()
	var props := get_nodes_in_group("interactive_props")
	if props.is_empty() or props.size() > 32:
		return fail("movable furniture absent/unbounded")
	var prop := props[0] as InteractiveProp
	prop.freeze = false
	prop.global_position = Vector3(0,80,0)
	player.set_physics_process(false)
	player.global_position = Vector3(-4,80,0)
	await frames(2)
	var result: Dictionary = game.weapons.ballistics.shoot(Vector3(-4,80,0), Vector3.RIGHT,8,30,60,player)
	await frames(2)
	if result["collider"] != prop or prop.linear_velocity.x <= 0.1:
		return fail("bullet did not physically move chair")
	player.global_position = Vector3(20,-2.4,200)
	player.camera.global_position = Vector3(20,-1.0,200)
	player.underwater_view._process(0.1)
	if not player.underwater_view.active or not player.camera.environment.fog_enabled:
		return fail("underwater tint/fog not activated by submerged camera")
	player.camera.global_position.y = 1.0
	player.underwater_view._process(0.1)
	if player.underwater_view.active or player.camera.environment != null:
		return fail("water effect retained above surface")
	if not await step_contacts(game):
		return fail("low-step traversal or wall/ceiling exclusion")
	player.set_process(false)
	game.hud.set_process(false)
	game.hud.mission_label.text = "MISIÓN · Lleva la copia del libro de cuentas al apartamento, evita a los perseguidores y regresa al vestíbulo para hablar con Inés."
	game.hud.prompt_label.text = "E · Entrar en Apartamentos Mirador · Vestíbulo, primera planta y apartamentos 01 / 02"
	game.hud.dialogue_label.text = "Inés: conserva las cuentas y no te detengas junto a una patrulla. Cuando regreses, sube al apartamento y comprueba quién te ha seguido desde el paseo."
	await frames(8)
	for label in [game.hud.info_label, game.hud.mission_label, game.hud.wanted_label, game.hud.prompt_label, game.hud.dialogue_label]:
		var panel := label.get_parent().get_parent().get_parent() as PanelContainer
		if not panel.get_global_rect().encloses(label.get_global_rect()):
			return fail("text escaped panel: " + label.text)
		if not Rect2(Vector2.ZERO, Vector2(1280,720)).encloses(panel.get_global_rect()):
			return fail("text panel is outside viewport: " + label.text)
	print("SURFACE CONTACTS PASS: real road support, low steps without wall/ceiling traversal, nine grounded vehicle variants/seated occupants, bounded furniture/bullet impulse, submerged-camera fog cleanup and long HUD text containment")
	game.queue_free()
	await process_frame
	quit()

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func step_contacts(game: Node) -> bool:
	var body := CharacterBody3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.75
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = 0.875
	body.add_child(collision)
	game.add_child(body)
	var floor_body := fixture_box(game, Vector3(1000,79.9,1000),Vector3(10,0.2,10))
	var step := fixture_box(game, Vector3(1001,80.145,1000),Vector3(2,0.29,4))
	var ceiling := fixture_box(game, Vector3(1000,84,1000),Vector3(10,0.2,10))
	var passed := true
	for case in range(3):
		step.global_position.y = 80.3 if case == 1 else 80.145
		(step.get_child(0).shape as BoxShape3D).size.y = 0.6 if case == 1 else 0.29
		ceiling.global_position.y = 81.88 if case == 2 else 84.0
		body.global_position = Vector3(999.65,80.05,1000)
		for i in range(4):
			await physics_frame
			body.velocity = Vector3.DOWN
			body.move_and_slide()
		var crossed := CharacterStep.climb(body,Vector3.RIGHT * 0.1,0.42)
		print("STEP CASE ",case, " crossed=",crossed, " at=",body.global_position)
		passed = passed and (crossed if case == 0 else not crossed)
		if crossed and body.global_position.y < 80.285:
			passed = false
	body.free()
	ceiling.global_position.y = 84.0
	step.global_position.y = 80.065
	(step.get_child(0).shape as BoxShape3D).size.y = 0.13
	var car := DriveableVehicle.new()
	car.variant = "mission_red"
	game.add_child(car)
	car.sector_data = null  # isolated support fixture, outside the geographic sector
	car.global_position = Vector3(997.3,80.05,1000)
	car.rotation.y = -PI * 0.5
	for i in range(75):
		car.speed = 4.0
		await physics_frame
	passed = passed and car.global_position.x > 1001.0 and car.health > 999.0
	print("TYRE CURB at=",car.global_position," health=",car.health)
	car.free()
	floor_body.free()
	step.free()
	ceiling.free()
	return passed

func fixture_box(game: Node, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	game.add_child(body)
	body.global_position = at
	return body

func fail(reason: String) -> void:
	push_error("SURFACE CONTACTS FAIL: " + reason)
	quit(1)
