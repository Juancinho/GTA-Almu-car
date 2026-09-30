class_name WorldMap
extends Control

## Full-screen map (M): the real coastline, parks, building footprints and every
## street with its name (OSM, ODbL), mission contacts, services, the current
## objective and the player. Click to set a waypoint (the minimap then draws a
## purple GPS route to it); right-click clears it. Wheel zooms, drag or WASD pans.

const SEA := Color("1b4a5c")
const LAND := Color("2b3833")
const PARK := Color("365a40")
const BEACH := Color("7c7358")
const BUILDING := Color("46544e")
const ROAD := Color("dccfad")
const LANE := Color(0.62, 0.6, 0.52, 0.8)
const WAYPOINT := Color("c77dff")

var world: SectorWorld
var mission: MissionController
var player: PlayerController
var minimap: DistrictMinimap
var zoom := 0.9  # pixels per metre
var center := Vector2.ZERO  # world x/z shown at the middle of the screen
var land := PackedVector2Array()
var land_triangles := PackedInt32Array()
var parks: Array = []  # [PackedVector2Array, PackedInt32Array]
var buildings: Array = []
var labels: Array = []  # [name, Vector2 position, angle, length]
var dragging := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func configure(target_world: SectorWorld, target_mission: MissionController, target_player: PlayerController, target_minimap: DistrictMinimap) -> void:
	world = target_world
	mission = target_mission
	player = target_player
	minimap = target_minimap
	var raw: Dictionary = world.data.raw
	var coast: Array = raw.get("coast", [])
	if coast.size() >= 2:
		for p in coast:
			land.append(Vector2(float(p[0]), float(p[1])))
		var north := float(raw["bounds"][1]) - 400.0
		land.append(Vector2(land[land.size() - 1].x, north))
		land.append(Vector2(land[0].x, north))
		land_triangles = Geometry2D.triangulate_polygon(land)
	for park in raw.get("parks", []):
		var polygon := PackedVector2Array()
		for p in park["polygon"]:
			polygon.append(Vector2(float(p[0]), float(p[1])))
		var tris := Geometry2D.triangulate_polygon(polygon)
		if not tris.is_empty():
			parks.append([polygon, tris])
	for b in raw.get("buildings", []):
		var polygon := PackedVector2Array()
		for p in b["footprint"]:
			polygon.append(Vector2(float(p[0]), float(p[1])))
		var tris := Geometry2D.triangulate_polygon(polygon)
		if not tris.is_empty():
			buildings.append([polygon, tris])
	# One label per street name, at the middle of its longest way.
	var best: Dictionary = {}
	for road in world.road_network.roads:
		var road_name := str(road["name"])
		var points: PackedVector3Array = road["points"]
		if road_name == "" or points.size() < 2:
			continue
		var total := 0.0
		for i in range(points.size() - 1):
			total += Vector2(points[i].x - points[i + 1].x, points[i].z - points[i + 1].z).length()
		if total <= float(best.get(road_name, [null, null, null, 0.0])[3]):
			continue
		var walked := 0.0
		for i in range(points.size() - 1):
			var a := Vector2(points[i].x, points[i].z)
			var b := Vector2(points[i + 1].x, points[i + 1].z)
			walked += a.distance_to(b)
			if walked >= total * 0.5:
				var angle := (b - a).angle()
				if angle > PI * 0.5:
					angle -= PI
				elif angle < -PI * 0.5:
					angle += PI
				best[road_name] = [road_name, (a + b) * 0.5, angle, total]
				break
	labels = best.values()


func open() -> void:
	center = Vector2(player.global_position.x, player.global_position.z)
	visible = true
	queue_redraw()


func close() -> void:
	visible = false
	dragging = false


func to_screen(p: Vector2) -> Vector2:
	return size * 0.5 + (p - center) * zoom


func to_world(screen: Vector2) -> Vector2:
	return center + (screen - size * 0.5) / zoom


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(button.position, 1.15)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(button.position, 1.0 / 1.15)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			var w := to_world(button.position)
			minimap.set_waypoint(Vector3(w.x, world.height_at(w.x, w.y), w.y))
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			minimap.set_waypoint(Vector3.INF)
		elif button.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = true
		queue_redraw()
	elif event is InputEventMouseButton and not event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE:
		dragging = false
	elif event is InputEventMouseMotion and (dragging or ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0):
		center -= (event as InputEventMouseMotion).relative / zoom
		queue_redraw()


func _zoom_at(screen: Vector2, factor: float) -> void:
	var before := to_world(screen)
	zoom = clampf(zoom * factor, 0.25, 6.0)
	center += before - to_world(screen)


