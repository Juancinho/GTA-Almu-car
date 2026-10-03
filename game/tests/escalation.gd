extends SceneTree

## Wanted escalation: three stars put a roadblock (two patrol cars across the
## road with officers) ahead of the player; four stars bring the helicopter,
## which flies above the player, keeps the pursuit "seen" and leaves when the
## stars are cleared.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(8):
		await physics_frame
	var wanted := root.get_node("WantedSystem") as WantedSystem
	var player := root.get_node("Player") as PlayerController
	var car := root.get_node("District_Altillo/FirstCar") as DriveableVehicle
	player.global_position = car.global_position + car.global_transform.basis.x * 2.0
	player._interact()
	var escalation: Node = wanted.escalation
	if escalation == null:
		return _fail("no escalation node")
	wanted.raise_to(3, player.global_position)
	escalation.set("roadblock_timer", 0.0)
	Input.action_press("move_forward")
	for i in range(90):
		await physics_frame
	Input.action_release("move_forward")
	var blocks: Array = escalation.get("roadblocks")
	if blocks.is_empty():
		return _fail("no roadblock at three stars")
	var block: Dictionary = blocks[0]
	if (block["cars"] as Array).size() != 2 or (block["officers"] as Array).size() != 2:
		return _fail("roadblock is not two cars with officers")
	var gap := (block["at"] as Vector3).distance_to(car.global_position)
	if gap < 60.0 or gap > 200.0:
		return _fail("roadblock not placed ahead (%.0f m)" % gap)
	for c in block["cars"]:
		if (c as DriveableVehicle).global_position.y - player.sector_data.height_at((c as Node3D).global_position.x, (c as Node3D).global_position.z) > 1.2:
			return _fail("roadblock car floating")
	wanted.raise_to(4, player.global_position)
	for i in range(240):
		await physics_frame
	var heli: Node3D = escalation.get("helicopter")
	if heli == null:
		return _fail("no helicopter at four stars")
	var above := heli.global_position.y - player.global_position.y
	var flat := Vector2(heli.global_position.x - player.global_position.x, heli.global_position.z - player.global_position.z).length()
	if above < 20.0 or flat > 120.0:
		return _fail("helicopter not over the player (above %.0f, flat %.0f)" % [above, flat])
	wanted.clear_wanted()
	if not (escalation.get("roadblocks") as Array).is_empty():
		return _fail("roadblocks not removed on clear")
	for i in range(60 * 14):
		await physics_frame
		if escalation.get("helicopter") == null:
			break
	if escalation.get("helicopter") != null:
		return _fail("helicopter did not leave")
	print("ESCALATION PASS: 3-star roadblock ahead (%.0f m, 2 cars + 2 officers), 4-star helicopter overhead (%.0f m up), both cleared" % [gap, above])
	root.queue_free()
	await process_frame
	quit(0)


func _fail(reason: String) -> void:
	push_error("ESCALATION FAIL: " + reason)
	quit(1)
