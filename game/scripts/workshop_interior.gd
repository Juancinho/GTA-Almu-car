class_name WorkshopInterior
extends Node3D

signal repair_requested

const BUILDING_ID := 1388939169
const FRONT_EDGE := 1
const ROOM_ORIGIN := Vector3(0, 1000, 0)
const DisplayCar = preload("res://assets/procedural/compact_car.glb")

var exterior_entry := Vector3.ZERO
var exterior_normal := Vector3.ZERO
var inside_entry := ROOM_ORIGIN + Vector3(0, 0.2, 6.3)
var service_point := ROOM_ORIGIN + Vector3(3.4, 0.2, -2.6)
var source_building_id := 0


func configure(data: SectorData, mats: SectorMaterials) -> bool:
	for building in data.raw["buildings"]:
		if int(building["id"]) != BUILDING_ID:
			continue
		var footprint: Array = building["footprint"]
		var a := Vector2(float(footprint[FRONT_EDGE][0]), float(footprint[FRONT_EDGE][1]))
		var b := Vector2(float(footprint[(FRONT_EDGE + 1) % footprint.size()][0]), float(footprint[(FRONT_EDGE + 1) % footprint.size()][1]))
		var edge := b - a
		exterior_normal = Vector3(edge.y, 0, -edge.x).normalized()
		var mid := (a + b) * 0.5
		var entry_xz := Vector3(mid.x, 0, mid.y) + exterior_normal * 1.65
		exterior_entry = Vector3(entry_xz.x, data.height_at(entry_xz.x, entry_xz.z) + 0.2, entry_xz.z)
		source_building_id = BUILDING_ID
		_make_exterior_sign(mid, data, mats)
		_make_room(mats)
		add_to_group("interiors")
		return true
	push_error("Taller Poniente building %d missing from sector" % BUILDING_ID)
	return false


func try_interact(player: PlayerController) -> bool:
	if player.driving_vehicle != null:
		return false
	if player.global_position.distance_to(exterior_entry) < 3.0:
		player.global_position = inside_entry
		player.velocity = Vector3.ZERO
		return true
	if player.global_position.distance_to(inside_entry) < 2.8:
		player.global_position = exterior_entry + exterior_normal * 0.4
		player.velocity = Vector3.ZERO
		return true
	if player.global_position.distance_to(service_point) < 2.8:
		repair_requested.emit()
		return true
	return false


func _make_exterior_sign(mid: Vector2, data: SectorData, mats: SectorMaterials) -> void:
	var at := Vector3(mid.x, data.height_at(mid.x, mid.y) + 2.8, mid.y) + exterior_normal * 0.08
	var panel := MeshInstance3D.new()
	panel.name = "TallerPonienteSign"
	var board := BoxMesh.new()
	board.size = Vector3(4.6, 0.8, 0.18)
	panel.mesh = board
	panel.position = at
	panel.rotation.y = atan2(exterior_normal.x, exterior_normal.z)
	panel.material_override = mats.textured("workshop_sign", "asphalt010", Color("243b41"), 0.7, 0.85)
	add_child(panel)
	var letters := Label3D.new()
	letters.name = "TallerPonienteLetters"
	letters.text = "TALLER PONIENTE"
	letters.font_size = 42
	letters.pixel_size = 0.0065
	letters.modulate = Color("f2e4b9")
	letters.outline_size = 5
	letters.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	letters.position = at + exterior_normal * 0.14
	add_child(letters)


