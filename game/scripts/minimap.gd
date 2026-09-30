class_name DistrictMinimap
extends Control

## North-up radar: streets, the GPS route to the current objective along the road
## graph, the objective (clamped to the edge with an arrow when off the map),
## contact letters for missions on offer, services, police and a heading arrow.

const GPS_COLOR := Color("f2c14e")
const OBJECTIVE_COLOR := Color("f2c14e")

var player: PlayerController
var mission: MissionController
var wanted: WantedSystem
var road_network: RoadNetwork
var workshop_marker := Vector2.INF
var venue_markers: Dictionary = {}
var redraw_timer := 0.0
var gps_timer := 0.0
var gps_path := PackedVector3Array()
var gps_goal := Vector3.INF
var gps_from := Vector3.INF
var offers: Array = []
var waypoint := Vector3.INF  # player-chosen destination from the full map
var waypoint_path := PackedVector3Array()
var waypoint_from := Vector3.INF


func _ready() -> void:
	custom_minimum_size = Vector2(186, 186)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	redraw_timer -= delta
	gps_timer -= delta
	if gps_timer <= 0.0 and player != null and mission != null:
		gps_timer = 0.6
		_update_gps()
	if redraw_timer <= 0.0:  # 15 Hz is plenty for a minimap with hundreds of streets
		redraw_timer = 1.0 / 15.0
		queue_redraw()


func _position() -> Vector3:
	return player.driving_vehicle.global_position if player.driving_vehicle != null else player.global_position


func set_waypoint(point: Vector3) -> void:
	waypoint = point
	waypoint_path = PackedVector3Array()
	waypoint_from = Vector3.INF
	_update_waypoint()


func _update_waypoint() -> void:
	if waypoint == Vector3.INF or road_network == null or player == null:
		waypoint_path = PackedVector3Array()
		return
	var from := _position()
	if Vector2(from.x - waypoint.x, from.z - waypoint.z).length() < 25.0:
		waypoint = Vector3.INF  # arrived
		waypoint_path = PackedVector3Array()
		return
	if not waypoint_path.is_empty() and from.distance_to(waypoint_from) < 12.0:
		return
	waypoint_from = from
	waypoint_path = road_network.find_path(from, waypoint)
	if not waypoint_path.is_empty():
		waypoint_path.insert(0, from)
		waypoint_path.append(waypoint)


func _update_gps() -> void:
	_update_waypoint()
	offers = mission.offers()
	var goal := mission.gps_target()
	var from := _position()
	if goal == Vector3.INF or road_network == null:
		gps_path = PackedVector3Array()
		gps_goal = Vector3.INF
		return
	var flat := Vector2(goal.x - from.x, goal.z - from.z).length()
	if flat < (35.0 if player.driving_vehicle == null else 20.0):
		gps_path = PackedVector3Array()
		gps_goal = goal
		return
	if gps_goal != Vector3.INF and goal.distance_to(gps_goal) < 6.0 and from.distance_to(gps_from) < 12.0 and not gps_path.is_empty():
		return
	gps_goal = goal
	gps_from = from
	gps_path = road_network.find_path(from, goal)
	if not gps_path.is_empty():
		gps_path.insert(0, from)
		gps_path.append(goal)


