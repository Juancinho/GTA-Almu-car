extends Node3D

const WorldScript = preload("res://scripts/sector_world.gd")
const PlayerScript = preload("res://scripts/player.gd")
const HudScript = preload("res://scripts/hud.gd")
const WantedScript = preload("res://scripts/wanted.gd")
const MissionScript = preload("res://scripts/mission.gd")
const PerfMonitorScript = preload("res://scripts/perf_monitor.gd")
const PlaytestLogScript = preload("res://scripts/playtest_log.gd")
const MarkersScript = preload("res://scripts/mission_markers.gd")
const WeaponScript = preload("res://scripts/weapons.gd")
const DayNightScript = preload("res://scripts/day_night.gd")
const ActivityScript = preload("res://scripts/activities.gd")
const ARREST_FEE := 100
const HOSPITAL_FEE := 100

var world: SectorWorld
var ARREST_RESPAWN := Vector3.ZERO
var HOSPITAL_RESPAWN := Vector3.ZERO
var player: PlayerController
var hud: GameHud
var wanted: WantedSystem
var mission: MissionController
var weapons: WeaponScript
var day_night: DayNightScript
var activities: ActivityScript
var perf_monitor: PerfMonitor
var playtest_log: PlaytestLog
var save_path := "user://save_v1.json"
var ui_audio: AudioStreamPlayer
var quality_level := 1
var volume_level := 2
var money := 0
var bank_balance := 0
var jewellery_robbed := false
var cigarettes := 0
var estanco_robbed_until := 0
var smoking: Node  # SmokingSystem
var stash_ready_at := 0
var discoveries: Dictionary = {}
var _warm_resources: Array = []  # scenes loaded up front: no hitch when police or weapons first appear


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_configure_input()
	_configure_audio()
	_warm_up()
	world = WorldScript.new()
	world.name = "District_Altillo"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	player = PlayerScript.new()
	player.name = "Player"
	player.sector_data = world.data
	player.position = world.anchor("player_spawn") + Vector3(0, 0.3, 0)
	player.camera_yaw = PI * 0.15
	ARREST_RESPAWN = world.anchor("arrest_release") + Vector3(0, 0.3, 0)
	HOSPITAL_RESPAWN = world.anchor("hospital") + Vector3(3.5, 0.4, 0)
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	wanted = WantedScript.new()
	wanted.name = "WantedSystem"
	wanted.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(wanted)
	wanted.configure(player, world.road_network)
	wanted.restricted_zones = world.restricted_zones
	wanted.player_busted.connect(_on_player_busted)
	wanted.wanted_changed.connect(_on_wanted_changed)
	mission = MissionScript.new()
	mission.name = "Mission"
	mission.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(mission)
	mission.anchors = world.data.raw.get("anchors", {})
	mission.world = world
	mission.configure(player, wanted)
	mission.objective_changed.connect(_play_ui_feedback)
	mission.objective_changed.connect(_on_objective_changed)
	mission.mission_completed.connect(_on_mission_completed)
	mission.mission_failed.connect(_on_mission_failed)
	mission.mission_started.connect(func(title: String) -> void: playtest_log.record("mission_started", {"id": mission.mission_id, "title": title}))
	weapons = WeaponScript.new() as WeaponScript
	weapons.name = "Weapons"
	weapons.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(weapons)
	weapons.configure(player, world, wanted)
	player.weapons = weapons
	weapons.fired.connect(func(id: String, _hit: Object) -> void: playtest_log.record("shot", {"weapon": id}))
	day_night = DayNightScript.new() as DayNightScript
	day_night.name = "DayNight"
	day_night.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(day_night)
	day_night.configure(world, player)
	activities = ActivityScript.new() as ActivityScript
	activities.name = "Activities"
	activities.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(activities)
	activities.configure(world, player)
	activities.activity_changed.connect(func(text: String) -> void: playtest_log.record("activity", {"label": text}))
	var markers := MarkersScript.new() as MarkersScript
	markers.name = "MissionMarkers"
	markers.mission = mission
	markers.player = player
	add_child(markers)
	player.vehicle_entered.connect(_on_vehicle_entered)
	player.vehicle_jacked.connect(_on_vehicle_jacked)
	player.died.connect(_on_player_died)
	player.assaulted.connect(func(victim: Pedestrian) -> void: wanted.report_crime("agresión", victim.global_position))
	player.civilian_interacted.connect(func(civilian: Pedestrian) -> void: mission._show_dialogue(civilian.speak()))
	world.workshop.repair_requested.connect(_on_workshop_repair)
	for venue in world.venues.values():
		(venue as VenueInterior).purchase_requested.connect(_on_venue_purchase)
		(venue as VenueInterior).bank_transaction_requested.connect(_on_bank_transaction)
		(venue as VenueInterior).robbery_requested.connect(_on_jewellery_robbery)
		(venue as VenueInterior).interior_event_requested.connect(_on_interior_event)
	for block in world.apartments.values():
		block.action_requested.connect(_on_block_action)
	for bar in world.beach_bars:
		bar.meal_requested.connect(func() -> void: _on_venue_purchase("restaurant"))
	wanted.crime_reported.connect(func(kind: String, witnessed: bool) -> void: playtest_log.record("crime", {"kind": kind, "witnessed": witnessed}))
	hud = HudScript.new()
	add_child(hud)
	hud.set_game(player, mission, wanted)
	hud.road_network = world.road_network
	hud.minimap.workshop_marker = Vector2(world.workshop.exterior_entry.x, world.workshop.exterior_entry.z)
	for kind in world.venues:
		var venue := world.venues[kind] as VenueInterior
		hud.minimap.venue_markers[kind] = Vector2(venue.exterior_entry.x, venue.exterior_entry.z)
	if world.apartments.has("residencial_poniente"):
		var home: Vector3 = world.apartments["residencial_poniente"].exterior_entry
		hud.minimap.venue_markers["piso_franco"] = Vector2(home.x, home.z)
	hud.world_map.configure(world, mission, player, hud.minimap)
	hud.minimap.activities = activities
	activities.activity_changed.connect(func(text: String) -> void: if text != "": hud._on_objective_changed(text, Vector3.ZERO))
	smoking = (load("res://scripts/smoking.gd") as GDScript).new()
	smoking.name = "Smoking"
	smoking.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(smoking)
	smoking.call("configure", player, self)
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
	if DisplayServer.get_name() != "headless":
		# Compile every material up front instead of stalling mid-game.
		(load("res://scripts/shader_warmup.gd") as GDScript).call("attach", player.camera, world, _warm_resources)


