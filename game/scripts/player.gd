class_name PlayerController
extends CharacterBody3D

signal contact_interacted(contact: Pedestrian)
signal civilian_interacted(civilian: Pedestrian)
signal vehicle_entered(vehicle: DriveableVehicle)
signal vehicle_jacked(vehicle: DriveableVehicle, driver: Pedestrian)
signal health_changed(value: float)
signal died
signal assaulted(victim: Pedestrian)

const WALK_SPEED := 5.0
const RUN_SPEED := 8.5
const ACCELERATION := 15.0
const JUMP_SPEED := 5.7
const GRAVITY := 16.0
const FOOT_CAMERA_DISTANCE := 5.0
const DRIVE_CAMERA_DISTANCE := 7.5
const CAMERA_RECENTER_DELAY := 0.9
const GAMEPAD_LOOK_SPEED := 2.6
const MAX_HEALTH := 100.0
const PUNCH_RANGE := 1.9
const SWIM_SPEED := 3.4
const DIVE_SPEED := 2.7
const MAX_BREATH := 16.0

var camera_pivot: Node3D
var camera_height := 1.55
var _last_tick_position := Vector3.INF
var camera_arm: SpringArm3D
var camera: Camera3D
var visual: Node3D
var human: HumanModel
var collider: CollisionShape3D
var step_audio: AudioStreamPlayer3D
var step_timer := 0.0
var driving_vehicle: DriveableVehicle
var camera_yaw := -2.0
var camera_pitch := -0.18
var look_idle_time := 0.0
var health := MAX_HEALTH
var dead := false
var attack_cooldown := 0.0
var sector_data: SectorData
var swimming := false
var diving := false
var breath := MAX_BREATH
var aiming := false  # set by WeaponSystem: over-the-shoulder camera, body faces the aim
var weapons: Node  # WeaponSystem; fists fall back to punch()
var interior_camera := false
var interior_probe_timer := 0.0
var swim_phase := 0.0
var underwater_view: UnderwaterView


func _ready() -> void:
	add_to_group("player")
	_build_body()
	_build_camera()
	underwater_view = UnderwaterView.new()
	underwater_view.player = self
	add_child(underwater_view)
	step_audio = AudioStreamPlayer3D.new()
	step_audio.stream = load("res://assets/audio/footstep.wav") as AudioStream
	step_audio.bus = "SFX"
	step_audio.max_distance = 32.0
	step_audio.position.y = 0.3
	add_child(step_audio)


func _build_body() -> void:
	visual = Node3D.new()
	visual.name = "CharacterVisual"
	add_child(visual)
	human = HumanModel.new("male_casual")
	human.name = "Human"
	visual.add_child(human)
	collider = CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.75
	collider.shape = shape
	collider.position.y = 0.875
	add_child(collider)


func _build_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	# Physics runs at 60 Hz but the screen at up to 120+: the body is drawn
	# interpolated between ticks, and the camera follows that interpolated body
	# every rendered frame (mouse look stays immediate). Without this the view
	# stepped at 60 Hz on a 120 Hz display and play felt jerky.
	camera_pivot.top_level = true
	camera_pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera_pivot)
	# The spring arm pulls the camera in front of walls in narrow streets.
	camera_arm = SpringArm3D.new()
	camera_arm.name = "CameraArm"
	camera_arm.position = Vector3(0, 0.5, 0)
	camera_arm.spring_length = FOOT_CAMERA_DISTANCE
	camera_arm.margin = 0.25
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	camera_arm.shape = probe
	camera_arm.add_excluded_object(get_rid())
	camera_pivot.add_child(camera_arm)
	camera = Camera3D.new()
	camera.current = true
	camera_arm.add_child(camera)
	_update_camera_orientation()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * 0.003
		camera_pitch = clampf(camera_pitch - event.relative.y * 0.003, -1.1, 0.55)
		look_idle_time = 0.0
		_update_camera_orientation()
	if event.is_action_pressed("interact") and not dead:
		_interact()
	elif event.is_action_pressed("attack") and InputMap.has_action("attack") and (weapons == null or str(weapons.get("current")) == "fists"):
		punch()


func _update_camera_orientation() -> void:
	var target: Node3D = driving_vehicle if driving_vehicle != null else self
	var anchor := target.get_global_transform_interpolated().origin if is_inside_tree() else position
	if driving_vehicle != null:
		anchor.y += 0.3
	camera_pivot.global_transform = Transform3D(Basis.from_euler(Vector3(camera_pitch, camera_yaw, 0)), anchor + Vector3(0, camera_height, 0))


