extends SceneTree

## Miradores: every viewpoint stands on walkable ground (terrain or a paved
## road, no building), walking up to one triggers the panorama once (200 €, a
## temporary camera that pans, the player's camera restored afterwards), E
## replays it without paying, Escape skips, stars block it, all five pay the
## 2,000 € bonus, and the discoveries survive save/load.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(10):
		await physics_frame
	var miradores: Node = root.get("miradores")
	if miradores == null:
		return _fail("no miradores node")
	var spots: Array = miradores.get("spots")
	if spots.size() < 4 or spots.size() > 5:
		return _fail("expected 4–5 miradores, got %d" % spots.size())
	var player := root.get_node("Player") as PlayerController
	var wanted := root.get_node("WantedSystem") as WantedSystem
	var space := player.get_world_3d().direct_space_state
	var report := []
	# 1. Walkable ground, room to stand, marker built.
	for spot in spots:
		var at: Vector3 = spot["at"]
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3(0, 40, 0), at - Vector3(0, 10, 0)))
		if hit.is_empty():
			return _fail("%s: nothing under the viewpoint" % spot["id"])
		var ground := hit["collider"] as Node
		var ground_name := str(ground.name)
		if not ground.is_in_group("terrain") or not (ground_name.begins_with("Terrain") or ground_name.begins_with("RoadSurface")):
			return _fail("%s stands on %s, not terrain/road" % [spot["id"], ground_name])
		if absf(float(hit["position"].y) - at.y) > 0.3:
			return _fail("%s marker height %.2f vs ground %.2f" % [spot["id"], at.y, float(hit["position"].y)])
		var q := PhysicsShapeQueryParameters3D.new()
		var body := CylinderShape3D.new()
		body.radius = 0.6
		body.height = 1.4
		q.shape = body
		q.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 1.0, 0))
		for h in space.intersect_shape(q, 8):
			var other := h["collider"] as Node
			if not (other.is_in_group("terrain") or other is Pedestrian or other is DriveableVehicle or other is PlayerController):
				return _fail("%s blocked by %s" % [spot["id"], other.name])
		var marker := spot["node"] as Node3D
		if marker == null or marker.get_node_or_null("Letrero") == null or marker.get_node_or_null("Telescopio") == null:
			return _fail("%s has no telescope/sign" % spot["id"])
		var label := marker.get_node("Letrero").get_child(marker.get_node("Letrero").get_child_count() - 1) as Label3D
		if label == null or not label.text.begins_with("MIRADOR") or label.visibility_range_end <= 0.0:
			return _fail("%s sign label wrong" % spot["id"])
		report.append("%s (%.0f, %.1f, %.0f) on %s" % [spot["name"], at.x, at.y, at.z, ground_name])
	# 2. Walk up to the Paseo del Altillo viewpoint.
	var index := -1
	for i in range(spots.size()):
		if str(spots[i]["id"]) == "altillo":
			index = i
	if index < 0:
		index = 0
	var target: Vector3 = spots[index]["at"]
	var look: Vector3 = spots[index]["look"]
	var away := Vector3(target.x - look.x, 0, target.z - look.z).normalized()
	player.global_position = target + away * 5.0 + Vector3(0, 0.4, 0)
	player.velocity = Vector3.ZERO
	var dir := (target - player.global_position)
	player.camera_yaw = atan2(-dir.x, -dir.z)
	player._update_camera_orientation()
	var money := int(root.get("money"))
	Input.action_press("move_forward")
	var started := false
	for i in range(240):
		await physics_frame
		if bool(miradores.get("cinematic")):
			started = true
			break
	Input.action_release("move_forward")
	if not started:
		return _fail("walking to the viewpoint did not start the panorama (player at %s, target %s)" % [player.global_position, target])
	if int(root.get("money")) != money + 200:
		return _fail("discovery paid %d" % (int(root.get("money")) - money))
	var cam := miradores.get("camera") as Camera3D
	if cam == null or player.get_viewport().get_camera_3d() != cam:
		return _fail("panorama camera not current")
	if player.process_mode != Node.PROCESS_MODE_DISABLED:
		return _fail("player not frozen during the panorama")
	if bool((root.get("hud") as CanvasLayer).visible):
		return _fail("HUD not hidden during the panorama")
	var yaw_start := cam.global_rotation.y
	await _seconds(1.5)
	if absf(angle_difference(yaw_start, cam.global_rotation.y)) < 0.2:
		return _fail("camera did not pan")
	# Keys are swallowed: the phone does not come out.
	_key(KEY_UP)
	await _seconds(0.1)
	if bool((root.get("phone") as Node).get("open")):
		return _fail("phone opened during the panorama")
	await _seconds(4.5)
	if bool(miradores.get("cinematic")):
		return _fail("panorama did not end after 5 s")
	if player.get_viewport().get_camera_3d() != player.camera or player.process_mode == Node.PROCESS_MODE_DISABLED or not (root.get("hud") as CanvasLayer).visible:
		return _fail("player camera/controls/HUD not restored")
	# 3. Standing there does not rediscover; E replays without paying; Escape skips.
	await _seconds(0.5)
	if bool(miradores.get("cinematic")) or int(root.get("money")) != money + 200:
		return _fail("viewpoint triggered twice")
	player.global_position = target + Vector3(0, 0.3, 0)
	await _seconds(0.2)
	if str(miradores.call("prompt_text")) == "":
		return _fail("no E prompt at a discovered viewpoint")
	_key(KEY_E)
	await _seconds(0.2)
	if not bool(miradores.get("cinematic")) or int(root.get("money")) != money + 200:
		return _fail("E did not replay the panorama for free")
	_key(KEY_ESCAPE)
	await _seconds(0.2)
	if bool(miradores.get("cinematic")) or player.get_viewport().get_camera_3d() != player.camera or root.get_tree().paused:
		return _fail("Escape did not skip the panorama cleanly")
	# 4. Stars block discovery.
	var other := (index + 1) % spots.size()
	wanted.raise_to(1, player.global_position)
	player.global_position = (spots[other]["at"] as Vector3) + Vector3(0, 0.3, 0)
	await _seconds(0.4)
	if bool(miradores.get("cinematic")) or (miradores.get("found") as Dictionary).size() != 1:
		return _fail("viewpoint discovered with a star")
	wanted.clear_wanted()
	# 5. The rest, skipping each panorama with E.
	for i in range(spots.size()):
		if i == index:
			continue
		player.global_position = (spots[i]["at"] as Vector3) + Vector3(0, 0.3, 0)
		player.velocity = Vector3.ZERO
		var ok := false
		for k in range(30):
			await physics_frame
			if bool(miradores.get("cinematic")):
				ok = true
				break
		if not ok:
			return _fail("%s not discovered on arrival" % spots[i]["id"])
		await _seconds(0.3)
		_key(KEY_E)
		await _seconds(0.2)
		if bool(miradores.get("cinematic")):
			return _fail("E did not skip")
		player.global_position += Vector3(0, 0, 0)
	if (miradores.get("found") as Dictionary).size() != spots.size():
		return _fail("not all found")
	var gained := int(root.get("money")) - money
	if gained != 200 * spots.size() + 2000:
		return _fail("all miradores paid %d" % gained)
	var phone: Node = root.get("phone")
	phone.call("_stats")
	var stats := str((phone.get("items") as Array).map(func(item: Dictionary) -> String: return str(item["label"])))
	if not stats.contains("Miradores: %d/%d" % [spots.size(), spots.size()]):
		return _fail("phone stats " + stats)
	# 6. Save/load.
	root.set("save_path", "user://test_miradores_save.json")
	root.call("_save_game")
	miradores.call("from_save", {})
	if (miradores.get("found") as Dictionary).size() != 0:
		return _fail("from_save({}) did not clear")
	root.call("_load_game")
	if (miradores.get("found") as Dictionary).size() != spots.size():
		return _fail("load restored %d miradores" % (miradores.get("found") as Dictionary).size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_miradores_save.json"))
	print("MIRADORES PASS: %d viewpoints on walkable ground [%s]; walking up starts a panning panorama (+200 €), camera/controls restored, no repeat, E replays, Esc skips, stars block, all = +%d € incl. 2000 bonus, stats + save/load" % [spots.size(), "; ".join(report), gained])
	root.queue_free()
	await process_frame
	quit(0)


func _seconds(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	get_root().push_input(event)
	var up := event.duplicate() as InputEventKey
	up.pressed = false
	get_root().push_input(up)


func _fail(reason: String) -> void:
	Input.action_release("move_forward")
	push_error("MIRADORES FAIL: " + reason)
	quit(1)