func _warm_up() -> void:
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/vehicles/models.json"))
	if catalog is Dictionary:
		for spec in (catalog["variants"] as Dictionary).values():
			_warm_resources.append(load(str(spec["scene"])))
	for id in HumanModel.MODELS:
		_warm_resources.append(load(HumanModel.MODEL_DIR + id + ".fbx"))


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


## Pay-and-spray: driving into Taller Poniente unseen repaints the car and clears
## the wanted level (150 €). Seen by a patrol, the mechanic will not open up.
const RESPRAY_FEE := 150
var respray_notice := 0.0


func _physics_process(delta: float) -> void:
	respray_notice -= delta
	if wanted == null or wanted.level == 0 or player.driving_vehicle == null:
		return
	if player.driving_vehicle.global_position.distance_to(world.workshop.exterior_entry) > 10.0:
		return
	if wanted.phase == "pursuit":
		if respray_notice <= 0.0:
			mission._show_dialogue("Mecánico: ¡Con la policía detrás no te abro! Despístalos primero.")
			respray_notice = 6.0
		return
	if money < RESPRAY_FEE:
		if respray_notice <= 0.0:
			mission._show_dialogue("Mecánico: pintura nueva son %d €." % RESPRAY_FEE)
			respray_notice = 6.0
		return
	add_money(-RESPRAY_FEE)
	wanted.clear_wanted()
	player.driving_vehicle.repair()
	hud.show_banner("PINTURA NUEVA", Color("6fd4a4"))
	mission._show_dialogue("Mecánico: color nuevo y matrícula limpia. Nadie te busca ya.")
	playtest_log.record("respray", {})


