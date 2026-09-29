class_name DriveableVehicle
extends CharacterBody3D

const CarScene = preload("res://assets/procedural/compact_car.glb")

const MAX_FORWARD_SPEED := 22.0
const MAX_REVERSE_SPEED := 8.0
const ACCELERATION := 16.0
const BRAKE_DECELERATION := 26.0
const HANDBRAKE_DECELERATION := 20.0
const DRAG := 7.0
const TURN_RATE := 1.6
const STEER_RESPONSE := 6.0
const AI_REPATH_SECONDS := 1.0
const AI_STUCK_SECONDS := 1.3
const AI_REVERSE_SECONDS := 1.1

var driver: PlayerController
var speed := 0.0
var steer_input := 0.0
var body_color := Color("c3614c")
var auto_drive := false
var route: Array[Vector3] = []
var route_index := 0
var pursuing := false
var pursuit_target := Vector3.ZERO
var pursuit_speed := 14.0
var road_network: RoadNetwork
var engine_audio: AudioStreamPlayer3D
var ai_path := PackedVector3Array()
var ai_path_index := 0
var ai_path_goal := Vector3.INF
var ai_repath_timer := 0.0
var ai_stuck_timer := 0.0
var ai_wait_timer := 0.0
var ai_reverse_timer := 0.0
var ai_reverse_steer := 1.0
var ai_blocker: Object


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
		_drive_from_input(delta)
	elif ai_reverse_timer > 0.0:
		_reverse_out(delta)
	elif pursuing:
		_pursue(delta)
	elif auto_drive and route.size() > 1:
		_follow_route(delta)
	else:
		speed = move_toward(speed, 0.0, DRAG * delta)
	var forward := -global_transform.basis.z
	velocity = forward * speed
	velocity.y = -8.0 if not is_on_floor() else -0.2
	move_and_slide()
	var engine_load := clampf(absf(speed) / MAX_FORWARD_SPEED, 0.0, 1.0)
	engine_audio.pitch_scale = 0.8 + engine_load * 0.75
	engine_audio.volume_db = -22.0 + engine_load * 9.0
	if is_on_wall():
		# Head-on impacts stop the car; glancing contacts keep most speed and slide.
		var impact := absf(forward.dot(get_wall_normal()))
		speed *= clampf(1.0 - impact * 0.85, 0.1, 1.0)


func _drive_from_input(delta: float) -> void:
	var throttle := Input.get_axis("move_back", "move_forward")
	var handbrake := Input.is_action_pressed("brake")
	var target_speed := throttle * (MAX_FORWARD_SPEED if throttle >= 0.0 else MAX_REVERSE_SPEED)
	var rate := DRAG
	if absf(throttle) > 0.05:
		# Pressing against the direction of travel brakes harder before reversing.
		rate = BRAKE_DECELERATION if throttle * speed < -0.1 else ACCELERATION
	speed = move_toward(speed, target_speed, rate * delta)
	if handbrake:
		speed = move_toward(speed, 0.0, HANDBRAKE_DECELERATION * delta)
	steer_input = move_toward(steer_input, Input.get_axis("move_left", "move_right"), STEER_RESPONSE * delta)
	var speed_factor := clampf(absf(speed) / 5.0, 0.0, 1.0)
	var high_speed_scale := lerpf(1.0, 0.62, clampf(absf(speed) / MAX_FORWARD_SPEED, 0.0, 1.0))
	var handbrake_scale := 1.45 if handbrake and absf(speed) > 6.0 else 1.0
	rotation.y -= steer_input * TURN_RATE * speed_factor * high_speed_scale * handbrake_scale * signf(speed) * delta


func _follow_route(delta: float) -> void:
	var target := route[route_index]
	var offset := target - global_position
	offset.y = 0
	if offset.length() < 5.0:
		route_index = (route_index + 1) % route.size()
		target = route[route_index]
	_follow_target(delta, target, 8.0)


