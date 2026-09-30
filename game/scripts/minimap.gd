class_name DistrictMinimap
extends Control

var player: PlayerController
var mission: MissionController
var wanted: WantedSystem
var road_network: RoadNetwork
var workshop_marker := Vector2.INF
var venue_markers: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(186, 186)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


var redraw_timer := 0.0


func _process(delta: float) -> void:
	redraw_timer -= delta
	if redraw_timer <= 0.0:  # 15 Hz is plenty for a minimap with hundreds of streets
		redraw_timer = 1.0 / 15.0
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.18, 0.21, 0.88), true)
	if player == null:
		return
	var center := Vector2(player.global_position.x, player.global_position.z)
	var map_center := size * 0.5
	var scale := 0.55
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
	if mission != null:
		var marker := mission.active_marker()
		if marker.size() == 2:
			var marker_pos := _to_map(Vector2(float(marker[0]), float(marker[1])), center, map_center, scale)
			if Rect2(Vector2.ZERO, size).has_point(marker_pos):
				draw_circle(marker_pos, 6.0, Color("efb65f"))
	if workshop_marker != Vector2.INF:
		var shop_pos := _to_map(workshop_marker, center, map_center, scale)
		if Rect2(Vector2.ZERO, size).has_point(shop_pos):
			draw_circle(shop_pos, 6.0, Color("6fd4a4"))
			draw_line(shop_pos + Vector2(-3, 0), shop_pos + Vector2(3, 0), Color("183b36"), 2.0)
	for kind in venue_markers:
		var venue_pos := _to_map(venue_markers[kind], center, map_center, scale)
		if Rect2(Vector2.ZERO, size).has_point(venue_pos):
			var marker_color := Color("63b5e3") if kind == "supermarket" else Color("ecaa73") if kind in ["restaurant", "cafe", "palm_restaurant"] else Color("d7c46e") if kind == "bank" else Color("d89cc9")
			draw_circle(venue_pos, 5.5, marker_color)
	if wanted != null:
		var blink := int(Time.get_ticks_msec() / 250) % 2 == 0
		for car in wanted.police_cars:
			if is_instance_valid(car):
				var police_pos := _to_map(Vector2(car.global_position.x, car.global_position.z), center, map_center, scale)
				if Rect2(Vector2.ZERO, size).has_point(police_pos):
					draw_circle(police_pos, 5.0, Color("e0504a") if blink else Color("4a7be0"))
	draw_circle(map_center, 6.0, Color("61d0d7"))
	draw_rect(Rect2(Vector2.ZERO, size), Color("99c5be"), false, 2.0)


func _to_map(world_point: Vector2, center: Vector2, map_center: Vector2, scale: float) -> Vector2:
	return map_center + Vector2(world_point.x - center.x, world_point.y - center.y) * scale
