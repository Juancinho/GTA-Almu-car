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
	var success := jammed <= 1 and max_off_road < 9.0
	print("TRAFFIC SOAK: cars=", cars.size(), " jammed=", jammed, " max_off_road_m=", snappedf(max_off_road, 0.1), " ", " ".join(summary))
	root.queue_free()
	for i in range(3):
		await process_frame
	if not success:
		push_error("TRAFFIC SOAK FAIL: jammed=%d max_off_road=%.1f" % [jammed, max_off_road])
	quit(0 if success else 1)
