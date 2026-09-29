class_name DriveableVehicle
extends CharacterBody3D

const CarScene = preload("res://assets/procedural/compact_car.glb")

const MAX_FORWARD_SPEED := 22.0
const MAX_REVERSE_SPEED := 8.0
const ACCELERATION := 16.0
const DRAG := 7.0
const TURN_RATE := 1.6

var driver: PlayerController
var speed := 0.0
var body_color := Color("c3614c")
var auto_drive := false
var route: Array[Vector3] = []
var route_index := 0
var pursuing := false
var pursuit_target := Vector3.ZERO
var engine_audio: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("vehicles")
	_build_visuals()
	engine_audio = AudioStreamPlayer3D.new()
	engine_audio.name = "EngineAudio"
	engine_audio.stream = load("res://assets/audio/engine_loop.wav") as AudioStream
	if engine_audio.stream is AudioStreamWAV:
		(engine_audio.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	engine_audio.bus = "SFX"
	engine_audio.max_distance = 65.0
	engine_audio.volume_db = -22.0
	add_child(engine_audio)
	if DisplayServer.get_name() != "headless":
		engine_audio.play()


func _build_visuals() -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.9, 1.1, 4.0)
	collider.shape = shape
	collider.position.y = 0.6
	add_child(collider)
	var model := CarScene.instantiate() as Node3D
	model.name = "CompactCarVisual"
	add_child(model)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if node.name.begins_with("Body") or node.name.begins_with("Roof"):
			(node as MeshInstance3D).material_override = _material(body_color)


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	return mat


func _physics_process(delta: float) -> void:
	if driver != null:
		var throttle := Input.get_axis("move_back", "move_forward")
		var target_speed := throttle * (MAX_FORWARD_SPEED if throttle >= 0.0 else MAX_REVERSE_SPEED)
		var rate := ACCELERATION if absf(throttle) > 0.05 else DRAG
		speed = move_toward(speed, target_speed, rate * delta)
		if Input.is_action_pressed("brake"):
			speed = move_toward(speed, 0.0, 28.0 * delta)
		var steer := Input.get_axis("move_left", "move_right")
		var speed_factor := clampf(absf(speed) / 6.0, 0.0, 1.0)
		rotation.y -= steer * TURN_RATE * speed_factor * signf(speed) * delta
	elif pursuing:
		_follow_target(delta, pursuit_target, 13.0)
	elif auto_drive and route.size() > 1:
		_follow_route(delta)
	else:
		speed = move_toward(speed, 0.0, DRAG * delta)
	velocity = -global_transform.basis.z * speed
	velocity.y = -8.0 if not is_on_floor() else -0.2
	move_and_slide()
	engine_audio.pitch_scale = 0.8 + clampf(absf(speed) / MAX_FORWARD_SPEED, 0.0, 1.0) * 0.75
	engine_audio.volume_db = -22.0 + clampf(absf(speed) / MAX_FORWARD_SPEED, 0.0, 1.0) * 9.0
	if is_on_wall():
		speed *= 0.3


func _follow_route(delta: float) -> void:
	var target := route[route_index]
	var offset := target - global_position
	offset.y = 0
	if offset.length() < 5.0:
		route_index = (route_index + 1) % route.size()
		target = route[route_index]
		offset = target - global_position
		offset.y = 0
	_follow_target(delta, target, 8.0)


func _follow_target(delta: float, target: Vector3, cruise_speed: float) -> void:
	var offset := target - global_position
	offset.y = 0
	if offset.length_squared() < 0.01:
		return
	var desired_angle := atan2(-offset.x, -offset.z)
	rotation.y = lerp_angle(rotation.y, desired_angle, minf(1.0, 2.4 * delta))
	var look_ahead := -global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.8, global_position + look_ahead * 7.0 + Vector3.UP * 0.8)
	query.exclude = [get_rid()]
	var blocked := not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	var target_speed := 0.0 if blocked else cruise_speed
	speed = move_toward(speed, target_speed, (16.0 if blocked else 6.0) * delta)
