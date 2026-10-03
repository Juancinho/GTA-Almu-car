extends CanvasLayer

## The player's phone (↑ to take it out). ↑/↓ move, Enter selects, Backspace
## goes back or puts it away. You can keep walking or driving while it is out.
##  · Contactos: call whoever has work for you (sets a GPS waypoint to them) or
##    the Taller Poniente.
##  · Sargento Molina: a bent officer who makes up to three stars go away for
##    600 € a star (the town's corruption is the story's theme).
##  · Guardar partida: quick save, only with no stars and between mission steps.
##  · Estadísticas: progress (missions, amphorae, jumps, street events, money).

const BRIBE_PER_STAR := 600
const BRIBE_MAX_STARS := 3
var main: Node
var player: PlayerController
var open := false
var screen := "home"  # home | contacts | stats
var items: Array = []  # {label, action, data}
var cursor := 0
var root: PanelContainer
var header: Label
var list: VBoxContainer
var footer: Label
var message := ""
var message_timer := 0.0


func configure(target_main: Node, target_player: PlayerController) -> void:
	main = target_main
	player = target_player
	layer = 11
	root = PanelContainer.new()
	root.anchor_left = 1.0
	root.anchor_right = 1.0
	root.anchor_top = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = -470.0
	root.offset_right = -226.0
	root.offset_top = -400.0
	root.offset_bottom = -90.0
	var shell := StyleBoxFlat.new()
	shell.bg_color = Color("101419")
	shell.border_color = Color("3a4250")
	shell.set_border_width_all(4)
	shell.set_corner_radius_all(22)
	shell.content_margin_left = 14
	shell.content_margin_right = 14
	shell.content_margin_top = 14
	shell.content_margin_bottom = 14
	root.add_theme_stylebox_override("panel", shell)
	root.visible = false
	add_child(root)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	root.add_child(column)
	header = Label.new()
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color("9fb3c8"))
	column.add_child(header)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(list)
	footer = Label.new()
	footer.text = "↑↓ elegir · Intro · Retroceso atrás"
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color("6c7a89"))
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(footer)


func _input(event: InputEvent) -> void:
	if player == null or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if not open:
		if event.is_action_pressed("phone") and not player.dead and not get_tree().paused:
			show_phone()
			get_viewport().set_input_as_handled()
		return
	match key:
		KEY_UP:
			move(-1)
		KEY_DOWN:
			move(1)
		KEY_ENTER, KEY_KP_ENTER:
			select()
		KEY_BACKSPACE:
			back()
		_:
			return
	get_viewport().set_input_as_handled()


func show_phone() -> void:
	open = true
	root.visible = true
	_home()


func hide_phone() -> void:
	open = false
	root.visible = false


func move(step: int) -> void:
	if items.is_empty():
		return
	cursor = posmod(cursor + step, items.size())
	_render()


func back() -> void:
	if screen == "home":
		hide_phone()
	else:
		_home()


func select() -> void:
	if items.is_empty():
		return
	var item: Dictionary = items[cursor]
	match str(item["action"]):
		"contacts":
			_contacts()
		"stats":
			_stats()
		"save":
			quick_save()
		"call":
			call_contact(item["data"])
		"close":
			hide_phone()


func _home() -> void:
	screen = "home"
	items = [
		{"label": "Contactos", "action": "contacts", "data": null},
		{"label": "Guardar partida", "action": "save", "data": null},
		{"label": "Estadísticas", "action": "stats", "data": null},
		{"label": "Guardar el móvil", "action": "close", "data": null},
	]
	cursor = 0
	_render()


func _contacts() -> void:
	screen = "contacts"
	items = []
	var mission: Node = main.get("mission")
	if mission != null:
		for offer in mission.call("offers"):
			items.append({"label": "%s · %s" % [str(mission.get("contact_specs").get(offer["name"], {}).get("display", offer["name"])), offer["title"]], "action": "call", "data": {"kind": "offer", "offer": offer}})
	items.append({"label": "Sargento Molina (%d € por estrella)" % BRIBE_PER_STAR, "action": "call", "data": {"kind": "bribe"}})
	items.append({"label": "Taller Poniente", "action": "call", "data": {"kind": "workshop"}})
	cursor = 0
	_render()