func _on_workshop_repair() -> void:
	var selected: DriveableVehicle
	var nearest := 15.0
	for node in get_tree().get_nodes_in_group("vehicles"):
		var vehicle := node as DriveableVehicle
		if vehicle == null or vehicle.destroyed or vehicle.traffic:
			continue
		var distance := vehicle.global_position.distance_to(world.workshop.exterior_entry)
		if distance < nearest:
			selected = vehicle
			nearest = distance
	if selected == null:
		mission._show_dialogue("Mecánico: aparca el coche junto al taller y vuelve.")
	elif money < 75:
		mission._show_dialogue("Mecánico: la reparación cuesta 75 €.")
	else:
		selected.repair()
		add_money(-75)
		mission._show_dialogue("Mecánico: listo. Ya puedes volver a la carretera.")


const GUN_PRICES := [["pistol", 300], ["shotgun", 800], ["smg", 1200], ["rifle", 1500]]


func _on_interior_event(event: String) -> void:
	if event == "casino_stash":
		if not discoveries.has(event):
			discoveries[event] = true
			add_money(125)
			(world.venues["casino"] as VenueInterior).restore_discoveries(discoveries)
			hud.show_banner("SECRETO ENCONTRADO · 125 €", Color("f2d36b"))
			playtest_log.record("discovery", {"id": event})
		return
	var previous_stage := mission.stage
	mission.notify_event(event)
	if previous_stage == mission.stage:
		mission._show_dialogue("El libro registra pagos a sociedades del puerto. Inés podría saber qué buscar.")


func _on_venue_purchase(kind: String) -> void:
	if kind.begins_with("estanco"):
		_on_estanco(kind.ends_with("_secondary"), kind.trim_suffix("_secondary"))
		return
	if bool(VenueInterior.SPECS.get(kind, {}).get("residential", false)):
		if wanted.level > 0:
			mission._show_dialogue("No puedes descansar mientras te busca la policía.")
		else:
			player.heal_full()
			mission._show_dialogue("Descansas en el apartamento. Salud y aire recuperados.")
		return
	if kind in ["barber", "clothing"]:
		var price := int(VenueInterior.SPECS[kind]["price"])
		if money < price:
			mission._show_dialogue("Necesitas %d € para cambiar de estilo." % price)
		else:
			add_money(-price)
			var styles := ["male_casual", "male_longsleeve", "male_shirt", "male_suit"]
			player.human.change_model(styles[(styles.find(player.human.model_name) + 1) % styles.size()])
			mission._show_dialogue("Estrenas un nuevo estilo. Se conservará al guardar la partida.")
		return
	if kind == "record_shop":
		var station := world.venues[kind].room.get_node("ListeningStation") as AudioStreamPlayer3D
		if station.playing:
			station.stop()
		else:
			station.play()
		mission._show_dialogue("Surco Sur: sesión original de Brisa de Poniente.")
		return
	match kind:
		"casino":
			_gamble(100, 0.46, 2, true)
			return
		"casino_secondary":
			_gamble(20, 0.22, 4, false)
			return
		"gun_shop":
			if not weapons.is_gun():
				mission._show_dialogue("Armero: primero necesitas un arma. Mira la vitrina de la derecha.")
			elif money < 100:
				mission._show_dialogue("Armero: la munición son 100 €.")
			else:
				add_money(-100)
				var clip_size := int(weapons.definition().get("clip", 10))
				weapons.reserve[weapons.current] = int(weapons.reserve.get(weapons.current, 0)) + clip_size * 3
				weapons.inventory_changed.emit()
				mission._show_dialogue("Armero: tres cargadores de %s. No me digas para qué." % weapons.display_name().to_lower())
			return
		"gun_shop_secondary":
			for pair in GUN_PRICES:
				if not weapons.owned.has(pair[0]):
					if money < int(pair[1]):
						mission._show_dialogue("Armero: %s cuesta %d €. Vuelve con el dinero." % [str(weapons.defs[pair[0]]["name"]), int(pair[1])])
					else:
						add_money(-int(pair[1]))
						weapons.give(str(pair[0]), int(weapons.defs[pair[0]].get("clip", 10)) * 3)
						mission._show_dialogue("Armero: %s, con tres cargadores. Usa la cabeza." % str(weapons.defs[pair[0]]["name"]))
					return
			mission._show_dialogue("Armero: ya tienes todo lo que vendo.")
			return
	if kind == "church":
		player.heal(20.0)
		mission._show_dialogue("Un momento de calma en la Encarnación. Recuperas fuerzas.")
		return
	var spec: Dictionary = VenueInterior.SPECS.get(kind, {})
	var price := int(spec.get("price", 15 if kind == "supermarket" or kind == "mall" else 35))
	if player.health >= PlayerController.MAX_HEALTH:
		mission._show_dialogue("Ahora mismo no necesitas recuperar salud.")
	elif money < price:
		mission._show_dialogue("Te faltan %d € para pagar." % (price - money))
	else:
		add_money(-price)
		player.heal(float(spec.get("heal", 30.0 if kind == "supermarket" or kind == "mall" else PlayerController.MAX_HEALTH)))
		mission._show_dialogue("Camarera: café recién hecho y tostada. ¡Que aproveche!" if kind == "cafe" else "Dependiente: aquí tienes. Que te aproveche." if kind == "supermarket" or kind == "mall" else "Camarero: el menú de hoy te sentará bien.")


