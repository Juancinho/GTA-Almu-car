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
	for i in range(90):
		await RenderingServer.frame_post_draw
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for i in range(240):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
	samples.sort()
	var sum_ms := 0.0
	for sample in samples:
		sum_ms += sample
	var average_ms := sum_ms / samples.size()
	var p99_ms := samples[int(samples.size() * 0.99)]
	var frame_size := viewport.get_texture().get_size()
	print("PERFORMANCE SAMPLE: framebuffer=", frame_size, " frames=", samples.size(),
		" average_fps=", snappedf(1000.0 / average_ms, 0.1),
		" 1pct_low_fps=", snappedf(1000.0 / p99_ms, 0.1),
		" average_ms=", snappedf(average_ms, 0.01), " p99_ms=", snappedf(p99_ms, 0.01))
	root.queue_free()
	viewport.queue_free()
	for i in range(3):
		await process_frame
	quit(0)
