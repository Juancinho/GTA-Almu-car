class_name GameHud
extends CanvasLayer

# Preloaded (not class_name) so a stale editor class cache cannot break the HUD.
const WorldMapScript = preload("res://scripts/world_map.gd")
const WeaponScript = preload("res://scripts/weapons.gd")

var player: PlayerController
var mission: MissionController
var wanted: WantedSystem
var road_network: RoadNetwork:
	set(value):
		road_network = value
		if minimap != null:
			minimap.road_network = value
var info_label: Label
var mission_label: Label
var wanted_label: Label
var dialogue_label: Label
var prompt_label: Label
var minimap: DistrictMinimap
var pause_overlay: ColorRect
var pause_label: Label
var stars_label: Label
var money_label: Label
var money_delta_label: Label
var bank_label: Label
var health_back: ColorRect
var health_fill: ColorRect
var banner_label: Label
var banner_timer := 0.0
var objective_flash: Label
var objective_flash_timer := 0.0
var title_label: Label
var title_timer := 0.0
var timer_label: Label
var world_map: WorldMapScript
var pause_missions: Label
var weapon_label: Label
var crosshair: Label
var money_delta_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var top := ColorRect.new()
	top.color = Color(0.08, 0.17, 0.20, 0.78)
	top.position = Vector2(18, 16)
	top.size = Vector2(390, 78)
	root.add_child(top)
	info_label = Label.new()
	info_label.position = Vector2(32, 24)
	info_label.add_theme_font_size_override("font_size", 20)
	info_label.text = "BRISA DE PONIENTE\nPaseo del Altillo · Exploración"
	root.add_child(info_label)
	var objective_back := ColorRect.new()
	objective_back.color = Color(0.08, 0.17, 0.20, 0.75)
	objective_back.position = Vector2(18, 98)
	objective_back.size = Vector2(470, 76)
	root.add_child(objective_back)
	mission_label = Label.new()
	mission_label.position = Vector2(32, 102)
	mission_label.add_theme_font_size_override("font_size", 19)
	root.add_child(mission_label)
	wanted_label = Label.new()
	wanted_label.position = Vector2(32, 137)
	wanted_label.add_theme_font_size_override("font_size", 18)
	root.add_child(wanted_label)
	minimap = DistrictMinimap.new()
	minimap.name = "Minimap"
	minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(-204, 16)
	minimap.size = Vector2(186, 186)
	root.add_child(minimap)
	# GTA-style status column under the minimap: stars, health bar, money.
	stars_label = Label.new()
	stars_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	stars_label.position = Vector2(-204, 206)
	stars_label.custom_minimum_size = Vector2(186, 30)
	stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stars_label.add_theme_font_size_override("font_size", 26)
	_outline(stars_label)
	root.add_child(stars_label)
	health_back = ColorRect.new()
	health_back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	health_back.position = Vector2(-204, 242)
	health_back.size = Vector2(186, 12)
	health_back.color = Color(0.05, 0.1, 0.1, 0.8)
	root.add_child(health_back)
	health_fill = ColorRect.new()
	health_fill.position = Vector2(2, 2)
	health_fill.size = Vector2(182, 8)
	health_fill.color = Color("6fbf73")
	health_back.add_child(health_fill)
	money_label = Label.new()
	money_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	money_label.position = Vector2(-204, 258)
	money_label.custom_minimum_size = Vector2(186, 30)
	money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_label.add_theme_font_size_override("font_size", 24)
	money_label.add_theme_color_override("font_color", Color("9fe39a"))
	_outline(money_label)
	root.add_child(money_label)
	money_delta_label = Label.new()
	money_delta_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	money_delta_label.position = Vector2(-204, 288)
	money_delta_label.custom_minimum_size = Vector2(186, 26)
	money_delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_delta_label.add_theme_font_size_override("font_size", 20)
	_outline(money_delta_label)
	root.add_child(money_delta_label)
	bank_label = Label.new()
	bank_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	bank_label.position = Vector2(-260, 322)
	bank_label.custom_minimum_size = Vector2(242, 30)
	bank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bank_label.add_theme_font_size_override("font_size", 20)
	bank_label.add_theme_color_override("font_color", Color("e6d79b"))
	_outline(bank_label)
	bank_label.visible = false
	root.add_child(bank_label)
	weapon_label = Label.new()
	weapon_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	weapon_label.position = Vector2(-300, 352)
	weapon_label.custom_minimum_size = Vector2(282, 30)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_label.add_theme_font_size_override("font_size", 22)
	weapon_label.add_theme_color_override("font_color", Color("f4ecd8"))
	_outline(weapon_label)
	root.add_child(weapon_label)
	crosshair = Label.new()
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-20, -24)
	crosshair.custom_minimum_size = Vector2(40, 40)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 30)
	_outline(crosshair, 4)
	crosshair.visible = false
	root.add_child(crosshair)
	banner_label = Label.new()
	banner_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	banner_label.position = Vector2(-400, -60)
	banner_label.custom_minimum_size = Vector2(800, 120)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner_label.add_theme_font_size_override("font_size", 72)
	_outline(banner_label, 10)
	banner_label.visible = false
	root.add_child(banner_label)
	# GTA-style guidance: the mission title when it starts, each new objective
	# in large type across the lower third, and a countdown for timed objectives.
	title_label = Label.new()
	title_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title_label.position = Vector2(-500, 150)
	title_label.custom_minimum_size = Vector2(1000, 90)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 54)
	title_label.add_theme_color_override("font_color", Color("f2c14e"))
	_outline(title_label, 10)
	title_label.visible = false
	root.add_child(title_label)
	objective_flash = Label.new()
	objective_flash.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	objective_flash.position = Vector2(-560, -250)
	objective_flash.custom_minimum_size = Vector2(1120, 60)
	objective_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_flash.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_flash.add_theme_font_size_override("font_size", 30)
	objective_flash.add_theme_color_override("font_color", Color("fff6d8"))
	_outline(objective_flash, 8)
	objective_flash.visible = false
	root.add_child(objective_flash)
	timer_label = Label.new()
	timer_label.position = Vector2(32, 180)
	timer_label.add_theme_font_size_override("font_size", 30)
	_outline(timer_label, 7)
	timer_label.visible = false
	root.add_child(timer_label)
	var prompt_back := ColorRect.new()
	prompt_back.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_back.position = Vector2(-290, -87)
	prompt_back.size = Vector2(580, 42)
	prompt_back.color = Color(0.08, 0.17, 0.20, 0.75)
	root.add_child(prompt_back)
	prompt_label = Label.new()
	prompt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.position = Vector2(-280, -85)
	prompt_label.custom_minimum_size = Vector2(560, 45)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 19)
	root.add_child(prompt_label)
	dialogue_label = Label.new()
	dialogue_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	dialogue_label.position = Vector2(-440, -155)
	dialogue_label.custom_minimum_size = Vector2(880, 48)
	dialogue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialogue_label.add_theme_font_size_override("font_size", 19)
	root.add_child(dialogue_label)
	world_map = WorldMapScript.new()
	world_map.name = "WorldMap"
	root.add_child(world_map)
	pause_overlay = ColorRect.new()
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.color = Color(0.04, 0.10, 0.13, 0.75)
	pause_overlay.visible = false
	root.add_child(pause_overlay)
	pause_label = Label.new()
	pause_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_label.position = Vector2(-300, -150)
	pause_label.custom_minimum_size = Vector2(600, 300)
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.add_theme_font_size_override("font_size", 28)
	pause_label.text = "PAUSA"
	pause_overlay.add_child(pause_label)
	pause_missions = Label.new()
	pause_missions.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_missions.position = Vector2(-300, 170)
	pause_missions.custom_minimum_size = Vector2(600, 200)
	pause_missions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_missions.add_theme_font_size_override("font_size", 19)
	pause_missions.add_theme_color_override("font_color", Color("f2e3b3"))
	pause_overlay.add_child(pause_missions)