var gamble_rng := RandomNumberGenerator.new()


func _gamble(stake: int, chance: float, multiplier: int, roulette: bool) -> void:
	if money < stake:
		mission._show_dialogue("Necesitas %d € para jugar." % stake)
		return
	add_money(-stake)
	var number := gamble_rng.randi_range(0, 36) if roulette else -1
	var red_numbers := [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]
	var won := red_numbers.has(number) if roulette else gamble_rng.randf() < chance
	if won:
		add_money(stake * multiplier)
		hud.show_banner("+%d €" % (stake * multiplier), Color("f2d36b"))
	if roulette:
		mission._show_dialogue("Crupier: %d, %s. %s" % [number, "rojo" if won else "verde" if number == 0 else "negro", "Cobras 200 € (incluye tu apuesta)." if won else "La banca gana."])
	else:
		mission._show_dialogue("Tragaperras: %s" % ("¡tres limones, premio!" if won else "nada esta vez."))
	playtest_log.record("gamble", {"stake": stake, "won": won})


## Buy a pack of 20 for 5 €, or grab a carton from behind the counter (one star).
func _on_estanco(steal: bool, kind: String) -> void:
	if steal:
		if Time.get_ticks_msec() < estanco_robbed_until:
			mission._show_dialogue("Estanquera: ¡Ya llamé a la policía la otra vez! No queda nada a mano.")
			return
		estanco_robbed_until = Time.get_ticks_msec() + 180000
		cigarettes += 200
		wanted.raise_to(1, player.global_position)
		hud.show_banner("CARTÓN ROBADO", Color("f2d36b"))
		mission._show_dialogue("Estanquera: ¡Al ladrón! ¡Que alguien llame a la policía!")
		playtest_log.record("crime", {"kind": "robo en estanco", "witnessed": true})
		return
	if money < 5:
		mission._show_dialogue("Estanquera: son 5 €, cariño.")
		return
	add_money(-5)
	cigarettes += 20
	mission._show_dialogue("Estanquera: aquí tienes tu paquete. Pulsa X para encender uno (fuera, que aquí no se fuma).")


func _on_bank_transaction(action: String) -> void:
	if action == "deposit":
		if money < 100:
			mission._show_dialogue("Caja Poniente: necesitas 100 € en efectivo. Saldo: %d €." % bank_balance)
			return
		add_money(-100)
		bank_balance += 100
		mission._show_dialogue("Caja Poniente: ingresados 100 €. Saldo: %d €." % bank_balance)
	elif action == "withdraw":
		if bank_balance < 100:
			mission._show_dialogue("Cajero: saldo insuficiente. Saldo: %d €." % bank_balance)
			return
		bank_balance -= 100
		add_money(100)
		mission._show_dialogue("Cajero: retirados 100 €. Saldo: %d €." % bank_balance)


