class_name WantedSystem
extends Node3D

signal wanted_changed(level: int, phase: String)
signal player_busted

const VehicleScript = preload("res://scripts/vehicle.gd")
const SIGHT_RANGE := 95.0
const SEARCH_SECONDS := 12.0
const UNSEEN_SECONDS := 20.0
const SEARCH_RADIUS := 80.0
const ARREST_RADIUS := 8.5
const ARREST_MAX_SPEED := 3.0
const ARREST_SECONDS := 2.5
const PURSUIT_SPEEDS := [0.0, 20.0, 21.5]
## Level 1: the witnessing patrol appears behind the player; level 2 intercepts ahead.
const SPAWN_BANDS := [Vector2.ZERO, Vector2(34.0, 48.0), Vector2(60.0, 85.0)]

var player: PlayerController
var road_network: RoadNetwork
var level := 0
var phase := "clear"
var last_known := Vector3.ZERO
var last_seen_velocity := Vector3.ZERO
var search_timer := 0.0
var unseen_timer := 0.0
var incident_cooldown := 0.0
var arrest_timer := 0.0
var in_restricted_zone := false
var police_cars: Array[DriveableVehicle] = []


func configure(target: PlayerController, network: RoadNetwork = null) -> void:
	player = target
	road_network = network


func _physics_process(delta: float) -> void:
	if player == null:
		return
	incident_cooldown = maxf(0.0, incident_cooldown - delta)
	var restricted := false
	if player.driving_vehicle != null:
		var vehicle_pos := player.driving_vehicle.global_position
		restricted = absf(vehicle_pos.x - 58.0) < 20.0 and absf(vehicle_pos.z + 78.0) < 18.0
		if restricted and not in_restricted_zone and incident_cooldown <= 0.0 and level < 2:
			report_incident(vehicle_pos)
	in_restricted_zone = restricted
	if level == 0:
		return
	var target_pos := player.driving_vehicle.global_position if player.driving_vehicle != null else player.global_position
	var seen := false
	var reached_last_known := false
	var close_unit := false
	for car in police_cars:
		if not is_instance_valid(car):
			continue
		if _can_see(car, target_pos):
			seen = true
			if car.global_position.distance_to(target_pos) < ARREST_RADIUS:
				close_unit = true
		if car.global_position.distance_to(last_known) < 22.0:
			reached_last_known = true
	if seen:
		last_seen_velocity = player.driving_vehicle.velocity if player.driving_vehicle != null else player.velocity
		last_seen_velocity.y = 0.0
		last_known = target_pos
	_update_arrest(delta, close_unit)
	if level == 0:
		return
	if seen:
		search_timer = 0.0
		unseen_timer = 0.0
		_set_phase("pursuit")
	else:
		unseen_timer += delta
		if reached_last_known or unseen_timer > 5.0:
			_set_phase("search")
		elif phase != "search":
			_set_phase("responding")
		if phase == "search":
			search_timer += delta
		if search_timer >= SEARCH_SECONDS or unseen_timer >= UNSEEN_SECONDS:
			clear_wanted()
			return
	_assign_targets(seen)


## Units chase the last sighting; once there, they sweep nearby roads in the
## direction the player was last seen travelling (no live position without sight).
func _assign_targets(seen: bool) -> void:
	var index := 0
	for car in police_cars:
		if not is_instance_valid(car):
			continue
		if seen or phase == "responding":
			car.pursuit_target = last_known
		elif car.global_position.distance_to(car.pursuit_target) < 12.0 or car.pursuit_target.distance_to(last_known) > SEARCH_RADIUS:
			car.pursuit_target = _search_point(index)
		index += 1


func _search_point(index: int) -> Vector3:
	var heading := last_seen_velocity
	heading.y = 0.0
	var ahead := last_known + (heading.normalized() * randf_range(25.0, 60.0) if heading.length() > 1.0 else Vector3.ZERO)
	var jitter := Vector3(randf_range(-30.0, 30.0), 0.0, randf_range(-30.0, 30.0)) * (1.0 + index * 0.5)
	var candidate := ahead + jitter
	if road_network != null:
		var hit := road_network.nearest(candidate)
		if not hit.is_empty():
			candidate = hit["point"]
	return candidate


## A seen player who stays slow next to a police unit for ARREST_SECONDS is arrested.
func _update_arrest(delta: float, close_unit: bool) -> void:
	if close_unit and player_speed() < ARREST_MAX_SPEED:
		arrest_timer += delta
	else:
		arrest_timer = maxf(0.0, arrest_timer - delta * 2.0)
	if arrest_timer >= ARREST_SECONDS:
		arrest_timer = 0.0
		clear_wanted()
		player_busted.emit()