func _outline(label: Label, size: int = 5) -> void:
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", size)


func show_banner(text: String, color: Color) -> void:
	banner_label.text = text
	banner_label.add_theme_color_override("font_color", color)
	banner_label.visible = true
	banner_timer = 3.0


func show_money_change(amount: int) -> void:
	money_delta_label.text = ("+%d €" if amount >= 0 else "%d €") % amount
	money_delta_label.add_theme_color_override("font_color", Color("9fe39a") if amount >= 0 else Color("e0645a"))
	money_delta_timer = 3.0


func set_game(value: PlayerController, mission_value: MissionController, wanted_value: WantedSystem) -> void:
	player = value
	mission = mission_value
	wanted = wanted_value
	minimap.player = player
	minimap.mission = mission
	minimap.wanted = wanted
	mission.objective_changed.connect(_on_objective_changed)
	mission.mission_started.connect(_on_mission_started)


func _on_objective_changed(text: String, _marker: Vector3) -> void:
	if text == "":
		return
	objective_flash.text = text
	objective_flash.visible = true
	objective_flash_timer = 5.0


func _on_mission_started(title: String) -> void:
	title_label.text = title.to_upper()
	title_label.visible = true
	title_timer = 3.5


func update_settings(quality: int, volume: int) -> void:
	var quality_text: String = ["Baja", "Media", "Alta"][quality]
	var volume_text: String = ["40 %", "70 %", "100 %"][volume]
	pause_label.text = "PAUSA\nEscape continuar · M mapa · R reiniciar partida\nF5 guardar · F9 cargar\nF3 gráficos: %s · F4 volumen: %s\nF2 rendimiento · F6 informe · F11 pantalla completa\n\nMap data © OpenStreetMap contributors · ODbL\nModelos Quaternius · Texturas ambientCG y Poly Haven (CC0)" % [quality_text, volume_text]


