extends SceneTree

## Incoming calls: the offers open at the start never ring; a mission that
## becomes available later rings (HUD notice), ↑ answers with the contact's lines
## and a GPS waypoint to them; an unanswered call leaves a text in Mensajes that
## sets the waypoint when read; nothing rings with stars (it waits); texts and
## known offers survive save/load without ringing again.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(8):
		await physics_frame
	var phone: Node = root.get("phone")
	var hud: Node = root.get("hud")
	var mission := root.get_node("Mission") as MissionController
	var wanted := root.get_node("WantedSystem") as WantedSystem
	var world: Node = root.get("world")
	await _seconds(1.5)
	if bool(phone.call("is_ringing")) or not (phone.get("pending") as Array).is_empty():
		return _fail("the phone rang for the offers open at the start")
	phone.set("ring_delay", 0.3)
	# 1. A new offer rings; ↑ answers.
	mission.completed_missions["el_recado"] = true
	if not await _wait_ring(phone, 3.0):
		return _fail("no call after el_recado was completed")
	var offer: Dictionary = phone.get("ring_offer")
	if str(offer["id"]) != "proteccion":
		return _fail("rang for %s, expected proteccion" % offer["id"])
	var notice := str(hud.notice_label.text)
	if not hud.notice_panel.visible or not notice.contains("Llamada de Paco") or not notice.contains("↑ para contestar"):
		return _fail("ring notice: %s" % notice)
	hud.minimap.set_waypoint(Vector3.INF)
	_key(KEY_UP)
	await _seconds(0.2)
	if bool(phone.call("is_ringing")) or bool(phone.get("open")):
		return _fail("↑ did not answer (or opened the phone)")
	var line := mission.dialogue
	if not line.begins_with("Paco") or not line.contains("Protección") and not line.contains(str(offer["title"])) or mission.dialogue_queue.size() < 1:
		return _fail("call dialogue: %s (+%d queued)" % [line, mission.dialogue_queue.size()])
	var paco := world.get_node("Paco") as Node3D
	var waypoint: Vector3 = hud.minimap.get("waypoint")
	if waypoint == Vector3.INF or Vector2(waypoint.x - paco.global_position.x, waypoint.z - paco.global_position.z).length() > 1.0:
		return _fail("answering set waypoint %s, Paco at %s" % [waypoint, paco.global_position])
	var answered := line
	# 2. Ignored call → text → reading it sets the waypoint.
	mission.completed_missions["proteccion"] = true
	if not await _wait_ring(phone, 3.0):
		return _fail("no call after proteccion")
	var second: Dictionary = phone.get("ring_offer")
	phone.set("ring_timer", 0.2)  # let it ring out
	await _seconds(0.6)
	if bool(phone.call("is_ringing")) and str((phone.get("ring_offer") as Dictionary).get("id", "")) == str(second["id"]):
		return _fail("call did not ring out")
	var messages: Array = phone.get("messages")
	if messages.size() != 1 or bool(messages[0]["read"]) or str(messages[0]["id"]) != str(second["id"]):
		return _fail("missed call left no text: %s" % str(messages))
	if not str(hud.notice_label.text).contains("Llamada perdida"):
		return _fail("missed-call notice: %s" % hud.notice_label.text)
	var player := root.get_node("Player") as PlayerController
	player.global_position = root.get("HOSPITAL_RESPAWN")  # far from Alba: the GPS does not count as arrived
	await _seconds(0.2)
	hud.minimap.set_waypoint(Vector3.INF)
	mission._show_dialogue("")
	_key(KEY_UP)
	await _seconds(0.1)
	if not bool(phone.get("open")) or not str((phone.get("items") as Array)[1]["label"]).begins_with("Mensajes (1"):
		return _fail("home has no unread Mensajes entry: %s" % str(phone.get("items")))
	phone.set("cursor", 1)
	_key(KEY_ENTER)
	await _seconds(0.1)
	if str(phone.get("screen")) != "messages":
		return _fail("Mensajes screen did not open: screen %s cursor %s items %s" % [phone.get("screen"), phone.get("cursor"), str(phone.get("items"))])
	_key(KEY_ENTER)
	await _seconds(0.1)
	var alba := world.get_node(str(messages[0]["contact"])) as Node3D
	waypoint = hud.minimap.get("waypoint")
	if not bool(messages[0]["read"]) or waypoint == Vector3.INF or Vector2(waypoint.x - alba.global_position.x, waypoint.z - alba.global_position.z).length() > 1.0:
		return _fail("reading the text: read=%s waypoint %s" % [messages[0]["read"], waypoint])
	if not mission.dialogue.contains(str(messages[0]["title"])):
		return _fail("text not shown: " + mission.dialogue)
	_key(KEY_BACKSPACE)
	_key(KEY_BACKSPACE)
	await _seconds(0.1)
	# 3. No ring with stars: it waits and rings once they are gone.
	wanted.raise_to(1, root.get_node("Player").global_position)
	mission.completed_missions["la_cuota"] = true
	await _seconds(1.5)
	if bool(phone.call("is_ringing")):
		return _fail("rang with a star")
	if (phone.get("pending") as Array).is_empty():
		return _fail("new offer not queued while wanted")
	wanted.clear_wanted()
	if not await _wait_ring(phone, 3.0):
		return _fail("queued call never rang after the stars went")
	var third := str((phone.get("ring_offer") as Dictionary)["id"])
	phone.call("answer")
	# 4. Save/load: texts and known offers kept, nothing rings again.
	root.set("save_path", "user://test_phone_calls_save.json")
	root.call("_save_game")
	phone.call("from_save", {})
	root.call("_load_game")
	if (phone.get("messages") as Array).size() != 1 or not (phone.get("announced") as Dictionary).has("proteccion"):
		return _fail("save/load lost the texts: %s" % str(phone.get("messages")))
	await _seconds(1.5)
	if bool(phone.call("is_ringing")):
		return _fail("loading made the phone ring")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_phone_calls_save.json"))
	print("PHONE CALLS PASS: no ring at start; new offer rings (\"%s\"), ↑ answers «%s» + waypoint to Paco; missed call → text → read → waypoint to %s; with a star it waits, then rings (%s); texts saved/loaded without re-ringing" % [notice, answered, messages[0]["contact"], third])
	root.queue_free()
	await process_frame
	quit(0)


func _wait_ring(phone: Node, seconds: float) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
		if bool(phone.call("is_ringing")):
			return true
	return false


func _seconds(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	get_root().push_input(event)
	var up := event.duplicate() as InputEventKey
	up.pressed = false
	get_root().push_input(up)


func _fail(reason: String) -> void:
	push_error("PHONE CALLS FAIL: " + reason)
	quit(1)
