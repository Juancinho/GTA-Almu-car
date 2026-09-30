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
	"jaime": {"camera": Vector3(27, 11, 76), "look": Vector3(36, 4, 52)},
	"beach_bars": {"camera": Vector3(100, 12, 103), "look": Vector3(110, 3, 78)},
}


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	var arguments := OS.get_cmdline_user_args()
	var view := "seafront"
	if arguments.size() >= 2 and arguments[0] == "--view":
		view = arguments[1]
	var player := root.get_node("Player") as PlayerController
	var world := root.get_node("District_Altillo") as SectorWorld
	var hide_at := arguments.find("--hide")
	if hide_at >= 0 and hide_at + 1 < arguments.size():  # debug: hide nodes whose name matches a pattern
		for node in world.find_children(arguments[hide_at + 1], "Node3D", false, false):
			(node as Node3D).visible = false
	if (world.venues.has(view) and view != "church") or view == "church_interior":
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
	RenderingServer.render_loop_enabled = false
	for i in range(25):
		await process_frame
	RenderingServer.render_loop_enabled = true
	for i in range(2):
		await process_frame
	print("VIEW=", view, " player=", player.global_position)
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
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
