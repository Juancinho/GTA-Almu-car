extends SceneTree

## Real GPU regression: use the game's F11 action, render after each resize and
## verify drawable output, quality scaling and text layout. Not a sustained FPS test.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in range(30):
		await RenderingServer.frame_post_draw
	for i in range(4):
		var event := InputEventAction.new()
		event.action = "fullscreen_toggle"
		event.pressed = true
		game._unhandled_input(event)
		for frame in range(25):
			await RenderingServer.frame_post_draw
		var expected := DisplayServer.WINDOW_MODE_FULLSCREEN if i % 2 == 0 else DisplayServer.WINDOW_MODE_WINDOWED
		var frame_image := root.get_texture().get_image()
		if DisplayServer.window_get_mode() != expected or frame_image.is_empty() or frame_image.get_size() != DisplayServer.window_get_size():
			return fail("mode/actual framebuffer after F11")
		if not is_equal_approx(root.scaling_3d_scale,0.85):
			return fail("Medium 3D scale changed after resize")
		for label in [game.hud.info_label,game.hud.mission_label,game.hud.prompt_label]:
			var panel := label.get_parent().get_parent().get_parent() as PanelContainer
			if not panel.get_global_rect().encloses(label.get_global_rect()):
				return fail("text escaped during window toggle")
		print("WINDOW TOGGLE ",i," mode=",expected," drawable=",frame_image.get_size()," scale_3d=",root.scaling_3d_scale)
	print("WINDOW MODES PASS: four F11 transitions, real GPU framebuffer, Medium scale and HUD containment")
	game.queue_free()
	await process_frame
	quit()

func fail(reason: String) -> void:
	push_error("WINDOW MODES FAIL: " + reason)
	quit(1)
