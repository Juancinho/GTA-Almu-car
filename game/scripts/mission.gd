class_name MissionController
extends Node

signal objective_changed(text: String, marker: Vector3)
signal dialogue_changed(text: String)
signal mission_completed
signal mission_failed(reason: String)

var player: PlayerController
var wanted: WantedSystem
var objectives: Array[Dictionary] = []
var stage := 0
var completed := false
var dialogue := ""
var dialogue_timer := 0.0
var fail_checkpoint := 0
var anchors: Dictionary = {}  # sector anchors; objectives may use "marker_anchor"
var fail_dialogue := ""
var mission_id := "el_recado"
var mission_title := "El Recado"
var reward := 500
var jaime_finished := false
var suspended_el_recado_stage := -1


func _ready() -> void:
	load_mission("el_recado")


func load_mission(id: String, announce: bool = true) -> bool:
	if id != "el_recado" and id != "jaime_playa":
		push_error("Unknown mission: " + id)
		return false
	var path := "res://data/missions/%s.json" % id
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Mission data missing: " + path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.has("objectives"):
		push_error("Invalid mission data: " + path)
		return false
	objectives.clear()
	for objective in parsed["objectives"]:
		objectives.append(objective)
	mission_id = id
	mission_title = str(parsed.get("title", id))
	reward = int(parsed.get("reward", 500))
	stage = 0
	completed = false
	fail_checkpoint = int(parsed.get("fail_checkpoint", 0))
	fail_dialogue = str(parsed.get("fail_dialogue", ""))
	if player != null and announce:
		_emit_objective()
	return true


## Resolve data-driven markers: "marker_anchor" names a sector anchor ([x, y, z]).
func marker_of(objective: Dictionary) -> Array:
	if objective.has("marker_anchor") and anchors.has(str(objective["marker_anchor"])):
		var p: Array = anchors[str(objective["marker_anchor"])]
		return [float(p[0]), float(p[2])]
	return objective.get("marker", [0, 0]) as Array


func objective_label() -> String:
	if completed:
		if mission_id == "el_recado":
			return "El Recado y La noche de Jaime completadas" if jaime_finished else "Habla con Marina en Jaime Playa"
		return "%s completada" % mission_title
	return str(objectives[stage].get("text", "")) if not objectives.is_empty() else ""


func active_marker() -> Array:
	if completed:
		if mission_id == "el_recado" and not jaime_finished and anchors.has("jaime_staff"):
			var p: Array = anchors["jaime_staff"]
			return [float(p[0]), float(p[2])]
		return []
	return marker_of(objectives[stage]) if not objectives.is_empty() else []


func configure(target: PlayerController, wanted_system: WantedSystem) -> void:
	player = target
	wanted = wanted_system
	player.contact_interacted.connect(_on_contact)
	player.vehicle_entered.connect(_on_vehicle_entered)
	_emit_objective()


func _process(delta: float) -> void:
	if player == null or completed or objectives.is_empty():
		return
	if dialogue_timer > 0.0:
		dialogue_timer -= delta
		if dialogue_timer <= 0.0:
			dialogue = ""
			dialogue_changed.emit("")
	var objective := objectives[stage]
	match str(objective.get("type", "")):
		"enter_vehicle":
			if player.driving_vehicle != null:
				_advance()
		"reach_area":
			if bool(objective.get("requires_vehicle", false)) and player.driving_vehicle == null:
				return
			if bool(objective.get("requires_on_foot", false)) and player.driving_vehicle != null:
				return
			var marker := marker_of(objective)
			var player_pos := player.driving_vehicle.global_position if player.driving_vehicle != null else player.global_position
			var distance := Vector2(player_pos.x - float(marker[0]), player_pos.z - float(marker[1])).length()
			if distance < float(objective.get("radius", 10)):
				if bool(objective.get("witnessed_incident", false)) and wanted.level == 0:
					if not wanted.report_incident(player_pos, true):  # the dialogue's officer saw it
						return
				_show_dialogue(str(objective.get("dialogue", "")))
				_advance()
		"escape_police":
			if wanted.level == 0:
				_advance()


func _on_contact(contact: Pedestrian) -> void:
	if mission_id == "el_recado" and not jaime_finished and contact.name == "Marina":
		var previous_stage := stage
		if not load_mission("jaime_playa"):
			return
		suspended_el_recado_stage = previous_stage
	if completed or objectives.is_empty():
		return
	var objective := objectives[stage]
	if str(objective.get("type", "")) == "talk_to" and contact.name == str(objective.get("target", "")):
		_show_dialogue(str(objective.get("dialogue", "")))
		_advance()


func _on_vehicle_entered(_vehicle: DriveableVehicle) -> void:
	if stage < objectives.size() and str(objectives[stage].get("type", "")) == "enter_vehicle":
		_advance()


func _advance() -> void:
	stage += 1
	if stage >= objectives.size():
		completed = true
		if mission_id == "jaime_playa":
			jaime_finished = true
		mission_completed.emit()
		if mission_id == "jaime_playa" and suspended_el_recado_stage >= 0:
			var previous_stage := suspended_el_recado_stage
			suspended_el_recado_stage = -1
			load_mission("el_recado", false)
			restore_stage(previous_stage)
		else:
			_emit_completed()
	else:
		_emit_objective()


func _emit_objective() -> void:
	if objectives.is_empty():
		return
	var objective := objectives[stage]
	var marker := marker_of(objective)
	objective_changed.emit(str(objective.get("text", "")), Vector3(float(marker[0]), 0, float(marker[1])))


func _show_dialogue(value: String) -> void:
	dialogue = value
	dialogue_timer = 6.0
	dialogue_changed.emit(dialogue)


func restore_stage(value: int) -> void:
	stage = clampi(value, 0, objectives.size())
	completed = stage == objectives.size()
	if completed:
		_emit_completed()
	else:
		_emit_objective()


func _emit_completed() -> void:
	var marker := active_marker()
	objective_changed.emit(objective_label(), Vector3(float(marker[0]), 0, float(marker[1])) if marker.size() == 2 else Vector3.ZERO)


## Arrest or other failure: return an in-progress mission to its data-defined checkpoint.
func fail_to_checkpoint(reason: String) -> void:
	if completed or objectives.is_empty():
		_show_dialogue(reason)
		return
	if stage > fail_checkpoint:
		stage = fail_checkpoint
		_emit_objective()
		mission_failed.emit(reason)
		_show_dialogue(reason + " " + fail_dialogue)
	else:
		_show_dialogue(reason)