func _make_room(mats: SectorMaterials) -> void:
	var floor_mat := mats.textured("workshop_floor", "tiles040", Color("aeb1ac"), 2.0, 0.88)
	var wall_mat := mats.textured("workshop_walls", "plaster003", Color("ddd9cc"), 2.5, 0.9)
	var metal := mats.textured("workshop_metal", "asphalt010", Color("697b80"), 0.75, 0.58)
	var dark := mats.textured("workshop_dark", "asphalt010", Color("252c30"), 0.55, 0.7)
	var bench := mats.textured("workshop_bench", "rock020", Color("968f80"), 1.2, 0.8)
	_box("Floor", Vector3(14, 0.4, 18), ROOM_ORIGIN + Vector3(0, -0.2, 0), floor_mat, true)
	_box("Ceiling", Vector3(14, 0.35, 18), ROOM_ORIGIN + Vector3(0, 4.5, 0), wall_mat, true)
	_box("LeftWall", Vector3(0.35, 4.5, 18), ROOM_ORIGIN + Vector3(-7, 2.25, 0), wall_mat, true)
	_box("RightWall", Vector3(0.35, 4.5, 18), ROOM_ORIGIN + Vector3(7, 2.25, 0), wall_mat, true)
	_box("BackWall", Vector3(14, 4.5, 0.35), ROOM_ORIGIN + Vector3(0, 2.25, -9), wall_mat, true)
	_box("FrontWall", Vector3(14, 4.5, 0.35), ROOM_ORIGIN + Vector3(0, 2.25, 9), wall_mat, true)
	# The service bay and retail counter use separate textured surfaces and solid
	# collision, so this is a navigable room with a clear return path.
	_box("ServiceCounter", Vector3(4.6, 1.0, 0.85), ROOM_ORIGIN + Vector3(3.4, 0.5, -3.6), bench, true)
	_box("CounterTop", Vector3(4.8, 0.1, 1.0), ROOM_ORIGIN + Vector3(3.4, 1.05, -3.6), metal)
	for side in [-1.0, 1.0]:
		_box("LiftPost", Vector3(0.28, 2.9, 0.34), ROOM_ORIGIN + Vector3(-3.3 + side * 1.55, 1.45, -2.2), metal)
		_box("LiftArm", Vector3(1.5, 0.16, 0.3), ROOM_ORIGIN + Vector3(-3.3 + side * 0.8, 0.45, -2.2), dark)
	var service_car := DisplayCar.instantiate() as Node3D
	service_car.name = "CarOnLift"
	service_car.position = ROOM_ORIGIN + Vector3(-3.3, 0.65, -2.2)
	add_child(service_car)
	for shelf in range(3):
		_box("PartsShelf", Vector3(3.7, 0.13, 0.6), ROOM_ORIGIN + Vector3(5.7, 0.75 + shelf * 0.95, 2.0), metal)
	for cabinet in range(3):
		_box("ToolCabinet", Vector3(0.9, 1.7, 0.6), ROOM_ORIGIN + Vector3(-5.8 + cabinet * 1.1, 0.85, -7.9), metal, true)
		_box("CabinetHandle", Vector3(0.48, 0.08, 0.08), ROOM_ORIGIN + Vector3(-5.8 + cabinet * 1.1, 1.0, -7.55), dark)
	_box("ToolBoard", Vector3(3.3, 1.7, 0.12), ROOM_ORIGIN + Vector3(4.2, 2.3, -8.75), dark)
	for tool in range(7):
		_box("HangingTool", Vector3(0.07, 0.5 + 0.12 * (tool % 3), 0.09), ROOM_ORIGIN + Vector3(2.9 + tool * 0.4, 2.2, -8.65), metal)
	for tire in range(3):
		var wheel := MeshInstance3D.new()
		wheel.name = "SpareTire_%d" % tire
		var torus := TorusMesh.new()
		torus.inner_radius = 0.28
		torus.outer_radius = 0.52
		wheel.mesh = torus
		wheel.position = ROOM_ORIGIN + Vector3(-5.5 + tire * 0.95, 0.53, -6.4)
		wheel.rotation.x = PI * 0.5
		wheel.material_override = dark
		add_child(wheel)
	var mechanic := HumanModel.new("male_casual")
	mechanic.name = "Mechanic"
	mechanic.position = ROOM_ORIGIN + Vector3(3.4, 0, -4.8)
	mechanic.rotation.y = PI
	add_child(mechanic)
	for light_x in [-3.5, 3.5]:
		var light := OmniLight3D.new()
		light.name = "WorkshopLight"
		light.position = ROOM_ORIGIN + Vector3(light_x, 3.9, 0)
		light.light_color = Color("fff1d7")
		light.light_energy = 1.8
		light.omni_range = 13.0
		add_child(light)
	var exit_label := Label3D.new()
	exit_label.text = "SALIDA  ·  E"
	exit_label.font_size = 46
	exit_label.pixel_size = 0.007
	exit_label.position = ROOM_ORIGIN + Vector3(0, 2.5, 8.7)
	exit_label.rotation.y = PI
	add_child(exit_label)
	var service_label := Label3D.new()
	service_label.text = "REPARAR COCHE  ·  75 €  ·  E"
	service_label.font_size = 58
	service_label.pixel_size = 0.011
	service_label.outline_size = 6
	service_label.position = ROOM_ORIGIN + Vector3(3.4, 2.0, -3.0)
	add_child(service_label)


func _box(label: String, size: Vector3, at: Vector3, material: Material, solid: bool = false) -> void:
	var visual := MeshInstance3D.new()
	visual.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = at
	visual.material_override = material
	add_child(visual)
	if solid:
		var body := StaticBody3D.new()
		body.name = label + "Collision"
		body.position = at
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		add_child(body)
