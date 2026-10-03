extends CanvasLayer

## The player's phone (↑ to take it out). ↑/↓ move, Enter selects, Backspace
## goes back or puts it away. You can keep walking or driving while it is out.
##  · Contactos: call whoever has work for you (sets a GPS waypoint to them) or
##    the Taller Poniente.
##  · Sargento Molina: a bent officer who makes up to three stars go away for
##    600 € a star (the town's corruption is the story's theme).
##  · Guardar partida: quick save, only with no stars and between mission steps.
##  · Estadísticas: progress (missions, amphorae, jumps, street events, money).
##  · Mensajes: texts left by contacts whose call you missed; reading one marks
##    the contact on the GPS.
## Incoming calls: when a mission becomes available that was not on offer before
## (never for the offers open at the start or after loading), the phone rings for
## RING_SECONDS once you are free (no mission step under way, no stars). ↑ answers:
## the contact explains in two or three lines and their position goes on the GPS.
## A missed call becomes a text in Mensajes. Saved as "phone" in the save file.

const BRIBE_PER_STAR := 600
const BRIBE_MAX_STARS := 3
const AudioUtil = preload("res://scripts/audio_util.gd")
const RING_SECONDS := 8.0
const POLL_SECONDS := 0.5
var main: Node
var player: PlayerController
var open := false
var screen := "home"  # home | contacts | messages | stats
var items: Array = []  # {label, action, data}
var cursor := 0
var root: PanelContainer
var header: Label
var list: VBoxContainer
var footer: Label
var message := ""
var message_timer := 0.0
var announced := {}  # mission id -> true: offers the player already knows about
var pending: Array[String] = []  # new offers waiting for a moment to ring
var ring_offer := {}  # the offer whose call is ringing now ({} when quiet)
var ring_timer := 0.0
var ring_delay := 4.0  # seconds between an offer appearing and the call
var messages: Array = []  # {id, contact, from, title, where, text, read}
var ring_audio: AudioStreamPlayer
var _poll := 0.0
var _wait := 0.0
var _primed := false


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
	ring_audio = AudioStreamPlayer.new()
	ring_audio.name = "Ringtone"
	ring_audio.bus = "UI"
	ring_audio.volume_db = -4.0
	ring_audio.stream = AudioUtil.stream("res://assets/audio/phone_ring.wav")
	add_child(ring_audio)


func _input(event: InputEvent) -> void:
	if player == null or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if is_ringing() and event.is_action_pressed("phone") and not get_tree().paused:
		answer()
		get_viewport().set_input_as_handled()
		return
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
		"messages":
			_messages()
		"read":
			read_message(int(item["data"]))
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
		{"label": "Mensajes" + ((" (%d nuevo)" if unread_count() == 1 else " (%d nuevos)") % unread_count() if unread_count() > 0 else ""), "action": "messages", "data": null},
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
	if main.get("miradores") != null:
		lines.append("Miradores: %d/%d" % [(main.miradores.get("found") as Dictionary).size(), (main.miradores.get("spots") as Array).size()])
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
	_update_calls(delta)
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
	header.text = "%s   %s" % [clock, {"home": "Brisa Móvil", "contacts": "Contactos", "messages": "Mensajes", "stats": "Estadísticas"}.get(screen, "")]
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


# --- Incoming calls and texts ----------------------------------------------------

func is_ringing() -> bool:
	return not ring_offer.is_empty()


func unread_count() -> int:
	var count := 0
	for m in messages:
		if not bool(m.get("read", false)):
			count += 1
	return count


func _offers() -> Array:
	var mission: Node = main.get("mission") if main != null else null
	return mission.call("offers") if mission != null else []


## Watch the mission offers: anything new is queued and rings when the player is
## free. The first look (game start, after loading) only records what is there.
func _update_calls(delta: float) -> void:
	if main == null or player == null or get_tree().paused:
		return
	_wait -= delta
	if is_ringing():
		ring_timer -= delta
		if ring_timer <= 0.0:
			_missed()
		elif not ring_audio.playing and DisplayServer.get_name() != "headless":
			ring_audio.play()
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL_SECONDS
	var current := _offers()
	if not _primed:
		_primed = true
		for offer in current:
			announced[str(offer["id"])] = true
		return
	for offer in current:
		var id := str(offer["id"])
		if not announced.has(id):
			announced[id] = true
			pending.append(id)
			_wait = ring_delay
	if pending.is_empty() or _wait > 0.0 or not can_ring():
		return
	while not pending.is_empty():
		var id: String = pending.pop_front()
		for offer in current:
			if str(offer["id"]) == id:
				_ring(offer)
				return


## Calls wait while a mission step is under way, with stars, with the phone
## out, on the pause screen or during a viewpoint panorama.
func can_ring() -> bool:
	if open or player.dead or get_tree().paused:
		return false
	var wanted: Node = main.get("wanted")
	if wanted != null and int(wanted.get("level")) > 0:
		return false
	var mission: Node = main.get("mission")
	if mission != null and bool(mission.call("mission_busy")):
		return false
	var miradores: Node = main.get("miradores")
	if miradores != null and bool(miradores.get("cinematic")):
		return false
	return true


func _display(contact_name: String) -> String:
	var mission: Node = main.get("mission")
	var spec: Dictionary = mission.get("contact_specs").get(contact_name, {}) if mission != null else {}
	return str(spec.get("display", contact_name)).get_slice(" · ", 0)


