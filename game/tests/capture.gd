extends SceneTree


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var root := scene.instantiate()
	get_root().add_child(root)
	var arguments := OS.get_cmdline_user_args()
	var view := "seafront"
	if arguments.size() >= 2 and arguments[0] == "--view":
		view = arguments[1]
	var player := root.get_node("Player") as PlayerController
	match view:
		"town":
			player.global_position = Vector3(39, 0.3, -62)
			player.camera_yaw = -0.5
			player._update_camera_orientation()
		"castle":
			player.global_position = Vector3(58, 0.3, -158)
			player.camera_yaw = -0.52
			player._update_camera_orientation()
		"car":
			var car := root.get_node("District_Altillo/FirstCar") as DriveableVehicle
			player.global_position = car.global_position + Vector3(2, 0, 0)
			player._interact()
			player.camera_yaw = PI * 0.5
			player._update_camera_orientation()
	for i in range(25):
		await process_frame
	print("VIEW=", view, " player=", player.global_position, " camera=", player.camera.global_position, " forward=", -player.camera.global_transform.basis.z)
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
