class_name DistrictMinimap
extends Control

var player: PlayerController
var mission: MissionController
var wanted: WantedSystem
var road_network: RoadNetwork


func _ready() -> void:
	custom_minimum_size = Vector2(186, 186)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.18, 0.21, 0.88), true)
	if player == null:
		return
	var center := Vector2(player.global_position.x, player.global_position.z)
	var map_center := size * 0.5
	var scale := 0.74
	var road_color := Color("d9ccaa")
	if road_network != null:
		for road in road_network.roads:
			var fixed := float(road["fixed"])
			var from := Vector2(float(road["from"]), fixed) if str(road["axis"]) == "x" else Vector2(fixed, float(road["from"]))
			var to := Vector2(float(road["to"]), fixed) if str(road["axis"]) == "x" else Vector2(fixed, float(road["to"]))
			draw_line(_to_map(from, center, map_center, scale), _to_map(to, center, map_center, scale), road_color, 5.0)
	if mission != null and not mission.completed and not mission.objectives.is_empty():
		var objective := mission.objectives[mission.stage]
		var marker := objective.get("marker", [0, 0]) as Array
		var marker_pos := _to_map(Vector2(float(marker[0]), float(marker[1])), center, map_center, scale)
		if Rect2(Vector2.ZERO, size).has_point(marker_pos):
			draw_circle(marker_pos, 6.0, Color("efb65f"))
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
