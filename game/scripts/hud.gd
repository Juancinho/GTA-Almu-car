class_name GameHud
extends CanvasLayer

var player: PlayerController
var mission: MissionController
var wanted: WantedSystem
var info_label: Label
var mission_label: Label
var wanted_label: Label
var dialogue_label: Label
var prompt_label: Label
var minimap: DistrictMinimap
var pause_overlay: ColorRect
var pause_label: Label


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
	pause_overlay = ColorRect.new()
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.color = Color(0.04, 0.10, 0.13, 0.75)
	pause_overlay.visible = false
	root.add_child(pause_overlay)
	pause_label = Label.new()
	pause_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_label.position = Vector2(-260, -125)
	pause_label.custom_minimum_size = Vector2(520, 250)
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.add_theme_font_size_override("font_size", 28)
	pause_label.text = "PAUSA"
	pause_overlay.add_child(pause_label)


func set_game(value: PlayerController, mission_value: MissionController, wanted_value: WantedSystem) -> void:
	player = value
	mission = mission_value
	wanted = wanted_value
	minimap.player = player
	minimap.mission = mission


func update_settings(quality: int, volume: int) -> void:
	var quality_text: String = ["Baja", "Media", "Alta"][quality]
	var volume_text: String = ["40 %", "70 %", "100 %"][volume]
	pause_label.text = "PAUSA\nEscape continuar · R reiniciar\nF5 guardar · F9 cargar\nF3 gráficos: %s · F4 volumen: %s\n\nMap data © OpenStreetMap contributors\nODbL · openstreetmap.org/copyright" % [quality_text, volume_text]


func _process(_delta: float) -> void:
	pause_overlay.visible = get_tree().paused
	if player == null:
		return
	mission_label.text = "MISIÓN · " + mission.objectives[mission.stage].get("text", "") if not mission.completed else "MISIÓN · El Recado completado"
	var phase_text: String = {"clear": "sin búsqueda", "responding": "en camino", "pursuit": "persecución", "search": "buscando"}.get(wanted.phase, wanted.phase)
	wanted_label.text = "ATENCIÓN POLICIAL · %d/5  %s" % [wanted.level, phase_text]
	dialogue_label.text = mission.dialogue
	if player.driving_vehicle != null:
		prompt_label.text = "WASD conducir · Espacio frenar · E salir  |  %d km/h" % int(absf(player.driving_vehicle.speed) * 3.6)
	elif player.nearby_contact() != null:
		prompt_label.text = "E · Hablar con " + player.nearby_contact().display_name
	elif player.nearby_vehicle() != null:
		prompt_label.text = "E · Entrar en el coche"
	else:
		prompt_label.text = "WASD caminar · Shift correr · Espacio saltar · Ratón cámara"