func _process(delta: float) -> void:
	pause_overlay.visible = get_tree().paused and not world_map.visible
	if pause_overlay.visible and mission != null:
		pause_missions.text = _mission_summary()
	if player == null:
		return
	mission_label.text = "MISIÓN · " + mission.objective_label()
	var phase_text: String = {"clear": "sin búsqueda", "responding": "en camino", "pursuit": "persecución", "search": "buscando"}.get(wanted.phase, wanted.phase)
	wanted_label.text = "POLICÍA · %s" % phase_text
	var blink := wanted.phase == "search" and int(Time.get_ticks_msec() / 400) % 2 == 0
	stars_label.text = "★".repeat(wanted.level) + "☆".repeat(5 - wanted.level)
	stars_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.35) if blink else Color("f2d36b"))
	var ratio := clampf(player.health / PlayerController.MAX_HEALTH, 0.0, 1.0)
	health_fill.size.x = 182.0 * ratio
	health_fill.color = Color("6fbf73") if ratio > 0.35 else Color("d9534a")
	var main := get_parent()
	if main != null and "money" in main:
		money_label.text = "%d €" % int(main.money)
	banner_timer -= delta
	banner_label.visible = banner_timer > 0.0
	title_timer -= delta
	title_label.visible = title_timer > 0.0
	objective_flash_timer -= delta
	objective_flash.visible = objective_flash_timer > 0.0 and not banner_label.visible
	_update_mission_status()
	_update_weapon()
	money_delta_timer -= delta
	money_delta_label.visible = money_delta_timer > 0.0
	if wanted.arrest_progress() > 0.0:
		wanted_label.text += "  ·  ¡DETENCIÓN %d %%!" % int(wanted.arrest_progress() * 100.0)
	var street := road_network.road_name_at(player.global_position) if road_network != null else ""
	var workshop: WorkshopInterior = main.world.workshop if main != null and "world" in main else null
	var in_workshop := workshop != null and player.global_position.distance_to(workshop.inside_entry) < 30.0
	var active_venue: VenueInterior
	if main != null and "world" in main:
		for venue in main.world.venues.values():
			if (venue as VenueInterior).contains_player(player.global_position):
				active_venue = venue
				break
	minimap.visible = not in_workshop and active_venue == null
	if in_workshop:
		street = "Taller Poniente"
	elif active_venue != null:
		street = _venue_display_name(active_venue.kind)
	bank_label.visible = active_venue != null and active_venue.kind == "bank"
	if bank_label.visible:
		bank_label.text = "Saldo bancario: %d €" % int(main.bank_balance)
	var movement_label := "A pie"
	if player.driving_vehicle != null:
		movement_label = "En coche"
	elif player.swimming:
		movement_label = "Buceando" if player.diving else "Nadando"
	info_label.text = "BRISA DE PONIENTE\n%s · %s" % [street if street != "" else "Paseo del Altillo", movement_label]
	dialogue_label.text = mission.dialogue
	if player.driving_vehicle != null:
		prompt_label.text = "WASD conducir · Espacio freno de mano · E salir  |  %d km/h" % int(absf(player.driving_vehicle.speed) * 3.6)
	elif workshop != null and in_workshop and player.global_position.distance_to(workshop.service_point) < 2.8:
		prompt_label.text = "E · Reparar coche aparcado (75 €)"
	elif workshop != null and in_workshop and player.global_position.distance_to(workshop.inside_entry) < 2.8:
		prompt_label.text = "E · Salir del Taller Poniente"
	elif workshop != null and player.global_position.distance_to(workshop.exterior_entry) < 3.0:
		prompt_label.text = "E · Entrar en Taller Poniente"
	elif active_venue != null and player.global_position.distance_to(active_venue.service_point) < 2.7:
		match active_venue.kind:
			"bank":
				prompt_label.text = "E · Ingresar 100 €"
			"jewellery":
				prompt_label.text = "E · Vitrina vacía" if main.jewellery_robbed else "E · Robar vitrina"
			"supermarket":
				prompt_label.text = "E · Comprar comida (15 €)"
			"mall":
				prompt_label.text = "E · Comprar comida (15 €)"
			"cafe":
				prompt_label.text = "E · Café y tostada (8 €)"
			"church":
				prompt_label.text = "E · Descansar"
			_:
				prompt_label.text = "E · Pedir menú (35 €)"
	elif active_venue != null and active_venue.kind == "bank" and player.global_position.distance_to(active_venue.secondary_service_point) < 2.7:
		prompt_label.text = "E · Retirar 100 €"
	elif active_venue != null and player.global_position.distance_to(active_venue.inside_entry) < 2.7:
		prompt_label.text = "E · Salir del local"
	elif _nearby_venue() != null:
		prompt_label.text = "E · Entrar en " + _venue_display_name(_nearby_venue().kind)
	elif _nearby_beach_bar() != null:
		prompt_label.text = "E · Pedir menú en " + _nearby_beach_bar().bar_name + " (35 €)"
	elif player.swimming:
		prompt_label.text = "WASD nadar · C bucear · Espacio subir  |  Aire %.0f s" % player.breath
	elif player.nearby_contact() != null:
		var contact := player.nearby_contact()
		var offer := mission.offer_of(str(contact.name))
		prompt_label.text = "E · Hablar con " + contact.display_name
		if offer != "" and (offer != mission.mission_id or mission.stage == 0):
			prompt_label.text += "  ·  Misión: " + str(mission._titles.get(offer, offer))
	elif player.nearby_vehicle() != null:
		prompt_label.text = "E · Entrar en el coche"
	else:
		var weapons: WeaponScript = main.weapons if main != null and "weapons" in main else null
		if weapons != null and weapons.is_gun():
			prompt_label.text = "Clic dcho. apuntar · Clic disparar · R recargar · 1-4 / rueda: armas"
		elif weapons != null and weapons.current == "bat":
			prompt_label.text = "Clic / F golpear con el bate · 1-4 / rueda: armas · M mapa"
		else:
			prompt_label.text = "WASD caminar · Shift correr · Espacio saltar · F puñetazo · M mapa"