func _process(delta: float) -> void:
	interior_probe_timer -= delta
	if interior_probe_timer <= 0.0:
		interior_probe_timer = 0.2
		interior_camera = false
		for interior in get_tree().get_nodes_in_group("interiors"):
			if interior.has_method("contains_player") and bool(interior.call("contains_player", global_position)):
				interior_camera = true
				break
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down") if InputMap.has_action("look_left") else Vector2.ZERO
	if look.length_squared() > 0.01:
		camera_yaw -= look.x * GAMEPAD_LOOK_SPEED * delta
		camera_pitch = clampf(camera_pitch - look.y * GAMEPAD_LOOK_SPEED * 0.6 * delta, -1.1, 0.55)
		look_idle_time = 0.0
	else:
		look_idle_time += delta
	var target_length := DRIVE_CAMERA_DISTANCE if driving_vehicle != null else (2.1 if aiming else 2.4 if interior_camera else FOOT_CAMERA_DISTANCE)
	if diving:
		target_length = 2.4
	camera_height = move_toward(camera_height, 0.6 if diving else 1.55, 4.0 * delta)
	camera_arm.spring_length = move_toward(camera_arm.spring_length, target_length, (14.0 if aiming else 6.0) * delta)
	camera_arm.position.x = move_toward(camera_arm.position.x, 0.62 if aiming else 0.0, 4.0 * delta)
	camera.fov = move_toward(camera.fov, 58.0 if aiming else 75.0, 60.0 * delta)
	if driving_vehicle == null:
		# With a wall right behind the player the arm collapses; hide the body
		# instead of filling the screen with the back of the head.
		visual.visible = camera_arm.get_hit_length() > 1.1
	if driving_vehicle != null and look_idle_time > CAMERA_RECENTER_DELAY:
		# Drift the camera behind the car when the player is not steering the view.
		var follow := minf(1.0, 2.2 * delta * clampf(absf(driving_vehicle.speed) / 4.0, 0.0, 1.0))
		var heading := driving_vehicle.rotation.y + (PI if driving_vehicle.speed < -1.0 else 0.0)
		camera_yaw = lerp_angle(camera_yaw, heading, follow)
		camera_pitch = lerpf(camera_pitch, -0.22, follow)
	_update_camera_orientation()


func _physics_process(delta: float) -> void:
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	# Teleports (doors, lifts, respawn, loading) must not be drawn as a swoop.
	if _last_tick_position != Vector3.INF and global_position.distance_squared_to(_last_tick_position) > 9.0:
		reset_physics_interpolation()
	_last_tick_position = global_position
	if dead:
		velocity = Vector3.ZERO
		return
	if driving_vehicle != null:
		global_position = driving_vehicle.global_position + Vector3(0, 0.3, 0)
		return
	var water_depth := -sector_data.height_at(global_position.x, global_position.z) if sector_data != null and sector_data.surface_at(global_position.x, global_position.z) == "sea" else 0.0
	if water_depth > 0.7 and global_position.y < 0.35:
		_swim(delta)
		return
	if swimming:
		reset_swimming()
		global_position.y = maxf(global_position.y, sector_data.height_at(global_position.x, global_position.z) + 0.1)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_SPEED
	var axis := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward := -camera.global_transform.basis.z
	var right := camera.global_transform.basis.x
	forward.y = 0
	right.y = 0
	var direction := (right.normalized() * axis.x + forward.normalized() * -axis.y).normalized()
	var target_speed := RUN_SPEED if Input.is_action_pressed("sprint") and not aiming else (3.2 if aiming else WALK_SPEED)
	var target := direction * target_speed
	velocity.x = move_toward(velocity.x, target.x, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCELERATION * delta)
	if aiming:
		visual.rotation.y = lerp_angle(visual.rotation.y, camera_yaw, minf(1.0, 20.0 * delta))
	elif direction.length_squared() > 0.01:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-direction.x, -direction.z), minf(1.0, 12.0 * delta))
	if is_on_wall():
		CharacterStep.climb(self, Vector3(velocity.x,0,velocity.z) * delta, 0.42)
	move_and_slide()
	human.update_motion(Vector2(velocity.x, velocity.z).length(), is_on_floor())
	for index in range(get_slide_collision_count()):
		var hit := get_slide_collision(index)
		if hit.get_collider() is InteractiveProp:
			var prop := hit.get_collider() as InteractiveProp
			if prop.linear_velocity.length() < 3.0:
				prop.freeze = false
				prop.apply_central_impulse(Vector3(velocity.x, 0, velocity.z).normalized() * 0.6)
	step_timer -= delta
	if is_on_floor() and direction.length_squared() > 0.01 and step_timer <= 0.0:
		if DisplayServer.get_name() != "headless":
			step_audio.play()
		step_timer = 0.29 if Input.is_action_pressed("sprint") else 0.43


