extends Node

## Random street events, the life between missions: every minute or two, while
## the player is free (no stars, no mission step, no side job), something happens
## nearby that they can choose to get involved in.
##  · Tirón: a thief snatches a bag and runs. Knock him down and the bag is yours.
##  · Robo de coche: someone's car is stolen in front of them. Stop the thief.
##  · Furgón de caudales: a cash van passes. Wreck it for the cash bags, and the
##    guards and the police come for you.
## Each event has a red blip on the minimap and expires if ignored.

signal event_started(kind: String)
signal event_finished(kind: String, success: bool)

const VehicleScript = preload("res://scripts/vehicle.gd")
const KINDS := ["mugging", "car_theft", "cash_van"]
const FIRST_DELAY := 45.0
const GAP_MIN := 70.0
const GAP_MAX := 140.0
const TITLES := {
	"mugging": "¡AL LADRÓN!",
	"car_theft": "¡COCHE ROBADO!",
	"cash_van": "FURGÓN DE CAUDALES",
}
const HINTS := {
	"mugging": "Un ratero ha dado un tirón a una vecina. Atrápalo antes de que se escape (punto rojo).",
	"car_theft": "Le acaban de robar el coche a una vecina. Para al ladrón (punto rojo).",
	"cash_van": "Pasa un furgón blindado cargado de dinero. Si lo revientas, las sacas son tuyas… y la policía irá a por ti.",
}

var player: PlayerController
var main: Node
var world: SectorWorld
var wanted: WantedSystem
var rng := RandomNumberGenerator.new()
var active := ""
var timer := FIRST_DELAY
var life := 0.0
var think := 0.0
var thief: Pedestrian
var victim: Pedestrian
var car: DriveableVehicle
var loot: Node3D
var loot_value := 0
var loot_life := 0.0
var shout: Label3D
var blip_target: Node3D  # the minimap draws this in red while an event runs
var done_count := 0
## Random timing only in the real game: scripted test scenes start events themselves.
var auto := true


func configure(target_player: PlayerController, target_main: Node, target_world: SectorWorld, target_wanted: WantedSystem) -> void:
	player = target_player
	main = target_main
	world = target_world
	wanted = target_wanted
	rng.seed = 4021


func busy() -> bool:
	if player == null or player.dead or wanted.level > 0:
		return true
	if main != null and "activities" in main and main.activities != null and str(main.activities.active) != "":
		return true
	var mission: Node = main.get("mission") if main != null else null
	if mission != null and mission.has_method("mission_busy") and bool(mission.call("mission_busy")):
		return true
	return false


func _physics_process(delta: float) -> void:
	if player == null:
		return
	if loot != null:
		_update_loot(delta)
	if active == "":
		if not auto or get_tree().current_scene == null:
			return
		timer -= delta
		if timer <= 0.0:
			timer = rng.randf_range(GAP_MIN, GAP_MAX)
			if not busy():
				start(KINDS[rng.randi() % KINDS.size()])
		return
	life -= delta
	match active:
		"mugging":
			_update_mugging(delta)
		"car_theft":
			_update_car_theft(delta)
		"cash_van":
			_update_cash_van(delta)


## Start an event now (also used by tests). Returns false if there is no spot.
func start(kind: String) -> bool:
	if active != "":
		return false
	var ok := false
	match kind:
		"mugging":
			ok = _start_mugging()
		"car_theft":
			ok = _start_car_theft()
		"cash_van":
			ok = _start_cash_van()
	if not ok:
		return false
	active = kind
	think = 0.0
	_banner(TITLES[kind], Color("ff6b5a"))
	_hint(HINTS[kind])
	event_started.emit(kind)
	return true


func _finish(success: bool, message: String) -> void:
	var kind := active
	active = ""
	blip_target = null
	if shout != null and is_instance_valid(shout):
		shout.queue_free()
	shout = null
	if message != "":
		_banner(message, Color("f2c14e") if success else Color("b8b8b8"))
	if success:
		done_count += 1
	event_finished.emit(kind, success)


