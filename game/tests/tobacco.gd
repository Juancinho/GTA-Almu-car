extends SceneTree

## Estancos and smoking: buy a pack, light a cigarette (visible, smoke, heals),
## steal a carton (one star), leave the shop, tobacco kept in the save.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(8):
		await physics_frame
	var world := root.get_node("District_Altillo") as SectorWorld
	var player := root.get_node("Player") as PlayerController
	var wanted := root.get_node("WantedSystem") as WantedSystem
	var smoking := root.get_node_or_null("Smoking")
	if smoking == null or not world.venues.has("estanco") or not world.venues.has("estanco_centro"):
		return _fail("smoking system or estancos missing")
	var shop := world.venues["estanco"] as VenueInterior
	player.global_position = shop.exterior_entry
	player._interact()
	await _frames(3)
	if not shop.contains_player(player.global_position):
		return _fail("could not enter the estanco")
	root.set("money", 20)
	player.global_position = shop.service_point
	player._interact()
	if int(root.get("cigarettes")) != 20 or int(root.get("money")) != 15:
		return _fail("buying a pack failed (cigs %d money %d)" % [int(root.get("cigarettes")), int(root.get("money"))])
	player.global_position = shop.secondary_service_point
	player._interact()
	if int(root.get("cigarettes")) != 220 or wanted.level < 1:
		return _fail("stealing a carton did not work or was not reported")
	wanted.clear_wanted()
	player.global_position = shop.inside_entry
	player._interact()
	await _frames(3)
	if shop.contains_player(player.global_position) or player.global_position.distance_to(shop.exterior_entry) > 2.0:
		return _fail("could not leave the estanco")
	player.health = 80.0
	if not smoking.call("light") or int(root.get("cigarettes")) != 219:
		return _fail("could not light a cigarette")
	await _frames(3)
	var cig := smoking.get("cigarette") as Node3D
	if not cig.visible or cig.global_position.distance_to(player.global_position) > 1.6:
		return _fail("cigarette not shown in the hand")
	for i in range(60 * 13):
		await physics_frame
	if bool(smoking.get("smoking")) or player.health <= 80.0:
		return _fail("the cigarette did not finish and calm the player")
	root.set("save_path", "user://test_tobacco_save.json")
	root.call("_save_game")
	root.set("cigarettes", 0)
	root.call("_load_game")
	if int(root.get("cigarettes")) != 219:
		return _fail("tobacco not saved")
	print("TOBACCO PASS: two estancos, buy pack, steal carton (1 star), exit, smoke with hand cigarette and heal, saved")
	root.queue_free()
	await process_frame
	quit(0)


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame


func _fail(reason: String) -> void:
	push_error("TOBACCO FAIL: " + reason)
	quit(1)