func map_scale() -> float:
	if player != null and player.driving_vehicle != null:
		return 0.36 + 0.14 * clampf(1.0 - absf(player.driving_vehicle.speed) / 22.0, 0.0, 1.0)
	return 0.55


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.18, 0.21, 0.88), true)
	if player == null:
		return
	var here := _position()
	var center := Vector2(here.x, here.z)
	var map_center := size * 0.5
	var scale := map_scale()
	var bounds := Rect2(Vector2.ZERO, size)
	var road_color := Color("d9ccaa")
	if road_network != null:
		var reach := size.length() / scale
		for road in road_network.roads:
			var points: PackedVector3Array = road["points"]
			var first := points[0]
			if Vector2(first.x - center.x, first.z - center.y).length() > reach + 250.0:
				continue
			var line := PackedVector2Array()
			for p in points:
				line.append(_to_map(Vector2(p.x, p.z), center, map_center, scale))
			if road["driveable"]:
				draw_polyline(line, road_color, maxf(2.0, float(road["width"]) * scale * 0.9))
			else:
				draw_polyline(line, Color(0.85, 0.8, 0.7, 0.45), 1.5)
	if waypoint_path.size() >= 2:
		var detour := PackedVector2Array()
		for p in waypoint_path:
			detour.append(_to_map(Vector2(p.x, p.z), center, map_center, scale))
		draw_polyline(detour, Color(0.1, 0.05, 0.12, 0.6), 6.0)
		draw_polyline(detour, Color("c77dff"), 3.5)
	if waypoint != Vector3.INF:
		var flag := _edge_clamp(_to_map(Vector2(waypoint.x, waypoint.z), center, map_center, scale), 9.0)
		draw_circle(flag, 6.5, Color(0.05, 0.05, 0.05, 0.85))
		draw_circle(flag, 5.0, Color("c77dff"))
	if gps_path.size() >= 2:
		var route := PackedVector2Array()
		for p in gps_path:
			route.append(_to_map(Vector2(p.x, p.z), center, map_center, scale))
		draw_polyline(route, Color(0.1, 0.08, 0.02, 0.6), 6.0)
		draw_polyline(route, GPS_COLOR, 3.5)
	if workshop_marker != Vector2.INF:
		var shop_pos := _to_map(workshop_marker, center, map_center, scale)
		if bounds.has_point(shop_pos):
			draw_circle(shop_pos, 6.0, Color("6fd4a4"))
			draw_line(shop_pos + Vector2(-3, 0), shop_pos + Vector2(3, 0), Color("183b36"), 2.0)
	for kind in venue_markers:
		var venue_pos := _to_map(venue_markers[kind], center, map_center, scale)
		if bounds.has_point(venue_pos):
			var marker_color := Color("63b5e3") if kind == "supermarket" else Color("ecaa73") if kind in ["restaurant", "cafe", "palm_restaurant"] else Color("d7c46e") if kind == "bank" else Color("d89cc9")
			draw_circle(venue_pos, 5.0, marker_color)
	var font := ThemeDB.fallback_font
	for offer in offers:
		var p: Vector3 = offer["position"]
		var at := _edge_clamp(_to_map(Vector2(p.x, p.z), center, map_center, scale), 10.0)
		draw_circle(at, 9.0, Color(0.05, 0.05, 0.05, 0.85))
		draw_circle(at, 7.5, offer["color"])
		draw_string(font, at + Vector2(-5, 5), str(offer["letter"]), HORIZONTAL_ALIGNMENT_CENTER, 10, 13, Color(0.08, 0.08, 0.08))
	if mission != null and not mission.completed:
		var goal := mission.marker_position()
		if goal != Vector3.INF:
			var raw := _to_map(Vector2(goal.x, goal.z), center, map_center, scale)
			if bounds.grow(-8.0).has_point(raw):
				draw_circle(raw, 7.5, Color(0.05, 0.05, 0.05, 0.85))
				draw_circle(raw, 6.0, OBJECTIVE_COLOR)
			else:
				var at := _edge_clamp(raw, 9.0)
				var dir := (raw - map_center).normalized()
				var side := Vector2(-dir.y, dir.x)
				draw_colored_polygon(PackedVector2Array([at + dir * 8.0, at - dir * 5.0 + side * 6.0, at - dir * 5.0 - side * 6.0]), OBJECTIVE_COLOR)
	if wanted != null:
		var blink := int(Time.get_ticks_msec() / 250) % 2 == 0
		for car in wanted.police_cars:
			if is_instance_valid(car):
				var police_pos := _to_map(Vector2(car.global_position.x, car.global_position.z), center, map_center, scale)
				if bounds.has_point(police_pos):
					draw_circle(police_pos, 5.0, Color("e0504a") if blink else Color("4a7be0"))
	var forward := -player.camera.global_transform.basis.z if player.camera != null else Vector3.FORWARD
	var heading := Vector2(forward.x, forward.z).normalized() if Vector2(forward.x, forward.z).length() > 0.01 else Vector2.UP
	var across := Vector2(-heading.y, heading.x)
	var tip := map_center + heading * 9.0
	draw_colored_polygon(PackedVector2Array([tip, map_center - heading * 6.0 + across * 6.5, map_center - heading * 3.0, map_center - heading * 6.0 - across * 6.5]), Color("61d0d7"))
	draw_rect(bounds, Color("99c5be"), false, 2.0)


func _edge_clamp(p: Vector2, inset: float) -> Vector2:
	var inner := Rect2(Vector2.ONE * inset, size - Vector2.ONE * inset * 2.0)
	if inner.has_point(p):
		return p
	var c := size * 0.5
	var d := p - c
	var t := 1.0
	if absf(d.x) > 0.001:
		t = minf(t, (inner.size.x * 0.5) / absf(d.x))
	if absf(d.y) > 0.001:
		t = minf(t, (inner.size.y * 0.5) / absf(d.y))
	return c + d * t


func _to_map(world_point: Vector2, center: Vector2, map_center: Vector2, scale: float) -> Vector2:
	return map_center + Vector2(world_point.x - center.x, world_point.y - center.y) * scale
