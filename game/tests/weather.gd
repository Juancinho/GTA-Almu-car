extends SceneTree

## Weather: rain darkens the sky and dims the sun, rain falls around the camera,
## the asphalt gets dark and glossy, wet roads lengthen braking, it dries after
## the rain, and the weather is saved.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(8):
		await physics_frame
	var weather: Node = root.get("weather")
	var day_night: Node = root.get("day_night")
	var world := root.get_node("District_Altillo") as SectorWorld
	if weather == null:
		return _fail("no weather system")
	day_night.set("hours", 13.0)
	await _frames(3)
	var sun_clear := world.sun_light.light_energy
	var asphalt := world.mats.road_asphalt()
	var dry_roughness := asphalt.roughness
	if str(weather.get("state")) != "clear" or float(day_night.get("overcast")) > 0.01:
		return _fail("game should start clear")
	weather.call("set_weather", "rain", true)
	await _frames(3)
	if float(day_night.get("overcast")) < 0.99:
		return _fail("rain did not cover the sky")
	if world.sun_light.light_energy > sun_clear * 0.5:
		return _fail("sun not dimmed by clouds (%.2f vs %.2f)" % [world.sun_light.light_energy, sun_clear])
	if not (weather.get("rain") as CPUParticles3D).emitting:
		return _fail("no rain falling")
	if asphalt.roughness > dry_roughness - 0.3:
		return _fail("asphalt not wet (roughness %.2f)" % asphalt.roughness)
	if DriveableVehicle.wet_grip > 0.75:
		return _fail("wet roads keep full grip")
	root.set("save_path", "user://test_weather_save.json")
	root.call("_save_game")
	weather.call("set_weather", "clear", true)
	weather.set("wet", 0.0)
	root.call("_load_game")
	if str(weather.get("state")) != "rain":
		return _fail("weather not saved")
	weather.call("set_weather", "clear")
	for i in range(60):
		await physics_frame
	if (weather.get("rain") as CPUParticles3D).emitting:
		return _fail("still raining after clearing")
	if float(weather.get("wet")) < 0.5:
		return _fail("roads dried instantly")
	weather.call("set_weather", "clear", true)
	weather.set("wet", 0.0)
	await _frames(3)
	if DriveableVehicle.wet_grip < 0.99 or asphalt.roughness < dry_roughness - 0.01:
		return _fail("dry state not restored")
	# Storm: lightning strikes and flashes; bathers and most strollers go home.
	weather.call("set_weather", "storm", true)
	var peds_before := get_nodes_in_group("pedestrians").filter(func(p: Node) -> bool: return (p as Node3D).visible).size()
	var flashed := false
	for i in range(60 * 20):
		await physics_frame
		flashed = flashed or (weather.get("lightning") as DirectionalLight3D).visible
	if int(weather.get("strikes")) < 1 or not flashed:
		return _fail("no lightning in a storm (%d strikes)" % int(weather.get("strikes")))
	var sheltered := int(weather.call("shelter_count"))
	if sheltered < peds_before / 4:
		return _fail("pedestrians stayed out in the storm (%d of %d sheltered)" % [sheltered, peds_before])
	if float(weather.get("wind")) < 0.4:
		return _fail("storm without wind")
	weather.call("set_weather", "clear", true)
	weather.set("wet", 0.0)
	for i in range(60 * 3):
		await physics_frame
	if int(weather.call("shelter_count")) > sheltered / 2:
		return _fail("pedestrians did not come back after the rain (%d still away)" % int(weather.call("shelter_count")))
	print("WEATHER PASS: storm %d strikes, %d/%d pedestrians sheltered and back; rain covers the sky, sun %.2f -> dimmed, rain particles, wet asphalt + grip 0.7, saved, slow drying, dry restored" % [int(weather.get("strikes")), sheltered, peds_before, sun_clear])
	root.queue_free()
	await process_frame
	quit(0)


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _fail(reason: String) -> void:
	push_error("WEATHER FAIL: " + reason)
	quit(1)
