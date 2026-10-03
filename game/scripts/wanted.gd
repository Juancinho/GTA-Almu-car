class_name WantedSystem
extends Node3D

signal wanted_changed(level: int, phase: String)
signal player_busted
signal crime_reported(kind: String, witnessed: bool)

const VehicleScript = preload("res://scripts/vehicle.gd")
const OfficerScript = preload("res://scripts/police_officer.gd")
const EscalationScript = preload("res://scripts/police_escalation.gd")
const MAX_LEVEL := 5
const OFFICER_DEPLOY_RANGE := 18.0
const OFFICERS_PER_CAR := 2
const SIGHT_RANGE := 95.0
const SEARCH_SECONDS := 12.0
const UNSEEN_SECONDS := 20.0
const SEARCH_RADIUS := 80.0
const ARREST_RADIUS := 8.5
const ARREST_MAX_SPEED := 3.0
const ARREST_SECONDS := 2.5
const PURSUIT_SPEEDS := [0.0, 20.0, 21.5, 23.0, 24.0, 25.0]
## Level 1: the witnessing patrol appears behind the player; level 2 intercepts ahead.
const SPAWN_BANDS := [Vector2.ZERO, Vector2(34.0, 48.0), Vector2(60.0, 85.0), Vector2(55.0, 95.0), Vector2(55.0, 110.0), Vector2(50.0, 120.0)]

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
var officers: Array[Node] = []
var reinforce_timer := 0.0
var stopped_time := 0.0
var spawn_serial := 0
var escalation: Node3D  # roadblocks (3+ stars) and the helicopter (4+)
var restricted_zones: Array = []  # [{name, x, z, radius}] from the sector data


func configure(target: PlayerController, network: RoadNetwork = null) -> void:
	player = target
	road_network = network
	add_to_group("wanted_system")
	escalation = EscalationScript.new()
	escalation.name = "PoliceEscalation"
	add_child(escalation)
	escalation.call("configure", self, player, network)


## Another police eye (the helicopter, a roadblock) has the player in sight.
func notify_sighting(at: Vector3) -> void:
	if level == 0:
		return
	last_known = at
	unseen_timer = 0.0
	search_timer = 0.0
	_set_phase("pursuit")


## Any player crime (assault, running someone over, carjacking seen by police...).
## Witnessed crimes raise the wanted level, subject to the incident cooldown.
func report_crime(kind: String, location: Vector3) -> void:
	var witnessed := report_incident(location)
	crime_reported.emit(kind, witnessed)


func report_scripted_crime(kind: String, location: Vector3) -> void:
	# A staffed venue has its own alarm, independent of nearby outdoor pedestrians.
	incident_cooldown = 0.0
	var reported := report_incident(location, true)
	crime_reported.emit(kind, reported)


func _physics_process(delta: float) -> void:
	if player == null:
		return
	incident_cooldown = maxf(0.0, incident_cooldown - delta)
	var restricted := false
	if player.driving_vehicle != null:
		var vehicle_pos := player.driving_vehicle.global_position
		for zone in restricted_zones:
			if Vector2(vehicle_pos.x - float(zone["x"]), vehicle_pos.z - float(zone["z"])).length() < float(zone["radius"]):
				restricted = true
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
		if not is_instance_valid(car) or car.destroyed:
			continue
		if _can_see(car, target_pos):
			seen = true
			# On foot a patrol car alongside is enough. In a car only a stopped car
			# counts (or an officer at the door): a cruiser blocking a narrow lane
			# while you shunt back and forth to get out is not an arrest.
			if car.global_position.distance_to(target_pos) < ARREST_RADIUS and (player.driving_vehicle == null or absf(player.driving_vehicle.speed) < 0.5):
				close_unit = true
		if car.global_position.distance_to(last_known) < 22.0:
			reached_last_known = true
	officers = officers.filter(func(o: Node) -> bool: return is_instance_valid(o) and not (o as Pedestrian).dead)
	for officer in officers:
		var o := officer as Pedestrian
		var gap := o.global_position.distance_to(target_pos)
		if gap < 60.0 and o.state != Pedestrian.State.DOWN:
			seen = seen or gap < 35.0
			if gap < 2.6 and level <= 1:
				close_unit = true
	_update_officers(target_pos, delta)
	_reinforce(delta)
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
		if search_timer >= SEARCH_SECONDS + maxi(level - 2, 0) * 5.0 or unseen_timer >= UNSEEN_SECONDS + maxi(level - 2, 0) * 6.0:
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


## Higher levels bring one patrol car per star, arriving a few seconds apart.
func _reinforce(delta: float) -> void:
	reinforce_timer -= delta
	police_cars = police_cars.filter(func(c: DriveableVehicle) -> bool: return is_instance_valid(c))
	var active := police_cars.filter(func(c: DriveableVehicle) -> bool: return not c.destroyed).size()
	if active < level and reinforce_timer <= 0.0:
		reinforce_timer = 5.0
		_spawn_police_car(mini(level, SPAWN_BANDS.size() - 1))