func _swim(delta: float) -> void:
	swimming = true
	# Surfacing must win even while the dive key is held.
	diving = Input.is_action_pressed("dive") and not Input.is_action_pressed("jump")
	var axis := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward := -camera.global_transform.basis.z
	var right := camera.global_transform.basis.x
	forward.y = 0.0
	right.y = 0.0
	var direction := (right.normalized() * axis.x + forward.normalized() * -axis.y).normalized()
	var target := direction * (DIVE_SPEED if diving else SWIM_SPEED)
	velocity.x = move_toward(velocity.x, target.x, 7.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 7.0 * delta)
	var bed := sector_data.height_at(global_position.x, global_position.z)
	var target_y := maxf(bed + 0.45, -2.4) if diving else maxf(bed + 0.1, -0.65)
	if Input.is_action_pressed("jump"):
		target_y = -0.15
	velocity.y = clampf((target_y - global_position.y) * 4.0, -2.5, 2.5)
	move_and_slide()
	if direction.length_squared() > 0.01:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-direction.x, -direction.z), minf(1.0, 6.0 * delta))
	swim_phase += delta * (5.0 if direction.length_squared() > 0.01 else 2.4)
	visual.rotation.x = move_toward(visual.rotation.x, -1.1 if diving or direction.length_squared() > 0.01 else -0.25, 3.0 * delta)
	# Keep shoulders/head above the rendered surface when the rig leans forward.
	var swim_offset := 0.0 if diving else 0.4 if direction.length_squared() > 0.01 else -0.35
	visual.position.y = move_toward(visual.position.y, swim_offset, 2.0 * delta)
	human.update_swim(swim_phase, direction.length(), diving)
	if global_position.y < -1.1:
		breath = maxf(0.0, breath - delta)
		if breath <= 0.0:
			take_damage(18.0 * delta, "drowning")
	else:
		breath = minf(MAX_BREATH, breath + 3.0 * delta)


func reset_swimming() -> void:
	swimming = false
	diving = false
	breath = MAX_BREATH
	visual.rotation.x = 0.0
	visual.position.y = 0.0
	human.clear_swim_pose()


func _interact() -> void:
	if driving_vehicle != null:
		var car := driving_vehicle
		driving_vehicle = null
		car.driver = null
		car.set_occupant("")
		camera_arm.clear_excluded_objects()
		camera_arm.add_excluded_object(get_rid())
		global_position = _safe_exit_position(car)
		velocity = Vector3.ZERO
		visual.visible = true
		collider.set_deferred("disabled", false)
		return
	for interior in get_tree().get_nodes_in_group("interiors"):
		if interior.has_method("try_interact") and bool(interior.call("try_interact", self)):
			return
	var best: DriveableVehicle
	var best_distance := 4.0
	for node in get_tree().get_nodes_in_group("vehicles"):
		var vehicle := node as DriveableVehicle
		if vehicle == null or vehicle.driver != null:
			continue
		var distance := global_position.distance_to(vehicle.global_position)
		if distance < best_distance:
			best = vehicle
			best_distance = distance
	if best != null:
		board_vehicle(best)
		vehicle_entered.emit(best)
		return
	var contact := nearby_contact()
	if contact != null:
		contact_interacted.emit(contact)
		return
	var civilian: Pedestrian
	var distance := 2.8
	for node in get_tree().get_nodes_in_group("pedestrians"):
		var person := node as Pedestrian
		if person == null or person.mission_contact or person.state == Pedestrian.State.DOWN:
			continue
		var gap := global_position.distance_to(person.global_position)
		if gap < distance:
			civilian = person
			distance = gap
	if civilian != null:
		civilian_interacted.emit(civilian)


## Put the player in the driver seat (used by interaction and save loading).
func board_vehicle(car: DriveableVehicle) -> void:
	reset_swimming()
	if car.traffic or car.occupant_name != "":
		var ejected := car.eject_occupant()
		vehicle_jacked.emit(car, ejected)
	driving_vehicle = car
	car.driver = self
	car.auto_drive = false
	car.pursuing = false
	car.traffic = false
	car.set_occupant(human.model_name)
	camera_arm.add_excluded_object(car.get_rid())
	visual.visible = false
	collider.set_deferred("disabled", true)


