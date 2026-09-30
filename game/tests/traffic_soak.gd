extends SceneTree

## 60 s traffic soak: every traffic car must keep moving (no permanent jams) and
## stay on the road network. Prints per-car distance travelled.

const SECONDS := 60
const WINDOW := 10


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	var world := root.get_node("District_Altillo")
	var network: RoadNetwork = world.road_network
	var cars: Array[DriveableVehicle] = []
	for node in get_nodes_in_group("vehicles"):
		if (node as DriveableVehicle).traffic:
			cars.append(node as DriveableVehicle)
	var travelled := {}
	var last := {}
	var window_start := {}
	var stalled_windows := {}
	var max_off_road := 0.0
	var max_air := 0.0  # height of any car above the real ground ("flying cars")
	var data := (root.get_node("District_Altillo") as SectorWorld).data if root.has_node("District_Altillo") else null
	for car in cars:
		travelled[car] = 0.0
		last[car] = car.global_position
		window_start[car] = car.global_position
		stalled_windows[car] = 0
	var ticks := Engine.physics_ticks_per_second
	for frame in range(SECONDS * ticks):
		await physics_frame
		for car in cars:
			travelled[car] += car.global_position.distance_to(last[car])
			last[car] = car.global_position
			max_off_road = maxf(max_off_road, float(network.nearest(car.global_position)["distance"]))
			if data != null:
				max_air = maxf(max_air, car.global_position.y - data.height_at(car.global_position.x, car.global_position.z))
		if frame % (WINDOW * ticks) == WINDOW * ticks - 1:
			for car in cars:
				if car.global_position.distance_to(window_start[car]) < 5.0:
					stalled_windows[car] += 1
				window_start[car] = car.global_position
	var jammed := 0
	var summary := []
	for car in cars:
		summary.append("%s:%dm/%d" % [car.name, int(travelled[car]), stalled_windows[car]])
		if stalled_windows[car] >= 3:
			jammed += 1
	var success := jammed <= 1 and max_off_road < 9.0 and max_air < 1.2
	print("TRAFFIC SOAK: cars=", cars.size(), " jammed=", jammed, " max_off_road_m=", snappedf(max_off_road, 0.1), " max_air_m=", snappedf(max_air, 0.01), " ", " ".join(summary))
	root.queue_free()
	for i in range(3):
		await process_frame
	if not success:
		push_error("TRAFFIC SOAK FAIL: jammed=%d max_off_road=%.1f max_air=%.2f" % [jammed, max_off_road, max_air])
	quit(0 if success else 1)