# --- Tirón (bag snatch) ----------------------------------------------------------

func _start_mugging() -> bool:
	var here := player.global_position
	var best: Pedestrian = null
	for node in get_tree().get_nodes_in_group("pedestrians"):
		var person := node as Pedestrian
		if person == null or person is PoliceOfficer or person.dead or person.mission_contact or person.enemy:
			continue
		if person.state != Pedestrian.State.WANDER or person.activity in ["work", "dance", "swim", "bathe"]:
			continue
		var d := person.global_position.distance_to(here)
		if d > 22.0 and d < 60.0 and absf(person.global_position.y - here.y) < 4.0:
			best = person
			break
	if best == null:
		return false
	victim = best
	thief = Pedestrian.new()
	thief.name = "Ratero"
	thief.display_name = "Ratero"
	thief.model_name = "male_longsleeve"
	world.add_child(thief)
	thief.global_position = victim.global_position + victim.global_transform.basis.x * 1.2
	thief.temperament = 0.0  # runs, never stands and fights
	thief.health = 60.0
	victim.flee_from(thief.global_position)
	_say(victim, "¡Al ladrón! ¡Mi bolso!")
	blip_target = thief
	life = 90.0
	return true


func _update_mugging(delta: float) -> void:
	if thief == null or not is_instance_valid(thief):
		_finish(false, "")
		return
	if thief.dead or thief.state == Pedestrian.State.DOWN:
		_drop_loot(thief.global_position, rng.randi_range(120, 260), "bag")
		thief = null
		_finish(true, "¡Ratero reducido!  Recoge el bolso")
		return
	var gap := thief.global_position.distance_to(player.global_position)
	if gap > 140.0 or life <= 0.0:
		thief.queue_free()
		thief = null
		_finish(false, "El ratero se ha escapado")
		return
	think -= delta
	if think <= 0.0 or thief.state != Pedestrian.State.FLEE:
		think = 1.0
		var away := thief.global_position - player.global_position
		away.y = 0.0
		if away.length() < 0.1:
			away = Vector3.FORWARD
		var goal := thief.global_position + away.normalized() * 18.0
		var walk := world.road_network.nearest(goal, false)
		if not walk.is_empty() and float(walk["distance"]) < 12.0:
			goal = walk["point"]
		thief.state = Pedestrian.State.FLEE
		thief.destination = goal
		thief.think_timer = 5.0


# --- Robo de coche --------------------------------------------------------------

func _start_car_theft() -> bool:
	var node := _road_node(45.0, 95.0)
	if node == Vector3.INF:
		return false
	var traffic: Array = VehicleScript.traffic_variants()
	car = VehicleScript.new() as DriveableVehicle
	car.name = "CocheRobado"
	car.variant = str(traffic[rng.randi() % traffic.size()]) if not traffic.is_empty() else "sedan_teal"
	car.position = Vector3(node.x, world.height_at(node.x, node.z) + 0.5, node.z)
	world.add_child(car)
	car.set_occupant("male_longsleeve")
	car.road_network = world.road_network
	car.health = 900.0
	car.pursuit_speed = 15.0
	car.pursuit_target = _away_on_road(car.global_position, 150.0)
	car.pursuing = true
	victim = Pedestrian.new()
	victim.name = "Propietaria"
	victim.display_name = "Propietaria"
	world.add_child(victim)
	var walk := world.road_network.nearest(node, false)
	victim.global_position = (walk["point"] as Vector3) if not walk.is_empty() and float(walk["distance"]) < 10.0 else node + Vector3(3, 0, 0)
	_say(victim, "¡Mi coche! ¡Que alguien lo pare!")
	blip_target = car
	life = 120.0
	return true


