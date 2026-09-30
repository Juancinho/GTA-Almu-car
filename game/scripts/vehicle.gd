class_name DriveableVehicle
extends CharacterBody3D

signal ran_over(victim: Pedestrian)
signal destroyed_vehicle

const CarScene = preload("res://assets/procedural/compact_car.glb")
const MODELS_PATH := "res://data/vehicles/models.json"
static var model_catalog: Dictionary = {}
## Paint materials are shared by colour and live for the whole session, so freeing a
## car never leaves the renderer holding a freed override material.
static var paint_materials: Dictionary = {}

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
const MAX_HEALTH := 1000.0
const IMPACT_THRESHOLD := 7.0
const EXPLOSION_RADIUS := 7.0
const FAR_SIMULATION_M := 130.0  # beyond this, traffic moves kinematically along its lane
static var terrain_rids: Array[RID] = []

var driver: PlayerController
var speed := 0.0
var steer_input := 0.0
var body_color := Color("c3614c")
var variant := "compact_generated"
var auto_drive := false
var route: Array[Vector3] = []
var route_index := 0
var pursuing := false
var traffic := false
var traffic_speed := 10.0
var lane_from := -1
var lane_to := -1
var lane_next := -1
var traffic_rng := RandomNumberGenerator.new()
var occupant: HumanModel
var health := MAX_HEALTH
var destroyed := false
var burn_timer := -1.0
var damage_fx: VehicleDamageFx
var far_tick := 0
var recent_speed := 0.0  # decaying peak speed: contacts are often reported a frame after the impact
var occupant_name := ""
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
var sector_data: SectorData
var last_dry_transform := Transform3D.IDENTITY


func _ready() -> void:
	add_to_group("vehicles")
	var sectors := get_tree().get_nodes_in_group("sector_world")
	if not sectors.is_empty():
		sector_data = (sectors[0] as SectorWorld).data
	last_dry_transform = global_transform
	floor_snap_length = 0.45
	_build_visuals()
	engine_audio = AudioStreamPlayer3D.new()
	engine_audio.name = "EngineAudio"
	engine_audio.stream = load("res://assets/audio/engine_loop.wav") as AudioStream
	if engine_audio.stream is AudioStreamWAV:
		(engine_audio.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	engine_audio.bus = "SFX"
	damage_fx = VehicleDamageFx.new()
	damage_fx.name = "DamageFx"
	add_child(damage_fx)
	engine_audio.max_distance = 65.0
	engine_audio.volume_db = -22.0
	add_child(engine_audio)
	if DisplayServer.get_name() != "headless":
		engine_audio.play()


func _build_visuals() -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.9, 1.2, 4.1)
	collider.shape = shape
	collider.position.y = 0.65
	add_child(collider)
	_build_model()


func _build_model() -> void:
	var spec := variant_spec(variant)
	var scene: PackedScene = CarScene
	if spec.has("scene"):
		scene = load(str(spec["scene"])) as PackedScene
	if scene == null:
		push_error("Vehicle %s: model for variant '%s' failed to load" % [name, variant])
		scene = CarScene
	var model := scene.instantiate() as Node3D
	model.name = "CarVisual"
	model.rotation.y = deg_to_rad(float(spec.get("yaw_degrees", 0.0)))
	add_child(model)
	var paint: Dictionary = spec.get("paint", {})
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		mesh_instance.visibility_range_end = 220.0
		if scene == CarScene:
			if node.name.begins_with("Body") or node.name.begins_with("Roof"):
				mesh_instance.material_override = _material(body_color)
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.mesh.surface_get_material(surface)
			if source != null and paint.has(source.resource_name):
				mesh_instance.set_surface_override_material(surface, _material(Color(str(paint[source.resource_name]))))


## Variant data from res://data/vehicles/models.json (cached for all vehicles).
static func variant_spec(key: String) -> Dictionary:
	if model_catalog.is_empty():
		var file := FileAccess.open(MODELS_PATH, FileAccess.READ)
		if file == null:
			push_error("Vehicle models missing: " + MODELS_PATH)
			return {}
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if not parsed is Dictionary:
			push_error("Invalid vehicle model data: " + MODELS_PATH)
			return {}
		model_catalog = parsed
	return (model_catalog.get("variants", {}) as Dictionary).get(key, {})


