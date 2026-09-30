extends SceneTree


func _initialize() -> void:
	call_deferred("_measure")


func _measure() -> void:
	if OS.get_cmdline_user_args().has("--uncapped"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	viewport.add_child(root)
	var arguments := OS.get_cmdline_user_args()
	var quality_arg := arguments.find("--quality")
	if quality_arg >= 0 and quality_arg + 1 < arguments.size():
		root.quality_level = clampi(int(arguments[quality_arg + 1]), 0, 2)
		root._apply_settings()
	var world := root.get_node("District_Altillo") as SectorWorld
	if "--without-interiors" in arguments:
		for venue in world.venues.values():
			(venue as VenueInterior).room.visible = false
	if arguments.size() >= 2 and arguments[0] == "--view":
		var kind := arguments[1]
		if not world.venues.has(kind):
			push_error("Unknown performance view: " + kind)
			quit(1)
			return
		var venue := world.venues[kind] as VenueInterior
		venue.room.visible = true
		var player := root.get_node("Player") as PlayerController
		player.global_position = venue.inside_entry
		player.camera_yaw = venue.room.rotation.y
		player._update_camera_orientation()
	for i in range(90):
		await RenderingServer.frame_post_draw
		if arguments.has("--combat"):
			_combat_load(root, i)
	var samples: Array[float] = []
	var total_draw_calls := 0.0
	var render_cpu_ms := 0.0
	var render_gpu_ms := 0.0
	var previous := Time.get_ticks_usec()
	for i in range(240):
		await RenderingServer.frame_post_draw
		if arguments.has("--combat"):
			_combat_load(root, i + 90)
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		total_draw_calls += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		render_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid())
		render_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
		previous = now
	samples.sort()
	var sum_ms := 0.0
	for sample in samples:
		sum_ms += sample
	var average_ms := sum_ms / samples.size()
	var p99_ms := samples[int(samples.size() * 0.99)]
	var frame_size := viewport.get_texture().get_size()
	print("PERFORMANCE SAMPLE: view=", arguments[1] if arguments.size() >= 2 and arguments[0] == "--view" else "outside", " framebuffer=", frame_size, " frames=", samples.size(),
		" average_fps=", snappedf(1000.0 / average_ms, 0.1),
		" 1pct_low_fps=", snappedf(1000.0 / p99_ms, 0.1),
		" average_ms=", snappedf(average_ms, 0.01), " p99_ms=", snappedf(p99_ms, 0.01),
		" average_draw_calls=", snappedf(total_draw_calls / samples.size(), 0.1),
		" texture_mib=", snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		" render_cpu_ms=", snappedf(render_cpu_ms / samples.size(),0.01), " render_gpu_ms=", snappedf(render_gpu_ms / samples.size(),0.01),
		" diagnostic_flags=", arguments)
	root.queue_free()
	viewport.queue_free()
	for i in range(3):
		await process_frame
	quit(0)


## Synthetic worst-case visual load; world/AI remain the same as the outside view.
func _combat_load(root: Node, frame: int) -> void:
	if frame % 2 != 0:
		return
	var weapons := root.get_node("Weapons") as WeaponSystem
	var player := root.get_node("Player") as PlayerController
	var forward := -player.camera.global_basis.z
	forward.y = 0.0
	var at := player.global_position + forward.normalized() * 3.0 + Vector3.UP * 0.8
	weapons._impact(at, Color("bbdfed") if frame % 4 == 0 else Color("9e9485"), 12)
	weapons.ballistics._mark(at + Vector3.DOWN * 0.75, Vector3.UP)