func _update_car_theft(delta: float) -> void:
	if car == null or not is_instance_valid(car):
		_finish(false, "")
		return
	if player.driving_vehicle == car:
		car.pursuing = false
		_pay(250, "COCHE RECUPERADO  +250 €")
		car = null
		_finish(true, "")
		return
	if car.destroyed or car.health <= 450.0:
		car.pursuing = false
		car.speed = 0.0
		if not car.destroyed:
			var runner := car.eject_occupant()
			if runner != null:
				runner.temperament = 0.0
		_pay(250, "LADRÓN DETENIDO  +250 €")
		car = null
		_finish(true, "")
		return
	if car.global_position.distance_to(player.global_position) > 320.0 or life <= 0.0:
		car.queue_free()
		car = null
		_finish(false, "El ladrón se ha escapado con el coche")
		return
	think -= delta
	if think <= 0.0:
		think = 2.0
		car.pursuit_target = _away_on_road(car.global_position, 150.0)


# --- Furgón de caudales -----------------------------------------------------------

func _start_cash_van() -> bool:
	var node := _road_node(60.0, 120.0)
	if node == Vector3.INF:
		return false
	car = VehicleScript.new() as DriveableVehicle
	car.name = "FurgonCaudales"
	car.variant = "suv_sand"
	car.position = Vector3(node.x, world.height_at(node.x, node.z) + 0.5, node.z)
	world.add_child(car)
	car.set_occupant("male_longsleeve")
	car.road_network = world.road_network
	car.health = 1000.0
	car.pursuit_speed = 9.0
	car.pursuit_target = _random_road_target(car.global_position)
	car.pursuing = true
	var sign := Label3D.new()
	sign.name = "VanSign"
	sign.text = "TRANSPORTE DE FONDOS"
	sign.font_size = 40
	sign.outline_size = 8
	sign.pixel_size = 0.006
	sign.modulate = Color("e8d27a")
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = Vector3(0, 2.3, 0)
	sign.visibility_range_end = 70.0
	car.add_child(sign)
	blip_target = car
	life = 150.0
	return true


func _update_cash_van(delta: float) -> void:
	if car == null or not is_instance_valid(car):
		_finish(false, "")
		return
	if car.destroyed or car.health <= 500.0:
		car.pursuing = false
		car.speed = 0.0
		var back := car.global_position + car.global_transform.basis.z * 3.2
		_drop_loot(back, rng.randi_range(1500, 3000), "cash")
		if not car.destroyed:
			car.set_occupant("")
		for i in range(2):
			var guard := Pedestrian.new()
			guard.name = "Vigilante_%d" % i
			guard.display_name = "Vigilante"
			guard.enemy = true
			guard.armed = true
			guard.health = 120.0
			world.add_child(guard)
			guard.global_position = car.global_position + car.global_transform.basis.x * (2.4 if i == 0 else -2.4)
			guard.start_fight(40.0)
		wanted.report_scripted_crime("atraco a furgón blindado", car.global_position)
		wanted.raise_to(maxi(wanted.level, 2), car.global_position)
		car = null
		_finish(true, "¡Furgón reventado!  Coge las sacas")
		return
	if car.global_position.distance_to(player.global_position) > 320.0 or life <= 0.0:
		car.queue_free()
		car = null
		_finish(false, "El furgón ha seguido su ruta")
		return
	think -= delta
	if think <= 0.0:
		think = 3.0
		if car.global_position.distance_to(car.pursuit_target) < 15.0:
			car.pursuit_target = _random_road_target(car.global_position)


# --- Loot -------------------------------------------------------------------------

