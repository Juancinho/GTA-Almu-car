extends Node3D

const WorldScript = preload("res://scripts/world.gd")
const PlayerScript = preload("res://scripts/player.gd")
const HudScript = preload("res://scripts/hud.gd")
const WantedScript = preload("res://scripts/wanted.gd")
const MissionScript = preload("res://scripts/mission.gd")
const PerfMonitorScript = preload("res://scripts/perf_monitor.gd")
const PlaytestLogScript = preload("res://scripts/playtest_log.gd")
const ARREST_RESPAWN := Vector3(92.0, 0.2, 30.0)
const HOSPITAL_RESPAWN := Vector3(-110.0, 0.2, 26.0)
const MISSION_REWARD := 500
const ARREST_FEE := 100
const HOSPITAL_FEE := 100

var world: Node3D
var player: PlayerController
var hud: GameHud
var wanted: WantedSystem
var mission: MissionController
var perf_monitor: PerfMonitor
var playtest_log: PlaytestLog
var save_path := "user://save_v1.json"
var ui_audio: AudioStreamPlayer
var quality_level := 2
var volume_level := 2
var money := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_configure_input()
	_configure_audio()
	world = WorldScript.new()
	world.name = "District_Altillo"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	player = PlayerScript.new()
	player.name = "Player"
	player.position = Vector3(92.0, 0.2, 30.0)
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	wanted = WantedScript.new()
	wanted.name = "WantedSystem"
	wanted.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(wanted)
	wanted.configure(player, world.road_network)
	wanted.player_busted.connect(_on_player_busted)
	wanted.wanted_changed.connect(_on_wanted_changed)
	mission = MissionScript.new()
	mission.name = "Mission"
	mission.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(mission)
	mission.configure(player, wanted)
	mission.objective_changed.connect(_play_ui_feedback)
	mission.objective_changed.connect(_on_objective_changed)
	mission.mission_completed.connect(_on_mission_completed)
	mission.mission_failed.connect(_on_mission_failed)
	player.vehicle_entered.connect(_on_vehicle_entered)
	player.vehicle_jacked.connect(_on_vehicle_jacked)
	player.died.connect(_on_player_died)
	player.assaulted.connect(func(victim: Pedestrian) -> void: wanted.report_crime("agresión", victim.global_position))
	wanted.crime_reported.connect(func(kind: String, witnessed: bool) -> void: playtest_log.record("crime", {"kind": kind, "witnessed": witnessed}))
	hud = HudScript.new()
	add_child(hud)
	hud.set_game(player, mission, wanted)
	hud.road_network = world.road_network
	perf_monitor = PerfMonitorScript.new()
	perf_monitor.name = "PerfMonitor"
	perf_monitor.context_provider = _perf_context
	add_child(perf_monitor)
	playtest_log = PlaytestLogScript.new()
	playtest_log.name = "PlaytestLog"
	playtest_log.perf = perf_monitor
	add_child(playtest_log)
	_apply_settings()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _configure_audio() -> void:
	for bus_name in ["SFX", "Music", "Ambience", "UI"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	var ambience := AudioStreamPlayer.new()
	ambience.name = "SeaWindAmbience"
	ambience.bus = "Ambience"
	ambience.volume_db = -11.0
	ambience.stream = load("res://assets/audio/sea_wind_loop.wav") as AudioStream
	if ambience.stream is AudioStreamWAV:
		(ambience.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	ambience.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(ambience)
	if DisplayServer.get_name() != "headless":
		ambience.play()
	ui_audio = AudioStreamPlayer.new()
	ui_audio.name = "UiFeedback"
	ui_audio.bus = "UI"
	ui_audio.volume_db = -8.0
	ui_audio.stream = load("res://assets/audio/ui_click.wav") as AudioStream
	add_child(ui_audio)


func _play_ui_feedback(_objective: String, _marker: Vector3) -> void:
	if DisplayServer.get_name() != "headless":
		ui_audio.play()


func _perf_context() -> String:
	if wanted.level > 0:
		return "pursuit"
	if player.driving_vehicle != null:
		return "driving"
	return "on_foot"


func _auto_report(reason: String) -> void:
	# Only real interactive sessions write automatically; tests write explicitly.
	if playtest_log.mode == "human" and DisplayServer.get_name() != "headless" and playtest_log.elapsed_seconds() > 20.0:
		playtest_log.write_report(reason)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and playtest_log != null:
		playtest_log.record("quit")
		_auto_report("window_closed")


func _on_objective_changed(text: String, _marker: Vector3) -> void:
	playtest_log.record("objective", {"stage": mission.stage, "text": text})


func add_money(amount: int) -> void:
	money = maxi(0, money + amount)
	hud.show_money_change(amount)


func _on_vehicle_jacked(vehicle: DriveableVehicle, _driver: Pedestrian) -> void:
	playtest_log.record("carjack", {"vehicle": str(vehicle.name)})


func _on_player_died() -> void:
	playtest_log.record("wasted", {"position": [player.global_position.x, player.global_position.z], "stage": mission.stage})
	hud.show_banner("HAS MUERTO", Color("d9534a"))
	get_tree().create_timer(3.0, false).timeout.connect(_respawn_at_hospital)


func _respawn_at_hospital() -> void:
	if player.driving_vehicle != null:
		player._interact()
	wanted.clear_wanted()
	player.global_position = HOSPITAL_RESPAWN
	player.velocity = Vector3.ZERO
	player.heal_full()
	world.reset_vehicle("FirstCar")
	add_money(-HOSPITAL_FEE)
	mission.fail_to_checkpoint("Centro de salud: -%d €." % HOSPITAL_FEE)


func _on_mission_completed() -> void:
	playtest_log.record("mission_completed", {"stage": mission.stage})
	add_money(MISSION_REWARD)
	_auto_report("mission_completed")


func _on_mission_failed(reason: String) -> void:
	playtest_log.record("mission_failed", {"reason": reason, "stage": mission.stage})


func _on_wanted_changed(level: int, phase: String) -> void:
	playtest_log.record("wanted", {"level": level, "phase": phase})


func _on_vehicle_entered(vehicle: DriveableVehicle) -> void:
	playtest_log.record("vehicle_entered", {"vehicle": str(vehicle.name)})


func _on_player_busted() -> void:
	playtest_log.record("busted", {"position": [player.global_position.x, player.global_position.z], "stage": mission.stage})
	if player.driving_vehicle != null:
		player._interact()
	player.global_position = ARREST_RESPAWN
	player.velocity = Vector3.ZERO
	world.reset_vehicle("FirstCar")
	hud.show_banner("DETENIDO", Color("5b8bd9"))
	add_money(-ARREST_FEE)
	mission.fail_to_checkpoint("Te han detenido (-%d €)." % ARREST_FEE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if get_tree().paused:
			get_tree().paused = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		playtest_log.record("pause", {"paused": get_tree().paused})
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart"):
		playtest_log.record("restart", {"stage": mission.stage})
		_auto_report("restart")
		get_tree().paused = false
		get_tree().reload_current_scene()
	elif event.is_action_pressed("save_game"):
		_save_game()
		playtest_log.record("save", {"stage": mission.stage})
	elif event.is_action_pressed("load_game"):
		_load_game()
		playtest_log.record("load", {"stage": mission.stage})
	elif event.is_action_pressed("quality_cycle"):
		quality_level = (quality_level + 1) % 3
		_apply_settings()
		playtest_log.record("quality", {"level": quality_level})
	elif event.is_action_pressed("volume_cycle"):
		volume_level = (volume_level + 1) % 3
		_apply_settings()
	elif event.is_action_pressed("fullscreen_toggle"):
		var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
		playtest_log.record("fullscreen", {"enabled": not fullscreen})
	elif event.is_action_pressed("perf_overlay"):
		perf_monitor.toggle_overlay()
	elif event.is_action_pressed("perf_report"):
		var path := playtest_log.write_report("manual_f6")
		mission._show_dialogue("Informe guardado: " + path.get_file() if path != "" else "No se pudo guardar el informe.")
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _configure_input() -> void:
	_add_key("move_forward", KEY_W)
	_add_key("move_back", KEY_S)
	_add_key("move_left", KEY_A)
	_add_key("move_right", KEY_D)
	_add_key("sprint", KEY_SHIFT)
	_add_key("jump", KEY_SPACE)
	_add_key("interact", KEY_E)
	_add_key("pause", KEY_ESCAPE)
	_add_key("brake", KEY_SPACE)
	_add_key("restart", KEY_R)
	_add_key("save_game", KEY_F5)
	_add_key("load_game", KEY_F9)
	_add_key("quality_cycle", KEY_F3)
	_add_key("volume_cycle", KEY_F4)
	_add_key("attack", KEY_F)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", click)
	_add_joy_button("attack", JOY_BUTTON_RIGHT_SHOULDER)
	_add_key("perf_overlay", KEY_F2)
	_add_key("fullscreen_toggle", KEY_F11)
	_add_key("perf_report", KEY_F6)
	for action in ["look_left", "look_right", "look_up", "look_down"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
	_add_joy_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_joy_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_add_joy_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_joy_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_add_joy_button("brake", JOY_BUTTON_B)
	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_button("jump", JOY_BUTTON_A)
	_add_joy_button("interact", JOY_BUTTON_X)
	_add_joy_button("sprint", JOY_BUTTON_LEFT_SHOULDER)
	_add_joy_button("pause", JOY_BUTTON_START)


func _add_key(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var key := InputEventKey.new()
	key.physical_keycode = keycode
	InputMap.action_add_event(action, key)


func _add_joy_axis(action: StringName, axis: JoyAxis, value: float) -> void:
	var motion := InputEventJoypadMotion.new()
	motion.axis = axis
	motion.axis_value = value
	InputMap.action_add_event(action, motion)


func _add_joy_button(action: StringName, button: JoyButton) -> void:
	var press := InputEventJoypadButton.new()
	press.button_index = button
	InputMap.action_add_event(action, press)


func _apply_settings() -> void:
	world.apply_quality(quality_level)
	if perf_monitor != null:
		perf_monitor.extra_info["quality_level"] = quality_level
	AudioServer.set_bus_volume_db(0, [-16.0, -6.0, 0.0][volume_level])
	hud.update_settings(quality_level, volume_level)


func _save_game() -> void:
	var vehicle: DriveableVehicle = player.driving_vehicle
	var data := {
		"version": 1,
		"player_position": [player.global_position.x, player.global_position.y, player.global_position.z],
		"camera_yaw": player.camera_yaw,
		"mission_stage": mission.stage,
		"quality_level": quality_level,
		"volume_level": volume_level,
		"money": money,
		"health": player.health,
		"vehicle_name": vehicle.name if vehicle != null else "",
		"vehicle_position": [vehicle.global_position.x, vehicle.global_position.y, vehicle.global_position.z] if vehicle != null else [],
		"vehicle_yaw": vehicle.rotation.y if vehicle != null else 0.0
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write game save: " + str(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data))
	file.close()
	mission._show_dialogue("Partida guardada.")


func _load_game() -> void:
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		mission._show_dialogue("No hay partida guardada.")
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or data.get("version", 0) != 1:
		push_error("Invalid save_v1.json")
		return
	if player.driving_vehicle != null:
		player._interact()
	wanted.clear_wanted()
	var point := data.get("player_position", []) as Array
	if point.size() != 3:
		push_error("Invalid player position in save_v1.json")
		return
	player.global_position = Vector3(float(point[0]), float(point[1]), float(point[2]))
	player.velocity = Vector3.ZERO
	player.camera_yaw = float(data.get("camera_yaw", -2.0))
	player._update_camera_orientation()
	mission.restore_stage(int(data.get("mission_stage", 0)))
	money = maxi(0, int(data.get("money", money)))
	player.heal_full()
	player.health = clampf(float(data.get("health", PlayerController.MAX_HEALTH)), 1.0, PlayerController.MAX_HEALTH)
	player.health_changed.emit(player.health)
	quality_level = clampi(int(data.get("quality_level", 2)), 0, 2)
	volume_level = clampi(int(data.get("volume_level", 2)), 0, 2)
	_apply_settings()
	var vehicle_name := str(data.get("vehicle_name", ""))
	if vehicle_name != "":
		var car := world.get_node_or_null(vehicle_name) as DriveableVehicle
		var car_point := data.get("vehicle_position", []) as Array
		if car != null and car_point.size() == 3:
			car.global_position = Vector3(float(car_point[0]), float(car_point[1]), float(car_point[2]))
			car.rotation.y = float(data.get("vehicle_yaw", 0.0))
			player.board_vehicle(car)
	mission._show_dialogue("Partida cargada.")
