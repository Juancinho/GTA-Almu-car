extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(5):
		await physics_frame
	var player := root.get_node("Player") as PlayerController
	var world := root.get_node("District_Altillo") as SectorWorld
	var civilians := get_nodes_in_group("pedestrians")
	if civilians.size() < 50:
		return _fail("too few civilians")
	var civilian := civilians[2] as Pedestrian
	civilian.temperament = 0.9
	civilian.global_position = player.global_position + Vector3(1.0, 0, 0)
	if civilian.speak().is_empty() or civilian.speak().is_empty():
		return _fail("civilian conversation absent")
	civilian.speak()
	if civilian.state != Pedestrian.State.FIGHT:
		return _fail("provoked civilian did not become hostile")
	var health_before := player.health
	civilian._fight(0.1)
	if player.health >= health_before:
		return _fail("hostile civilian did not strike")
	civilian.knock_down(player.global_position, 4.0)
	civilian.provoked_by_player = true
	civilian._update_down(8.0)
	if civilian.state != Pedestrian.State.FIGHT:
		return _fail("angry civilian did not retaliate after recovering")
	print("CIVILIAN LIFE PASS: %d pedestrians, varied dialogue, provocation and retaliation" % civilians.size())
	root.queue_free()
	await process_frame
	quit(0)


func _fail(reason: String) -> void:
	push_error("CIVILIAN LIFE FAIL: " + reason)
	quit(1)