func _drop_loot(at: Vector3, value: int, kind: String) -> void:
	if loot != null and is_instance_valid(loot):
		loot.queue_free()
	loot = Node3D.new()
	loot.name = "EventLoot"
	loot.top_level = true
	world.add_child(loot)
	var ground := at
	var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 6.0, 1))
	ground.y = (hit["position"] as Vector3).y if not hit.is_empty() else world.height_at(at.x, at.z)
	loot.global_position = ground
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.38, 0.28, 0.16) if kind == "bag" else Vector3(0.5, 0.45, 0.35)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("8a3b2e") if kind == "bag" else Color("cfc7a8")
	mesh.material_override = mat
	mesh.position.y = 0.2
	loot.add_child(mesh)
	var label := Label3D.new()
	label.text = "BOLSO" if kind == "bag" else "SACAS  %d €" % value
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.outline_size = 8
	label.pixel_size = 0.006
	label.modulate = Color("7bd88f")
	label.position.y = 1.0
	loot.add_child(label)
	loot_value = value
	loot_life = 60.0
	blip_target = loot


func _update_loot(delta: float) -> void:
	if not is_instance_valid(loot):
		loot = null
		return
	loot_life -= delta
	(loot.get_child(0) as Node3D).rotation.y += delta * 2.0
	if loot_life <= 0.0:
		loot.queue_free()
		loot = null
		blip_target = null
		return
	if player.driving_vehicle == null and not player.dead and player.global_position.distance_to(loot.global_position) < 1.8:
		_pay(loot_value, "+%d €" % loot_value)
		loot.queue_free()
		loot = null
		blip_target = null


# --- Helpers ------------------------------------------------------------------------

func _pay(amount: int, text: String) -> void:
	if main != null and main.has_method("add_money"):
		main.add_money(amount)
	_banner(text, Color("7bd88f"))


func _banner(text: String, color: Color) -> void:
	if main != null and "hud" in main and main.hud != null:
		main.hud.show_banner(text, color)


func _hint(text: String) -> void:
	var mission: Node = main.get("mission") if main != null else null
	if mission != null and mission.has_method("_show_dialogue"):
		mission.call("_show_dialogue", text)


func _say(person: Pedestrian, line: String) -> void:
	if shout != null and is_instance_valid(shout):
		shout.queue_free()
	shout = Label3D.new()
	shout.text = line
	shout.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shout.font_size = 28
	shout.outline_size = 8
	shout.pixel_size = 0.004
	shout.visibility_range_end = 45.0
	shout.modulate = Color("ffffff")
	shout.position.y = 2.2
	person.add_child(shout)
	get_tree().create_timer(5.0, false).timeout.connect(func() -> void:
		if is_instance_valid(shout):
			shout.queue_free())


## A driveable road node `near`–`far` metres away with a lane through it.
func _road_node(near: float, far: float) -> Vector3:
	var here := player.global_position
	var network := world.road_network
	var options: Array[Vector3] = []
	for i in range(network.nodes.size()):
		var p: Vector3 = network.nodes[i]
		var d := Vector2(p.x - here.x, p.z - here.z).length()
		if d < near or d > far or (network.edges.get(i, []) as Array).is_empty():
			continue
		var lane: Dictionary = network.nearest(p, true)
		if lane.is_empty() or (lane["point"] as Vector3).distance_to(p) > 1.5:
			continue
		options.append(p)
	if options.is_empty():
		return Vector3.INF
	return options[rng.randi() % options.size()]


func _away_on_road(from: Vector3, distance: float) -> Vector3:
	var away := from - player.global_position
	away.y = 0.0
	var goal := from + away.normalized() * distance
	var lane: Dictionary = world.road_network.nearest(goal, true)
	return (lane["point"] as Vector3) if not lane.is_empty() else goal


func _random_road_target(from: Vector3) -> Vector3:
	var network := world.road_network
	for attempt in range(12):
		var p: Vector3 = network.nodes[rng.randi() % network.nodes.size()]
		var d := p.distance_to(from)
		if d > 80.0 and d < 260.0:
			var lane: Dictionary = network.nearest(p, true)
			if not lane.is_empty():
				return lane["point"]
	return from


func to_save() -> Dictionary:
	return {"done": done_count}


func from_save(value: Dictionary) -> void:
	done_count = int(value.get("done", 0))