static func traffic_variants() -> Array:
	variant_spec("")
	return model_catalog.get("traffic", [])


## Seated driver model (NPC or player) visible through the windows; "" hides it.
func set_occupant(model_name: String) -> void:
	occupant_name = model_name
	if model_name == "":
		if occupant != null:
			occupant.visible = false
		return
	if occupant == null or occupant.model_name != model_name:
		if occupant != null:
			occupant.queue_free()
		occupant = HumanModel.new(model_name)
		occupant.name = "Occupant"
		# FBX sitting animation retains a tall root offset. Keep the seated model
		# under the roof line while the on-foot player body is hidden.
		occupant.position = Vector3(-0.38, -0.45, 0.15)
		add_child(occupant)
	occupant.visible = true
	occupant.play_state("sitting")


## Carjacking: the NPC driver gets out on the far side and runs away.
func eject_occupant() -> Pedestrian:
	traffic = false
	if occupant_name == "" or get_parent() == null:
		set_occupant("")
		return null
	var person := Pedestrian.new()
	person.name = "Conductor_%s" % name
	person.model_name = occupant_name
	get_parent().add_child(person)
	person.global_position = global_position - global_transform.basis.x * 2.4 + Vector3(0, 0.1, 0)
	person.flee_from(global_position)
	set_occupant("")
	return person


## Right-hand lane driving on the road graph with random turns at intersections.
func start_traffic(network: RoadNetwork, from_node: int, to_node: int, seed_value: int) -> void:
	road_network = network
	traffic = true
	lane_from = from_node
	lane_to = to_node
	traffic_rng.seed = seed_value
	traffic_speed = traffic_rng.randf_range(8.0, 11.0)
	lane_next = _choose_next(lane_from, lane_to)


func _lane_offset(a: int, b: int) -> float:
	return road_network.lane_offset if road_network.is_two_way(a, b) else 0.0


func _drive_traffic(delta: float) -> void:
	var a := road_network.nodes[lane_from]
	var b := road_network.nodes[lane_to]
	var segment := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := segment.length()
	if length < 0.3:
		_advance_lane()
		return
	var direction := segment / length
	var right := Vector3(-direction.z, 0.0, direction.x)
	var along := Vector3(global_position.x - a.x, 0.0, global_position.z - a.z).dot(direction)
	if along > length - 3.0:
		_advance_lane()
		return
	var look := along + 10.0
	var aim: Vector3
	if look <= length:
		aim = a + direction * look + right * _lane_offset(lane_from, lane_to)
	else:  # look ahead into the next segment so curves are anticipated
		var c := road_network.nodes[lane_next]
		var next_dir := Vector3(c.x - b.x, 0.0, c.z - b.z).normalized()
		aim = b + next_dir * (look - length) + Vector3(-next_dir.z, 0.0, next_dir.x) * _lane_offset(lane_to, lane_next)
	var cruise := traffic_speed
	if length - along < 20.0 and _turn_is_sharp(direction):
		cruise = minf(cruise, 5.5)
	_follow_target(delta, aim, cruise)


func _turn_is_sharp(direction: Vector3) -> bool:
	if (road_network.edges[lane_to] as Array).size() > 2:
		return true  # intersection: slow down
	var b := road_network.nodes[lane_to]
	var c := road_network.nodes[lane_next]
	var next_dir := Vector3(c.x - b.x, 0.0, c.z - b.z).normalized()
	return direction.dot(next_dir) < 0.85


func _choose_next(from_node: int, to_node: int) -> int:
	var options: Array = (road_network.edges[to_node] as Array).duplicate()
	if options.size() > 1:
		options.erase(from_node)
	if options.is_empty():
		return from_node
	return options[traffic_rng.randi_range(0, options.size() - 1)]


func _advance_lane() -> void:
	lane_from = lane_to
	lane_to = lane_next
	lane_next = _choose_next(lane_from, lane_to)


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if paint_materials.has(key):
		return paint_materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	paint_materials[key] = mat
	return mat


