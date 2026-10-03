extends SceneTree

## Hidden amphorae: 30 placed on land, spaced, reachable; walking onto one pays,
## the tenth gives the SMG, and the set survives save/load.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(8):
		await physics_frame
	var player := root.get_node("Player") as PlayerController
	var items: Node = root.get("collectibles")
	var spots: Array = items.get("spots")
	if spots.size() != 30:
		return _fail("expected 30 amphorae, got %d" % spots.size())
	for p in spots:
		var ground := player.sector_data.height_at((p as Vector3).x, (p as Vector3).z)
		if absf((p as Vector3).y - ground) > 0.6:
			return _fail("amphora floating or buried at %s" % p)
	var money := int(root.get("money"))
	for i in range(10):
		player.global_position = (spots[i] as Vector3) + Vector3(0, 0.3, 0)
		await _frames(10)
	if (items.get("found") as Dictionary).size() != 10:
		return _fail("walking onto amphorae did not collect them (%d)" % (items.get("found") as Dictionary).size())
	if int(root.get("money")) != money + 1000 or not root.weapons.owned.has("smg"):
		return _fail("rewards missing")
	root.set("save_path", "user://test_collectibles_save.json")
	root.call("_save_game")
	items.call("from_save", [])
	root.call("_load_game")
	if (items.get("found") as Dictionary).size() != 10:
		return _fail("collected amphorae not saved")
	print("COLLECTIBLES PASS: 30 amphorae on the ground, 10 collected on foot, 1000 € + SMG reward, saved")
	root.queue_free()
	await process_frame
	quit(0)


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _fail(reason: String) -> void:
	push_error("COLLECTIBLES FAIL: " + reason)
	quit(1)
