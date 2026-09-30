class_name MissionController
extends Node

## Data-driven missions (res://data/missions/*.json, listed in index.json).
## A mission is offered by a contact (a blip letter on the map and over their head);
## talking to them starts it. Objectives run in order; each may spawn vehicles or
## enemies, carry a time limit and resolve its marker from an anchor, a venue, the
## workshop, a contact or a live spawned target. Failure (time out, target escaped,
## vehicle wrecked, arrest, death) returns to the mission's checkpoint and resets
## its spawns. Starting another contact's mission before the current one gets going
## suspends it and resumes it afterwards. Completed missions never pay twice.

signal objective_changed(text: String, marker: Vector3)
signal dialogue_changed(text: String)
signal mission_completed
signal mission_failed(reason: String)
signal mission_started(title: String)

const INDEX_PATH := "res://data/missions/index.json"
const VehicleScript = preload("res://scripts/vehicle.gd")
const PedestrianScript = preload("res://scripts/pedestrian.gd")

var player: PlayerController
var wanted: WantedSystem
var world: SectorWorld
var objectives: Array[Dictionary] = []
var stage := 0
var completed := false
var dialogue := ""
var dialogue_timer := 0.0
var dialogue_queue: Array[String] = []
var fail_checkpoint := 0
var anchors: Dictionary = {}  # sector anchors; objectives may use "marker_anchor"
var fail_dialogue := ""
var mission_id := "el_recado"
var mission_title := "El Recado"
var reward := 500
var mission_data: Dictionary = {}
var catalog: Array[Dictionary] = []  # index entries in story order
var contact_specs: Dictionary = {}  # name -> {display, model, at, idle}
var completed_missions: Dictionary = {}
var suspended_id := ""
var suspended_stage := -1
var objective_time_left := -1.0
var wait_left := 0.0
var spawned: Dictionary = {}  # spawn id -> Node3D
var spawn_specs: Dictionary = {}  # spawn id -> spec
var last_positions: Dictionary = {}  # spawn id -> Vector3 (for markers after a target is gone)
var _titles: Dictionary = {}

var jaime_finished: bool:
	get:
		return completed_missions.has("jaime_playa")
	set(value):
		if value:
			completed_missions["jaime_playa"] = true
		else:
			completed_missions.erase("jaime_playa")

var suspended_el_recado_stage: int:
	get:
		return suspended_stage if suspended_id == "el_recado" else -1
	set(value):
		if value >= 0:
			suspended_id = "el_recado"
			suspended_stage = value
		elif suspended_id == "el_recado":
			suspended_id = ""
			suspended_stage = -1


func _ready() -> void:
	add_to_group("mission_controller")
	_load_index()
	load_mission("el_recado")


func _load_index() -> void:
	var parsed: Variant = _read_json(INDEX_PATH)
	if not parsed is Dictionary:
		push_error("Mission index missing or invalid: " + INDEX_PATH)
		return
	catalog.clear()
	for entry in parsed.get("missions", []):
		catalog.append(entry)
	contact_specs = parsed.get("contacts", {})
	for entry in catalog:
		var mission: Variant = _read_json("res://data/missions/%s.json" % str(entry["id"]))
		_titles[str(entry["id"])] = str(mission.get("title", entry["id"])) if mission is Dictionary else str(entry["id"])


## "Paco en el Chiringuito Arenas" style description of where a contact waits.
func _where(contact_name: String) -> String:
	return str(contact_specs.get(contact_name, {}).get("where", contact_name))


static func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	return JSON.parse_string(file.get_as_text())


func _entry(id: String) -> Dictionary:
	for entry in catalog:
		if str(entry["id"]) == id:
			return entry
	return {}


