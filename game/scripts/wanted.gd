class_name WantedSystem
extends Node3D

signal wanted_changed(level: int, phase: String)

const VehicleScript = preload("res://scripts/vehicle.gd")

var player: PlayerController
var level := 0
var phase := "clear"
var last_known := Vector3.ZERO
var search_timer := 0.0
var unseen_timer := 0.0
var incident_cooldown := 0.0
var in_restricted_zone := false
var police_cars: Array[DriveableVehicle] = []


func configure(target: PlayerController) -> void:
	player = target


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
	for car in police_cars:
		if not is_instance_valid(car):
			continue
		if _can_see(car, target_pos):
			seen = true
			last_known = target_pos
		if car.global_position.distance_to(last_known) < 22.0:
			reached_last_known = true
		car.pursuit_target = last_known
	if seen:
		search_timer = 0.0
		unseen_timer = 0.0
		_set_phase("pursuit")
	else:
		unseen_timer += delta
		if reached_last_known:
			search_timer += delta
		if reached_last_known or unseen_timer > 5.0:
			_set_phase("search")
		else:
			_set_phase("responding")
		if search_timer >= 10.0 or unseen_timer >= 18.0:
			clear_wanted()


func report_incident(location: Vector3) -> bool:
	if incident_cooldown > 0.0 or not _witness_near(location):
		return false
	incident_cooldown = 14.0
	last_known = location
	search_timer = 0.0
	unseen_timer = 0.0
	level = mini(level + 1, 2)
	_set_phase("responding")
	_spawn_police_car(level)
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
	car.position = Vector3(151.0 if index == 1 else -20.0, 0.2, -78.0)
	car.pursuing = true
	car.pursuit_target = last_known
	get_parent().add_child(car)
	police_cars.append(car)


func _can_see(car: DriveableVehicle, target: Vector3) -> bool:
	if car.global_position.distance_to(target) > 72.0:
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
	incident_cooldown = 8.0
	for car in police_cars:
		if is_instance_valid(car):
			if car.engine_audio != null:
				car.engine_audio.stop()
			car.queue_free()
	police_cars.clear()
	wanted_changed.emit(level, phase)