func _stats() -> void:
	screen = "stats"
	var mission: Node = main.get("mission")
	var lines := []
	lines.append("Misiones: %d" % (mission.get("completed_missions") as Dictionary).size() if mission != null else "Misiones: 0")
	if main.get("collectibles") != null:
		lines.append("Ánforas: %d/30" % (main.collectibles.get("found") as Dictionary).size())
	if main.get("stunt_jumps") != null:
		lines.append("Saltos únicos: %d/%d" % [(main.stunt_jumps.get("done") as Dictionary).size(), (main.stunt_jumps.get("ramps") as Array).size()])
	if main.get("street_events") != null:
		lines.append("Sucesos resueltos: %d" % int(main.street_events.get("done_count")))
	lines.append("Dinero: %d € · Banco: %d €" % [int(main.get("money")), int(main.get("bank_balance"))])
	items = []
	for line in lines:
		items.append({"label": line, "action": "none", "data": null})
	cursor = 0
	_render()


## Phone call: a contact with work tells you where to find them and a waypoint
## goes on the map; the workshop gets a waypoint too.
func call_contact(data: Dictionary) -> void:
	var mission: Node = main.get("mission")
	var hud: Node = main.get("hud")
	var at := Vector3.INF
	var line := ""
	if str(data["kind"]) == "bribe":
		bribe()
		return
	if str(data["kind"]) == "offer":
		var offer: Dictionary = data["offer"]
		at = offer["position"]
		var display := str(mission.get("contact_specs").get(offer["name"], {}).get("display", offer["name"]))
		line = "%s: Tengo un trabajo para ti, «%s». Te espero aquí: %s." % [display, offer["title"], str(mission.call("_where", offer["name"]))]
	else:
		var world: Node = main.get("world")
		if world != null and world.get("workshop") != null:
			at = world.workshop.exterior_entry
		line = "Mecánico: Taller Poniente, dime. ¿Pintura nueva? Ven cuando quieras, te marco la dirección."
	if at != Vector3.INF and hud != null and hud.get("minimap") != null:
		hud.minimap.set_waypoint(at)
	if mission != null:
		mission.call("_show_dialogue", line)
	_flash("Llamada terminada · ruta marcada")


## Pay the sergeant to lose the file: up to three stars, 600 € each.
func bribe() -> bool:
	var wanted: Node = main.get("wanted")
	var mission: Node = main.get("mission")
	var level := int(wanted.get("level")) if wanted != null else 0
	var line := ""
	var ok := false
	if level == 0:
		line = "Molina: ¿Para qué me llamas? Nadie te busca. No me hagas perder el tiempo."
	elif level > BRIBE_MAX_STARS:
		line = "Molina: ¿Con todo eso detrás? Ni por todo el dinero del casino. Apáñatelas."
	elif int(main.get("money")) < level * BRIBE_PER_STAR:
		line = "Molina: Esto son %d €. Vuelve cuando los tengas." % (level * BRIBE_PER_STAR)
	else:
		main.call("add_money", -level * BRIBE_PER_STAR)
		wanted.call("clear_wanted")
		line = "Molina: Hecho. Tu matrícula se ha traspapelado. Y esta llamada nunca ha existido."
		ok = true
	if mission != null:
		mission.call("_show_dialogue", line)
	_flash("Soborno pagado" if ok else "Llamada terminada")
	return ok


func quick_save() -> bool:
	var wanted: Node = main.get("wanted")
	var mission: Node = main.get("mission")
	if wanted != null and int(wanted.get("level")) > 0:
		_flash("No puedes guardar con la policía detrás")
		return false
	if mission != null and bool(mission.call("mission_busy")):
		_flash("Termina antes este paso de la misión")
		return false
	main.call("_save_game")
	_flash("Partida guardada")
	return true


func _flash(text: String) -> void:
	message = text
	message_timer = 3.0
	_render()


func _process(delta: float) -> void:
	if message_timer > 0.0:
		message_timer -= delta
		if message_timer <= 0.0:
			message = ""
			if open:
				_render()
	if open and player != null and player.dead:
		hide_phone()


func _render() -> void:
	if not open:
		return
	var clock := ""
	var day_night: Node = main.get("day_night")
	if day_night != null and day_night.has_method("clock_text"):
		clock = str(day_night.call("clock_text"))
	header.text = "%s   %s" % [clock, {"home": "Brisa Móvil", "contacts": "Contactos", "stats": "Estadísticas"}.get(screen, "")]
	for child in list.get_children():
		child.queue_free()
	for i in range(items.size()):
		var row := Label.new()
		row.text = str(items[i]["label"])
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size = Vector2(200, 0)
		row.add_theme_font_size_override("font_size", 15)
		var chosen := i == cursor and str(items[i]["action"]) != "none"
		row.add_theme_color_override("font_color", Color("101418") if chosen else Color("e8eef4"))
		if chosen:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("f2c14e")
			style.set_corner_radius_all(6)
			style.content_margin_left = 6
			style.content_margin_right = 6
			row.add_theme_stylebox_override("normal", style)
		list.add_child(row)
	footer.text = message if message != "" else "↑↓ elegir · Intro · Retroceso atrás"