## Police pursuit: follow the road graph toward the last known player position.
func _pursue(delta: float) -> void:
	ai_repath_timer -= delta
	var goal := pursuit_target
	var direct := _flat_distance(global_position, goal)
	if road_network != null and (ai_path.is_empty() or ai_repath_timer <= 0.0 or _flat_distance(goal, ai_path_goal) > 10.0):
		ai_path = road_network.find_path(global_position, goal)
		ai_path_index = 0
		ai_path_goal = goal
		ai_repath_timer = AI_REPATH_SECONDS
	var target := goal
	var cruise := pursuit_speed
	var on_final_leg := ai_path.is_empty() or ai_path_index >= ai_path.size() - 1
	if not on_final_leg or direct > 25.0:
		while ai_path_index < ai_path.size() - 1 and _flat_distance(global_position, ai_path[ai_path_index]) < 7.0:
			ai_path_index += 1
		if ai_path_index < ai_path.size():
			target = ai_path[ai_path_index]
			var to_waypoint := _flat_distance(global_position, target)
			if ai_path_index < ai_path.size() - 1 and to_waypoint < 22.0:
				var incoming := (target - global_position).normalized()
				var outgoing := (ai_path[ai_path_index + 1] - target).normalized()
				if incoming.dot(outgoing) < 0.6:
					cruise = minf(cruise, 8.0)
	if direct < 6.0:
		cruise = 0.0
	_follow_target(delta, target, cruise)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _follow_target(delta: float, target: Vector3, cruise_speed: float) -> void:
	var offset := target - global_position
	offset.y = 0
	if offset.length_squared() < 0.01:
		speed = move_toward(speed, 0.0, 16.0 * delta)
		return
	var desired_angle := atan2(-offset.x, -offset.z)
	rotation.y = lerp_angle(rotation.y, desired_angle, minf(1.0, 2.4 * delta))
	var look_ahead := -global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.8, global_position + look_ahead * 7.0 + Vector3.UP * 0.8)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var blocked := not hit.is_empty()
	ai_blocker = hit.get("collider") if blocked else null
	var target_speed := 0.0 if blocked else cruise_speed
	var acceleration := 10.0 if pursuing else 6.0
	speed = move_toward(speed, target_speed, (16.0 if blocked or speed > target_speed else acceleration) * delta)
	_update_stuck(delta, blocked, cruise_speed)


## Static geometry ahead (or a long wait behind traffic while pursuing) triggers a
## short reverse manoeuvre so AI cars never stay wedged against a façade.
func _update_stuck(delta: float, blocked: bool, cruise_speed: float) -> void:
	if cruise_speed <= 0.5:
		ai_stuck_timer = 0.0
		ai_wait_timer = 0.0
		return
	var static_block := blocked and ai_blocker is StaticBody3D
	var dynamic_block := blocked and not static_block
	var player_block := dynamic_block and (ai_blocker is PlayerController or (ai_blocker is DriveableVehicle and (ai_blocker as DriveableVehicle).driver != null))
	if static_block or (not blocked and absf(speed) < 0.6):
		ai_stuck_timer += delta
	else:
		ai_stuck_timer = 0.0
	if dynamic_block and pursuing and not player_block:
		ai_wait_timer += delta
	else:
		ai_wait_timer = 0.0
	if ai_stuck_timer > AI_STUCK_SECONDS or ai_wait_timer > 3.0:
		ai_stuck_timer = 0.0
		ai_wait_timer = 0.0
		ai_reverse_timer = AI_REVERSE_SECONDS
		ai_reverse_steer = -ai_reverse_steer
		ai_repath_timer = 0.0


func _reverse_out(delta: float) -> void:
	ai_reverse_timer -= delta
	speed = move_toward(speed, -5.0, 20.0 * delta)
	rotation.y += ai_reverse_steer * 1.2 * delta
