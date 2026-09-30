class_name ActivitySystem
extends Node3D

## Free-roam side activities between story missions:
## - Taxi: in any taxi press T to go on duty. Pick up the marked fare (stop next
##   to them), drive them to their destination before the meter runs out, get
##   paid with a speed bonus, and the next fare appears. Leaving the cab ends it.
## - Street race: drive any car into the chequered column on the Paseo del Altillo
##   to start a timed run through the checkpoints; beating the par time pays more.
## Both show a column in the world and a GPS route on the minimap.

signal activity_changed(label: String)

const RACE_START := Vector2(-6.0, 6.0)
const RACE_POINTS := [Vector2(114.0, 41.0), Vector2(257.0, 46.0), Vector2(150.0, -105.0), Vector2(0.9, 2.7)]
const RACE_PAR := 75.0

var world: SectorWorld
var player: PlayerController
var active := ""
var stage := ""
var target := Vector3.INF
var fare: Pedestrian
var fare_distance := 0.0
var time_left := -1.0
var race_time := 0.0
var race_index := 0
var race_points: Array[Vector3] = []
var best_race := 0.0
var fares_done := 0
var column: MeshInstance3D
var start_column: MeshInstance3D
var rng := RandomNumberGenerator.new()
var cooldown := 0.0


func configure(target_world: SectorWorld, target_player: PlayerController) -> void:
	world = target_world
	player = target_player
	rng.seed = 7430
	for p in RACE_POINTS:
		race_points.append(_on_road(Vector3(p.x, 0, p.y)))
	column = _make_column(Color(0.35, 0.8, 1.0, 0.3))
	start_column = _make_column(Color(1.0, 1.0, 1.0, 0.28))
	start_column.global_position = _on_road(Vector3(RACE_START.x, 0, RACE_START.y)) + Vector3(0, 4.0, 0)
	start_column.scale = Vector3(2.6, 8.0, 2.6)


func _make_column(color: Color) -> MeshInstance3D:
	var tube := CylinderMesh.new()
	tube.top_radius = 1.0
	tube.bottom_radius = 1.0
	tube.height = 1.0
	tube.cap_top = false
	tube.cap_bottom = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	var node := MeshInstance3D.new()
	node.mesh = tube
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.top_level = true
	node.visible = false
	add_child(node)
	return node


func _on_road(p: Vector3) -> Vector3:
	var hit := world.road_network.nearest(p, true)
	var q: Vector3 = hit["point"] if not hit.is_empty() else p
	return Vector3(q.x, world.height_at(q.x, q.z), q.z)


func gps_target() -> Vector3:
	return target if active != "" else Vector3.INF


func label() -> String:
	match active:
		"taxi":
			return "TAXI · " + ("Recoge al cliente marcado y para a su lado" if stage == "pickup" else "Lleva al cliente a su destino")
		"race":
			return "CARRERA · Punto de control %d de %d" % [race_index + 1, race_points.size()]
	return ""


func status_text() -> String:
	if active == "taxi" and time_left > 0.0:
		return "TAXÍMETRO %d s · servicios %d" % [int(ceil(time_left)), fares_done]
	if active == "race":
		return "TIEMPO %.1f s%s" % [race_time, ("  · récord %.1f s" % best_race) if best_race > 0.0 else ""]
	return ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("activity") and player.driving_vehicle != null:
		if active == "taxi":
			stop("Servicio de taxi terminado.")
		elif active == "" and player.driving_vehicle.variant == "taxi":
			start_taxi()


func start_taxi() -> void:
	active = "taxi"
	fares_done = 0
	_next_fare()
	activity_changed.emit(label())


func _next_fare() -> void:
	stage = "pickup"
	fare = null
	var here := player.global_position
	var best_d := INF
	for node in get_tree().get_nodes_in_group("pedestrians"):
		var person := node as Pedestrian
		if person == null or person.mission_contact or person.enemy or person.dead or person.state == Pedestrian.State.DOWN or person.is_in_group("police_officers"):
			continue
		var d := person.global_position.distance_to(here)
		if d > 40.0 and d < 260.0 and d < best_d:
			best_d = d
			fare = person
	if fare == null:
		stop("No hay clientes cerca. Prueba en el paseo.")
		return
	target = fare.global_position
	time_left = 45.0 + best_d / 6.0