## Residential blocks: the safehouse bed (rest + save), its stash, Ferrer's safe, burglaries.
func _on_block_action(block_id: String, action: String) -> void:
	if action.begins_with("burgle:"):
		var block: Node = world.apartments.get(block_id)
		var door := action.trim_prefix("burgle:")
		if block == null or not block.can_burgle(door):
			return
		block.mark_burgled(door)
		var night := float(day_night.night) > 0.5
		var loot := randi_range(80, 260) if night else randi_range(40, 160)
		add_money(loot)
		hud.show_banner("ROBO EN EL %s  +%d €" % [door, loot], Color("f2d36b"))
		if randf() < (0.25 if night else 0.6):
			wanted.report_scripted_crime("robo en vivienda", player.global_position)
			mission._show_dialogue("Vecina: ¡Al ladrón! ¡Que llamen a la policía!")
		else:
			mission._show_dialogue("Todos duermen. Sales con el dinero sin que nadie se entere." if night else "No hay nadie en casa. Un sobre con dinero en el cajón... y a correr.")
		return
	match action:
		"sleep":
			if wanted.level > 0:
				mission._show_dialogue("Con la policía buscándote no hay quien duerma.")
				return
			player.heal_full()
			day_night.hours = fmod(day_night.hours + 8.0, 24.0)
			hud.show_banner("PISO FRANCO  ·  %s" % day_night.clock_text(), Color("9fd8a8"))
			_save_game()
		"stash":
			if Time.get_ticks_msec() < stash_ready_at:
				mission._show_dialogue("El armario está vacío. Vuelve más tarde.")
				return
			stash_ready_at = Time.get_ticks_msec() + 300000
			weapons.give("bat", 0)
			weapons.give("pistol", 36)
			cigarettes += 20
			mission._show_dialogue("Alijo: la pistola con 36 balas, el bate y un paquete de tabaco.")
		"heist":
			var office: Node = world.apartments.get(block_id)
			if office == null or not office.can_burgle("office_safe"):
				return
			office.mark_burgled("office_safe")
			var take := randi_range(900, 1600)
			add_money(take)
			hud.show_banner("CAJA DE MAR AZUL  +%d €" % take, Color("f2d36b"))
			wanted.raise_to(2, player.global_position)
			mission._show_dialogue("Dinero negro de las comisiones. ¡Ha saltado la alarma de la empresa de seguridad!")
		"safe":
			var before := "%s:%d:%s" % [mission.mission_id, mission.stage, mission.completed]
			mission.notify_event("atico_safe")
			if before == "%s:%d:%s" % [mission.mission_id, mission.stage, mission.completed]:
				mission._show_dialogue("Una caja fuerte con combinación. Ahora no.")


func _garage_state() -> Dictionary:
	var state := {}
	for block in world.apartments.values():
		if str(block.garage_variant) != "":
			state[block.block_id] = block.garage_variant
	return state


func _on_jewellery_robbery() -> void:
	if jewellery_robbed:
		mission._show_dialogue("La vitrina está vacía. La dependienta ya ha avisado a la policía.")
		return
	jewellery_robbed = true
	(world.venues["jewellery"] as VenueInterior).set_robbed(true)
	add_money(250)
	wanted.report_scripted_crime("robo en joyería", (world.venues["jewellery"] as VenueInterior).exterior_entry)
	hud.show_banner("BOTÍN 250 €", Color("f2d36b"))
	mission.notify_event("jewellery_robbed")
	mission._show_dialogue("Dependienta: ¡Alto! La alarma está conectada con la comisaría.")


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
	_sync_venue_rooms()
	player.velocity = Vector3.ZERO
	player.heal_full()
	world.reset_vehicle("FirstCar")
	add_money(-HOSPITAL_FEE)
	mission.fail_to_checkpoint("Centro de salud: -%d €." % HOSPITAL_FEE)