func load_mission(id: String, announce: bool = true) -> bool:
	if _entry(id).is_empty():
		push_error("Unknown mission: " + id)
		return false
	var path := "res://data/missions/%s.json" % id
	var parsed: Variant = _read_json(path)
	if not parsed is Dictionary or not parsed.has("objectives"):
		push_error("Invalid mission data: " + path)
		return false
	_release_spawns()
	mission_data = parsed
	objectives.clear()
	for objective in parsed["objectives"]:
		objectives.append(objective)
	mission_id = id
	mission_title = str(parsed.get("title", id))
	reward = int(parsed.get("reward", 500))
	stage = 0
	completed = false
	objective_time_left = -1.0
	fail_checkpoint = int(parsed.get("fail_checkpoint", 0))
	fail_dialogue = str(parsed.get("fail_dialogue", ""))
	spawn_specs.clear()
	for spec in parsed.get("spawns", []):
		spawn_specs[str(spec["id"])] = spec
	for spec in parsed.get("spawns", []):
		if str(spec.get("when", "start")) == "start":
			_spawn(str(spec["id"]))
	if player != null and announce:
		_emit_objective()
	return true


func configure(target: PlayerController, wanted_system: WantedSystem) -> void:
	player = target
	wanted = wanted_system
	player.contact_interacted.connect(_on_contact)
	player.vehicle_entered.connect(_on_vehicle_entered)
	_create_contacts()
	for id in spawn_specs:  # spawns skipped while the world was not attached yet
		if str(spawn_specs[id].get("when", "start")) == "start" and not spawned.has(id):
			_spawn(id)
	_emit_objective()


## Contacts listed in the index that the sector did not already place.
func _create_contacts() -> void:
	if world == null:
		return
	for contact_name in contact_specs:
		if world.get_node_or_null(str(contact_name)) != null:
			continue
		var spec: Dictionary = contact_specs[contact_name]
		var person := PedestrianScript.new() as Pedestrian
		person.name = str(contact_name)
		person.display_name = str(spec.get("display", contact_name))
		person.mission_contact = true
		person.model_name = str(spec.get("model", "male_casual"))
		var at: Array = spec["at"]
		person.position = Vector3(float(at[0]), world.height_at(float(at[0]), float(at[1])) + 0.1, float(at[1]))
		person.rotation.y = deg_to_rad(float(spec.get("yaw", 0.0)))
		world.add_child(person)


# --- Offers --------------------------------------------------------------------

func is_available(id: String) -> bool:
	var entry := _entry(id)
	if entry.is_empty() or completed_missions.has(id):
		return false
	for required in entry.get("requires", []):
		if not completed_missions.has(str(required)):
			return false
	return true


## The mission a contact offers right now ("" if none).
func offer_of(contact_name: String) -> String:
	for entry in catalog:
		if str(entry.get("contact", "")) == contact_name and is_available(str(entry["id"])):
			return str(entry["id"])
	return ""


## Contacts with something to offer: [{name, letter, color, position, title, id}].
func offers() -> Array:
	var result := []
	if world == null:
		return result
	var seen := {}
	for entry in catalog:
		var contact_name := str(entry.get("contact", ""))
		var id := str(entry["id"])
		if seen.has(contact_name) or not is_available(id):
			continue
		if id == mission_id and not completed and stage > 0:
			continue  # already under way
		var person := world.get_node_or_null(contact_name) as Node3D
		if person == null:
			continue
		seen[contact_name] = true
		var title := str(_titles.get(id, id))
		result.append({"name": contact_name, "letter": str(entry.get("blip", contact_name.left(1))), "color": Color(str(entry.get("color", "f2c14e"))), "position": person.global_position, "title": title, "id": id})
	return result


func mission_busy() -> bool:
	return not completed and stage > fail_checkpoint


# --- Labels and markers ---------------------------------------------------------

func objective_label() -> String:
	if completed:
		var nearest := _nearest_offer()
		if nearest.is_empty():
			return "%s completada · explora Almuñécar" % mission_title
		return "Nueva misión: habla con %s (%s)" % [_where(str(nearest["name"])), nearest["letter"]]
	return str(objectives[stage].get("text", "")) if not objectives.is_empty() else ""


