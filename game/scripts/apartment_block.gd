extends Node3D

## A residential block you can walk into from the street: marble lobby with
## mailboxes and a conserje, a switchback stair (real ramps under the steps, so
## people and bodies stay on them) serving every floor, a lift that jumps between
## the portal and the block's key floor, landings with the neighbours' doors and,
## where the catalog says so, a furnished flat: the player's safehouse (bed = save
## and rest, wardrobe = weapon stash) or Ferrer's penthouse (safe for the mission).
## Local frame: +Z faces the street, the façade is z = 0, the lobby floor y = 0.
## Only the floors next to the player are drawn (and lit) while inside.

signal action_requested(block_id: String, action: String)

const Catalog = preload("res://scripts/apartment_catalog.gd")
const VehicleScript = preload("res://scripts/vehicle.gd")
const HALF_W := 4.5
const DEPTH := 15.0
const FH := 3.1
const SLAB := 0.22
const STAIR_FRONT := -8.5  # the stair well opens onto each landing here
const STAIR_BACK := -12.9  # half-landing edge
const FLIGHT_A := 1.45  # centre x of the up-going flight (towards the back)
const FLIGHT_B := 3.55  # centre x of the return flight
const FLIGHT_W := 1.9
const LIFT := Vector3(-3.4, 0, -12.2)  # where you stand to call the lift
const PARTITION_Z := -6.5  # flats occupy the street side of their floor
const FLAT_DOOR_X := -2.0

var block_id := ""
var spec: Dictionary = {}
var levels := 1
var display_name := ""
var exterior_entry := Vector3.ZERO
var exterior_normal := Vector3.ZERO
var level_nodes: Array[Node3D] = []
var shell: Node3D
var points := {}  # name -> local Vector3 (interaction spots, guard posts)
var body: StaticBody3D
var mats: SectorMaterials
var _gate_timer := 0.0
var _holding_player := false
var garage_spot := Vector3.INF  # safehouse garage: a car left here is kept in the save
var garage_yaw := 0.0
var garage_variant := ""
var garage_car: DriveableVehicle
var burgled := {}  # door title -> msec when it can be forced again
const BURGLE_COOLDOWN_MS := 600000
var _materials := {}


func configure(value: String, data: SectorData, materials: SectorMaterials) -> bool:
	if not Catalog.SPECS.has(value):
		push_error("Apartment block not configured: " + value)
		return false
	block_id = value
	spec = Catalog.SPECS[value]
	mats = materials
	var frame := Catalog.frame(data, spec)
	if frame.is_empty():
		push_error("Apartment block %s: building %d missing" % [value, spec["building_id"]])
		return false
	levels = int(spec["levels"])
	display_name = str(spec["name"])
	position = frame["origin"]
	rotation.y = float(frame["angle"])
	exterior_normal = frame["normal"]
	exterior_entry = frame["outside"]
	body = StaticBody3D.new()
	body.name = "BlockCollision"
	add_child(body)
	_make_materials()
	shell = Node3D.new()
	shell.name = "Shell"
	add_child(shell)
	_build_shell(float(frame["pavement"]) - float(frame["floor_y"]))
	for k in range(levels):
		var node := Node3D.new()
		node.name = "Level_%d" % k
		add_child(node)
		level_nodes.append(node)
		_build_level(k, node)
	if spec.has("garage"):
		_build_garage(data, spec["garage"])
	add_to_group("interiors")
	add_to_group("apartment_blocks")
	return true


# --- Queries --------------------------------------------------------------------

func contains_player(at: Vector3) -> bool:
	var local := to_local(at)
	return absf(local.x) < HALF_W and local.z > -DEPTH and local.z < 0.05 and local.y > -0.6 and local.y < levels * FH + 0.5


func level_at(at: Vector3) -> int:
	return clampi(int(floor((to_local(at).y + 0.8) / FH)), 0, levels - 1)


## World position of a named spot ("safe", "bed", "guard_1", "portal"...).
func point(name: String) -> Vector3:
	if name == "portal" or not points.has(name):
		return exterior_entry
	return to_global(points[name])


func location_text(at: Vector3) -> String:
	var k := level_at(at)
	if k == 0:
		return "%s · Portal" % display_name
	if k == int(spec.get("penthouse_floor", -1)):
		return "%s · Ático" % display_name
	return "%s · Planta %d" % [display_name, k]


func _near(player: PlayerController, name: String, radius: float = 1.5) -> bool:
	if not points.has(name) or not contains_player(player.global_position):
		return false
	var local := to_local(player.global_position)
	var p: Vector3 = points[name]
	return absf(local.y - p.y) < 1.2 and Vector2(local.x - p.x, local.z - p.z).length() < radius


func _lift_target(from_level: int) -> int:
	return int(spec.get("lift_floor", levels - 1)) if from_level == 0 else 0


func prompt_text(player: PlayerController) -> String:
	if player.driving_vehicle != null or not contains_player(player.global_position):
		return ""
	var k := level_at(player.global_position)
	if _near(player, "lift_%d" % k):
		var target := _lift_target(k)
		return "E · Ascensor: bajar al portal" if target == 0 else "E · Ascensor: subir a la planta %d" % target
	if _near(player, "bed"):
		return "E · Dormir (guarda la partida y recupera la salud)"
	if _near(player, "stash"):
		return "E · Armario: coger el alijo (pistola y munición)"
	if _near(player, "safe", 1.3):
		return "E · Abrir la caja fuerte"
	if _near(player, "office_safe", 1.3):
		return "E · Reventar la caja de la constructora (botín · alarma 2★)" if can_burgle("office_safe") else "La caja está vacía. Vuelve otro día."
	var door := _door_at(player)
	if door != "":
		return "Puerta forzada. Aquí ya no queda nada." if not can_burgle(door) else "E · Forzar la puerta del %s (robo en vivienda)" % door
	return ""