func _on_mission_completed() -> void:
	playtest_log.record("mission_completed", {"id": mission.mission_id, "stage": mission.stage})
	add_money(mission.reward)
	if mission.mission_id == "poniente":
		wanted.clear_wanted()
		hud.show_credits()
	hud.show_banner("¡MISIÓN SUPERADA!\n+%d €" % mission.reward, Color("f2c14e"))
	_auto_report("mission_completed")


func _on_mission_failed(reason: String) -> void:
	playtest_log.record("mission_failed", {"reason": reason, "stage": mission.stage})
	if not hud.banner_label.visible:  # arrest and death show their own banner
		hud.show_banner("MISIÓN FALLIDA", Color("d9534a"))


func _on_wanted_changed(level: int, phase: String) -> void:
	playtest_log.record("wanted", {"level": level, "phase": phase})


func _on_vehicle_entered(vehicle: DriveableVehicle) -> void:
	playtest_log.record("vehicle_entered", {"vehicle": str(vehicle.name)})


func _on_player_busted() -> void:
	playtest_log.record("busted", {"position": [player.global_position.x, player.global_position.z], "stage": mission.stage})
	if player.driving_vehicle != null:
		player._interact()
	player.global_position = ARREST_RESPAWN
	_sync_venue_rooms()
	player.velocity = Vector3.ZERO
	world.reset_vehicle("FirstCar")
	hud.show_banner("DETENIDO", Color("5b8bd9"))
	add_money(-ARREST_FEE)
	mission.fail_to_checkpoint("Te han detenido (-%d €)." % ARREST_FEE)


