extends SceneTree


func _initialize() -> void:
	call_deferred("_measure")


func _measure() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	viewport.add_child(root)
	var arguments := OS.get_cmdline_user_args()
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
	var samples: Array[float] = []
	var total_draw_calls := 0.0
	var previous := Time.get_ticks_usec()
	for i in range(240):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		total_draw_calls += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		previous = now
	samples.sort()
	var sum_ms := 0.0
	for sample in samples:
		sum_ms += sample
	var average_ms := sum_ms / samples.size()
	var p99_ms := samples[int(samples.size() * 0.99)]
	var frame_size := viewport.get_texture().get_size()
	print("PERFORMANCE SAMPLE: view=", arguments[1] if arguments.size() >= 2 else "outside", " framebuffer=", frame_size, " frames=", samples.size(),
		" average_fps=", snappedf(1000.0 / average_ms, 0.1),
		" 1pct_low_fps=", snappedf(1000.0 / p99_ms, 0.1),
		" average_ms=", snappedf(average_ms, 0.01), " p99_ms=", snappedf(p99_ms, 0.01),
		" average_draw_calls=", snappedf(total_draw_calls / samples.size(), 0.1),
		" texture_mib=", snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		" diagnostic_flags=", arguments)
	root.queue_free()
	viewport.queue_free()
	for i in range(3):
		await process_frame
	quit(0)
