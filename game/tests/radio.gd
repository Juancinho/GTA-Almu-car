extends SceneTree

## Car radio: three stations with real streams, on when boarding a car, Q cycles
## (including off), off when leaving the car.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(8):
		await physics_frame
	var radio: Node = root.get("radio")
	var player := root.get_node("Player") as PlayerController
	var car := root.get_node("District_Altillo/FirstCar") as DriveableVehicle
	var stations: Array = radio.get("stations")
	if stations.size() != 3:
		return _fail("expected 3 stations")
	for s in stations:
		for t in s["tracks"]:
			if t["stream"] == null or float(t["length"]) < 30.0:
				return _fail("track missing or too short: %s" % t["file"])
	player.global_position = car.global_position + car.global_transform.basis.x * 2.0
	player._interact()
	await process_frame
	await process_frame
	if int(radio.get("playing_track")) < 0:
		return _fail("radio did not tune in when boarding")
	var press := InputEventAction.new()
	press.action = "radio_next"
	press.pressed = true
	var names := []
	for i in range(4):
		radio.call("_unhandled_input", press)
		names.append(radio.call("current_name"))
	if names != ["PONIENTE FM", "SEXI ROCK 98.4", "APAGADA", "RADIO COSTA TROPICAL"]:
		return _fail("station cycle wrong: %s" % str(names))
	player._interact()
	await process_frame
	await process_frame
	if int(radio.get("playing_track")) != -1:
		return _fail("radio kept playing after leaving the car")
	print("RADIO PASS: 3 stations x 2 original tracks, on when boarding, Q cycles %s, off on foot" % str(names))
	root.queue_free()
	await process_frame
	quit(0)


func _fail(reason: String) -> void:
	push_error("RADIO FAIL: " + reason)
	quit(1)