## Neighbours' doors can be forced for cash; someone may call the police.
func _door_at(player: PlayerController) -> String:
	for key in points:
		if str(key).begins_with("door:") and _near(player, str(key), 1.1):
			return str(key).trim_prefix("door:")
	return ""


func can_burgle(door: String) -> bool:
	return Time.get_ticks_msec() >= int(burgled.get(door, 0))


func mark_burgled(door: String) -> void:
	burgled[door] = Time.get_ticks_msec() + BURGLE_COOLDOWN_MS


func try_interact(player: PlayerController) -> bool:
	if player.driving_vehicle != null or not contains_player(player.global_position):
		return false
	var k := level_at(player.global_position)
	if _near(player, "lift_%d" % k):
		var target := _lift_target(k)
		player.global_position = to_global(Vector3(LIFT.x, target * FH + 0.15, LIFT.z + 0.6))
		player.velocity = Vector3.ZERO
		update_room_visibility(player.global_position)
		get_tree().call_group("mission_controller", "_show_dialogue", "Ascensor: %s." % ("portal" if target == 0 else "planta %d" % target))
		return true
	if _near(player, "office_safe", 1.3) and can_burgle("office_safe"):
		action_requested.emit(block_id, "heist")
		return true
	for action in ["bed", "stash", "safe"]:
		if _near(player, action, 1.3 if action == "safe" else 1.5):
			action_requested.emit(block_id, "sleep" if action == "bed" else action)
			return true
	var door := _door_at(player)
	if door != "" and can_burgle(door):
		action_requested.emit(block_id, "burgle:" + door)
		return true
	return false


# --- Room gating ----------------------------------------------------------------

func _process(delta: float) -> void:
	_gate_timer -= delta
	if _gate_timer > 0.0:
		return
	_gate_timer = 0.25
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player := players[0] as CharacterBody3D
	update_room_visibility(player.global_position)
	_update_garage(player as PlayerController)
	# On a stair flight against a wall Godot's floor_block_on_wall pins the body
	# in the crease; indoors there are no terrain walls to guard against.
	var inside := contains_player(player.global_position)
	if inside != _holding_player:
		_holding_player = inside
		player.floor_block_on_wall = not inside


func update_room_visibility(at: Vector3) -> void:
	var inside := contains_player(at)
	var near := at.distance_to(exterior_entry) < 55.0
	shell.visible = inside or near
	var current := level_at(at)
	for k in range(level_nodes.size()):
		level_nodes[k].visible = (inside and absi(k - current) <= 1) or (not inside and near and k == 0)


# --- Safehouse garage -----------------------------------------------------------

## A parking bay by the portal: any car left standing in it is "in the garage"
## and comes back after loading a save; driving it away frees the bay.
func _update_garage(player: PlayerController) -> void:
	if garage_spot == Vector3.INF:
		return
	if garage_car != null and (not is_instance_valid(garage_car) or garage_car.destroyed or _flat(garage_car.global_position, garage_spot) > 10.0):
		garage_car = null
		garage_variant = ""
	if garage_car != null or (player != null and player.driving_vehicle != null):
		return
	for node in get_tree().get_nodes_in_group("vehicles"):
		var car := node as DriveableVehicle
		if car == null or car.boat or car.destroyed or car.driver != null or car.traffic:
			continue
		if _flat(car.global_position, garage_spot) < 3.2 and absf(car.speed) < 0.5:
			garage_car = car
			garage_variant = car.variant
			get_tree().call_group("mission_controller", "_show_dialogue", "Coche guardado en el garaje del piso franco. Seguirá aquí al cargar la partida.")
			return


func restore_garage(variant: String) -> void:
	if variant == "" or garage_spot == Vector3.INF:
		return
	if garage_car != null and is_instance_valid(garage_car) and not garage_car.destroyed:
		return
	var car := VehicleScript.new() as DriveableVehicle
	car.name = "GarageCar_" + block_id
	car.variant = variant
	car.position = garage_spot + Vector3(0, 0.45, 0)
	car.rotation.y = garage_yaw
	get_parent().add_child(car)
	garage_car = car
	garage_variant = variant


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _build_garage(data: SectorData, offset: Array) -> void:
	var local := Vector3(float(offset[0]), 0, float(offset[1]))
	var world_xz := to_global(local)
	var ground := data.height_at(world_xz.x, world_xz.z)
	garage_spot = Vector3(world_xz.x, ground, world_xz.z)
	garage_yaw = rotation.y + PI * 0.5
	var top := ground
	for corner: Vector3 in [Vector3(-2.8, 0, -1.5), Vector3(2.8, 0, -1.5), Vector3(-2.8, 0, 1.5), Vector3(2.8, 0, 1.5)]:
		var c := to_global(local + corner)
		top = maxf(top, data.height_at(c.x, c.z))
	var lift := top - global_position.y + 0.19  # painted lines stay above the paving (it sits ~16 cm over the heightmap)
	var paint := mats.plain("garage_paint", Color("e8c547"), 0.7)
	for side: float in [-1.0, 1.0]:
		_box(shell, "GarageLine", Vector3(5.4, 0.03, 0.12), Vector3(local.x, lift, local.z + side * 1.4), paint)
		_box(shell, "GarageLine", Vector3(0.12, 0.03, 2.9), Vector3(local.x + side * 2.7, lift, local.z), paint)
	_box(shell, "GarageSignPole", Vector3(0.1, 2.4, 0.1), Vector3(local.x + 3.0, lift + 1.2, local.z - 1.6), _materials["metal"])
	_box(shell, "GarageSign", Vector3(1.3, 0.5, 0.06), Vector3(local.x + 3.0, lift + 2.3, local.z - 1.6), mats.plain("garage_sign", Color("1f4f7a"), 0.6))
	_label(shell, "GarageLabel", "GARAJE\nPISO FRANCO", Vector3(local.x + 3.0, lift + 2.3, local.z - 1.55), 0.0, Color("f4f1e6"), 0.0035)