func _physics_process(delta: float) -> void:
	if _deep_water(global_position):
		global_transform = last_dry_transform
		speed = 0.0
		velocity = Vector3.ZERO
		return
	if burn_timer > 0.0:
		var before := burn_timer
		burn_timer -= delta
		if int(before) != int(burn_timer):
			_scare_bystanders(15.0)  # once per second while burning
		if burn_timer <= 0.0:
			_explode()
	if destroyed:
		speed = move_toward(speed, 0.0, 20.0 * delta)
	elif driver != null:
		_drive_from_input(delta)
	elif ai_reverse_timer > 0.0:
		_reverse_out(delta)
	elif pursuing:
		_pursue(delta)
	elif traffic and road_network != null and lane_to >= 0:
		if _far_from_player():
			_far_traffic_step(delta)
			return
		_drive_traffic(delta)
	elif auto_drive and route.size() > 1:
		_follow_route(delta)
	else:
		speed = move_toward(speed, 0.0, DRAG * delta)
	var forward := -global_transform.basis.z
	if absf(speed) > 0.1 and _deep_water(global_position + forward * (speed * delta + signf(speed) * 2.3)):
		speed = 0.0
	velocity = forward * speed
	velocity.y = maxf(velocity.y - 16.0 * delta, -18.0) if not is_on_floor() else -0.2
	var speed_before := absf(speed)
	recent_speed = maxf(speed_before, recent_speed - 25.0 * delta)
	move_and_slide()
	if not _deep_water(global_position) and is_on_floor():
		last_dry_transform = global_transform
	_resolve_contacts(recent_speed)
	var engine_load := clampf(absf(speed) / MAX_FORWARD_SPEED, 0.0, 1.0)
	engine_audio.pitch_scale = 0.8 + engine_load * 0.75
	engine_audio.volume_db = -22.0 + engine_load * 9.0
	if is_on_wall():
		# Head-on impacts stop the car; glancing contacts keep most speed and slide.
		var impact := absf(forward.dot(get_wall_normal()))
		apply_damage(maxf(0.0, speed_before * impact - IMPACT_THRESHOLD) ** 2 * 2.5)
		speed *= clampf(1.0 - impact * 0.85, 0.1, 1.0)


func _deep_water(at: Vector3) -> bool:
	return sector_data != null and sector_data.surface_at(at.x, at.z) == "sea" and sector_data.height_at(at.x, at.z) < -0.7


## Pedestrians and an on-foot player hit at speed are knocked down / hurt.
func _resolve_contacts(speed_before: float) -> void:
	if speed_before < 3.5:
		return
	for i in range(get_slide_collision_count()):
		var other := get_slide_collision(i).get_collider()
		if other is Pedestrian and (other as Pedestrian).state != Pedestrian.State.DOWN:
			(other as Pedestrian).knock_down(global_position, speed_before)
			ran_over.emit(other)
			if driver != null:
				get_tree().call_group("wanted_system", "report_crime", "atropello", global_position)
		elif other is PlayerController and (other as PlayerController).driving_vehicle == null:
			(other as PlayerController).take_damage(speed_before * 2.5, "vehicle")


func apply_damage(amount: float) -> void:
	if destroyed or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		if burn_timer < 0.0:
			burn_timer = 4.0  # burning countdown: get out!
		damage_fx.set_stage(2)
	elif health < 150.0:
		damage_fx.set_stage(2)
		if burn_timer < 0.0:
			burn_timer = 6.0
	elif health < 400.0:
		damage_fx.set_stage(1)


func _scare_bystanders(radius: float) -> void:
	for node in get_tree().get_nodes_in_group("pedestrians"):
		var person := node as Pedestrian
		if person != null and not person.mission_contact and person.global_position.distance_to(global_position) < radius:
			person.flee_from(global_position)


