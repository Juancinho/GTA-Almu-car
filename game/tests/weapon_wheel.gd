extends SceneTree

## Weapon wheel: holding TAB slows time and lists owned weapons and throwables;
## pointing the mouse picks one and releasing equips it; a car closes it.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(8):
		await physics_frame
	var weapons: Node = root.get("weapons")
	var thrown: Node = root.get("throwables")
	var wheel: Node = root.get("weapon_wheel")
	if wheel == null:
		return _fail("no weapon wheel")
	weapons.call("give", "pistol", 30)
	weapons.call("give", "shotgun", 10)
	weapons.call("select", "fists")
	await _frames(15)  # weapon-switch cooldown
	thrown.call("add", "molotov", 2)
	_press(true)
	await _frames(2)
	if not bool(wheel.get("open")) or absf(Engine.time_scale - 0.3) > 0.01:
		return _fail("TAB did not open the wheel in slow motion")
	var entries: Array = wheel.get("entries")
	var ids := entries.map(func(e: Dictionary) -> String: return str(e["id"]))
	if not ("pistol" in ids and "shotgun" in ids and "molotov" in ids and "fists" in ids):
		return _fail("wheel entries " + str(ids))
	# Point at the shotgun's slot.
	var target := ids.find("shotgun")
	var angle := -PI * 0.5 + TAU * float(target) / float(ids.size())
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(cos(angle), sin(angle)) * 100.0
	get_root().push_input(motion)
	await _frames(2)
	if int(wheel.get("highlighted")) != target:
		return _fail("pointer highlighted %d, expected %d" % [int(wheel.get("highlighted")), target])
	_press(false)
	await _frames(15)
	if bool(wheel.get("open")) or absf(Engine.time_scale - 1.0) > 0.01:
		return _fail("release did not close the wheel / restore time")
	if str(weapons.get("current")) != "shotgun":
		return _fail("shotgun not equipped (" + str(weapons.get("current")) + ")")
	# Throwable choice.
	_press(true)
	await _frames(2)
	entries = wheel.get("entries")
	ids = entries.map(func(e: Dictionary) -> String: return str(e["id"]))
	wheel.call("choose", ids.find("molotov"))
	wheel.call("close_wheel", false)
	if str(thrown.get("selected")) != "molotov":
		return _fail("molotov not selected")
	print("WEAPON WHEEL PASS: TAB opens in slow motion with %d entries, mouse picks the shotgun, release equips + restores time, throwable selectable" % ids.size())
	root.queue_free()
	await process_frame
	quit(0)


func _press(down: bool) -> void:
	var event := InputEventAction.new()
	event.action = "weapon_wheel"
	event.pressed = down
	get_root().push_input(event)


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _fail(reason: String) -> void:
	push_error("WEAPON WHEEL FAIL: " + reason)
	quit(1)