## Patrols that reach a player on foot (or stopped) put officers on the street;
## when the player gets away by car they climb back in and resume the chase.
func _update_officers(target_pos: Vector3, delta: float) -> void:
	# Officers get out for a player on foot, or a driver who has stopped for a while.
	stopped_time = stopped_time + delta if player_speed() < 1.0 else 0.0
	var slow := player.driving_vehicle == null or stopped_time > 1.5
	for car in police_cars:
		if not is_instance_valid(car) or car.destroyed:
			continue
		var crew: Array = car.get_meta("crew", [])
		crew = crew.filter(func(o: Node) -> bool: return is_instance_valid(o) and not (o as Pedestrian).dead)
		var near := car.global_position.distance_to(target_pos) < OFFICER_DEPLOY_RANGE
		if crew.is_empty() and near and slow and not bool(car.get_meta("crew_out", false)):
			car.set_meta("crew_out", true)
			car.pursuing = false
			car.speed = 0.0
			for k in range(OFFICERS_PER_CAR if level >= 2 else 1):
				var officer := OfficerScript.new() as OfficerScript
				officer.name = "Agente_%d" % spawn_serial
				spawn_serial += 1
				officer.wanted = self
				officer.car = car
				var side := car.global_transform.basis.x * (1.8 if k == 0 else -1.8)
				officer.position = car.global_position + side + Vector3(0, 0.2, 0)
				get_parent().add_child(officer)
				officer.state = Pedestrian.State.FIGHT
				crew.append(officer)
				officers.append(officer)
		elif bool(car.get_meta("crew_out", false)) and (crew.is_empty() or car.global_position.distance_to(target_pos) > 45.0 and not slow):
			for officer in crew:
				officers.erase(officer)
				(officer as Node).queue_free()
			crew.clear()
			car.set_meta("crew_out", false)
			car.pursuing = true
		car.set_meta("crew", crew)


## Scripted alarms (an armoured van's tracker...): jump straight to `stars`.
func raise_to(stars: int, location: Vector3) -> void:
	if level >= stars:
		return
	var before := level
	level = clampi(stars, 1, MAX_LEVEL)
	last_known = location
	search_timer = 0.0
	unseen_timer = 0.0
	incident_cooldown = 6.0
	if before == 0:
		_spawn_police_car(1)
	_set_phase("responding")
	wanted_changed.emit(level, phase)


## Attacking the police is always seen: at least three stars.
func report_police_attack(location: Vector3) -> void:
	var before := level
	level = clampi(maxi(level + 1, 3), 1, MAX_LEVEL) if level < MAX_LEVEL else MAX_LEVEL
	incident_cooldown = 6.0
	last_known = location
	search_timer = 0.0
	unseen_timer = 0.0
	if before == 0:
		_spawn_police_car(1)
	_set_phase("pursuit")
	if before != level:
		wanted_changed.emit(level, phase)
		crime_reported.emit("agresión a la policía", true)


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


## `forced` skips the witness check (scripted sightings, e.g. a mission officer).
func report_incident(location: Vector3, forced: bool = false) -> bool:
	if incident_cooldown > 0.0 or not (forced or _witness_near(location)):
		return false
	incident_cooldown = 14.0
	last_known = location
	last_seen_velocity = Vector3.ZERO
	search_timer = 0.0
	unseen_timer = 0.0
	level = mini(level + 1, MAX_LEVEL)
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
		if person != null and not person.dead and person.global_position.distance_to(location) < 34.0:
			return true
	return false


func _spawn_police_car(index: int) -> void:
	var car := VehicleScript.new() as DriveableVehicle
	car.name = "Policia_%d" % index if police_cars.is_empty() else "Policia_%d_%d" % [index, spawn_serial]
	spawn_serial += 1
	car.body_color = Color("344d67")
	car.variant = "police_suv" if level >= 3 and spawn_serial % 2 == 0 else "police_local"
	if level >= MAX_LEVEL and spawn_serial % 2 == 1:
		car.variant = "police_guardia"  # five stars: the Guardia Civil joins the hunt
	var spawn := _spawn_point(last_known, index)
	car.position = spawn + Vector3(0, 0.6, 0)
	var facing := last_known - spawn
	car.rotation.y = atan2(-facing.x, -facing.z) if facing.length_squared() > 1.0 else 0.0
	car.pursuing = true
	car.pursuit_target = last_known
	car.pursuit_speed = PURSUIT_SPEEDS[clampi(maxi(index, level), 0, MAX_LEVEL)]
	car.road_network = road_network
	get_parent().add_child(car)
	police_cars.append(car)


func _spawn_point(location: Vector3, index: int) -> Vector3:
	var fallback := location + Vector3(40, 0, 0)
	if road_network == null or road_network.nodes.is_empty():
		return fallback
	var band: Vector2 = SPAWN_BANDS[clampi(index, 0, SPAWN_BANDS.size() - 1)]
	var heading := _player_heading()
	var best := fallback
	var best_score := INF
	for point in road_network.nodes:
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
	for officer in officers:
		if is_instance_valid(officer):
			officer.queue_free()
	officers.clear()
	wanted_changed.emit(level, phase)
