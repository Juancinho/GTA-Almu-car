extends SceneTree

## Integration check for the Jaime Playa venue, its second mission and save/load.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		return _fail("main scene did not load")
	var root := scene.instantiate()
	get_root().add_child(root)
	for i in range(8):
		await physics_frame
	var world := root.get_node("District_Altillo") as SectorWorld
	var player := root.get_node("Player") as PlayerController
	var mission := root.get_node("Mission") as MissionController
	var marina := world.get_node_or_null("Marina") as Pedestrian
	var venue := world.get_node_or_null("JaimePlaya") as Node3D
	if marina == null or venue == null or venue.get_node_or_null("JaimePlayaSign") == null:
		return _fail("Jaime Playa venue or contact missing")
	if world.anchor("jaime_playa").distance_to(marina.global_position) > 12.0:
		return _fail("Marina is too far from the venue")
	if mission.mission_id != "el_recado" or mission.stage != 0:
		return _fail("main mission did not start correctly")
	mission.restore_stage(1)
	player.global_position = marina.global_position + Vector3(0.8, 0.3, 0)
	player._interact()
	if mission.mission_id != "jaime_playa" or mission.stage != 1:
		return _fail("talking to Marina did not start Jaime mission")
	root.set("save_path", "user://test_jaime_save.json")
	root.call("_save_game")
	mission.load_mission("el_recado")
	root.call("_load_game")
	if mission.mission_id != "jaime_playa" or mission.stage != 1 or mission.suspended_el_recado_stage != 1:
		return _fail("active Jaime mission did not survive save/load")
	player.global_position = world.anchor("jaime_equipment") + Vector3(0, 0.3, 0)
	for i in range(3):
		await process_frame
	if mission.stage != 2:
		return _fail("equipment pickup did not advance")
	var bar := world.anchor("jaime_playa")
	player.global_position = bar + Vector3(0, 0.3, 4.0)
	for i in range(3):
		await process_frame
	if mission.stage != 3:
		return _fail("returning to Jaime Playa did not advance")
	player.global_position = marina.global_position + Vector3(0.8, 0.3, 0)
	player._interact()
	if mission.mission_id != "el_recado" or mission.stage != 1 or mission.jaime_finished != true or int(root.get("money")) != 150:
		return _fail("mission completion, reward or El Recado resume failed")
	root.call("_save_game")
	mission.load_mission("jaime_playa")
	root.call("_load_game")
	if mission.mission_id != "el_recado" or mission.stage != 1 or not mission.jaime_finished:
		return _fail("Jaime mission did not survive save/load")
	player.global_position = marina.global_position + Vector3(0.8, 0.3, 0)
	player._interact()
	if mission.mission_id != "el_recado":
		return _fail("Jaime mission could be replayed for another reward")
	print("JAIME MISSION PASS: venue, contact, objectives, reward, save/load")
	root.queue_free()
	await process_frame
	quit(0)


func _fail(reason: String) -> void:
	push_error("JAIME MISSION FAIL: " + reason)
	quit(1)
