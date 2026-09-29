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
var fail_dialogue := ""


func _ready() -> void:
	var file := FileAccess.open("res://data/missions/el_recado.json", FileAccess.READ)
	if file == null:
		push_error("Mission data missing: res://data/missions/el_recado.json")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.has("objectives"):
		push_error("Invalid mission data: el_recado.json")
		return
	for objective in parsed["objectives"]:
		objectives.append(objective)
	fail_checkpoint = int(parsed.get("fail_checkpoint", 0))
	fail_dialogue = str(parsed.get("fail_dialogue", ""))


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
			var marker := objective.get("marker", [0, 0]) as Array
			var player_pos := player.driving_vehicle.global_position if player.driving_vehicle != null else player.global_position
			var distance := Vector2(player_pos.x - float(marker[0]), player_pos.z - float(marker[1])).length()
			if distance < float(objective.get("radius", 10)):
				if bool(objective.get("witnessed_incident", false)) and wanted.level == 0:
					if not wanted.report_incident(player_pos):
						return
				_show_dialogue(str(objective.get("dialogue", "")))
				_advance()
		"escape_police":
			if wanted.level == 0:
				_advance()


func _on_contact(contact: Pedestrian) -> void:
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
		mission_completed.emit()
		objective_changed.emit("El Recado completado", Vector3.ZERO)
	else:
		_emit_objective()


func _emit_objective() -> void:
	if objectives.is_empty():
		return
	var objective := objectives[stage]
	var marker := objective.get("marker", [0, 0]) as Array
	objective_changed.emit(str(objective.get("text", "")), Vector3(float(marker[0]), 0, float(marker[1])))


func _show_dialogue(value: String) -> void:
	dialogue = value
	dialogue_timer = 6.0
	dialogue_changed.emit(dialogue)


func restore_stage(value: int) -> void:
	stage = clampi(value, 0, objectives.size())
	completed = stage == objectives.size()
	if completed:
		objective_changed.emit("El Recado completado", Vector3.ZERO)
	else:
		_emit_objective()


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
