extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(6):
		await physics_frame
	var world := root.get_node("District_Altillo") as SectorWorld
	var player := root.get_node("Player") as PlayerController
	var wanted := root.get_node("WantedSystem") as WantedSystem
	if world.venues.size() != 8:
		return _fail("expected eight physical venues")
	if int(world.build_stats.get("businesses", 0)) < 10 or int(world.build_stats.get("beach_bars", 0)) != 5:
		return _fail("promenade businesses or walk-in beach bars missing")
	if world.beach_bars.size() != 5:
		return _fail("beach bar counters unavailable")
	for kind in ["supermarket", "restaurant", "cafe", "palm_restaurant"]:
		var venue := world.venues[kind] as VenueInterior
		if venue.source_building_id != int(VenueInterior.SPECS[kind]["building_id"]):
			return _fail(kind + " not attached to the selected building")
		if not DressingBuilder._clear_of_driveable(venue.exterior_entry, world.road_network, 0.0):
			return _fail(kind + " doorway inside a driveable lane")
		if not venue.room.visible or venue.inside_entry.y > 100.0:
			return _fail(kind + " is not a visible street-level interior")
		player.global_position = venue.exterior_entry
		player._interact()
		if player.global_position.distance_to(venue.inside_entry) > 0.2 or not venue.room.visible:
			return _fail("could not enter " + kind)
		for i in range(4):
			await physics_frame
		if player.global_position.y < venue.inside_entry.y - 0.5:
			return _fail(kind + " floor did not support the player")
		player.health = 45.0
		root.money = 0
		player.global_position = venue.service_point
		player._interact()
		if player.health != 45.0 or root.money != 0:
			return _fail(kind + " service ignored insufficient funds")
		root.money = 40
		player._interact()
		if kind == "supermarket" and (player.health != 75.0 or root.money != 25):
			return _fail("supermarket food transaction wrong")
		if kind == "restaurant" and (player.health != 100.0 or root.money != 5):
			return _fail("restaurant meal transaction wrong")
		if kind == "cafe" and (player.health != 65.0 or root.money != 32):
			return _fail("cafe breakfast transaction wrong")
		if kind == "palm_restaurant" and (player.health != 100.0 or root.money != 5):
			return _fail("La Palmera meal transaction wrong")
		player.health = PlayerController.MAX_HEALTH
		var cash_before: int = root.money
		player._interact()
		if root.money != cash_before:
			return _fail(kind + " charged a player at full health")
		if kind in ["cafe", "palm_restaurant"]:
			if not _room_fits(venue, world):
				return _fail(kind + " room extends beyond its building")
			if venue.room.find_children("FurnitureBatch_*", "MultiMeshInstance3D", false, false).is_empty():
				return _fail(kind + " repeated furnishings were not batched")
		player.global_position = venue.inside_entry
		player._interact()
		if player.global_position.distance_to(venue.exterior_entry) > 1.0 or not venue.room.visible:
			return _fail("could not leave " + kind)
	var market := world.venues["supermarket"] as VenueInterior
	root.save_path = "user://venues_test_save.json"
	player.global_position = market.inside_entry
	root._sync_venue_rooms()
	root._save_game()
	player.global_position = market.exterior_entry
	root._sync_venue_rooms()
	root._load_game()
	if player.global_position.distance_to(market.inside_entry) > 0.2 or not market.room.visible:
		return _fail("loading an interior save left the room hidden")
	player.global_position = market.inside_entry
	player._interact()
	if not market.room.visible:
		return _fail("storefront disappeared after exiting loaded save")
	var bank := world.venues["bank"] as VenueInterior
	if bank.source_building_id != int(VenueInterior.SPECS["bank"]["building_id"]):
		return _fail("bank not attached to the selected building")
	if not DressingBuilder._clear_of_driveable(bank.exterior_entry, world.road_network, 0.0):
		return _fail("bank doorway inside a driveable lane")
	player.global_position = bank.exterior_entry
	player._interact()
	if player.global_position.distance_to(bank.inside_entry) > 0.2 or not bank.room.visible:
		return _fail("could not enter bank")
	for i in range(4):
		await physics_frame
	if player.global_position.y < bank.inside_entry.y - 0.5:
		return _fail("bank floor did not support the player")
	if bank.inside_entry.distance_to(bank.service_point) > 20.0:
		return _fail("bank counter lies outside the physical building")
	root.money = 250
	root.bank_balance = 0
	player.global_position = bank.service_point
	player._interact()
	if root.money != 150 or root.bank_balance != 100:
		return _fail("bank deposit did not transfer exactly 100 euros")
	player._interact()
	player._interact()
	if root.money != 50 or root.bank_balance != 200:
		return _fail("bank accepted a deposit without sufficient cash")
	player.global_position = bank.secondary_service_point
	player._interact()
	if root.money != 150 or root.bank_balance != 100:
		return _fail("ATM withdrawal did not transfer exactly 100 euros")
	root._save_game()
	root.money = 0
	root.bank_balance = 0
	player.global_position = bank.exterior_entry
	root._sync_venue_rooms()
	root._load_game()
	if root.money != 150 or root.bank_balance != 100 or not bank.room.visible:
		return _fail("bank balance, cash or room did not restore from save")
	player.global_position = bank.inside_entry
	player._interact()
	if not bank.room.visible or player.global_position.distance_to(bank.exterior_entry) > 1.0:
		return _fail("could not leave bank")
	root._on_player_busted()
	if root.bank_balance != 100 or root.money != 50:
		return _fail("arrest fee should use cash without changing the bank balance")
	var jewellery := world.venues["jewellery"] as VenueInterior
	var full_loot_count := _loot_count(jewellery)
	if full_loot_count < 10:
		return _fail("jewellery loot identities were lost during furniture batching")
	if jewellery.source_building_id != int(VenueInterior.SPECS["jewellery"]["building_id"]):
		return _fail("jewellery not attached to selected building")
	if not DressingBuilder._clear_of_driveable(jewellery.exterior_entry, world.road_network, 0.0):
		return _fail("jewellery doorway inside a driveable lane")
	player.global_position = jewellery.exterior_entry
	player._interact()
	if player.global_position.distance_to(jewellery.inside_entry) > 0.2 or not jewellery.room.visible:
		return _fail("could not enter jewellery")
	root.money = 0
	root.jewellery_robbed = false
	wanted.clear_wanted()
	player.global_position = jewellery.service_point
	root._save_game()
	player._interact()
	if root.money != 250 or not root.jewellery_robbed or wanted.level == 0 or _loot_visible(jewellery):
		return _fail("jewellery robbery did not pay once and raise police alert")
	player._interact()
	if root.money != 250 or wanted.level != 1:
		return _fail("jewellery robbery repeated")
	root._load_game()
	if root.money != 0 or root.jewellery_robbed or _loot_count(jewellery) != full_loot_count:
		return _fail("loading before the robbery did not restore the full display")
	player._interact()
	if root.money != 250 or not root.jewellery_robbed:
		return _fail("jewellery could not be robbed after loading pre-robbery save")
	root._save_game()
	root.money = 0
	root.jewellery_robbed = false
	player.global_position = jewellery.exterior_entry
	root._sync_venue_rooms()
	root._load_game()
	if root.money != 250 or not root.jewellery_robbed or not jewellery.room.visible or _loot_visible(jewellery):
		return _fail("jewellery robbery state did not survive save/load")
	player._interact()
	if root.money != 250:
		return _fail("loaded jewellery robbery could be repeated")
	player.global_position = jewellery.inside_entry
	player._interact()
	if not jewellery.room.visible:
		return _fail("could not leave jewellery")
	for kind in ["church", "mall"]:
		var place := world.venues[kind] as VenueInterior
		if place.inside_entry.y > 100.0 or not place.room.visible:
			return _fail(kind + " is not built in its street-level footprint")
		player.global_position = place.exterior_entry
		player._interact()
		if player.global_position.distance_to(place.inside_entry) > 0.2:
			return _fail("could not enter " + kind)
		player.global_position = place.inside_entry
		player._interact()
		if player.global_position.distance_to(place.exterior_entry) > 1.0:
			return _fail("could not leave " + kind)
	var beach_bar := world.beach_bars[0]
	root.money = 40
	player.health = 50.0
	player.global_position = beach_bar.global_position
	player._interact()
	if root.money != 5 or player.health != PlayerController.MAX_HEALTH:
		return _fail("beach bar meal did not heal and charge once")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root.save_path))
	print("VENUES PASS: eight physical interiors, cafe breakfast, La Palmera dining, five beach bars, bank transfers and all jewellery loot restored/hidden")
	root.queue_free()
	await process_frame
	quit(0)