# --- Construction ---------------------------------------------------------------

func _make_materials() -> void:
	var key := "block_" + block_id
	var luxe := spec.has("penthouse_floor")
	_materials = {
		"marble": mats.textured(key + "_marble", "tiles040", Color("efe9df") if luxe else Color("d9d2c4"), 0.9, 0.35),
		"floor": mats.textured(key + "_floor", "tiles040", Color("cfc6b6"), 1.2, 0.7),
		"stair": mats.textured(key + "_stair", "rock020", Color("e8e1d2"), 1.4, 0.6),
		"wall": mats.textured(key + "_wall", "plaster003", Color("efe8da") if luxe else Color("e7ddc9"), 2.4, 0.9),
		"dado": mats.plain(key + "_dado", Color("7c6a58") if luxe else Color("8f7d62"), 0.6),
		"wood": mats.textured(key + "_wood", "roofingtiles006", Color("7a5238"), 1.0, 0.7),
		"parquet": mats.textured(key + "_parquet", "pavingstones046", Color("b88a5e"), 0.8, 0.6),
		"metal": mats.plain(key + "_metal", Color("8d969b"), 0.35, 0.7),
		"dark": mats.plain(key + "_dark", Color("2b2f33"), 0.5, 0.4),
		"brass": mats.plain(key + "_brass", Color("c8a45a"), 0.3, 0.8),
		"fabric": mats.plain(key + "_fabric", Color("5d7482"), 0.95),
		"cream": mats.plain(key + "_cream", Color("e9e2d2"), 0.9),
		"leather": mats.plain(key + "_leather", Color("3b2a22"), 0.55),
		"green": mats.plain(key + "_green", Color("4f7a42"), 0.9),
		"pot": mats.plain(key + "_pot", Color("b0643c"), 0.8),
		"stone": mats.textured(key + "_stone", "rock020", Color("d9ccb2"), 1.6, 0.85),
		"window": _glow(key + "_window", Color("9ecbe2"), 0.55),
		"screen": _glow(key + "_screen", Color("5d8fb8"), 0.7),
		"lamp": _glow(key + "_lamp", Color("fff0cf"), 2.2),
	}