func _process(delta: float) -> void:
	if not visible:
		return
	var pan := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if pan.length() > 0.05:
		center += pan * 500.0 / zoom * delta
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), SEA, true)
	var font := ThemeDB.fallback_font
	if not land_triangles.is_empty():
		_fill(land, land_triangles, LAND)
	for park in parks:
		_fill(park[0], park[1], PARK)
	var view := Rect2(to_world(Vector2.ZERO), size / zoom)
	for b in buildings:
		var polygon: PackedVector2Array = b[0]
		if view.has_point(polygon[0]):
			_fill(polygon, b[1], BUILDING)
	for road in world.road_network.roads:
		var line := PackedVector2Array()
		for p in road["points"]:
			line.append(to_screen(Vector2(p.x, p.z)))
		if road["driveable"]:
			draw_polyline(line, ROAD, maxf(1.5, float(road["width"]) * zoom * 0.8))
		else:
			draw_polyline(line, LANE, maxf(1.0, 2.0 * zoom * 0.6))
	if zoom >= 0.5:
		var size_px := 11 if zoom < 1.5 else 13
		for label in labels:
			var at := to_screen(label[1])
			if not Rect2(Vector2.ZERO, size).has_point(at) or float(label[3]) * zoom < 90.0:
				continue
			var text := str(label[0])
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
			draw_set_transform(at, float(label[2]), Vector2.ONE)
			draw_string_outline(font, Vector2(-width * 0.5, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 4, Color(0.08, 0.1, 0.1, 0.9))
			draw_string(font, Vector2(-width * 0.5, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color("f4ecd8"))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_services(font)
	var route := minimap.waypoint_path if minimap != null else PackedVector3Array()
	if route.size() >= 2:
		var line := PackedVector2Array()
		for p in route:
			line.append(to_screen(Vector2(p.x, p.z)))
		draw_polyline(line, WAYPOINT, 4.0)
	if minimap != null and minimap.gps_path.size() >= 2:
		var line := PackedVector2Array()
		for p in minimap.gps_path:
			line.append(to_screen(Vector2(p.x, p.z)))
		draw_polyline(line, DistrictMinimap.GPS_COLOR, 4.0)
	for offer in mission.offers():
		var p: Vector3 = offer["position"]
		var at := to_screen(Vector2(p.x, p.z))
		draw_circle(at, 12.0, Color(0.05, 0.05, 0.05, 0.9))
		draw_circle(at, 10.0, offer["color"])
		draw_string(font, at + Vector2(-6, 6), str(offer["letter"]), HORIZONTAL_ALIGNMENT_CENTER, 12, 16, Color(0.08, 0.08, 0.08))
		draw_string_outline(font, at + Vector2(16, 5), str(offer["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
		draw_string(font, at + Vector2(16, 5), str(offer["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, offer["color"])
	if not mission.completed:
		var goal := mission.marker_position()
		if goal != Vector3.INF:
			var at := to_screen(Vector2(goal.x, goal.z))
			draw_circle(at, 11.0, Color(0.05, 0.05, 0.05, 0.9))
			draw_circle(at, 9.0, DistrictMinimap.OBJECTIVE_COLOR)
	if minimap != null and minimap.waypoint != Vector3.INF:
		var at := to_screen(Vector2(minimap.waypoint.x, minimap.waypoint.z))
		draw_line(at, at + Vector2(0, -22), Color.WHITE, 2.0)
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -22), at + Vector2(14, -17), at + Vector2(0, -12)]), WAYPOINT)
	var here := player.driving_vehicle.global_position if player.driving_vehicle != null else player.global_position
	var me := to_screen(Vector2(here.x, here.z))
	var forward := -player.camera.global_transform.basis.z
	var heading := Vector2(forward.x, forward.z).normalized() if Vector2(forward.x, forward.z).length() > 0.01 else Vector2.UP
	var across := Vector2(-heading.y, heading.x)
	draw_colored_polygon(PackedVector2Array([me + heading * 13.0, me - heading * 8.0 + across * 9.0, me - heading * 4.0, me - heading * 8.0 - across * 9.0]), Color("61d0d7"))
	_draw_legend(font)


func _draw_services(font: Font) -> void:
	var services: Array = []
	for kind in world.venues:
		var venue := world.venues[kind] as VenueInterior
		services.append([venue.exterior_entry, str(VenueInterior.SPECS[kind].get("sign", kind)).get_slice("·", 0).strip_edges(), Color("63b5e3")])
	services.append([world.workshop.exterior_entry, "TALLER PONIENTE", Color("6fd4a4")])
	services.append([world.anchor("hospital"), "CENTRO DE SALUD", Color("e0645a")])
	for bar in world.beach_bars:
		services.append([bar.global_position, bar.bar_name, Color("ecaa73")])
	for service in services:
		var at := to_screen(Vector2((service[0] as Vector3).x, (service[0] as Vector3).z))
		if not Rect2(Vector2.ZERO, size).has_point(at):
			continue
		draw_circle(at, 6.0, Color(0.05, 0.05, 0.05, 0.9))
		draw_circle(at, 4.5, service[2])
		if zoom >= 1.1:
			draw_string_outline(font, at + Vector2(9, 4), str(service[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0, 0, 0, 0.9))
			draw_string(font, at + Vector2(9, 4), str(service[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, (service[2] as Color).lightened(0.3))


func _draw_legend(font: Font) -> void:
	var box := Rect2(Vector2(20, size.y - 132), Vector2(430, 112))
	draw_rect(box, Color(0.05, 0.12, 0.14, 0.85), true)
	var lines := [
		"MAPA DE ALMUÑÉCAR",
		"Letras: misiones disponibles · Amarillo: objetivo actual",
		"Clic: marcar destino (ruta morada) · Clic dcho.: quitarlo",
		"Rueda: zoom · WASD o arrastrar: mover · M / Esc: cerrar",
		"Map data © OpenStreetMap contributors · ODbL",
	]
	for i in range(lines.size()):
		draw_string(font, box.position + Vector2(14, 24 + i * 19), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15 if i == 0 else 13, Color("f2c14e") if i == 0 else Color("e6e0cf"))


func _fill(polygon: PackedVector2Array, triangles: PackedInt32Array, color: Color) -> void:
	var points := PackedVector2Array()
	points.resize(polygon.size())
	for i in range(polygon.size()):
		points[i] = to_screen(polygon[i])
	for i in range(0, triangles.size(), 3):
		draw_primitive(PackedVector2Array([points[triangles[i]], points[triangles[i + 1]], points[triangles[i + 2]]]), PackedColorArray([color, color, color]), PackedVector2Array())