func _ring(offer: Dictionary) -> void:
	ring_offer = offer
	ring_timer = RING_SECONDS
	if DisplayServer.get_name() != "headless":
		ring_audio.play()
	_notify("%sLlamada de %s — ↑ para contestar" % [_emoji("📱"), _display(str(offer["name"]))], RING_SECONDS, true)
	var recorder: Node = main.get("playtest_log")
	if recorder != null:
		recorder.call("record", "phone_ring", {"id": str(offer["id"])})


## ↑ while it rings: the contact explains the job and their position goes on the GPS.
func answer() -> void:
	if not is_ringing():
		return
	var offer := ring_offer
	_stop_ring()
	var who := _display(str(offer["name"]))
	var mission: Node = main.get("mission")
	var where := str(mission.call("_where", str(offer["name"]))) if mission != null else ""
	var lines := [
		"%s: ¡Eh, soy %s! Escucha, tengo algo para ti: «%s»." % [who, who, str(offer["title"])],
		"%s: Por teléfono no, que nunca se sabe quién escucha. Ven a verme %s." % [who, _place(who, where)],
		"%s: Te mando la ubicación al GPS. No tardes." % who,
	]
	if mission != null:
		mission.call("_show_lines", lines)
	_waypoint_to(str(offer["name"]), offer.get("position", Vector3.INF))
	_notify("Llamada de %s · ruta marcada en el GPS" % who, 3.0)


## "Paco en el Chiringuito Arenas" → "en el Chiringuito Arenas" (the caller speaks).
func _place(who: String, where: String) -> String:
	if where.begins_with(who + " "):
		return where.substr(who.length() + 1)
	if not where.contains(" "):  # no "where" in the index: just the contact's name
		return "donde siempre"
	return "aquí: " + where


func _missed() -> void:
	var offer := ring_offer
	_stop_ring()
	var who := _display(str(offer["name"]))
	var mission: Node = main.get("mission")
	var where := str(mission.call("_where", str(offer["name"]))) if mission != null else ""
	var p: Vector3 = offer.get("position", Vector3.INF)
	messages.append({
		"id": str(offer["id"]), "contact": str(offer["name"]), "from": who, "title": str(offer["title"]), "where": where,
		"text": "%s: Te he llamado y no lo coges. Tengo un trabajo para ti, «%s». Estoy %s." % [who, str(offer["title"]), _place(who, where)],
		"position": [p.x, p.y, p.z] if p != Vector3.INF else [], "read": false,
	})
	_notify("%sLlamada perdida de %s · nuevo mensaje (↑ Mensajes)" % [_emoji("✉"), who], 5.0)
	if open and screen == "home":
		_home()


func _stop_ring() -> void:
	ring_offer = {}
	ring_timer = 0.0
	ring_audio.stop()
	var hud: Node = main.get("hud")
	if hud != null and hud.has_method("hide_notification"):
		hud.call("hide_notification")


func _messages() -> void:
	screen = "messages"
	items = []
	for i in range(messages.size() - 1, -1, -1):
		var m: Dictionary = messages[i]
		items.append({"label": "%s%s · %s" % ["● " if not bool(m.get("read", false)) else "", str(m["from"]), str(m["title"])], "action": "read", "data": i})
	if items.is_empty():
		items.append({"label": "No tienes mensajes.", "action": "none", "data": null})
	cursor = 0
	_render()


## Show a text and mark its sender on the GPS.
func read_message(index: int) -> void:
	if index < 0 or index >= messages.size():
		return
	var m: Dictionary = messages[index]
	m["read"] = true
	var mission: Node = main.get("mission")
	if mission != null:
		mission.call("_show_dialogue", str(m["text"]))
	var p: Array = m.get("position", [])
	_waypoint_to(str(m["contact"]), Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() == 3 else Vector3.INF)
	if screen == "messages":
		var keep := cursor
		_messages()
		cursor = mini(keep, items.size() - 1)
		_render()
	_flash("Mensaje leído · ruta marcada")


func _waypoint_to(contact_name: String, fallback: Vector3) -> void:
	var at := fallback
	var world: Node = main.get("world")
	var person := world.get_node_or_null(contact_name) as Node3D if world != null else null
	if person != null:
		at = person.global_position
	var hud: Node = main.get("hud")
	if at != Vector3.INF and hud != null and hud.get("minimap") != null:
		hud.minimap.set_waypoint(at)


func _notify(text: String, seconds: float, ringing: bool = false) -> void:
	var hud: Node = main.get("hud")
	if hud != null and hud.has_method("show_notification"):
		hud.call("show_notification", text, seconds, ringing)


## The emoji and a space when the UI font can draw it (the HUD also draws its own handset).
func _emoji(glyph: String) -> String:
	return glyph + " " if ThemeDB.fallback_font != null and ThemeDB.fallback_font.has_char(glyph.unicode_at(0)) else ""


func to_save() -> Dictionary:
	return {"announced": announced.keys(), "messages": messages.duplicate(true)}


## Loading restores the texts; the offers open in the loaded game count as known.
func from_save(value: Variant) -> void:
	if is_ringing():
		_stop_ring()
	pending.clear()
	announced.clear()
	messages.clear()
	if value is Dictionary:
		for id in (value as Dictionary).get("announced", []):
			announced[str(id)] = true
		for m in (value as Dictionary).get("messages", []):
			if m is Dictionary and (m as Dictionary).has("contact"):
				messages.append(m)
	_primed = false
	_poll = 0.0