func _nearest_offer() -> Dictionary:
	var best := {}
	var best_distance := INF
	for offer in offers():
		var d := player.global_position.distance_to(offer["position"]) if player != null else 0.0
		if d < best_distance:
			best_distance = d
			best = offer
	return best


## Legacy 2D marker [x, z] (or []) for the map and tests.
func active_marker() -> Array:
	var p := marker_position()
	return [] if p == Vector3.INF else [p.x, p.z]


## 3D position of the current objective (or of the nearest offer when free).
func marker_position() -> Vector3:
	if completed or objectives.is_empty():
		var nearest := _nearest_offer()
		return Vector3.INF if nearest.is_empty() else nearest["position"]
	return resolve_marker(objectives[stage])


func resolve_marker(objective: Dictionary) -> Vector3:
	if objective.has("marker_target"):
		var id := str(objective["marker_target"])
		var node := spawned.get(id) as Node3D
		if node != null and is_instance_valid(node):
			return node.global_position
		return last_positions.get(id, Vector3.INF)
	if objective.has("marker_contact") and world != null:
		var person := world.get_node_or_null(str(objective["marker_contact"])) as Node3D
		if person != null:
			return person.global_position
	if objective.has("marker_venue") and world != null and world.venues.has(str(objective["marker_venue"])):
		return (world.venues[str(objective["marker_venue"])] as VenueInterior).exterior_entry
	if objective.has("marker_workshop") and world != null:
		return world.workshop.exterior_entry
	if objective.has("marker_anchor") and anchors.has(str(objective["marker_anchor"])):
		var p: Array = anchors[str(objective["marker_anchor"])]
		return Vector3(float(p[0]), float(p[1]), float(p[2]))
	if objective.has("marker"):
		var m: Array = objective["marker"]
		var y := world.height_at(float(m[0]), float(m[1])) if world != null else 0.0
		return Vector3(float(m[0]), y, float(m[1]))
	if str(objective.get("type", "")) == "talk_to" and world != null:
		var target := world.get_node_or_null(str(objective.get("target", ""))) as Node3D
		if target != null:
			return target.global_position
	return Vector3.INF


## Kept for tests/tools: [x, z] of an objective.
func marker_of(objective: Dictionary) -> Array:
	var p := resolve_marker(objective)
	return [0, 0] if p == Vector3.INF else [p.x, p.z]


## Where the GPS should lead: the objective, unless it is a person/vehicle chase
## right next to the player.
func gps_target() -> Vector3:
	return marker_position()


## Live spawned target of the current objective (vehicle to chase, enemies...).
func objective_targets() -> Array[Node3D]:
	var result: Array[Node3D] = []
	if completed or objectives.is_empty():
		return result
	var objective := objectives[stage]
	var ids: Array = objective.get("targets", [])
	if objective.has("target_spawn"):
		ids = [objective["target_spawn"]]
	if objective.has("vehicle"):
		ids = ids + [objective["vehicle"]]
	for id in ids:
		var node := spawned.get(str(id)) as Node3D
		if node != null and is_instance_valid(node):
			result.append(node)
	return result


