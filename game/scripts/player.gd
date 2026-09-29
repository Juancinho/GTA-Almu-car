class_name PlayerController
extends CharacterBody3D

signal contact_interacted(contact: Pedestrian)
signal vehicle_entered(vehicle: DriveableVehicle)

const WALK_SPEED := 5.0
const RUN_SPEED := 8.5
const ACCELERATION := 15.0
const JUMP_SPEED := 5.7
const GRAVITY := 16.0
const FOOT_CAMERA_DISTANCE := 5.0
const DRIVE_CAMERA_DISTANCE := 7.5
const CAMERA_RECENTER_DELAY := 0.9
const GAMEPAD_LOOK_SPEED := 2.6

var camera_pivot: Node3D
var camera_arm: SpringArm3D
var camera: Camera3D
var visual: Node3D
var collider: CollisionShape3D
var step_audio: AudioStreamPlayer3D
var step_timer := 0.0
var driving_vehicle: DriveableVehicle
var camera_yaw := -2.0
var camera_pitch := -0.18
var look_idle_time := 0.0


func _ready() -> void:
	add_to_group("player")
	_build_body()
	_build_camera()
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
	_body_box("Torso", Vector3(0, 1.22, 0), Vector3(0.67, 0.75, 0.33), Color("396f80"))
	_body_box("Shorts", Vector3(0, 0.72, 0), Vector3(0.59, 0.29, 0.34), Color("ba8468"))
	for side in [-1.0, 1.0]:
		_body_box("Arm", Vector3(side * 0.44, 1.16, 0), Vector3(0.18, 0.68, 0.22), Color("b88a68"))
		_body_box("Leg", Vector3(side * 0.17, 0.36, 0), Vector3(0.23, 0.62, 0.25), Color("b88a68"))
		_body_box("Shoe", Vector3(side * 0.17, 0.09, -0.07), Vector3(0.26, 0.18, 0.39), Color("343e41"))
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.27
	head_mesh.height = 0.53
	head.mesh = head_mesh
	head.position = Vector3(0, 1.83, 0)
	head.material_override = _body_material(Color("b88a68"))
	visual.add_child(head)
	_body_box("Hair", Vector3(0, 2.08, 0.01), Vector3(0.48, 0.13, 0.47), Color("403c38"))
	collider = CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.75
	collider.shape = shape
	collider.position.y = 0.875
	add_child(collider)


func _body_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat


func _body_box(label: String, at: Vector3, size: Vector3, color: Color) -> void:
	var part := MeshInstance3D.new()
	part.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = at
	part.material_override = _body_material(color)
	visual.add_child(part)


func _build_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position.y = 1.55
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
	if event.is_action_pressed("interact"):
		_interact()


func _update_camera_orientation() -> void:
	camera_pivot.rotation = Vector3(camera_pitch, camera_yaw, 0)


func _process(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down") if InputMap.has_action("look_left") else Vector2.ZERO
	if look.length_squared() > 0.01:
		camera_yaw -= look.x * GAMEPAD_LOOK_SPEED * delta
		camera_pitch = clampf(camera_pitch - look.y * GAMEPAD_LOOK_SPEED * 0.6 * delta, -1.1, 0.55)
		look_idle_time = 0.0
	else:
		look_idle_time += delta
	var target_length := DRIVE_CAMERA_DISTANCE if driving_vehicle != null else FOOT_CAMERA_DISTANCE
	camera_arm.spring_length = move_toward(camera_arm.spring_length, target_length, 6.0 * delta)
	if driving_vehicle != null and look_idle_time > CAMERA_RECENTER_DELAY:
		# Drift the camera behind the car when the player is not steering the view.
		var follow := minf(1.0, 2.2 * delta * clampf(absf(driving_vehicle.speed) / 4.0, 0.0, 1.0))
		var heading := driving_vehicle.rotation.y + (PI if driving_vehicle.speed < -1.0 else 0.0)
		camera_yaw = lerp_angle(camera_yaw, heading, follow)
		camera_pitch = lerpf(camera_pitch, -0.22, follow)
	_update_camera_orientation()


func _physics_process(delta: float) -> void:
	if driving_vehicle != null:
		global_position = driving_vehicle.global_position + Vector3(0, 0.3, 0)
		return
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
	var target_speed := RUN_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var target := direction * target_speed
	velocity.x = move_toward(velocity.x, target.x, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCELERATION * delta)
	if direction.length_squared() > 0.01:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-direction.x, -direction.z), minf(1.0, 12.0 * delta))
	move_and_slide()
	step_timer -= delta
	if is_on_floor() and direction.length_squared() > 0.01 and step_timer <= 0.0:
		if DisplayServer.get_name() != "headless":
			step_audio.play()
		step_timer = 0.29 if Input.is_action_pressed("sprint") else 0.43


func _interact() -> void:
	if driving_vehicle != null:
		var car := driving_vehicle
		driving_vehicle = null
		car.driver = null
		camera_arm.clear_excluded_objects()
		camera_arm.add_excluded_object(get_rid())
		global_position = _safe_exit_position(car)
		velocity = Vector3.ZERO
		visual.visible = true
		collider.set_deferred("disabled", false)
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


## Put the player in the driver seat (used by interaction and save loading).
func board_vehicle(car: DriveableVehicle) -> void:
	driving_vehicle = car
	car.driver = self
	car.auto_drive = false
	car.pursuing = false
	camera_arm.add_excluded_object(car.get_rid())
	visual.visible = false
	collider.set_deferred("disabled", true)


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
		if space.intersect_shape(query, 1).is_empty():
			return spot
	return car.global_position + Vector3(0, 2.2, 0)