func player_speed() -> float:
	if player.driving_vehicle != null:
		return absf(player.driving_vehicle.speed)
	return Vector2(player.velocity.x, player.velocity.z).length()


func arrest_progress() -> float:
	return clampf(arrest_timer / ARREST_SECONDS, 0.0, 1.0)


func report_incident(location: Vector3) -> bool:
	if incident_cooldown > 0.0 or not _witness_near(location):
		return false
	incident_cooldown = 14.0
	last_known = location
	last_seen_velocity = Vector3.ZERO
	search_timer = 0.0
	unseen_timer = 0.0
	level = mini(level + 1, 2)
	_set_phase("responding")
	_spawn_police_car(level)
	for car in police_cars:
		if is_instance_valid(car):
			car.pursuit_speed = maxf(car.pursuit_speed, PURSUIT_SPEEDS[level])
	wanted_changed.emit(level, phase)
	for node in get_tree().get_nodes_in_group("pedestrians"):
		var person := node as Pedestrian
		if person != null and person.global_position.distance_to(location) < 20.0 and not person.mission_contact:
			person.flee_from(location)
	return true


func _witness_near(location: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group("pedestrians"):
		var person := node as Pedestrian
		if person != null and person.global_position.distance_to(location) < 34.0:
			return true
	return false


func _spawn_police_car(index: int) -> void:
	var car := VehicleScript.new() as DriveableVehicle
	car.name = "Policia_%d" % index
	car.body_color = Color("344d67")
	car.variant = "police_local"
	var spawn := _spawn_point(last_known, index)
	car.position = spawn + Vector3(0, 0.2, 0)
	var facing := last_known - spawn
	car.rotation.y = atan2(-facing.x, -facing.z) if facing.length_squared() > 1.0 else 0.0
	car.pursuing = true
	car.pursuit_target = last_known
	car.pursuit_speed = PURSUIT_SPEEDS[mini(index, 2)]
	car.road_network = road_network
	get_parent().add_child(car)
	police_cars.append(car)


func _spawn_point(location: Vector3, index: int) -> Vector3:
	var fallback := Vector3(151.0 if index == 1 else -20.0, 0.0, -78.0)
	if road_network == null:
		return fallback
	var band: Vector2 = SPAWN_BANDS[mini(index, 2)]
	var heading := _player_heading()
	var best := fallback
	var best_score := INF
	for road in road_network.roads:
		var t := float(road["from"])
		while t <= float(road["to"]):
			var point := Vector3(t, 0, float(road["fixed"])) if str(road["axis"]) == "x" else Vector3(float(road["fixed"]), 0, t)
			t += 4.0
			var distance := Vector2(point.x - location.x, point.z - location.z).length()
			if distance < band.x or distance > band.y:
				continue
			var direction := (point - location).normalized()
			var score := direction.dot(heading)
			if index >= 2:
				score = -score
			for car in police_cars:
				if is_instance_valid(car) and car.global_position.distance_to(point) < 15.0:
					score += 10.0
			if score < best_score:
				best_score = score
				best = point
	return best


func _player_heading() -> Vector3:
	var heading := Vector3.ZERO
	if player.driving_vehicle != null:
		heading = -player.driving_vehicle.global_transform.basis.z * signf(player.driving_vehicle.speed if absf(player.driving_vehicle.speed) > 0.5 else 1.0)
	else:
		heading = Vector3(player.velocity.x, 0, player.velocity.z)
	heading.y = 0
	return heading.normalized() if heading.length_squared() > 0.01 else Vector3.FORWARD


func _can_see(car: DriveableVehicle, target: Vector3) -> bool:
	if car.global_position.distance_to(target) > SIGHT_RANGE:
		return false
	var from := car.global_position + Vector3.UP * 1.4
	var to := target + Vector3.UP * 1.1
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [car.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.get("collider") == player or hit.get("collider") == player.driving_vehicle


func _set_phase(value: String) -> void:
	if phase == value:
		return
	phase = value
	wanted_changed.emit(level, phase)


func clear_wanted() -> void:
	level = 0
	phase = "clear"
	search_timer = 0.0
	unseen_timer = 0.0
	arrest_timer = 0.0
	incident_cooldown = 8.0
	for car in police_cars:
		if is_instance_valid(car):
			if car.engine_audio != null:
				car.engine_audio.stop()
			car.queue_free()
	police_cars.clear()
	wanted_changed.emit(level, phase)