# --- Update ---------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_dialogue(delta)
	if player == null or completed or objectives.is_empty():
		return
	var objective := objectives[stage]
	if objective_time_left > 0.0:
		objective_time_left -= delta
		if objective_time_left <= 0.0:
			objective_time_left = -1.0
			_fail(str(objective.get("timeout_text", "¡Se acabó el tiempo!")))
			return
	var vehicle_id := str(objective.get("vehicle", ""))
	if vehicle_id != "":
		var required := spawned.get(vehicle_id) as DriveableVehicle
		if required == null or not is_instance_valid(required) or required.destroyed:
			_fail(str(objective.get("wrecked_text", "El vehículo ha quedado destrozado.")))
			return
	match str(objective.get("type", "")):
		"enter_vehicle":
			if player.driving_vehicle != null and _is_required_vehicle(objective, player.driving_vehicle):
				_advance()
		"reach_area":
			if bool(objective.get("requires_vehicle", false)) and player.driving_vehicle == null:
				return
			if vehicle_id != "" and player.driving_vehicle != spawned.get(vehicle_id):
				return
			if bool(objective.get("requires_on_foot", false)) and player.driving_vehicle != null:
				return
			var marker := resolve_marker(objective)
			if marker == Vector3.INF:
				return
			var player_pos := player.driving_vehicle.global_position if player.driving_vehicle != null else player.global_position
			var distance := Vector2(player_pos.x - marker.x, player_pos.z - marker.z).length()
			if distance < float(objective.get("radius", 10)):
				if bool(objective.get("witnessed_incident", false)) and wanted.level == 0:
					if not wanted.report_incident(player_pos, true):  # the dialogue's officer saw it
						return
				if bool(objective.get("requires_no_wanted", false)) and wanted.level > 0:
					return
				_show_lines(objective.get("dialogue", ""))
				_advance()
		"escape_police":
			if wanted.level == 0:
				_show_lines(objective.get("dialogue", ""))
				_advance()
		"destroy_vehicle":
			var target := spawned.get(str(objective.get("target_spawn", ""))) as DriveableVehicle
			if target == null or not is_instance_valid(target):
				_advance()
				return
			last_positions[str(objective["target_spawn"])] = target.global_position
			if target.destroyed or target.health <= float(objective.get("health_below", 0.0)):
				target.traffic = false
				target.speed = 0.0
				if bool(objective.get("eject_driver", true)) and target.occupant_name != "":
					target.eject_occupant()
				_show_lines(objective.get("dialogue", ""))
				_advance()
				return
			var escape := float(objective.get("escape_distance", 0.0))
			var from := player.driving_vehicle.global_position if player.driving_vehicle != null else player.global_position
			if escape > 0.0 and from.distance_to(target.global_position) > escape:
				_fail(str(objective.get("escape_text", "Se ha escapado.")))
		"beat_up":
			var remaining := 0
			for id in objective.get("targets", []):
				var person := spawned.get(str(id)) as Pedestrian
				if person != null and is_instance_valid(person) and not person.defeated:
					remaining += 1
			if remaining == 0:
				_show_lines(objective.get("dialogue", ""))
				_advance()
		"wait":
			wait_left -= delta
			if wait_left <= 0.0:
				_show_lines(objective.get("dialogue", ""))
				_advance()


func _is_required_vehicle(objective: Dictionary, vehicle: DriveableVehicle) -> bool:
	if not objective.has("vehicle"):
		return true
	return spawned.get(str(objective["vehicle"])) == vehicle


func _on_contact(contact: Pedestrian) -> void:
	var offered := offer_of(str(contact.name))
	if offered != "" and offered != mission_id:
		if mission_busy():
			_show_dialogue("%s: Termina primero lo que tienes entre manos." % contact.display_name.get_slice(" · ", 0))
			return
		var previous_id := mission_id
		var previous_stage := stage
		var previous_done := completed
		if not load_mission(offered, false):
			return
		if not previous_done:
			suspended_id = previous_id
			suspended_stage = previous_stage
	if completed or objectives.is_empty():
		var idle := str(contact_specs.get(str(contact.name), {}).get("idle", ""))
		if idle != "":
			_show_dialogue(idle)
		return
	var objective := objectives[stage]
	if str(objective.get("type", "")) == "talk_to" and str(contact.name) == str(objective.get("target", "")):
		if stage == 0:
			mission_started.emit(mission_title)
		_show_lines(objective.get("dialogue", ""))
		_advance()