func _glow(key: String, color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = key
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


func _build_shell(ramp_drop: float) -> void:
	var top := levels * FH + 0.3
	var wall: Material = _materials["wall"]
	# Outer walls (the building's own façade shell is one-sided and seen from the street).
	_box(shell, "LeftWall", Vector3(0.2, top, DEPTH), Vector3(-HALF_W - 0.1, top * 0.5, -DEPTH * 0.5), wall, true)
	_box(shell, "RightWall", Vector3(0.2, top, DEPTH), Vector3(HALF_W + 0.1, top * 0.5, -DEPTH * 0.5), wall, true)
	_box(shell, "BackWall", Vector3(HALF_W * 2.0 + 0.4, top, 0.2), Vector3(0, top * 0.5, -DEPTH - 0.1), wall, true)
	var door := Catalog.DOOR_HALF
	var side_w := HALF_W - door
	_box(shell, "FrontWall", Vector3(side_w, top, 0.24), Vector3(-door - side_w * 0.5, top * 0.5, -0.14), wall, true)
	_box(shell, "FrontWall", Vector3(side_w, top, 0.24), Vector3(door + side_w * 0.5, top * 0.5, -0.14), wall, true)
	_box(shell, "FrontWall", Vector3(door * 2.0, top - Catalog.DOOR_HEIGHT, 0.24), Vector3(0, Catalog.DOOR_HEIGHT + (top - Catalog.DOOR_HEIGHT) * 0.5, -0.14), wall, true)
	_box(shell, "Roof", Vector3(HALF_W * 2.0 + 0.4, 0.3, DEPTH + 0.2), Vector3(0, top + 0.15, -DEPTH * 0.5), wall, true)
	# Stair well: side wall, the central divider between flights, lift shaft.
	_box(shell, "StairWall", Vector3(0.15, top, DEPTH + STAIR_FRONT), Vector3(0.425, top * 0.5, (STAIR_FRONT - DEPTH) * 0.5), wall, true)
	_box(shell, "StairDivider", Vector3(0.2, top, STAIR_FRONT - STAIR_BACK), Vector3(2.5, top * 0.5, (STAIR_FRONT + STAIR_BACK) * 0.5), wall, true)
	_box(shell, "LiftShaft", Vector3(0.15, top, 2.2), Vector3(-2.225, top * 0.5, -13.9), _materials["dark"], true)
	_box(shell, "LiftShaft", Vector3(2.35, top, 0.15), Vector3(-3.375, top * 0.5, -12.875), _materials["metal"], true)
	# Street side: stone door frame, the block's name and number, entrance ramp.
	var stone: Material = _materials["stone"]
	_box(shell, "PortalJamb", Vector3(0.3, Catalog.DOOR_HEIGHT, 0.3), Vector3(-door - 0.05, Catalog.DOOR_HEIGHT * 0.5, 0.05), stone)
	_box(shell, "PortalJamb", Vector3(0.3, Catalog.DOOR_HEIGHT, 0.3), Vector3(door + 0.05, Catalog.DOOR_HEIGHT * 0.5, 0.05), stone)
	_box(shell, "PortalLintel", Vector3(door * 2.0 + 0.7, 0.35, 0.34), Vector3(0, Catalog.DOOR_HEIGHT + 0.12, 0.06), stone)
	_box(shell, "PortalGlass", Vector3(0.05, Catalog.DOOR_HEIGHT - 0.1, 0.9), Vector3(-door + 0.1, (Catalog.DOOR_HEIGHT - 0.1) * 0.5, -0.5), _materials["dark"])  # open door leaf
	_box(shell, "PortalSign", Vector3(3.6, 0.34, 0.06), Vector3(0, Catalog.DOOR_HEIGHT + 0.13, 0.26), _materials["leather"])  # on the lintel, under any balcony
	var title := Label3D.new()
	title.name = "PortalName"
	title.text = "%s  ·  %s" % [str(spec["name"]).to_upper(), str(spec["number"])]
	title.font_size = 48
	title.pixel_size = 0.0042
	title.outline_size = 0
	title.modulate = Color("f2dca0")
	title.position = Vector3(0, Catalog.DOOR_HEIGHT + 0.13, 0.3)
	shell.add_child(title)
	if ramp_drop < -0.12:
		# The pavement is lower than the lobby: a short stone ramp with steps drawn on it.
		var run := clampf(-ramp_drop * 2.2, 0.8, 2.6)
		_ramp(shell, "EntranceRamp", Vector3(0, ramp_drop, run + 0.05), Vector3(0, 0, 0.02), door * 2.0 + 0.4, stone, int(ceil(-ramp_drop / 0.16)))


func _build_level(k: int, node: Node3D) -> void:
	var y := k * FH
	var luxe := spec.has("penthouse_floor")
	var floor_mat: Material = _materials["marble"] if k == 0 else _materials["floor"]
	# Floor slab: whole plan on the ground floor, everything but the stair well above.
	if k == 0:
		_box(node, "Floor", Vector3(HALF_W * 2.0, 0.4, DEPTH), Vector3(0, -0.2, -DEPTH * 0.5), floor_mat, true)
		_box(node, "MeterRoom", Vector3(2.0, FH - SLAB, 0.15), Vector3(3.5, (FH - SLAB) * 0.5, STAIR_FRONT - 0.1), _materials["wall"], true)
	else:
		_box(node, "Floor", Vector3(HALF_W * 2.0, SLAB, -STAIR_FRONT), Vector3(0, y - SLAB * 0.5, STAIR_FRONT * 0.5), floor_mat, true)
		_box(node, "Floor", Vector3(HALF_W + 0.35, SLAB, DEPTH + STAIR_FRONT), Vector3((-HALF_W + 0.35) * 0.5, y - SLAB * 0.5, (STAIR_FRONT - DEPTH) * 0.5), floor_mat, true)
	# Skirting / dado band on the landing walls.
	_box(node, "Dado", Vector3(0.04, 1.0, DEPTH - 0.4), Vector3(-HALF_W + 0.02, y + 0.5, -DEPTH * 0.5), _materials["dado"])
	if k < levels - 1:
		_ramp(node, "FlightA", Vector3(FLIGHT_A, y, STAIR_FRONT), Vector3(FLIGHT_A, y + FH * 0.5, STAIR_BACK), FLIGHT_W, _materials["stair"], 10)
		_box(node, "HalfLanding", Vector3(4.0, SLAB, DEPTH + STAIR_BACK), Vector3(2.5, y + FH * 0.5 - SLAB * 0.5, (STAIR_BACK - DEPTH) * 0.5), _materials["stair"], true)
		_ramp(node, "FlightB", Vector3(FLIGHT_B, y + FH * 0.5, STAIR_BACK), Vector3(FLIGHT_B, y + FH, STAIR_FRONT), FLIGHT_W, _materials["stair"], 10)
	else:
		# Top floor: rail round the open well above the last flight.
		_box(node, "WellRail", Vector3(1.95, 1.05, 0.12), Vector3(1.45, y + 0.52, STAIR_FRONT - 0.06), _materials["metal"], true)
		_box(node, "WellRailTop", Vector3(2.0, 0.07, 0.16), Vector3(1.45, y + 1.08, STAIR_FRONT - 0.06), _materials["wood"])
	# Lift: steel doors, call button, floor indicator; the shaft is sealed.
	points["lift_%d" % k] = Vector3(LIFT.x, y, LIFT.z)
	_box(node, "LiftDoor", Vector3(1.1, 2.2, 0.05), Vector3(-3.4, y + 1.1, -12.78), _materials["metal"])
	_box(node, "LiftFrame", Vector3(1.35, 0.12, 0.08), Vector3(-3.4, y + 2.26, -12.77), _materials["brass"])
	_box(node, "LiftButton", Vector3(0.1, 0.16, 0.05), Vector3(-2.6, y + 1.2, -12.77), _materials["lamp"])
	_label(node, "LiftSign", "ASCENSOR  ·  E", Vector3(-3.4, y + 2.55, -12.74), 0.0, Color("f2e6c8"), 0.0055)
	_label(node, "FloorSign", "PORTAL" if k == 0 else "PLANTA %d" % k, Vector3(0.33, y + 1.9, -10.6), -PI * 0.5, Color("3c3228"), 0.008)
	# Lights: ceiling fittings and real lamps over this floor.
	for p: Vector3 in [Vector3(-1.2, 0, -3.5), Vector3(-1.5, 0, -10.5)]:
		_box(node, "CeilingLamp", Vector3(0.5, 0.06, 0.5), Vector3(p.x, y + FH - SLAB - 0.04, p.z), _materials["lamp"])
		var light := OmniLight3D.new()
		light.name = "LandingLight"
		light.position = Vector3(p.x, y + FH - 0.6, p.z)
		light.light_color = Color("ffe6c2")
		light.light_energy = 1.3
		light.omni_range = 9.0
		node.add_child(light)
	var stair_light := OmniLight3D.new()
	stair_light.name = "StairLight"
	stair_light.position = Vector3(2.5, y + FH * 0.5 + 1.8, -13.9)
	stair_light.light_color = Color("fff1dc")
	stair_light.light_energy = 1.0
	stair_light.omni_range = 7.0
	node.add_child(stair_light)
	if k == 0:
		_build_lobby(node, luxe)
	elif k == int(spec.get("safehouse_floor", -1)):
		_build_flat_front(node, y, "%dºA  ·  PISO FRANCO" % k)
		_build_safehouse(node, y)
		_neighbour_door(node, y, Vector3(-HALF_W + 0.05, 0, -9.6), PI * 0.5, "%dºB" % k)
	elif k == int(spec.get("penthouse_floor", -1)):
		_build_flat_front(node, y, "ÁTICO  ·  T. FERRER")
		_build_penthouse(node, y)
	elif k == int(spec.get("office_floor", -1)):
		_build_flat_front(node, y, str(spec.get("office", "OFICINAS")))
		_build_office(node, y)
		_neighbour_door(node, y, Vector3(-HALF_W + 0.05, 0, -9.6), PI * 0.5, "%dºB" % k)
	else:
		_neighbour_door(node, y, Vector3(-HALF_W + 0.05, 0, -3.2), PI * 0.5, "%dºA" % k)
		_neighbour_door(node, y, Vector3(-HALF_W + 0.05, 0, -9.6), PI * 0.5, "%dºB" % k)
		_neighbour_door(node, y, Vector3(-1.4, 0, -0.3), PI, "%dºC" % k)
		_neighbour_door(node, y, Vector3(2.6, 0, -0.3), PI, "%dºD" % k)
		_plant(node, Vector3(3.9, y, -7.6))


func _build_lobby(node: Node3D, luxe: bool) -> void:
	_box(node, "Doormat", Vector3(2.0, 0.02, 1.2), Vector3(0, 0.01, -1.0), _materials["leather"])
	_box(node, "Mailboxes", Vector3(0.28, 1.1, 2.4), Vector3(-HALF_W + 0.15, 1.45, -5.2), _materials["brass"])
	for row in range(3):
		for col in range(6):
			_box(node, "MailboxSlot", Vector3(0.02, 0.05, 0.28), Vector3(-HALF_W + 0.3, 1.15 + row * 0.33, -4.15 - col * 0.4), _materials["dark"])
	_label(node, "MailboxSign", "BUZONES", Vector3(-HALF_W + 0.31, 2.2, -5.2), PI * 0.5, Color("3c3228"), 0.006)
	_box(node, "Bench", Vector3(0.5, 0.45, 1.8), Vector3(-HALF_W + 0.35, 0.22, -1.9), _materials["wood"], true)
	_box(node, "Mirror", Vector3(0.03, 1.6, 1.4), Vector3(-HALF_W + 0.03, 1.7, -8.2), _materials["window"])
	# Conserje's desk.
	_box(node, "ConserjeDesk", Vector3(0.9, 1.05, 2.6), Vector3(2.9, 0.52, -3.4), _materials["wood"], true)
	_box(node, "ConserjeDeskTop", Vector3(1.05, 0.06, 2.75), Vector3(2.9, 1.08, -3.4), _materials["marble"])
	_box(node, "Monitor", Vector3(0.05, 0.35, 0.5), Vector3(3.2, 1.3, -3.9), _materials["screen"])
	var conserje := HumanModel.new("male_suit")
	conserje.name = "Conserje"
	conserje.position = Vector3(3.85, 0, -3.3)
	conserje.rotation.y = PI * 0.5
	node.add_child(conserje)
	_plant(node, Vector3(3.9, 0, -1.0))
	_plant(node, Vector3(-3.9, 0, -7.2))
	if luxe:
		_box(node, "LobbyRug", Vector3(2.4, 0.02, 5.0), Vector3(-0.6, 0.012, -4.5), _materials["fabric"])
		_label(node, "Directory", "ÁTICO: T. FERRER  ·  ACCESO RESTRINGIDO", Vector3(0.33, 1.4, -9.8), -PI * 0.5, Color("3c3228"), 0.004)
	if spec.has("office"):
		_label(node, "Directory", "PLANTA %d: %s" % [int(spec["office_floor"]), str(spec["office"])], Vector3(0.33, 1.4, -9.8), -PI * 0.5, Color("3c3228"), 0.004)


## Partition between a floor's landing and its flat, with the flat's door.
func _build_flat_front(node: Node3D, y: float, title: String) -> void:
	var gap := 0.65
	var left_w := FLAT_DOOR_X - gap + HALF_W
	var right_w := HALF_W - (FLAT_DOOR_X + gap)
	_box(node, "FlatWall", Vector3(left_w, FH - SLAB, 0.15), Vector3(-HALF_W + left_w * 0.5, y + (FH - SLAB) * 0.5, PARTITION_Z), _materials["wall"], true)
	_box(node, "FlatWall", Vector3(right_w, FH - SLAB, 0.15), Vector3(FLAT_DOOR_X + gap + right_w * 0.5, y + (FH - SLAB) * 0.5, PARTITION_Z), _materials["wall"], true)
	_box(node, "FlatWall", Vector3(gap * 2.0, FH - SLAB - 2.3, 0.15), Vector3(FLAT_DOOR_X, y + 2.3 + (FH - SLAB - 2.3) * 0.5, PARTITION_Z), _materials["wall"], true)
	_box(node, "FlatDoorLeaf", Vector3(1.2, 2.25, 0.05), Vector3(FLAT_DOOR_X - gap - 0.62, y + 1.13, PARTITION_Z + 0.11), _materials["wood"])  # swung open against the wall
	_label(node, "FlatSign", title, Vector3(FLAT_DOOR_X, y + 2.55, PARTITION_Z - 0.1), PI, Color("f2e6c8"), 0.005)
	points["flat_door"] = Vector3(FLAT_DOOR_X, y, PARTITION_Z - 0.9)
	for p: Vector3 in [Vector3(-2.0, 0, -3.2), Vector3(2.0, 0, -3.2)]:
		var light := OmniLight3D.new()
		light.name = "FlatLight"
		light.position = Vector3(p.x, y + FH - 0.7, p.z)
		light.light_color = Color("ffd9a8")
		light.light_energy = 1.2
		light.omni_range = 8.0
		node.add_child(light)
	# Windows on the street side (the façade outside has its own).
	if title.begins_with("ÁTICO"):
		_window(node, Vector3(-1.2, y + 1.45, -0.27), Vector2(5.8, 2.1), 4)  # glass wall over the sea
	else:
		for x: float in [-2.6, 0.4]:
			_window(node, Vector3(x, y + 1.55, -0.27), Vector2(1.4, 1.7), 2)


func _build_safehouse(node: Node3D, y: float) -> void:
	_box(node, "FlatFloor", Vector3(HALF_W * 2.0 - 0.1, 0.02, -PARTITION_Z - 0.35), Vector3(0, y + 0.012, PARTITION_Z * 0.5 - 0.1), _materials["parquet"])
	# Bed: save and rest.
	_box(node, "Bed", Vector3(1.6, 0.5, 2.1), Vector3(-3.6, y + 0.25, -1.45), _materials["wood"], true)
	_box(node, "Mattress", Vector3(1.5, 0.18, 2.0), Vector3(-3.6, y + 0.58, -1.45), _materials["cream"])
	_box(node, "Blanket", Vector3(1.55, 0.06, 1.3), Vector3(-3.6, y + 0.68, -1.05), _materials["fabric"])
	_box(node, "Pillow", Vector3(1.2, 0.14, 0.4), Vector3(-3.6, y + 0.72, -2.2), _materials["cream"])
	points["bed"] = Vector3(-2.4, y, -1.5)
	_label(node, "BedLabel", "DORMIR · GUARDAR  ·  E", Vector3(-3.6, y + 1.5, -1.45), PI * 0.5, Color("f2e6c8"), 0.005)
	# Wardrobe: the stash.
	_box(node, "Wardrobe", Vector3(0.62, 2.1, 1.8), Vector3(-4.15, y + 1.05, -4.6), _materials["wood"], true)
	_box(node, "WardrobeHandle", Vector3(0.04, 0.3, 0.04), Vector3(-3.82, y + 1.1, -4.55), _materials["brass"])
	points["stash"] = Vector3(-3.25, y, -4.6)
	_label(node, "StashLabel", "ALIJO  ·  E", Vector3(-3.8, y + 2.3, -4.6), PI * 0.5, Color("f2e6c8"), 0.005)
	# Living corner and kitchenette.
	_box(node, "Sofa", Vector3(2.2, 0.45, 0.9), Vector3(1.8, y + 0.22, -5.5), _materials["fabric"], true)
	_box(node, "SofaBack", Vector3(2.2, 0.5, 0.2), Vector3(1.8, y + 0.7, -5.85), _materials["fabric"])
	_box(node, "CoffeeTable", Vector3(1.1, 0.4, 0.6), Vector3(1.8, y + 0.2, -4.2), _materials["wood"], true)
	_box(node, "Ashtray", Vector3(0.18, 0.04, 0.18), Vector3(2.0, y + 0.42, -4.2), _materials["dark"])
	_box(node, "TvStand", Vector3(1.6, 0.5, 0.45), Vector3(2.6, y + 0.25, -0.55), _materials["dark"], true)
	_box(node, "Tv", Vector3(1.5, 0.85, 0.06), Vector3(2.6, y + 1.0, -0.8), _materials["screen"])
	_box(node, "Kitchen", Vector3(0.65, 0.9, 3.0), Vector3(4.1, y + 0.45, -3.0), _materials["cream"], true)
	_box(node, "KitchenTop", Vector3(0.7, 0.05, 3.05), Vector3(4.1, y + 0.92, -3.0), _materials["dark"])
	_box(node, "Fridge", Vector3(0.7, 1.9, 0.7), Vector3(4.1, y + 0.95, -5.3), _materials["metal"], true)
	_box(node, "Rug", Vector3(2.6, 0.02, 2.0), Vector3(1.8, y + 0.025, -3.2), _materials["leather"])


## Construcciones Mar Azul: the builder who pays the bribes. Open-plan office,
## models of the promotions, the boss's desk and a safe full of black money.
func _build_office(node: Node3D, y: float) -> void:
	_box(node, "FlatFloor", Vector3(HALF_W * 2.0 - 0.1, 0.02, -PARTITION_Z - 0.35), Vector3(0, y + 0.012, PARTITION_Z * 0.5 - 0.1), _materials["floor"])
	_box(node, "Reception", Vector3(2.2, 1.05, 0.7), Vector3(0.6, y + 0.52, -5.4), _materials["wood"], true)
	_label(node, "OfficeLogo", "MAR AZUL  ·  PROMOCIONES Y OBRAS", Vector3(0.6, y + 2.2, PARTITION_Z + 0.1), 0.0, Color("1f4f7a"), 0.0045)
	for row in range(2):
		for col in range(2):
			var at := Vector3(-3.2 + col * 2.4, y, -3.9 + row * 2.0)
			_box(node, "OfficeDesk", Vector3(1.6, 0.75, 0.8), at + Vector3(0, 0.37, 0), _materials["cream"], true)
			_box(node, "OfficeMonitor", Vector3(0.55, 0.38, 0.05), at + Vector3(0, 0.98, -0.2), _materials["screen"])
			_box(node, "OfficeChair", Vector3(0.55, 0.9, 0.55), at + Vector3(0, 0.45, 0.75), _materials["dark"])
	# Model of the "Residencial Altamar" promotion on a table.
	_box(node, "ModelTable", Vector3(1.4, 0.8, 1.0), Vector3(0.8, y + 0.4, -0.9), _materials["wood"], true)
	for i in range(4):
		_box(node, "ModelTower", Vector3(0.2, 0.25 + i * 0.12, 0.2), Vector3(0.4 + i * 0.27, y + 0.92 + i * 0.06, -0.9), _materials["cream"])
	_label(node, "ModelLabel", "RESIDENCIAL ALTAMAR\n(recalificado)", Vector3(0.8, y + 1.55, -1.3), PI, Color("3c3228"), 0.0035)
	# Boss's corner: desk and the safe.
	_box(node, "BossDesk", Vector3(1.9, 0.78, 0.9), Vector3(2.6, y + 0.39, -2.0), _materials["wood"], true)
	_box(node, "BossChair", Vector3(0.7, 1.2, 0.7), Vector3(2.6, y + 0.6, -1.1), _materials["leather"], true)
	_box(node, "Safe", Vector3(0.35, 0.95, 0.85), Vector3(HALF_W - 0.2, y + 0.75, -4.4), _materials["dark"], true)
	_box(node, "SafeDial", Vector3(0.04, 0.18, 0.18), Vector3(HALF_W - 0.4, y + 0.85, -4.4), _materials["brass"])
	_label(node, "SafeLabel", "CAJA FUERTE", Vector3(HALF_W - 0.42, y + 1.45, -4.4), -PI * 0.5, Color("f2d36b"), 0.004)
	points["office_safe"] = Vector3(3.55, y, -4.4)
	_plant(node, Vector3(4.0, y, -0.7))


func _build_penthouse(node: Node3D, y: float) -> void:
	_box(node, "FlatFloor", Vector3(HALF_W * 2.0 - 0.1, 0.02, -PARTITION_Z - 0.35), Vector3(0, y + 0.012, PARTITION_Z * 0.5 - 0.1), _materials["parquet"])
	# Office: desk, leather chair and the wall safe.
	_box(node, "Desk", Vector3(2.0, 0.78, 0.95), Vector3(2.2, y + 0.39, -2.6), _materials["wood"], true)
	_box(node, "DeskTop", Vector3(2.1, 0.05, 1.05), Vector3(2.2, y + 0.8, -2.6), _materials["leather"])
	_box(node, "Laptop", Vector3(0.4, 0.02, 0.3), Vector3(2.0, y + 0.84, -2.6), _materials["dark"])
	_box(node, "Chair", Vector3(0.7, 1.2, 0.7), Vector3(2.2, y + 0.6, -3.6), _materials["leather"], true)
	_box(node, "Safe", Vector3(0.35, 0.95, 0.85), Vector3(HALF_W - 0.2, y + 0.75, -4.6), _materials["dark"], true)
	_box(node, "SafeDial", Vector3(0.04, 0.18, 0.18), Vector3(HALF_W - 0.4, y + 0.85, -4.6), _materials["brass"])
	points["safe"] = Vector3(3.55, y, -4.6)
	_label(node, "SafeLabel", "CAJA FUERTE", Vector3(HALF_W - 0.42, y + 1.45, -4.6), -PI * 0.5, Color("f2d36b"), 0.004)
	# Lounge: leather sofas, bar, art, the sea view.
	_box(node, "Sofa", Vector3(0.9, 0.45, 2.6), Vector3(-3.9, y + 0.22, -3.2), _materials["leather"], true)
	_box(node, "SofaBack", Vector3(0.2, 0.5, 2.6), Vector3(-4.3, y + 0.7, -3.2), _materials["leather"])
	_box(node, "LowTable", Vector3(1.0, 0.35, 1.4), Vector3(-2.5, y + 0.18, -3.2), _materials["marble"], true)
	_box(node, "Whisky", Vector3(0.1, 0.25, 0.1), Vector3(-2.4, y + 0.48, -3.0), _materials["brass"])
	_box(node, "Bar", Vector3(2.2, 1.05, 0.6), Vector3(-0.2, y + 0.52, -5.8), _materials["wood"], true)
	_box(node, "BarTop", Vector3(2.3, 0.05, 0.7), Vector3(-0.2, y + 1.07, -5.8), _materials["marble"])
	_box(node, "Painting", Vector3(1.6, 1.0, 0.04), Vector3(2.4, y + 1.8, PARTITION_Z + 0.1), _materials["pot"])
	_box(node, "Rug", Vector3(3.0, 0.02, 2.6), Vector3(-2.6, y + 0.025, -3.2), _materials["fabric"])
	_plant(node, Vector3(-4.0, y, -0.7))
	_plant(node, Vector3(4.0, y, -0.7))
	# Guard posts used by the mission.
	points["guard_1"] = Vector3(-2.8, y, -10.2)
	points["guard_2"] = Vector3(-0.6, y, -2.2)
	points["guard_3"] = Vector3(3.2, y, -1.4)


func _window(node: Node3D, at: Vector3, size: Vector2, panes: int) -> void:
	_box(node, "WindowGlass", Vector3(size.x, size.y, 0.03), at, _materials["window"])
	var frame: Material = _materials["dark"]
	for side: float in [-0.5, 0.5]:
		_box(node, "WindowFrame", Vector3(0.08, size.y + 0.08, 0.07), at + Vector3(size.x * side, 0, -0.02), frame)
		_box(node, "WindowFrame", Vector3(size.x + 0.08, 0.08, 0.07), at + Vector3(0, size.y * side, -0.02), frame)
		_box(node, "Curtain", Vector3(0.5, size.y + 0.3, 0.06), at + Vector3((size.x * 0.5 + 0.2) * side * 2.0, 0.05, -0.08), _materials["cream"])
	for k in range(1, panes):
		_box(node, "WindowMullion", Vector3(0.05, size.y, 0.06), at + Vector3(-size.x * 0.5 + size.x * k / panes, 0, -0.02), frame)
	_box(node, "WindowSill", Vector3(size.x + 0.2, 0.06, 0.2), at + Vector3(0, -size.y * 0.5 - 0.04, -0.07), _materials["stone"])


func _neighbour_door(node: Node3D, y: float, at: Vector3, yaw: float, title: String) -> void:
	points["door:" + title] = Vector3(at.x, y, at.z) + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.75)
	var door := MeshInstance3D.new()
	door.name = "NeighbourDoor"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 2.2, 0.06)
	door.mesh = mesh
	door.position = Vector3(at.x, y + 1.1, at.z)
	door.rotation.y = yaw
	door.material_override = _materials["wood"]
	node.add_child(door)
	var knob := MeshInstance3D.new()
	knob.name = "DoorKnob"
	var knob_mesh := BoxMesh.new()
	knob_mesh.size = Vector3(0.06, 0.06, 0.08)
	knob.mesh = knob_mesh
	knob.position = door.position + Basis(Vector3.UP, yaw) * Vector3(0.36, -0.05, 0.05)
	knob.material_override = _materials["brass"]
	node.add_child(knob)
	_box(node, "Doormat", Vector3(0.9, 0.02, 0.6) if absf(sin(yaw)) < 0.5 else Vector3(0.6, 0.02, 0.9), Vector3(at.x, y + 0.012, at.z) + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.45), _materials["leather"])
	_label(node, "DoorNumber", title, door.position + Basis(Vector3.UP, yaw) * Vector3(0, 1.3, 0.05), yaw, Color("3c3228"), 0.005)


