extends SceneTree

## Screenshot views of the real sector: `-- --view <name>`.
## seafront | town | castle | car | penon | church | aerial | aerial_castle

const VIEWS := {
	"seafront": {"pos": Vector3(-5, 0, 34), "yaw": -1.35, "pitch": -0.08},
	"town": {"pos": Vector3(-90, 0, -228), "yaw": 0.6, "pitch": 0.05},
	"castle": {"pos": Vector3(-160, 0, 20), "yaw": -0.95, "pitch": 0.12},
	"penon": {"pos": Vector3(-250, 0, 200), "yaw": 2.6, "pitch": 0.12},
	"church": {"pos": Vector3(-60, 0, -300), "yaw": 0.2, "pitch": 0.22},
	"aerial": {"camera": Vector3(60, 170, 260), "look": Vector3(-150, 0, -80)},
	"aerial_castle": {"camera": Vector3(-120, 70, 160), "look": Vector3(-215, 30, 80)},
	"sierra": {"camera": Vector3(80,90,300), "look": Vector3(-70,90,-1100)},
	"jaime": {"camera": Vector3(27, 11, 76), "look": Vector3(36, 4, 52)},
	"beach_bars": {"camera": Vector3(100, 12, 103), "look": Vector3(110, 3, 78)},
}


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	if OS.get_cmdline_user_args().has("--fullscreen"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	var arguments := OS.get_cmdline_user_args()
	var view := "seafront"
	if arguments.size() >= 2 and arguments[0] == "--view":
		view = arguments[1]
	var player := root.get_node("Player") as PlayerController
	player.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var world := root.get_node("District_Altillo") as SectorWorld
	var hide_at := arguments.find("--hide")
	if hide_at >= 0 and hide_at + 1 < arguments.size():  # debug: hide nodes whose name matches a pattern
		for node in world.find_children(arguments[hide_at + 1], "Node3D", false, false):
			(node as Node3D).visible = false
	if view in ["swimming", "diving"]:
		player.global_position = Vector3(20, -0.65, 200)
		player.camera_yaw = 0.0
		player._update_camera_orientation()
		Input.action_press("move_forward")
		if view == "diving":
			Input.action_press("dive")
		if view == "swimming":
			var camera := Camera3D.new()
			root.add_child(camera)
			camera.global_position = player.global_position + Vector3(4, 1.6, -2)
			camera.look_at(player.global_position + Vector3(0, 0.3, -1))
			camera.current = true
	elif view in ["beach_resident", "skater"]:
		var person := world.get_node("BeachResident_0") as Pedestrian
		if view == "skater":
			for candidate in get_nodes_in_group("pedestrians"):
				if candidate.activity == "skate":
					person = candidate as Pedestrian
					break
		if view == "skater":
			# Place the actual skater on a clear segment for a readable asset review.
			person.global_position = world.anchor("player_spawn") + Vector3(-3, 0.2, 0)
			person.home = person.global_position
			person.rotation.y = 0.0
		person.set_physics_process(false)
		person.human.update_motion(0)
		player.global_position = person.global_position + Vector3.RIGHT * 4.0
		player.set_physics_process(false)
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.global_position = person.global_position - person.global_basis.z * 3.0 + Vector3(1.0, 1.1, 0)
		camera.look_at(person.global_position + Vector3.UP * 0.85)
		camera.fov = 50.0
		camera.current = true
		for i in range(4):
			await physics_frame
			person.velocity = Vector3.DOWN * 3.0
			person.move_and_slide()
		if view == "skater":
			person.activity_phase = 0.8
			person.AmbientPose.update(person.human, "skate", 0.8)
			person.AmbientPose.place_skates(person.human)
	elif view == "police_aim":
		player.global_position = world.anchor("player_spawn") + Vector3(0,0.1,-7)
		player.set_physics_process(false)
		root.wanted.report_police_attack(player.global_position)
		root.wanted.set_process(false)
		var officer := PoliceOfficer.new()
		officer.wanted = root.wanted
		officer.player = player
		officer.position = world.anchor("player_spawn") + Vector3.UP * 0.1
		world.add_child(officer)
		officer.set_physics_process(false)
		officer.human.update_motion(0)
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.global_position = officer.global_position + Vector3(1.8,1.5,-3.5)
		camera.look_at(officer.global_position + Vector3.UP * 1.15)
		camera.fov = 50.0
		camera.current = true
	elif view == "apartment":
		var venue := world.venues["residence_altillo"] as VenueInterior
		player.global_position = venue.point_position("bed")
		var camera := Camera3D.new()
		root.add_child(camera)
		var origin: Vector3 = VenueInterior.SPECS[venue.kind]["origin"]
		camera.global_position = venue.room.to_global(origin + Vector3(1.0, 6.4, -2.0))
		camera.look_at(venue.room.to_global(origin + Vector3(-3.8,5.4,-6.2)))
		camera.current = true
	elif view == "broken_glass":
		var venue := world.venues["supermarket"] as VenueInterior
		var pane := venue.room.get_node("ShopWindowShots") as BreakableGlass
		player.global_position = pane.global_position + venue.exterior_normal * 3.0 - Vector3.UP
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.global_position = pane.global_position + venue.exterior_normal * 5.0 + Vector3.UP * 0.5
		camera.look_at(pane.global_position)
		camera.current = true
	elif view.begins_with("weapon_"):
		var id := view.trim_prefix("weapon_").trim_suffix("_idle")
		var weapons := root.get_node("Weapons") as WeaponSystem
		weapons.give(id, 60)
		weapons.select(id)
		player.set_physics_process(false)
		player.visual.rotation.y = 0.0
		player.camera_yaw = 0.0
		player.camera_pitch = 0.0
		if not view.ends_with("_idle"):
			Input.action_press("aim")
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.global_position = player.global_position + Vector3(2.0, 1.55, -1.6)
		camera.look_at(player.global_position + Vector3(0, 1.12, -0.25))
		camera.fov = 45.0
		camera.current = true
		root.hud.hide()
	elif view in ["casino_upper", "casino_office"]:
		var venue := world.venues["casino"] as VenueInterior
		player.global_position = venue.point_position("ledger" if view == "casino_office" else "landing")
		player.camera_yaw = venue.room.rotation.y + 0.95
		player.camera_pitch = -0.08
		player._update_camera_orientation()
		if view == "casino_office":
			root.mission.load_mission("cuentas_pendientes")
			root.mission.restore_stage(2)
			player.camera_yaw = venue.room.rotation.y
			player._update_camera_orientation()
	elif (world.venues.has(view) and view != "church") or view == "church_interior":
		var kind := "church" if view == "church_interior" else view
		var venue := world.venues[kind] as VenueInterior
		venue.room.visible = true
		player.global_position = venue.inside_entry
		player.camera_yaw = venue.room.rotation.y
		player.camera_pitch = -0.08
		player._update_camera_orientation()
	elif view.ends_with("_exterior") and world.venues.has(view.trim_suffix("_exterior")):
		var kind := view.trim_suffix("_exterior")
		var venue := world.venues[kind] as VenueInterior
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.global_position = venue.exterior_entry + venue.exterior_normal * 7.0 + Vector3.UP * 2.2
		camera.look_at(venue.exterior_entry + Vector3.UP * 2.0)
		camera.current = true
	elif view == "workshop_exterior":
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.global_position = world.workshop.exterior_entry + world.workshop.exterior_normal * 7.0 + Vector3.UP * 2.4
		camera.look_at(world.workshop.exterior_entry + Vector3.UP * 2.0)
		camera.current = true
	elif view == "workshop":
		player.global_position = world.workshop.inside_entry
		player.camera_yaw = 0.0
		player.camera_pitch = -0.08
		player._update_camera_orientation()
	elif view == "car":
		var car := world.get_node("FirstCar") as DriveableVehicle
		player.global_position = car.global_position + car.global_transform.basis.x * 2.0
		player._interact()
		player.camera_yaw = car.rotation.y
		player._update_camera_orientation()
	elif VIEWS.has(view) and VIEWS[view].has("camera"):
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.global_position = VIEWS[view]["camera"]
		camera.look_at(VIEWS[view]["look"])
		camera.far = 4000.0
		camera.current = true
	elif VIEWS.has(view):
		var spec: Dictionary = VIEWS[view]
		var p: Vector3 = spec["pos"]
		var street: Dictionary = world.road_network.nearest(p, false)  # stand on a real street, never inside a building
		if not street.is_empty():
			p = street["point"]
		player.global_position = Vector3(p.x, world.height_at(p.x, p.z) + 0.3, p.z)
		player.camera_yaw = spec["yaw"]
		player.camera_pitch = spec["pitch"]
		player._update_camera_orientation()
	# Let physics and animation settle without drawing (software GL is slow), then render.
	if arguments.has("--night"):
		root.day_night.hours = 0.0
	RenderingServer.render_loop_enabled = false
	for i in range(100 if view in ["swimming", "diving"] else 25):
		await physics_frame
		await process_frame
	if view == "broken_glass":
		var venue := world.venues["supermarket"] as VenueInterior
		var pane := venue.room.get_node("ShopWindowShots") as BreakableGlass
		var weapons := root.get_node("Weapons") as WeaponSystem
		weapons.ballistics.shoot(pane.global_position + venue.exterior_normal * 2.0,
			-venue.exterior_normal, 8.0, 30.0, 50.0, player)
		if not pane.broken:
			push_error("Capture: exterior shot did not shatter the real storefront")
			quit(1)
			return
	Input.action_release("move_forward")
	if view != "diving":
		Input.action_release("dive")
	if view == "swimming":
		player.set_process(false)
		player.set_physics_process(false)
		player.visual.visible = true
		var camera := get_root().get_camera_3d()
		camera.global_position = player.global_position + Vector3(3.0, 1.6, -2.0)
		camera.look_at(player.global_position + Vector3(0, 0.5, -0.6))
	RenderingServer.render_loop_enabled = true
	for i in range(2):
		await process_frame
	if view == "diving":
		print("DIVE CAMERA: ", player.camera.global_position, " effect=", player.underwater_view.active)
		if not player.underwater_view.active:
			push_error("Capture: actual diving camera is not underwater")
			quit(1)
			return
	print("VIEW=", view, " player=", player.global_position)
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	print("FRAMEBUFFER: actual=", image.get_size(), " texture_reported=", get_root().get_texture().get_size(), " window=", DisplayServer.window_get_size())
	if image.is_empty():
		push_error("Screenshot failed: viewport image empty")
		quit(1)
		return
	var output := ProjectSettings.globalize_path("res://").path_join("../generated/%s_%d.png" % [view, Time.get_unix_time_from_system()]).simplify_path()
	var result := image.save_png(output)
	if result != OK:
		push_error("Screenshot failed: %s (%d)" % [output, result])
		quit(1)
		return
	print("SCREENSHOT: " + output)
	root.queue_free()
	await process_frame
	quit(0)