func _on_vehicle_entered(vehicle: DriveableVehicle) -> void:
	if stage < objectives.size() and not completed and str(objectives[stage].get("type", "")) == "enter_vehicle" and _is_required_vehicle(objectives[stage], vehicle):
		_advance()


func _advance() -> void:
	var finished := objectives[stage] if stage < objectives.size() else {}
	if finished.has("set_wanted") and wanted != null:
		wanted.raise_to(int(finished["set_wanted"]), player.global_position)
	if finished.has("crime_on_complete") and wanted != null:
		var pos := player.driving_vehicle.global_position if player.driving_vehicle != null else player.global_position
		wanted.report_scripted_crime(str(finished["crime_on_complete"]), pos)
	stage += 1
	objective_time_left = -1.0
	if stage >= objectives.size():
		completed = true
		completed_missions[mission_id] = true
		_release_spawns()
		mission_completed.emit()
		if suspended_id != "":
			var resume_id := suspended_id
			var resume_stage := suspended_stage
			suspended_id = ""
			suspended_stage = -1
			load_mission(resume_id, false)
			restore_stage(resume_stage)
		else:
			_emit_completed()
	else:
		_begin_objective()


func _begin_objective() -> void:
	if stage >= objectives.size():
		return
	var objective := objectives[stage]
	for id in objective.get("spawn", []):
		if not spawned.has(str(id)) or not is_instance_valid(spawned[str(id)]):
			_spawn(str(id))
	for id in objective.get("targets", []):
		var person := spawned.get(str(id)) as Pedestrian
		if person != null:
			person.start_fight(999.0)
	if objective.has("give_weapon"):
		var gift: Dictionary = objective["give_weapon"]
		get_tree().call_group("weapon_system", "give", str(gift["weapon"]), int(gift.get("ammo", 0)))
	objective_time_left = float(objective.get("time_limit", -1.0))
	wait_left = float(objective.get("seconds", 0.0))
	_emit_objective()


func _emit_objective() -> void:
	if objectives.is_empty():
		return
	if completed:
		_emit_completed()
		return
	var marker := marker_position()
	objective_changed.emit(str(objectives[stage].get("text", "")), marker if marker != Vector3.INF else Vector3.ZERO)


func _update_dialogue(delta: float) -> void:
	if dialogue_timer > 0.0:
		dialogue_timer -= delta
		if dialogue_timer <= 0.0:
			if dialogue_queue.is_empty():
				dialogue = ""
				dialogue_changed.emit("")
			else:
				_show_dialogue(dialogue_queue.pop_front(), false)


## A line or a list of lines, shown one after another.
func _show_lines(value: Variant) -> void:
	var lines: Array = value if value is Array else [value]
	var text_lines: Array[String] = []
	for line in lines:
		if str(line) != "":
			text_lines.append(str(line))
	if text_lines.is_empty():
		return
	dialogue_queue = text_lines.slice(1)
	_show_dialogue(text_lines[0], false)


func _show_dialogue(value: String, clear_queue: bool = true) -> void:
	if clear_queue:
		dialogue_queue.clear()
	dialogue = value
	dialogue_timer = clampf(2.2 + value.length() / 16.0, 3.0, 8.0)
	dialogue_changed.emit(dialogue)


func restore_stage(value: int) -> void:
	stage = clampi(value, 0, objectives.size())
	completed = stage == objectives.size()
	if completed:
		completed_missions[mission_id] = true
		_emit_completed()
	else:
		for i in range(stage):  # targets introduced by earlier objectives
			for id in objectives[i].get("spawn", []):
				if not spawned.has(str(id)):
					_spawn(str(id))
		_begin_objective()


func _emit_completed() -> void:
	var marker := marker_position()
	objective_changed.emit(objective_label(), marker if marker != Vector3.INF else Vector3.ZERO)


# --- Failure --------------------------------------------------------------------