func _plant(node: Node3D, at: Vector3) -> void:
	var pot := MeshInstance3D.new()
	pot.name = "PlantPot"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.28
	cylinder.bottom_radius = 0.22
	cylinder.height = 0.55
	pot.mesh = cylinder
	pot.position = at + Vector3(0, 0.27, 0)
	pot.material_override = _materials["pot"]
	node.add_child(pot)
	var leaves := MeshInstance3D.new()
	leaves.name = "PlantLeaves"
	var sphere := SphereMesh.new()
	sphere.radius = 0.45
	sphere.height = 1.1
	leaves.mesh = sphere
	leaves.position = at + Vector3(0, 1.05, 0)
	leaves.material_override = _materials["green"]
	node.add_child(leaves)


func _label(node: Node3D, name: String, text: String, at: Vector3, yaw: float, tint: Color, pixel: float) -> void:
	var letters := Label3D.new()
	letters.name = name
	letters.text = text
	letters.font_size = 48
	letters.pixel_size = pixel
	letters.outline_size = 4
	letters.modulate = tint
	letters.position = at
	letters.rotation.y = yaw
	node.add_child(letters)


func _box(node: Node3D, name: String, size: Vector3, at: Vector3, material: Material, solid: bool = false) -> void:
	var visual := MeshInstance3D.new()
	visual.name = name
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = at
	visual.material_override = material
	node.add_child(visual)
	if solid:
		var collision := CollisionShape3D.new()
		collision.name = name + "Shape"
		var box := BoxShape3D.new()
		box.size = size
		collision.shape = box
		collision.position = at
		body.add_child(collision)