func _update_weapon() -> void:
	var main := get_parent()
	var weapons: WeaponScript = main.weapons if main != null and "weapons" in main else null
	if weapons == null:
		weapon_label.visible = false
		crosshair.visible = false
		return
	weapon_label.visible = player.driving_vehicle == null
	var text := weapons.display_name().to_upper()
	if weapons.is_gun():
		text += "   " + weapons.ammo_text()
		if weapons.reload_timer > 0.0:
			text += "  · recargando"
	weapon_label.text = text
	crosshair.visible = weapons.is_gun() and player.driving_vehicle == null and not player.dead
	crosshair.add_theme_color_override("font_color", Color("ffffff") if weapons.aiming else Color(1, 1, 1, 0.45))


func _mission_summary() -> String:
	var lines: Array[String] = ["MISIONES"]
	for entry in mission.catalog:
		var id := str(entry["id"])
		var title := str(mission._titles.get(id, id))
		if mission.completed_missions.has(id):
			lines.append("✔ " + title)
		elif id == mission.mission_id and not mission.completed and mission.stage > 0:
			lines.append("▶ %s — %s" % [title, mission.objective_label()])
		elif mission.is_available(id):
			lines.append("● %s — habla con %s (%s)" % [title, str(entry.get("contact", "")), str(entry.get("blip", ""))])
	return "\n".join(lines)


