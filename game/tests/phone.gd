extends SceneTree

## Phone: ↑ takes it out, contacts list mission offers and the workshop, a call
## puts a waypoint on the map, quick save works only without stars, stats list
## progress, Backspace puts it away.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(8):
		await physics_frame
	var phone: Node = root.get("phone")
	var hud: Node = root.get("hud")
	var wanted := root.get_node("WantedSystem") as WantedSystem
	if phone == null:
		return _fail("no phone")
	_key(KEY_UP)
	await _frames(2)
	if not bool(phone.get("open")):
		return _fail("↑ did not take the phone out")
	# Contacts → first entry.
	phone.set("cursor", 0)
	_key(KEY_ENTER)
	await _frames(2)
	if str(phone.get("screen")) != "contacts":
		return _fail("contacts screen did not open")
	var items: Array = phone.get("items")
	if items.is_empty() or str(items[items.size() - 1]["label"]) != "Taller Poniente":
		return _fail("contacts missing the workshop")
	hud.minimap.set_waypoint(Vector3.INF)
	_key(KEY_UP)  # wraps to the last contact: the workshop, far from the start
	await _frames(2)
	_key(KEY_ENTER)
	await _frames(2)
	if (hud.minimap.get("waypoint") as Vector3) == Vector3.INF:
		return _fail("calling a contact set no waypoint")
	var first_call := str(items[0]["label"])
	_key(KEY_BACKSPACE)
	await _frames(2)
	if str(phone.get("screen")) != "home":
		return _fail("Backspace did not go back")
	# Quick save, refused with stars.
	root.set("save_path", "user://test_phone_save.json")
	if not bool(phone.call("quick_save")):
		return _fail("quick save refused in free roam")
	if not FileAccess.file_exists("user://test_phone_save.json"):
		return _fail("quick save wrote no file")
	wanted.raise_to(2, root.get_node("Player").global_position)
	if bool(phone.call("quick_save")):
		return _fail("quick save allowed with two stars")
	# Bribe: two stars cost 1,200 €; five stars are beyond the sergeant.
	root.set("money", 1500)
	if not bool(phone.call("bribe")) or wanted.level != 0 or int(root.get("money")) != 300:
		return _fail("bribe did not clear two stars for 1200 € (level %d, money %d)" % [wanted.level, int(root.get("money"))])
	wanted.raise_to(5, root.get_node("Player").global_position)
	root.set("money", 50000)
	if bool(phone.call("bribe")) or wanted.level != 5:
		return _fail("bribe accepted at five stars")
	wanted.clear_wanted()
	phone.call("_stats")
	var lines := (phone.get("items") as Array).map(func(item: Dictionary) -> String: return str(item["label"]))
	if not str(lines).contains("Ánforas") or not str(lines).contains("Dinero"):
		return _fail("stats " + str(lines))
	phone.call("_home")
	_key(KEY_BACKSPACE)
	await _frames(2)
	if bool(phone.get("open")):
		return _fail("Backspace did not put the phone away")
	print("PHONE PASS: ↑ opens, contacts (first: %s) call sets a waypoint, quick save only without stars, bribe clears 2 stars (not 5), stats %s, put away" % [first_call, str(lines)])
	root.queue_free()
	await process_frame
	quit(0)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	get_root().push_input(event)
	var up := event.duplicate() as InputEventKey
	up.pressed = false
	get_root().push_input(up)


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _fail(reason: String) -> void:
	push_error("PHONE FAIL: " + reason)
	quit(1)