func _process(delta: float) -> void:
	if world == null:
		return
	cooldown = maxf(0.0, cooldown - delta)
	start_column.visible = active == "" and player.driving_vehicle != null
	var car := player.driving_vehicle
	match active:
		"":
			if car != null and cooldown <= 0.0 and Vector2(car.global_position.x - start_column.global_position.x, car.global_position.z - start_column.global_position.z).length() < 6.0 and not car.boat:
				start_race()
		"taxi":
			_taxi(delta, car)
		"race":
			_race(delta, car)
	column.visible = active != "" and target != Vector3.INF
	if column.visible:
		column.global_position = target + Vector3(0, 4.0, 0)
		column.scale = Vector3(2.2, 8.0, 2.2)


func _taxi(delta: float, car: DriveableVehicle) -> void:
	if car == null or car.variant != "taxi":
		stop("Has dejado el taxi.")
		return
	time_left -= delta
	if time_left <= 0.0:
		if fare != null and is_instance_valid(fare):
			fare.visible = true
		stop("El cliente se ha cansado de esperar.")
		return
	if stage == "pickup":
		if fare == null or not is_instance_valid(fare) or fare.dead:
			_next_fare()
			return
		target = fare.global_position
		if car.global_position.distance_to(fare.global_position) < 8.0 and absf(car.speed) < 2.0:
			stage = "dropoff"
			fare.visible = false
			fare.process_mode = Node.PROCESS_MODE_DISABLED
			var angle := rng.randf() * TAU
			var destination := _on_road(car.global_position + Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(250.0, 550.0))
			fare_distance = car.global_position.distance_to(destination)
			target = destination
			time_left = 25.0 + fare_distance / 7.0
			_say("Cliente: A %s, por favor. Y sin correr... bueno, un poco." % _place_name(destination))
			activity_changed.emit(label())
	elif car.global_position.distance_to(target) < 10.0 and absf(car.speed) < 2.5:
		var pay := int(15 + fare_distance * 0.06 + time_left * 0.8)
		var main := get_parent()
		if main != null and main.has_method("add_money"):
			main.add_money(pay)
		fares_done += 1
		if fare != null and is_instance_valid(fare):
			fare.global_position = car.global_position + car.global_transform.basis.x * 2.4 + Vector3(0, 0.2, 0)
			fare.home = fare.global_position
			fare.visible = true
			fare.process_mode = Node.PROCESS_MODE_INHERIT
		_say("Cliente: Gracias. Tome, %d € con propina." % pay)
		_next_fare()


func _place_name(p: Vector3) -> String:
	var street := world.road_network.road_name_at(p, 25.0)
	return street if street != "" else "esa calle"


func start_race() -> void:
	active = "race"
	race_index = 0
	race_time = 0.0
	target = race_points[0]
	_say("¡Carrera! Pasa por los puntos de control lo más rápido posible. Récord a batir: %.0f s." % RACE_PAR)
	activity_changed.emit(label())


func _race(delta: float, car: DriveableVehicle) -> void:
	if car == null or car.destroyed:
		stop("Carrera abandonada.")
		return
	race_time += delta
	if race_time > RACE_PAR * 3.0:
		stop("Demasiado lento: carrera anulada.")
		return
	if Vector2(car.global_position.x - target.x, car.global_position.z - target.z).length() < 14.0:
		race_index += 1
		if race_index >= race_points.size():
			var pay := 600 if race_time <= RACE_PAR else 200
			if best_race <= 0.0 or race_time < best_race:
				best_race = race_time
			var main := get_parent()
			if main != null and main.has_method("add_money"):
				main.add_money(pay)
				if "hud" in main:
					main.hud.show_banner("META  %.1f s  +%d €" % [race_time, pay], Color("f2c14e"))
			stop("")
			return
		target = race_points[race_index]
		activity_changed.emit(label())


func stop(message: String) -> void:
	if active == "taxi" and fare != null and is_instance_valid(fare):
		fare.visible = true
		fare.process_mode = Node.PROCESS_MODE_INHERIT
	active = ""
	stage = ""
	target = Vector3.INF
	time_left = -1.0
	cooldown = 8.0
	if message != "":
		_say(message)
	activity_changed.emit("")


func _say(line: String) -> void:
	get_tree().call_group("mission_controller", "_show_dialogue", line)