## Arrest or death: return an in-progress mission to its data-defined checkpoint.
func fail_to_checkpoint(reason: String) -> void:
	if completed or objectives.is_empty():
		_show_dialogue(reason)
		return
	if stage > fail_checkpoint:
		_reset_spawns()
		stage = fail_checkpoint
		_begin_objective()
		mission_failed.emit(reason)
		_show_dialogue(reason + " " + fail_dialogue)
	else:
		_show_dialogue(reason)


func _fail(reason: String) -> void:
	_reset_spawns()
	stage = mini(fail_checkpoint, stage)
	mission_failed.emit(reason)
	_begin_objective()
	_show_dialogue(reason + " " + fail_dialogue)


# --- Spawns ---------------------------------------------------------------------

func _spawn(id: String) -> void:
	if world == null or not spawn_specs.has(id):
		return
	var spec: Dictionary = spawn_specs[id]
	var at: Array = spec["at"]
	var point := Vector3(float(at[0]), 0, float(at[1]))
	var node: Node3D
	match str(spec.get("kind", "vehicle")):
		"vehicle":
			var car := VehicleScript.new() as DriveableVehicle
			car.name = "Mission_" + id
			car.variant = str(spec.get("variant", "sedan_teal"))
			var network := world.road_network
			var from_node := network.nearest_node(point)
			var outgoing: Array = network.edges.get(from_node, [])
			var yaw := 0.0
			if bool(spec.get("on_road", true)) and not outgoing.is_empty():
				var a := network.nodes[from_node]
				var b := network.nodes[int(outgoing[0])]
				var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
				var lane := network.lane_offset if network.is_two_way(from_node, int(outgoing[0])) else 0.0
				point = a.lerp(b, 0.35) + Vector3(-dir.z, 0, dir.x) * lane
				yaw = atan2(-dir.x, -dir.z)
			if spec.has("yaw"):
				yaw = deg_to_rad(float(spec["yaw"]))
			car.position = Vector3(point.x, world.height_at(point.x, point.z) + 0.4, point.z)
			car.rotation.y = yaw
			world.add_child(car)
			if spec.has("occupant"):
				car.set_occupant(str(spec["occupant"]))
			if spec.has("health"):
				car.health = float(spec["health"])
			if bool(spec.get("traffic", false)) and not outgoing.is_empty():
				car.start_traffic(network, from_node, int(outgoing[0]), 9100 + id.length())
				car.traffic_speed = float(spec.get("speed", 12.0))
			node = car
		"enemy":
			var person := PedestrianScript.new() as Pedestrian
			person.name = "Mission_" + id
			person.display_name = str(spec.get("display", "Matón"))
			person.model_name = str(spec.get("model", "male_longsleeve"))
			person.enemy = true
			person.toughness = int(spec.get("toughness", 3))
			person.armed = bool(spec.get("armed", false))
			person.position = Vector3(point.x, world.height_at(point.x, point.z) + 0.1, point.z)
			world.add_child(person)
			node = person
	if node != null:
		spawned[id] = node


## Failure: remove this attempt's spawns and put the start ones back.
func _reset_spawns() -> void:
	for id in spawned.keys():
		var node := spawned[id] as Node3D
		if node != null and is_instance_valid(node):
			if node == player.driving_vehicle:
				player._interact()
			node.queue_free()
	spawned.clear()
	last_positions.clear()
	for id in spawn_specs:
		if str(spawn_specs[id].get("when", "start")) == "start":
			_spawn(id)


## Mission over: vehicles stay in the world as ordinary cars, enemies calm down.
func _release_spawns() -> void:
	for id in spawned:
		var node := spawned[id] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		if node is Pedestrian:
			(node as Pedestrian).enemy = false
			if (node as Pedestrian).state == Pedestrian.State.FIGHT:
				(node as Pedestrian).flee_from(player.global_position if player != null else node.global_position)
	spawned.clear()
	last_positions.clear()