func take_damage(amount: float, source: String = "") -> void:
	if dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health)
	if health <= 0.0:
		dead = true
		if driving_vehicle == null:
			human.play_action("death", 999.0)
		died.emit()


func heal_full() -> void:
	reset_swimming()
	health = MAX_HEALTH
	dead = false
	human.action_timer = 0.0
	health_changed.emit(health)


func heal(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	health = minf(MAX_HEALTH, health + amount)
	health_changed.emit(health)


## On-foot punch: the hit lands 0.25 s into the clip on the nearest person in front.
func punch() -> void:
	if dead or driving_vehicle != null or attack_cooldown > 0.0:
		return
	attack_cooldown = 0.65
	human.play_action("punch", 0.55)
	get_tree().create_timer(0.25, false).timeout.connect(_land_punch)


func _land_punch() -> void:
	if dead or driving_vehicle != null:
		return
	var forward := -visual.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	for node in get_tree().get_nodes_in_group("pedestrians"):
		var person := node as Pedestrian
		if person == null or person.mission_contact or person.state == Pedestrian.State.DOWN:
			continue
		var offset := person.global_position - global_position
		offset.y = 0.0
		if offset.length() < PUNCH_RANGE and offset.normalized().dot(forward) > 0.35:
			var probe := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, person.global_position + Vector3.UP)
			probe.exclude = [get_rid()]
			var hit := get_world_3d().direct_space_state.intersect_ray(probe)
			if not hit.is_empty() and hit.get("collider") != person:
				continue
			person.provoked_by_player = true
			person.take_hit(global_position, 4.0)
			assaulted.emit(person)
			var defenders := 0
			for witness in get_tree().get_nodes_in_group("pedestrians"):
				if witness != person and not witness.mission_contact and not witness.dead and witness.state != Pedestrian.State.DOWN and witness.temperament > 0.85 and witness.global_position.distance_squared_to(person.global_position) < 36.0:
					witness.start_fight(12.0)
					defenders += 1
					if defenders >= 2:
						break
			return


func nearby_vehicle() -> DriveableVehicle:
	if driving_vehicle != null:
		return driving_vehicle
	for node in get_tree().get_nodes_in_group("vehicles"):
		var vehicle := node as DriveableVehicle
		if vehicle != null and global_position.distance_to(vehicle.global_position) < 4.0:
			return vehicle
	return null


func nearby_contact() -> Pedestrian:
	if driving_vehicle != null:
		return null
	for node in get_tree().get_nodes_in_group("mission_contacts"):
		var contact := node as Pedestrian
		if contact != null and global_position.distance_to(contact.global_position) < 3.4:
			return contact
	return null


## Pick the first free spot beside the car (driver side, passenger side, behind, front).
func _safe_exit_position(car: DriveableVehicle) -> Vector3:
	if car.boat and sector_data != null:
		# Step onto the nearest dry ground within reach, else into the water beside the boat.
		for radius: float in [3.0, 5.0, 7.0, 9.0]:
			for k in range(12):
				var dir := Vector3(cos(k * TAU / 12.0), 0, sin(k * TAU / 12.0))
				var spot := car.global_position + dir * radius
				if sector_data.surface_at(spot.x, spot.z) != "sea" or sector_data.height_at(spot.x, spot.z) > -0.3:
					return Vector3(spot.x, maxf(sector_data.height_at(spot.x, spot.z), 0.0) + 0.3, spot.z)
		return car.global_position + car.global_transform.basis.x * 2.6 + Vector3(0, 0.2, 0)
	var car_basis := car.global_transform.basis
	var candidates: Array[Vector3] = [car_basis.x * 2.4, -car_basis.x * 2.4, car_basis.z * 3.4, -car_basis.z * 3.4]
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.75
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.exclude = [car.get_rid(), get_rid()]
	var space := get_world_3d().direct_space_state
	for offset in candidates:
		var spot := car.global_position + Vector3(offset.x, 0.2, offset.z)
		query.transform = Transform3D(Basis.IDENTITY, spot + Vector3(0, 1.0, 0))
		# Building colliders are one-sided shells: a spot already past a wall does not
		# overlap anything, so also require a clear line from the car to the spot.
		var line := PhysicsRayQueryParameters3D.create(car.global_position + Vector3(0, 1.0, 0), spot + Vector3(0, 1.0, 0) + Vector3(offset.x, 0, offset.z).normalized() * 0.4)
		line.exclude = [car.get_rid(), get_rid()]
		if space.intersect_shape(query, 1).is_empty() and space.intersect_ray(line).is_empty():
			return spot
	return car.global_position + Vector3(0, 2.2, 0)
