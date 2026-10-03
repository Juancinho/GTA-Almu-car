extends SceneTree

## Vest and first-aid kits: pickups exist, the vest soaks damage before health,
## full health/armour leaves a pickup in place, and armour is saved.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(8):
		await physics_frame
	var player := root.get_node("Player") as PlayerController
	var weapons: Node = root.get("weapons")
	var vest: Dictionary
	var kit: Dictionary
	for pickup in weapons.get("pickups"):
		if pickup["weapon"] == "armor" and vest.is_empty():
			vest = pickup
		if pickup["weapon"] == "health" and kit.is_empty():
			kit = pickup
	if vest.is_empty() or kit.is_empty():
		return _fail("no vest/first-aid pickups")
	player.global_position = (vest["node"] as Node3D).global_position + Vector3(0, 0.2, 0)
	await _frames(4)
	if player.armor < PlayerController.MAX_ARMOR or (vest["node"] as Node3D).visible:
		return _fail("vest not picked up")
	player.take_damage(30.0, "police")
	if player.health < PlayerController.MAX_HEALTH or absf(player.armor - 70.0) > 0.1:
		return _fail("vest did not soak the hit (health %.0f armour %.0f)" % [player.health, player.armor])
	player.take_damage(90.0, "police")
	if absf(player.armor) > 0.1 or absf(player.health - (PlayerController.MAX_HEALTH - 20.0)) > 0.1:
		return _fail("overflow damage did not reach health")
	player.global_position = (kit["node"] as Node3D).global_position + Vector3(0, 0.2, 0)
	await _frames(4)
	if player.health < PlayerController.MAX_HEALTH or (kit["node"] as Node3D).visible:
		return _fail("first-aid kit not used")
	player.armor = 55.0
	root.set("save_path", "user://test_armor_save.json")
	root.call("_save_game")
	player.armor = 0.0
	root.call("_load_game")
	if absf(player.armor - 55.0) > 0.1:
		return _fail("armour not saved")
	print("ARMOR PASS: vest pickup, soaks 30 then overflow to health, first-aid kit heals, armour saved")
	root.queue_free()
	await process_frame
	quit(0)


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _fail(reason: String) -> void:
	push_error("ARMOR FAIL: " + reason)
	quit(1)