## Countdown for timed objectives and the state of a chased vehicle.
func _update_mission_status() -> void:
	var parts: Array[String] = []
	var urgent := false
	if mission.objective_time_left > 0.0:
		var seconds := int(ceil(mission.objective_time_left))
		parts.append("TIEMPO %d:%02d" % [seconds / 60, seconds % 60])
		urgent = seconds <= 15
	if not mission.completed and not mission.objectives.is_empty():
		var objective: Dictionary = mission.objectives[mission.stage]
		if str(objective.get("type", "")) == "destroy_vehicle":
			var target := mission.spawned.get(str(objective.get("target_spawn", ""))) as DriveableVehicle
			if target != null and is_instance_valid(target):
				var floor_health := float(objective.get("health_below", 0.0))
				var left := clampf((target.health - floor_health) / (DriveableVehicle.MAX_HEALTH - floor_health), 0.0, 1.0)
				parts.append("OBJETIVO %s" % ("■".repeat(int(ceil(left * 10.0))) + "□".repeat(10 - int(ceil(left * 10.0)))))
		elif str(objective.get("type", "")) == "beat_up":
			var remaining := 0
			for id in objective.get("targets", []):
				var person := mission.spawned.get(str(id)) as Pedestrian
				if person != null and is_instance_valid(person) and not person.defeated:
					remaining += 1
			parts.append("QUEDAN %d" % remaining)
	timer_label.visible = not parts.is_empty()
	timer_label.text = "   ".join(parts)
	timer_label.add_theme_color_override("font_color", Color("e0645a") if urgent and int(Time.get_ticks_msec() / 300) % 2 == 0 else Color("fff1c1"))


func _nearby_venue() -> VenueInterior:
	for node in get_tree().get_nodes_in_group("interiors"):
		if node is VenueInterior and player.global_position.distance_to((node as VenueInterior).exterior_entry) < 3.0:
			return node as VenueInterior
	return null


func _nearby_beach_bar() -> BeachBarService:
	var main := get_parent()
	if main == null or not ("world" in main):
		return null
	for bar in main.world.beach_bars:
		if player.global_position.distance_to(bar.global_position) < 2.6:
			return bar
	return null


func _venue_display_name(kind: String) -> String:
	match kind:
		"supermarket":
			return "Mercado Azul"
		"restaurant":
			return "La Brisa · Restaurante"
		"bank":
			return "Caja Poniente"
		"jewellery":
			return "Joyería Faro"
		"church":
			return "Iglesia de la Encarnación"
		"mall":
			return "Galería Costa Tropical"
	return str(VenueInterior.SPECS.get(kind, {}).get("sign", kind))
