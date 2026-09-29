class_name DistrictMinimap
extends Control

var player: PlayerController
var mission: MissionController


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
	for x in [-168.0, -55.0, 58.0, 170.0]:
		var a := _to_map(Vector2(x, -212), center, map_center, scale)
		var b := _to_map(Vector2(x, 48), center, map_center, scale)
		draw_line(a, b, road_color, 5.0)
	for z in [8.0, -78.0, -158.0]:
		var a := _to_map(Vector2(-285, z), center, map_center, scale)
		var b := _to_map(Vector2(285, z), center, map_center, scale)
		draw_line(a, b, road_color, 5.0)
	if mission != null and not mission.completed and not mission.objectives.is_empty():
		var objective := mission.objectives[mission.stage]
		var marker := objective.get("marker", [0, 0]) as Array
		var marker_pos := _to_map(Vector2(float(marker[0]), float(marker[1])), center, map_center, scale)
		if Rect2(Vector2.ZERO, size).has_point(marker_pos):
			draw_circle(marker_pos, 6.0, Color("efb65f"))
	draw_circle(map_center, 6.0, Color("61d0d7"))
	draw_rect(Rect2(Vector2.ZERO, size), Color("99c5be"), false, 2.0)


func _to_map(world_point: Vector2, center: Vector2, map_center: Vector2, scale: float) -> Vector2:
	return map_center + Vector2(world_point.x - center.x, world_point.y - center.y) * scale