func _fail(reason: String) -> void:
	push_error("VENUES FAIL: " + reason)
	quit(1)


func _loot_visible(jewellery: VenueInterior) -> bool:
	return _loot_count(jewellery) > 0


func _loot_count(jewellery: VenueInterior) -> int:
	var count := 0
	for node in jewellery.room.get_children():
		var label := str(node.get_meta("detail_kind", node.name))
		if node is MeshInstance3D and (label.begins_with("Gemstone") or label.begins_with("GoldSetting") or label.begins_with("GoldDisplay")) and (node as MeshInstance3D).visible:
			count += 1
	return count


func _room_fits(venue: VenueInterior, world: SectorWorld) -> bool:
	var polygon := PackedVector2Array()
	for building in world.data.raw["buildings"]:
		if int(building["id"]) == venue.source_building_id:
			for p in building["footprint"]:
				polygon.append(Vector2(float(p[0]), float(p[1])))
	var origin: Vector3 = VenueInterior.SPECS[venue.kind]["origin"]
	# Sample the complete room rectangle, not just its centre. Leave 20 cm for
	# the shared outer wall; this catches stale edge indices after regeneration.
	for x in [-6.8, -3.4, 0.0, 3.4, 6.8]:
		for z in [-8.8, -4.4, 0.0, 4.4, 8.8]:
			var at := venue.room.to_global(origin + Vector3(x, 0.5, z))
			if not Geometry2D.is_point_in_polygon(Vector2(at.x, at.z), polygon):
				return false
	return true