## Sloped walking surface from `from` to `to` (tops), with `steps` treads drawn on it.
## The collider is a smooth ramp so feet, bodies and the camera never snag.
func _ramp(node: Node3D, name: String, from: Vector3, to: Vector3, width: float, material: Material, steps: int) -> void:
	var run := to - from
	var direction := run.normalized()
	var side := direction.cross(Vector3.UP).normalized()
	var up := side.cross(direction)
	var basis := Basis(side, up, -direction)
	var collision := CollisionShape3D.new()
	collision.name = name + "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(width, 0.2, run.length())
	collision.shape = box
	collision.transform = Transform3D(basis, (from + to) * 0.5 - up * 0.1)
	body.add_child(collision)
	var underside := MeshInstance3D.new()
	underside.name = name + "Slab"
	var slab := BoxMesh.new()
	slab.size = Vector3(width, 0.2, run.length())
	underside.mesh = slab
	underside.transform = Transform3D(basis, (from + to) * 0.5 - up * 0.18)
	underside.material_override = material
	node.add_child(underside)
	var horizontal := Vector3(run.x, 0, run.z)
	var rise := run.y / steps
	var tread := horizontal.length() / steps
	var flat_dir := horizontal.normalized()
	var yaw := atan2(flat_dir.x, flat_dir.z)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, absf(rise) + 0.02, tread + 0.02)
	for i in range(steps):
		var tread_center := from + flat_dir * tread * (i + 0.5)
		var step := MeshInstance3D.new()
		step.name = name + "Step"
		step.mesh = mesh
		# Each tread top meets the ramp line at its centre: feet stay within half
		# a riser of the stone.
		step.position = Vector3(tread_center.x, from.y + rise * (i + 0.5) - (absf(rise) + 0.02) * 0.5, tread_center.z)
		step.rotation.y = yaw
		step.material_override = material
		node.add_child(step)
