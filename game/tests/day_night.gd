extends SceneTree

## Day/night: sun path, night sky and ambient, window glow, street-lamp lights
## near the player, car head/tail lamps and the clock in the save.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(8):
		await physics_frame
	var cycle := root.get_node_or_null("DayNight")
	var world := root.get_node("District_Altillo") as SectorWorld
	var player := root.get_node("Player") as PlayerController
	if cycle == null:
		return _fail("no day/night cycle")
	cycle.set("paused_clock", true)
	cycle.set("hours", 14.0)
	cycle.call("apply")
	var noon_dir := -world.sun_light.global_transform.basis.z
	if float(cycle.get("night")) > 0.01 or world.sun_light.light_energy < 1.0 or noon_dir.y > -0.7 or noon_dir.z > 0.0:
		return _fail("midday sun should be high in the south (dir %s)" % str(noon_dir))
	cycle.set("hours", 8.0)
	cycle.call("apply")
	var morning := -world.sun_light.global_transform.basis.z
	if morning.x > -0.3:
		return _fail("morning light should come from the east (dir %s)" % str(morning))
	cycle.set("hours", 23.0)
	cycle.call("apply")
	var lamps: PackedVector3Array = world.get_meta("lamp_positions", PackedVector3Array())
	if lamps.is_empty():
		return _fail("lamp positions not exported")
	player.global_position = lamps[0] + Vector3(2, 0.4, 0)
	for i in range(70):
		await physics_frame
	var lit := 0
	for light in world.find_children("StreetLamp_*", "OmniLight3D", false, false):
		if (light as OmniLight3D).visible:
			lit += 1
	var glow: float = world.mats.facade_detail().get_shader_parameter("night_glow")
	if float(cycle.get("night")) < 0.9 or lit == 0 or glow < 1.0 or world.sun_light.shadow_enabled:
		return _fail("night not applied (night %.2f lamps %d glow %.2f)" % [float(cycle.get("night")), lit, glow])
	var car := world.get_node("FirstCar") as DriveableVehicle
	if car.lamps == null or not car.lamps.visible:
		return _fail("cars did not switch their lamps on at night")
	root.set("save_path", "user://test_daynight_save.json")
	root.call("_save_game")
	cycle.set("hours", 9.0)
	root.call("_load_game")
	if absf(float(cycle.get("hours")) - 23.0) > 0.05:
		return _fail("time of day not saved")
	print("DAY NIGHT PASS: east morning, south noon, night sky/lamps (%d lights), window glow, car lamps, saved clock" % lit)
	root.queue_free()
	await process_frame
	quit(0)


func _fail(reason: String) -> void:
	push_error("DAY NIGHT FAIL: " + reason)
	quit(1)