func _toggle_map() -> void:
	if hud.world_map.visible:
		hud.world_map.close()
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		hud.world_map.open()
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	playtest_log.record("map", {"open": hud.world_map.visible})


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map_toggle") or (hud.world_map.visible and event.is_action_pressed("pause")):
		_toggle_map()
		get_viewport().set_input_as_handled()
		return
	if hud.world_map.visible:
		return
	if event.is_action_pressed("pause"):
		if get_tree().paused:
			get_tree().paused = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		playtest_log.record("pause", {"paused": get_tree().paused})
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart") and get_tree().paused:
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
	_add_key("dive", KEY_C)
	_add_key("interact", KEY_E)
	_add_key("pause", KEY_ESCAPE)
	_add_key("brake", KEY_SPACE)
	_add_key("restart", KEY_R)
	_add_key("reload", KEY_R)
	_add_key("weapon_1", KEY_1)
	_add_key("weapon_2", KEY_2)
	_add_key("weapon_3", KEY_3)
	_add_key("weapon_4", KEY_4)
	_add_key("weapon_5", KEY_5)
	_add_key("weapon_6", KEY_6)
	for pair in [["weapon_next", MOUSE_BUTTON_WHEEL_DOWN], ["weapon_prev", MOUSE_BUTTON_WHEEL_UP], ["aim", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		var wheel := InputEventMouseButton.new()
		wheel.button_index = pair[1]
		InputMap.action_add_event(pair[0], wheel)
	_add_joy_button("weapon_next", JOY_BUTTON_DPAD_RIGHT)
	_add_joy_button("weapon_prev", JOY_BUTTON_DPAD_LEFT)
	_add_joy_button("reload", JOY_BUTTON_Y)
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_LEFT
	trigger.axis_value = 1.0
	InputMap.action_add_event("aim", trigger)
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
	_add_key("map_toggle", KEY_M)
	_add_key("smoke", KEY_X)
	_add_key("activity", KEY_T)
	_add_joy_button("map_toggle", JOY_BUTTON_BACK)
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
	_add_joy_button("dive", JOY_BUTTON_B)
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
	get_viewport().scaling_3d_scale = [0.67, 0.85, 1.0][quality_level]
	if perf_monitor != null:
		perf_monitor.extra_info["quality_level"] = quality_level
		perf_monitor.extra_info["render_scale_3d"] = get_viewport().scaling_3d_scale
	AudioServer.set_bus_volume_db(0, [-16.0, -6.0, 0.0][volume_level])
	hud.update_settings(quality_level, volume_level)


func _save_game() -> void:
	var vehicle: DriveableVehicle = player.driving_vehicle
	var data := {
		"version": 1,
		"player_position": [player.global_position.x, player.global_position.y, player.global_position.z],
		"player_model": player.human.model_name,
		"camera_yaw": player.camera_yaw,
		"mission_stage": mission.stage,
		"mission_id": mission.mission_id,
		"jaime_finished": mission.jaime_finished,
		"suspended_el_recado_stage": mission.suspended_el_recado_stage,
		"completed_missions": mission.completed_missions.keys(),
		"suspended_id": mission.suspended_id,
		"suspended_stage": mission.suspended_stage,
		"quality_level": quality_level,
		"volume_level": volume_level,
		"money": money,
		"bank_balance": bank_balance,
		"jewellery_robbed": jewellery_robbed,
		"garages": _garage_state(),
		"cigarettes": cigarettes,
		"discoveries": discoveries,
		"weapons": weapons.to_save(),
		"broken_glass": weapons.ballistics.glass_to_save(),
		"hours": day_night.hours,
		"best_race": activities.best_race,
		"health": player.health,
		"breath": player.breath,
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
	player.human.change_model(str(data.get("player_model", "male_casual")))
	if point.size() != 3:
		push_error("Invalid player position in save_v1.json")
		return
	player.global_position = Vector3(float(point[0]), float(point[1]), float(point[2]))
	_sync_venue_rooms()
	player.velocity = Vector3.ZERO
	player.camera_yaw = float(data.get("camera_yaw", -2.0))
	player._update_camera_orientation()
	if not mission.load_mission(mission.alias(str(data.get("mission_id", "el_recado"))), false):
		return
	mission.completed_missions.clear()
	for id in data.get("completed_missions", []):
		mission.completed_missions[mission.alias(str(id))] = true
	mission.jaime_finished = bool(data.get("jaime_finished", false)) or mission.completed_missions.has("jaime_playa")
	mission.suspended_el_recado_stage = int(data.get("suspended_el_recado_stage", -1))
	if data.has("suspended_id"):
		mission.suspended_id = str(data["suspended_id"])
		mission.suspended_stage = int(data.get("suspended_stage", -1))
	mission.restore_stage(int(data.get("mission_stage", 0)))
	money = maxi(0, int(data.get("money", money)))
	bank_balance = maxi(0, int(data.get("bank_balance", 0)))
	jewellery_robbed = bool(data.get("jewellery_robbed", false))
	for block in world.apartments.values():
		block.restore_garage(str((data.get("garages", {}) as Dictionary).get(block.block_id, "")))
	cigarettes = maxi(0, int(data.get("cigarettes", 0)))
	discoveries = data.get("discoveries", {}) if data.get("discoveries", {}) is Dictionary else {}
	for venue in world.venues.values():
		(venue as VenueInterior).restore_discoveries(discoveries)
	weapons.from_save(data.get("weapons", {}))
	weapons.ballistics.glass_from_save(data.get("broken_glass", []) if data.get("broken_glass", []) is Array else [])
	day_night.hours = float(data.get("hours", day_night.hours))
	activities.best_race = float(data.get("best_race", activities.best_race))
	activities.stop("")
	(world.venues["jewellery"] as VenueInterior).set_robbed(jewellery_robbed)
	player.heal_full()
	player.health = clampf(float(data.get("health", PlayerController.MAX_HEALTH)), 1.0, PlayerController.MAX_HEALTH)
	player.breath = clampf(float(data.get("breath", PlayerController.MAX_BREATH)), 0.0, PlayerController.MAX_BREATH)
	player.health_changed.emit(player.health)
	quality_level = clampi(int(data.get("quality_level", 1)), 0, 2)
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


func _sync_venue_rooms() -> void:
	for block in world.apartments.values():
		block.update_room_visibility(player.global_position)
	for venue in world.venues.values():
		var interior := venue as VenueInterior
		interior.room.visible = true