func _explode() -> void:
	destroyed = true
	burn_timer = -1.0
	traffic = false
	pursuing = false
	engine_audio.stop()
	damage_fx.set_stage(3)
	damage_fx.explode()
	var burnt := StandardMaterial3D.new()
	burnt.albedo_color = Color("1d1b1a")
	burnt.roughness = 1.0
	var model := get_node_or_null("CarVisual")
	if model != null:
		for node in model.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).material_override = burnt
	if occupant != null and occupant_name != "" and driver == null:
		set_occupant("")
	for node in get_tree().get_nodes_in_group("pedestrians"):
		var person := node as Pedestrian
		if person != null and person.global_position.distance_to(global_position) < EXPLOSION_RADIUS:
			person.knock_down(global_position, 8.0)
	for node in get_tree().get_nodes_in_group("player"):
		var target := node as PlayerController
		if target == null:
			continue
		if target.driving_vehicle == self:
			target.take_damage(target.health + 1.0, "explosion")
		elif target.global_position.distance_to(global_position) < EXPLOSION_RADIUS:
			target.take_damage(70.0 * (1.0 - target.global_position.distance_to(global_position) / EXPLOSION_RADIUS) + 10.0, "explosion")
	for node in get_tree().get_nodes_in_group("vehicles"):
		var car := node as DriveableVehicle
		if car != null and car != self and car.global_position.distance_to(global_position) < EXPLOSION_RADIUS:
			car.apply_damage(350.0)
	destroyed_vehicle.emit()


## Back to factory condition (used when the mission car is reset after death/arrest).
func repair() -> void:
	health = MAX_HEALTH
	destroyed = false
	burn_timer = -1.0
	damage_fx.set_stage(0)
	var model := get_node_or_null("CarVisual")
	if model != null:
		remove_child(model)
		model.queue_free()
	_build_model()
	if DisplayServer.get_name() != "headless" and not engine_audio.playing:
		engine_audio.play()


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
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.0, global_position + look_ahead * 7.0 + Vector3.UP * 1.0)
	query.exclude = _ray_exclusions()
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var blocked := not hit.is_empty()
	ai_blocker = hit.get("collider") if blocked else null
	var target_speed := 0.0 if blocked else cruise_speed
	var acceleration := 10.0 if pursuing else 6.0
	speed = move_toward(speed, target_speed, (16.0 if blocked or speed > target_speed else acceleration) * delta)
	_update_stuck(delta, blocked, cruise_speed)


## The ground never counts as an obstacle (steep old-town lanes would read as walls).
func _ray_exclusions() -> Array[RID]:
	if terrain_rids.is_empty() or not terrain_rids[0].is_valid():
		terrain_rids.clear()
		for node in get_tree().get_nodes_in_group("terrain"):
			terrain_rids.append((node as CollisionObject3D).get_rid())
	var list: Array[RID] = [get_rid()]
	list.append_array(terrain_rids)
	return list


func _far_from_player() -> bool:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return false
	var p := (players[0] as Node3D).global_position
	return Vector2(p.x - global_position.x, p.z - global_position.z).length() > FAR_SIMULATION_M


## Distance-based simulation: far traffic glides along its lane every 4th tick with no
## physics queries; it snaps back to full physics when the player comes close.
func _far_traffic_step(delta: float) -> void:
	far_tick += 1
	if far_tick % 4 != 0:
		return
	var step := traffic_speed * delta * 4.0
	var a := road_network.nodes[lane_from]
	var b := road_network.nodes[lane_to]
	var segment := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := segment.length()
	if length < 0.3:
		_advance_lane()
		return
	var direction := segment / length
	var along := Vector3(global_position.x - a.x, 0.0, global_position.z - a.z).dot(direction) + step
	if along >= length:
		_advance_lane()
		return
	var offset := _lane_offset(lane_from, lane_to)
	var point := a.lerp(b, along / length) + Vector3(-direction.z, 0.0, direction.x) * offset
	global_position = Vector3(point.x, point.y + 0.35, point.z)
	rotation.y = atan2(-direction.x, -direction.z)
	speed = traffic_speed


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
	if dynamic_block and (pursuing or traffic) and not (player_block and pursuing):
		ai_wait_timer += delta
	else:
		ai_wait_timer = 0.0
	var patience := 3.0 if pursuing else (6.0 if player_block else 4.5)
	if ai_stuck_timer > AI_STUCK_SECONDS or ai_wait_timer > patience:
		ai_stuck_timer = 0.0
		ai_wait_timer = 0.0
		ai_reverse_timer = AI_REVERSE_SECONDS
		ai_reverse_steer = -ai_reverse_steer
		ai_repath_timer = 0.0


func _reverse_out(delta: float) -> void:
	ai_reverse_timer -= delta
	speed = move_toward(speed, -5.0, 20.0 * delta)
	rotation.y += ai_reverse_steer * 1.2 * delta
