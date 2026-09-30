class_name VenueInterior
extends Node3D

const DetailBatcher = preload("res://scripts/interior_details.gd")
const UpperFloor = preload("res://scripts/venue_upper_floor.gd")

signal purchase_requested(kind: String)
signal bank_transaction_requested(action: String)
signal robbery_requested
signal interior_event_requested(event: String)

const SPECS = preload("res://scripts/venue_catalog.gd").SPECS

var kind := ""
var exterior_entry := Vector3.ZERO
var exterior_normal := Vector3.ZERO
var inside_entry := Vector3.ZERO
var service_point := Vector3.ZERO
var secondary_service_point := Vector3.ZERO
var source_building_id := 0
var room: Node3D
var mission_points: Dictionary = {}
var stash_collected := false
var glow_materials: Dictionary = {}
var visibility_distance := 28.0


func restore_discoveries(discoveries: Dictionary) -> void:
	stash_collected = bool(discoveries.get("casino_stash", false)) if kind == "casino" else false
	if kind == "casino":
		var envelope := room.get_node_or_null("SecretEnvelope") as Node3D
		if envelope != null:
			envelope.visible = not stash_collected


func point_position(id: String) -> Vector3:
	return room.to_global(SPECS[kind]["origin"] + mission_points[id]) if mission_points.has(id) else Vector3.INF


func floor_number(at: Vector3) -> int:
	return maxi(0, floori((room.to_local(at).y + 0.15) / 4.5))


func mission_prompt(at: Vector3) -> String:
	if _near_bed(at):
		return "E · Descansar en el apartamento"
	if mission_points.has("stash") and at.distance_to(point_position("stash")) < 1.3:
		return "Sobre vacío" if stash_collected else "E · Recoger el sobre escondido"
	if mission_points.has("ledger") and at.distance_to(point_position("ledger")) < 1.5:
		return "E · Examinar el libro de cuentas"
	return ""


func _near_bed(at: Vector3) -> bool:
	for id in ["bed", "bed_two"]:
		if mission_points.has(id) and at.distance_to(point_position(id)) < 1.6:
			return true
	return false


func configure(value: String, data: SectorData, mats: SectorMaterials) -> bool:
	if not SPECS.has(value):
		push_error("Venue kind not configured: " + value)
		return false
	kind = value
	var spec: Dictionary = SPECS[kind]
	var origin: Vector3 = spec["origin"]
	for building in data.raw["buildings"]:
		if int(building["id"]) != int(spec["building_id"]):
			continue
		var footprint: Array = building["footprint"]
		var edge_index: int = spec["front_edge"]
		var a := Vector2(float(footprint[edge_index][0]), float(footprint[edge_index][1]))
		var b := Vector2(float(footprint[(edge_index + 1) % footprint.size()][0]), float(footprint[(edge_index + 1) % footprint.size()][1]))
		var edge := b - a
		exterior_normal = Vector3(edge.y, 0, -edge.x).normalized()
		var mid := (a + b) * 0.5
		var entry_xz := Vector3(mid.x, 0, mid.y) + exterior_normal * 1.7
		exterior_entry = Vector3(entry_xz.x, data.height_at(entry_xz.x, entry_xz.z) + 0.2, entry_xz.z)
		source_building_id = int(spec["building_id"])
		_make_sign(mid, data, mats, str(spec["sign"]))
		_make_room(origin, mats, spec)
		DetailBatcher.optimize(room)
		# The room occupies its surveyed building footprint. Local +Z faces the
		# street; only the horizontal plan is scaled, preserving headroom.
		var scale_xz := float(spec["scale"])
		var angle := atan2(exterior_normal.x, exterior_normal.z)
		var rotation_basis := Basis(Vector3.UP, angle)
		var physical_center := Vector3(mid.x, data.height_at(mid.x, mid.y) + 0.12, mid.y) - exterior_normal * (9.0 * scale_xz)
		if int(spec.get("floors", 1)) > 1 or kind in ["gun_shop", "nightclub", "seafood", "bakery", "pharmacy", "barber", "gym", "record_shop", "clothing"]:
			# A level floor must sit above the hillside across the entire plan.
			# Portal entry handles the difference from the street's ground datum.
			for x in range(-7, 8, 2):
				for z in range(-9, 10, 2):
					var sample := physical_center + rotation_basis * Vector3(x * scale_xz, 0, z * scale_xz)
					physical_center.y = maxf(physical_center.y, data.height_at(sample.x, sample.z) + 0.12)
		room.rotation.y = angle
		room.scale = Vector3(scale_xz, 1.0, scale_xz)
		for person in room.get_children():
			if person is HumanModel or person is Pedestrian:
				person.scale = Vector3(1.0 / scale_xz, 1.0, 1.0 / scale_xz)
		room.position = physical_center - rotation_basis * Vector3(origin.x * scale_xz, origin.y, origin.z * scale_xz)
		for person in room.get_children():
			if person is Pedestrian:
				person.home = person.global_position
				person.destination = person.global_position
		inside_entry = room.to_global(origin + Vector3(0, 0.2, 3.0))
		service_point = room.to_global(origin + Vector3(4.0, 0.2, -5.1))
		secondary_service_point = room.to_global(origin + Vector3(-4.8, 0.2, -5.1))
		add_to_group("interiors")
		return true
	push_error("Venue %s source building %d missing" % [kind, spec["building_id"]])
	return false


func try_interact(player: PlayerController) -> bool:
	if player.driving_vehicle != null:
		return false
	if contains_player(player.global_position) and mission_prompt(player.global_position) != "":
		if _near_bed(player.global_position):
			purchase_requested.emit(kind)
		elif mission_points.has("stash") and player.global_position.distance_to(point_position("stash")) < 1.3:
			if not stash_collected:
				interior_event_requested.emit("casino_stash")
		else:
			interior_event_requested.emit("casino_ledger")
		return true
	if not contains_player(player.global_position) and player.global_position.distance_to(exterior_entry) < 3.0:
		player.global_position = inside_entry
		player.velocity = Vector3.ZERO
		player.camera_yaw = room.rotation.y
		player.camera_pitch = -0.12
		player._update_camera_orientation()
		room.visible = true
		return true
	if contains_player(player.global_position) and player.global_position.distance_to(inside_entry) < 2.7:
		if kind == "record_shop":
			(room.get_node("ListeningStation") as AudioStreamPlayer3D).stop()
		player.global_position = exterior_entry + exterior_normal * 0.35
		player.velocity = Vector3.ZERO
		return true
	if not bool(SPECS[kind].get("residential", false)) and contains_player(player.global_position) and player.global_position.distance_to(service_point) < 2.7:
		if kind == "bank":
			bank_transaction_requested.emit("deposit")
		elif kind == "jewellery":
			robbery_requested.emit()
		else:
			purchase_requested.emit(kind)
		return true
	if kind == "bank" and contains_player(player.global_position) and player.global_position.distance_to(secondary_service_point) < 2.7:
		bank_transaction_requested.emit("withdraw")
		return true
	if SPECS[kind].has("secondary") and contains_player(player.global_position) and player.global_position.distance_to(secondary_service_point) < 2.7:
		purchase_requested.emit(kind + "_secondary")
		return true
	return false


## Furnished rooms are only drawn near their doors or with the player inside
## (eight always-drawn interiors cost ~350 draw calls from the street).
var _gate_timer := 0.0


func _process(delta: float) -> void:
	_gate_timer -= delta
	if room == null or _gate_timer > 0.0:
		return
	_gate_timer = 0.25
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	update_room_visibility((players[0] as Node3D).global_position)


func update_room_visibility(at: Vector3) -> void:
	var radius_squared := visibility_distance * visibility_distance
	room.visible = contains_player(at) or at.distance_squared_to(inside_entry) < radius_squared or at.distance_squared_to(exterior_entry) < radius_squared


func contains_player(at: Vector3) -> bool:
	if room == null:
		return false
	var local := room.to_local(at)
	var origin: Vector3 = SPECS[kind]["origin"]
	return absf(local.x - origin.x) < 6.9 and absf(local.z - origin.z) < 8.9 and local.y > -0.5 and local.y < 4.5 * int(SPECS[kind].get("floors", 1)) + 0.3


func set_robbed(value: bool) -> void:
	if kind != "jewellery":
		return
	for node in room.get_children():
		var label := str(node.get_meta("detail_kind", node.name))
		if node is MeshInstance3D and (label.begins_with("Gemstone") or label.begins_with("GoldSetting") or label.begins_with("GoldDisplay")):
			(node as MeshInstance3D).visible = not value


func _make_sign(mid: Vector2, data: SectorData, mats: SectorMaterials, title: String) -> void:
	var at := Vector3(mid.x, data.height_at(mid.x, mid.y) + 2.9, mid.y) + exterior_normal * 0.08
	var panel := MeshInstance3D.new()
	panel.name = "VenueSign"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(8.0, 0.62, 0.16) if kind == "church" else Vector3(5.5, 0.78, 0.16)
	panel.mesh = mesh
	panel.position = at
	panel.rotation.y = atan2(exterior_normal.x, exterior_normal.z)
	var sign_color := Color("35596a") if kind == "supermarket" else Color("6c4031") if kind == "restaurant" else Color("244a58") if kind == "bank" else Color("d4c2a4") if kind == "church" else Color("356775") if kind == "mall" else Color("344c4b")
	panel.material_override = mats.textured("venue_sign_" + kind, "rock020" if kind == "church" else "asphalt010", sign_color, 1.6 if kind == "church" else 0.6, 0.8)
	add_child(panel)
	var letters := Label3D.new()
	letters.name = "VenueLetters"
	letters.text = title
	letters.font_size = 42
	letters.pixel_size = 0.0063
	letters.outline_size = 6
	letters.modulate = Color("514332") if kind == "church" else Color("f4eee1")
	letters.rotation.y = atan2(exterior_normal.x, exterior_normal.z)
	letters.position = at + exterior_normal * 0.14
	add_child(letters)


func _make_room(origin: Vector3, mats: SectorMaterials, spec: Dictionary) -> void:
	room = Node3D.new()
	room.name = "Room"
	add_child(room)
	var floor_mat := mats.textured("venue_floor_" + kind, "tiles040" if kind != "restaurant" else "pavingstones046", Color("d7d4ca") if kind != "restaurant" else Color("c2a184"), 1.6, 0.83)
	var wall_mat := mats.textured("venue_wall_" + kind, "plaster003", Color("4a2b33") if kind == "casino" else Color("1a1a22") if kind == "nightclub" else Color("9b917d") if kind == "gun_shop" else Color("d9dfda") if kind == "jewellery" else Color("e0e6e4") if kind == "bank" else Color("ebe7de") if kind == "supermarket" else Color("e6d3bd"), 2.4, 0.9)
	var wood := mats.textured("venue_wood_" + kind, "roofingtiles006", Color("776d62") if kind == "bank" else Color("565f5d") if kind == "jewellery" else Color("857058") if kind == "supermarket" else Color("72523d"), 1.0, 0.8)
	var metal := mats.textured("venue_metal_" + kind, "asphalt010", Color("657579"), 0.8, 0.6)
	var accent := mats.textured("venue_accent_" + kind, "tiles040", Color("3d7180") if kind == "bank" else Color("536d67") if kind == "jewellery" else Color("507d83") if kind == "supermarket" else Color("945a3a"), 1.2, 0.7)
	_box("Floor", Vector3(14, 0.4, 18), origin + Vector3(0, -0.2, 0), floor_mat, true)
	if bool(spec.get("residential", false)):
		preload("res://scripts/venue_neighborhood.gd").residential(self, origin, floor_mat, wall_mat, wood, metal, mats)
	elif int(spec.get("floors", 1)) > 1:
		UpperFloor.build(self, origin, floor_mat, wall_mat, wood, metal, mats)
	else:
		_box("Ceiling", Vector3(14, 0.35, 18), origin + Vector3(0, 4.5, 0), wall_mat, true)
	_box("LeftWall", Vector3(0.35, 4.5, 18), origin + Vector3(-7, 2.25, 0), wall_mat, true)
	_box("RightWall", Vector3(0.35, 4.5, 18), origin + Vector3(7, 2.25, 0), wall_mat, true)
	_box("BackWall", Vector3(14, 4.5, 0.35), origin + Vector3(0, 2.25, -9), wall_mat, true)
	# Glazed street front: display windows reveal the furnished ground floor and
	# receive the same daylight as the city. The central door remains interactive.
	var frame := mats.plain("venue_frame_" + kind, Color("303c43") if kind == "bank" else Color("594b3f"), 0.55, 0.2)
	var glass := mats.plain("venue_window_" + kind, Color(0.68, 0.45, 0.23, 0.42) if kind == "church" else Color(0.67, 0.82, 0.84, 0.28), 0.08)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if kind == "church":
		var portal_stone := mats.textured("church_portal_stone", "rock020", Color("d9c8aa"), 2.0, 0.91)
		_box("StoneLintel", Vector3(14, 0.55, 0.4), origin + Vector3(0, 4.22, 9), portal_stone, true)
		_box("StonePlinth", Vector3(14, 0.3, 0.4), origin + Vector3(0, 0.15, 9), portal_stone, true)
		for side in [-1.0, 1.0]:
			_box("StonePier", Vector3(2.8, 3.9, 0.38), origin + Vector3(side * 5.6, 2.1, 9), portal_stone, true)
			_box("StoneMullion", Vector3(0.4, 3.9, 0.4), origin + Vector3(side * 2.5, 2.1, 9), portal_stone, true)
			_box("StainedWindow", Vector3(1.6, 2.9, 0.08), origin + Vector3(side * 3.6, 2.15, 9.05), glass)
		_box("ChurchDoor", Vector3(2.35, 3.7, 0.08), origin + Vector3(0, 2.15, 9.05), glass)
		_box("PortalBeam", Vector3(3.3, 0.32, 0.46), origin + Vector3(0, 3.95, 9), portal_stone)
	else:
		_box("StorefrontHeader", Vector3(14, 0.35, 0.35), origin + Vector3(0, 4.32, 9), frame, true)
		_box("StorefrontSill", Vector3(14, 0.28, 0.35), origin + Vector3(0, 0.14, 9), frame, true)
		for x in [-7.0, -4.2, -1.2, 1.2, 4.2, 7.0]:
			_box("StorefrontMullion", Vector3(0.12, 4.0, 0.24), origin + Vector3(x, 2.18, 9), frame, true)
		for x in [-5.6, -2.7, 2.7, 5.6]:
			_box("ShopWindow", Vector3(2.68, 3.72, 0.07), origin + Vector3(x, 2.2, 9), glass)
		_box("GlassDoor", Vector3(2.25, 3.72, 0.07), origin + Vector3(0, 2.2, 9), glass)
		_box("DoorHandle", Vector3(0.08, 0.42, 0.15), origin + Vector3(0.85, 1.2, 9.14), frame)
	_box("AccentBand", Vector3(13.6, 0.45, 0.08), origin + Vector3(0, 3.3, -8.75), accent)
	if kind == "supermarket":
		_make_market(origin, wood, metal, accent, mats)
	elif kind == "restaurant":
		_make_restaurant(origin, wood, metal, accent, mats)
	elif kind == "cafe":
		_make_cafe(origin, wood, metal, accent, mats)
	elif kind == "palm_restaurant":
		_make_palm_restaurant(origin, wood, metal, accent, mats)
	elif kind == "bank":
		_make_bank(origin, wood, metal, accent, mats)
	elif kind == "jewellery":
		_make_jewellery(origin, wood, metal, accent, mats)
	elif kind == "church":
		_make_church(origin, wood, accent, mats)
	elif kind == "mall":
		_make_mall(origin, wood, metal, accent, mats)
	elif kind == "casino":
		_make_casino(origin, wood, metal, mats)
	elif kind == "gun_shop":
		_make_gun_shop(origin, wood, metal, accent, mats)
	elif kind == "nightclub":
		_make_nightclub(origin, metal, mats)
	elif kind == "seafood":
		_make_restaurant(origin, wood, metal, accent, mats)
		_wall_label("SeafoodBoard", "ESPETOS  ·  FRITURA  ·  GAMBAS", origin + Vector3(0, 3.6, -8.6), Color("f4e6c8"))
	elif not bool(spec.get("residential", false)):
		preload("res://scripts/venue_neighborhood.gd").build(self, origin, wood, metal, accent, mats)
	var clerk := Pedestrian.new()
	clerk.model_name = "male_suit" if kind == "bank" else "female_dress" if kind == "jewellery" else "female_casual" if kind == "supermarket" else "male_casual"
	clerk.activity = "work"
	clerk.display_name = "Dependiente"
	clerk.name = "VenueStaff"
	clerk.position = origin + Vector3(4.0, 0, -6.7)
	clerk.rotation.y = PI
	room.add_child(clerk)
	for lx in [-3.8, 3.8]:
		var light := OmniLight3D.new()
		light.name = "VenueLight"
		light.position = origin + Vector3(lx, 3.9, 0)
		light.light_color = Color("e5f2f5") if kind == "bank" else Color("f3e9de") if kind == "jewellery" else Color("eff5f1") if kind == "supermarket" else Color("ffe1b3")
		light.light_energy = 1.8
		light.omni_range = 13.0
		room.add_child(light)
	var exit_label := Label3D.new()
	exit_label.name = "ExitLabel"
	exit_label.text = "SALIDA  ·  E"
	exit_label.font_size = 46
	exit_label.pixel_size = 0.009
	exit_label.position = origin + Vector3(0, 2.4, 8.72)
	exit_label.rotation.y = PI
	room.add_child(exit_label)
	var service_label := Label3D.new()
	service_label.name = "ServiceLabel"
	service_label.text = str(spec["service"]) + "  ·  E"
	service_label.font_size = 54
	service_label.pixel_size = 0.01
	service_label.outline_size = 6
	service_label.position = origin + Vector3(4.0, 2.0, -4.55)
	room.add_child(service_label)
	if bool(spec.get("residential", false)):
		clerk.queue_free()
		service_label.queue_free()
	if spec.has("secondary"):
		var second := Label3D.new()
		second.name = "SecondaryLabel"
		second.text = str(spec["secondary"]) + "  ·  E"
		second.font_size = 50
		second.pixel_size = 0.009
		second.outline_size = 6
		second.position = origin + Vector3(-4.8, 2.4, -4.55)
		room.add_child(second)
	if kind == "bank":
		var atm_label := Label3D.new()
		atm_label.name = "AtmLabel"
		atm_label.text = "RETIRAR 100 €  ·  E"
		atm_label.font_size = 50
		atm_label.pixel_size = 0.009
		atm_label.outline_size = 6
		atm_label.position = origin + Vector3(-4.8, 2.4, -4.55)
		room.add_child(atm_label)


func _make_market(origin: Vector3, wood: Material, metal: Material, accent: Material, mats: SectorMaterials) -> void:
	var stock: Array[Material] = [
		mats.plain("market_stock_coral", Color("b9634d")),
		mats.plain("market_stock_olive", Color("718265")),
		mats.plain("market_stock_cream", Color("e5d7ac")),
		mats.plain("market_stock_blue", Color("598698")),
	]
	_box("Checkout", Vector3(4.7, 1.0, 0.8), origin + Vector3(4.0, 0.5, -5.5), wood, true)
	_box("Register", Vector3(0.55, 0.42, 0.48), origin + Vector3(2.9, 1.22, -5.5), metal)
	_box("CheckoutConveyor", Vector3(2.1, 0.06, 0.6), origin + Vector3(4.3, 1.04, -5.5), metal)
	for aisle in [-3.5, 0.0]:
		for level in range(3):
			_box("Shelf", Vector3(1.2, 0.12, 4.0), origin + Vector3(aisle, 0.8 + level * 0.8, -1.2), metal)
			for item in range(8):
				for side in [-1.0, 1.0]:
					_box("Pack", Vector3(0.22, 0.34 + 0.06 * ((item + level) % 2), 0.29), origin + Vector3(aisle + side * 0.34, 1.02 + level * 0.8, -2.7 + item * 0.43), stock[(item + level + (0 if side < 0 else 2)) % stock.size()])
		_box("ShelfBase", Vector3(1.2, 0.75, 4.0), origin + Vector3(aisle, 0.38, -1.2), wood, true)
		_box("AisleEnd", Vector3(1.22, 0.38, 0.08), origin + Vector3(aisle, 2.7, 0.85), accent)
	for door in range(3):
		_box("ColdCase", Vector3(1.3, 2.5, 0.55), origin + Vector3(-4.6 + door * 1.5, 1.25, -8.45), metal)
		_box("ColdCaseGlass", Vector3(1.12, 2.1, 0.04), origin + Vector3(-4.6 + door * 1.5, 1.3, -8.12), accent)
	for crate in range(4):
		_box("ProduceCrate", Vector3(0.85, 0.42, 0.85), origin + Vector3(-5.9, 0.35, 1.2 + crate * 1.1), wood)
		for piece in range(3):
			_sphere("Produce", 0.16, origin + Vector3(-6.15 + piece * 0.25, 0.63, 1.0 + crate * 1.1), stock[(crate + 1) % stock.size()])
	_wall_label("MarketDepartment", "FRUTA  ·  FRESCOS  ·  CAJA", origin + Vector3(0, 3.45, -8.6), Color("e6f2ea"))


func _make_restaurant(origin: Vector3, wood: Material, metal: Material, accent: Material, mats: SectorMaterials) -> void:
	var linen := mats.textured("restaurant_linen", "plaster003", Color("eee2cf"), 0.9, 0.94)
	var ceramic := mats.plain("restaurant_ceramic", Color("f3eadc"), 0.35)
	var leaf := mats.plain("restaurant_leaf", Color("4f7058"), 0.9)
	var dark := mats.plain("restaurant_frame", Color("3b302a"), 0.7)
	_box("Bar", Vector3(5.0, 1.1, 0.95), origin + Vector3(4.0, 0.55, -5.5), wood, true)
	_box("BarTop", Vector3(5.1, 0.12, 1.05), origin + Vector3(4.0, 1.15, -5.5), accent)
	_box("BarBack", Vector3(5.3, 2.3, 0.16), origin + Vector3(3.9, 1.55, -8.75), wood)
	for level in range(2):
		_box("BarShelf", Vector3(4.8, 0.1, 0.45), origin + Vector3(3.9, 1.5 + level * 0.9, -8.45), accent)
	for row in range(2):
		for col in range(2):
			var center := origin + Vector3(-4.0 + col * 3.0, 0, -3.5 + row * 4.0)
			_box("TableTop", Vector3(1.55, 0.1, 1.35), center + Vector3(0, 0.8, 0), wood, true)
			_box("TableLinen", Vector3(1.42, 0.045, 1.23), center + Vector3(0, 0.88, 0), linen)
			_box("TableLeg", Vector3(0.18, 0.75, 0.18), center + Vector3(0, 0.38, 0), metal)
			for side in [-1.0, 1.0]:
				_box("ChairSeat", Vector3(0.55, 0.12, 0.5), center + Vector3(side * 1.15, 0.48, 0), wood)
				_box("ChairBack", Vector3(0.12, 0.55, 0.5), center + Vector3(side * 1.43, 0.78, 0), wood)
				_cylinder("Plate", 0.24, 0.025, center + Vector3(side * 0.34, 0.93, 0), ceramic)
				_cylinder("Glass", 0.055, 0.2, center + Vector3(side * 0.34, 1.03, 0.38), ceramic)
			_box("TableMenu", Vector3(0.18, 0.26, 0.05), center + Vector3(0, 1.03, -0.3), dark)
	for bottle in range(9):
		var bottle_mesh := CylinderMesh.new()
		bottle_mesh.top_radius = 0.08
		bottle_mesh.bottom_radius = 0.1
		bottle_mesh.height = 0.4
		var visual := MeshInstance3D.new()
		visual.name = "BarBottle"
		visual.mesh = bottle_mesh
		visual.material_override = accent
		visual.position = origin + Vector3(2.2 + bottle * 0.43, 1.44, -5.65)
		room.add_child(visual)
	var guest := HumanModel.new("female_casual")
	guest.name = "Guest"
	guest.position = origin + Vector3(-4.8, 0, 1.2)
	room.add_child(guest)
	for corner in [-5.8, 5.8]:
		_cylinder("PlantPot", 0.34, 0.55, origin + Vector3(corner, 0.28, 5.2), accent)
		_cylinder("PlantStem", 0.04, 0.9, origin + Vector3(corner, 0.98, 5.2), wood)
		for branch in range(5):
			_sphere("PlantLeaf", 0.28, origin + Vector3(corner + sin(float(branch) * TAU / 5.0) * 0.3, 1.35 + (branch % 2) * 0.17, 5.2 + cos(float(branch) * TAU / 5.0) * 0.3), leaf)
	_box("MenuBoard", Vector3(3.0, 1.45, 0.09), origin + Vector3(-2.3, 2.0, -8.7), dark)
	_wall_label("MenuText", ("EL ESPIGÓN" if kind == "seafood" else "LA BRISA") + "\nPESCAÍTO  ·  ARROZ\nMENÚ DEL DÍA", origin + Vector3(-2.3, 2.05, -8.62), Color("f4e8c6"))
	for wall_x in [-6.8, 6.8]:
		_box("WallPicture", Vector3(0.09, 1.3, 1.7), origin + Vector3(wall_x, 2.2, 1.2), dark)
		_box("WallPictureInset", Vector3(0.1, 1.05, 1.45), origin + Vector3(wall_x + (0.06 if wall_x < 0 else -0.06), 2.2, 1.2), accent)


func _make_cafe(origin: Vector3, wood: Material, metal: Material, accent: Material, mats: SectorMaterials) -> void:
	var teal := mats.textured("cafe_tiles", "tiles040", Color("487d7b"), 0.7, 0.55)
	var bread := mats.textured("cafe_bread", "plaster003", Color("c99a59"), 0.15, 0.95)
	var ceramic := mats.plain("cafe_ceramic", Color("f3e9cf"), 0.28)
	var chalk := mats.plain("cafe_chalkboard", Color("283b3a"), 0.95)
	var cushion := mats.textured("cafe_upholstery", "plaster003", Color("9f603f"), 0.35, 0.98)
	_box("CoffeeCounter", Vector3(5.4, 1.05, 1.15), origin + Vector3(3.8, 0.525, -5.8), teal, true)
	_box("CoffeeTop", Vector3(5.6, 0.12, 1.3), origin + Vector3(3.8, 1.1, -5.8), wood)
	_box("CoffeeMachine", Vector3(1.4, 0.58, 0.65), origin + Vector3(3.3, 1.45, -6.0), metal)
	_box("CoffeeMachineFace", Vector3(1.15, 0.22, 0.04), origin + Vector3(3.3, 1.58, -5.66), chalk)
	_box("DripTray", Vector3(1.25, 0.055, 0.36), origin + Vector3(3.3, 1.2, -5.55), metal)
	for x in [3.0, 3.6]:
		_cylinder("CoffeeSpout", 0.065, 0.15, origin + Vector3(x, 1.4, -5.51), metal)
		_cylinder("CoffeeCup", 0.09, 0.13, origin + Vector3(x, 1.29, -5.48), ceramic)
	_box("PastryTray", Vector3(1.4, 0.045, 0.7), origin + Vector3(5.3, 1.19, -5.7), ceramic)
	for i in range(6):
		_box("Pastry", Vector3(0.32, 0.16, 0.22), origin + Vector3(4.86 + (i % 3) * 0.4, 1.28, -5.87 + (i / 3) * 0.32), bread)
	_box("CoffeeBack", Vector3(5.5, 1.1, 0.65), origin + Vector3(3.6, 0.55, -8.4), wood, true)
	for level in [1.75, 2.55]:
		_box("CupShelf", Vector3(5.1, 0.09, 0.45), origin + Vector3(3.6, level, -8.4), wood)
		for i in range(10):
			_cylinder("ShelfCup", 0.085, 0.15, origin + Vector3(1.4 + i * 0.46, level + 0.12, -8.3), ceramic)
	# A window lounge and long upholstered bench leave a clear central aisle.
	_box("CafeBench", Vector3(1.1, 0.46, 8.2), origin + Vector3(-5.95, 0.3, -0.7), wood, true)
	_box("BenchCushion", Vector3(1.1, 0.15, 8.2), origin + Vector3(-5.95, 0.6, -0.7), cushion)
	_box("BenchBack", Vector3(0.22, 0.8, 8.2), origin + Vector3(-6.45, 0.93, -0.7), cushion)
	for z in [-3.5, -0.5, 2.5]:
		_cylinder("CafeTable", 0.7, 0.1, origin + Vector3(-4.6, 0.8, z), wood)
		_cylinder("CafeTableStem", 0.075, 0.73, origin + Vector3(-4.6, 0.37, z), metal)
		_cylinder("CafeTableFoot", 0.38, 0.06, origin + Vector3(-4.6, 0.03, z), metal)
		_cylinder("TableSaucer", 0.14, 0.025, origin + Vector3(-4.6, 0.87, z), ceramic)
		_cylinder("TableCup", 0.085, 0.15, origin + Vector3(-4.6, 0.96, z), ceramic)
		_box("CafeChairSeat", Vector3(0.55, 0.12, 0.55), origin + Vector3(-3.4, 0.5, z), wood)
		_box("CafeChairBack", Vector3(0.12, 0.65, 0.55), origin + Vector3(-3.15, 0.77, z), wood)
		for dx in [-0.2, 0.2]:
			for dz in [-0.2, 0.2]:
				_box("CafeChairLeg", Vector3(0.055, 0.47, 0.055), origin + Vector3(-3.4 + dx, 0.235, z + dz), metal)
	_box("WindowCounter", Vector3(3.4, 0.12, 0.65), origin + Vector3(4.4, 1.0, 7.7), wood, true)
	for x in [3.4, 4.4, 5.4]:
		_cylinder("WindowStool", 0.27, 0.12, origin + Vector3(x, 0.65, 6.8), wood)
		_cylinder("WindowStoolStem", 0.055, 0.6, origin + Vector3(x, 0.3, 6.8), metal)
		_cylinder("WindowStoolBase", 0.3, 0.05, origin + Vector3(x, 0.025, 6.8), metal)
	_box("CoffeeMenu", Vector3(4.1, 2.2, 0.08), origin + Vector3(-3.7, 2.0, -8.7), chalk)
	_wall_label("CoffeeMenuText", "BRISA Y LIMÓN\nCAFÉ RECIÉN HECHO\nTOSTADA · ACEITE · TOMATE\nDESAYUNO  8 €", origin + Vector3(-3.7, 2.05, -8.64), Color("f3e7c7"))
	var guest := HumanModel.new("female_casual")
	guest.name = "CafeGuest"
	guest.position = origin + Vector3(3.0, 0, 5.7)
	guest.rotation.y = PI
	room.add_child(guest)


func _make_palm_restaurant(origin: Vector3, wood: Material, metal: Material, accent: Material, mats: SectorMaterials) -> void:
	var linen := mats.textured("palmera_linen", "plaster003", Color("e9dfbf"), 0.45, 0.95)
	var tile := mats.textured("palmera_tiles", "tiles040", Color("567967"), 0.8, 0.68)
	var stone := mats.textured("palmera_stone", "rock020", Color("b4a487"), 1.2, 0.84)
	var ceramic := mats.plain("palmera_ceramic", Color("edece0"), 0.3)
	_box("HostCounter", Vector3(3.8, 1.1, 0.95), origin + Vector3(4.4, 0.55, -5.8), tile, true)
	_box("HostTop", Vector3(3.95, 0.12, 1.05), origin + Vector3(4.4, 1.15, -5.8), stone)
	# Open kitchen pass, with its own tiled back wall and stainless work surface.
	_box("KitchenPassBase", Vector3(7.4, 1.05, 0.55), origin + Vector3(-2.8, 0.525, -6.0), stone, true)
	_box("KitchenPassTop", Vector3(7.6, 0.12, 0.9), origin + Vector3(-2.8, 1.1, -6.0), wood)
	_box("KitchenCanopy", Vector3(7.4, 0.6, 0.7), origin + Vector3(-2.8, 3.35, -6.0), wood)
	for x in [-6.35, 0.75]:
		_box("KitchenPassPost", Vector3(0.18, 2.8, 0.25), origin + Vector3(x, 1.8, -6.0), wood)
	_box("KitchenTiles", Vector3(7.3, 2.6, 0.1), origin + Vector3(-2.8, 1.7, -8.7), tile)
	_box("KitchenWorktop", Vector3(6.7, 0.15, 1.2), origin + Vector3(-2.8, 1.0, -8.0), metal)
	_box("KitchenUnits", Vector3(6.7, 0.9, 1.0), origin + Vector3(-2.8, 0.45, -8.0), metal, true)
	for x in [-5.1, -4.4, -3.7]:
		_cylinder("KitchenPan", 0.23, 0.14, origin + Vector3(x, 1.15, -7.9), metal)
	for row in range(2):
		for col in range(2):
			var table := origin + Vector3(-3.9 + col * 7.7, 0, -2.6 + row * 6.0)
			_box("DiningTable", Vector3(2.2, 0.12, 1.65), table + Vector3(0, 0.8, 0), wood, true)
			_box("TableRunner", Vector3(0.65, 0.035, 1.6), table + Vector3(0, 0.88, 0), linen)
			for side in [-1.0, 1.0]:
				for dx in [-0.65, 0.65]:
					_box("DiningLeg", Vector3(0.09, 0.74, 0.09), table + Vector3(dx, 0.37, side * 0.6), wood)
					_cylinder("DinnerPlate", 0.23, 0.025, table + Vector3(dx, 0.9, side * 0.48), ceramic)
					_cylinder("DinnerGlass", 0.055, 0.2, table + Vector3(dx + 0.24, 1.0, side * 0.57), ceramic)
					var chair := table + Vector3(dx, 0, side * 1.35)
					_box("DiningSeat", Vector3(0.55, 0.12, 0.55), chair + Vector3(0, 0.5, 0), wood)
					_box("DiningBack", Vector3(0.55, 0.6, 0.1), chair + Vector3(0, 0.82, side * 0.23), wood)
					for lx in [-0.2, 0.2]:
						for lz in [-0.2, 0.2]:
							_box("DiningChairLeg", Vector3(0.055, 0.46, 0.055), chair + Vector3(lx, 0.23, lz), wood)
	_wall_label("PalmeraMenu", "LA PALMERA\nCOCINA MEDITERRÁNEA · MENÚ 35 €", origin + Vector3(1.4, 3.8, -8.6), Color("f3e5c5"))
	var chef := HumanModel.new("male_casual")
	chef.name = "KitchenStaff"
	chef.position = origin + Vector3(-2.3, 0, -7.0)
	chef.rotation.y = PI
	room.add_child(chef)


func _make_bank(origin: Vector3, wood: Material, metal: Material, accent: Material, mats: SectorMaterials) -> void:
	var dark := mats.textured("bank_dark", "asphalt010", Color("303c43"), 0.7, 0.58)
	var stone := mats.textured("bank_counter", "rock020", Color("bbc3c1"), 1.2, 0.42)
	var screen := mats.plain("bank_atm_screen", Color("447f8d"), 0.12)
	screen.emission_enabled = true
	screen.emission = Color("3c8995")
	screen.emission_energy_multiplier = 0.8
	_box("TellerCounter", Vector3(5.1, 1.05, 0.85), origin + Vector3(4.0, 0.53, -5.7), stone, true)
	_box("TellerTop", Vector3(5.2, 0.12, 0.98), origin + Vector3(4.0, 1.12, -5.7), accent)
	for window in range(3):
		var x := 2.35 + float(window) * 1.65
		_box("TellerDivider", Vector3(0.07, 1.1, 0.15), origin + Vector3(x, 1.74, -5.75), metal)
		_box("TellerWindow", Vector3(1.4, 0.78, 0.045), origin + Vector3(x + 0.78, 1.79, -5.72), screen)
	_box("AtmBody", Vector3(1.45, 2.45, 0.66), origin + Vector3(-4.8, 1.23, -7.2), dark, true)
	_box("AtmScreen", Vector3(0.88, 0.55, 0.06), origin + Vector3(-4.8, 1.68, -6.83), screen)
	_box("AtmKeypad", Vector3(0.7, 0.12, 0.4), origin + Vector3(-4.8, 1.02, -6.84), metal)
	_box("AtmSlot", Vector3(0.64, 0.045, 0.08), origin + Vector3(-4.8, 0.73, -6.82), accent)
	for row in range(2):
		_box("WaitingBench", Vector3(2.4, 0.15, 0.62), origin + Vector3(-3.3, 0.5, 1.8 + float(row) * 2.0), wood, true)
		_box("WaitingBenchBack", Vector3(2.4, 0.75, 0.14), origin + Vector3(-3.3, 0.91, 2.14 + float(row) * 2.0), wood)
		for x_offset in [-0.95, 0.95]:
			_box("BenchLeg", Vector3(0.12, 0.46, 0.42), origin + Vector3(-3.3 + x_offset, 0.23, 1.8 + float(row) * 2.0), metal)
	_box("VaultFrame", Vector3(2.15, 2.9, 0.18), origin + Vector3(0.1, 1.45, -8.7), metal)
	_box("VaultDoor", Vector3(1.75, 2.5, 0.2), origin + Vector3(0.1, 1.35, -8.54), dark)
	_cylinder("VaultWheel", 0.34, 0.08, origin + Vector3(0.1, 1.4, -8.4), accent)
	_box("BrandPanel", Vector3(4.1, 0.7, 0.08), origin + Vector3(0, 3.7, -8.66), accent)
	_wall_label("BrandText", "CAJA PONIENTE", origin + Vector3(0, 3.7, -8.59), Color("ecf4ef"))
	for post in range(3):
		_cylinder("QueuePost", 0.07, 0.9, origin + Vector3(0.1, 0.45, -3.4 + float(post) * 1.5), metal)
		if post < 2:
			_box("QueueRope", Vector3(0.04, 0.04, 1.5), origin + Vector3(0.1, 0.83, -2.65 + float(post) * 1.5), accent)


func _make_jewellery(origin: Vector3, wood: Material, metal: Material, accent: Material, mats: SectorMaterials) -> void:
	var velvet := mats.textured("jewellery_velvet", "plaster003", Color("52646a"), 0.7, 0.95)
	var stone := mats.textured("jewellery_counter", "rock020", Color("c5c5b8"), 1.2, 0.38)
	var gold := mats.plain("jewellery_gold", Color("cfac64"), 0.22, 0.8)
	var gems: Array[Material] = [
		mats.plain("jewellery_ruby", Color("a44950"), 0.15),
		mats.plain("jewellery_emerald", Color("4d9983"), 0.15),
		mats.plain("jewellery_sapphire", Color("5d80ab"), 0.15),
	]
	var glass := mats.plain("jewellery_glass", Color(0.65, 0.84, 0.88, 0.33), 0.05)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_box("CentralRunner", Vector3(2.1, 0.025, 11.5), origin + Vector3(0.8, 0.02, 0.5), velvet)
	for display in range(3):
		var x := -5.1 + float(display) * 2.7
		_box("DisplayBase", Vector3(1.9, 0.9, 1.4), origin + Vector3(x, 0.45, -2.6), wood, true)
		_box("DisplayTop", Vector3(1.95, 0.1, 1.45), origin + Vector3(x, 0.95, -2.6), velvet)
		_box("DisplayGlass", Vector3(1.82, 0.67, 1.32), origin + Vector3(x, 1.33, -2.6), glass)
		for ornament in range(3):
			var piece_x := x - 0.5 + float(ornament) * 0.5
			_cylinder("JewelleryStand", 0.16, 0.08, origin + Vector3(piece_x, 1.06, -2.6), stone)
			_sphere("Gemstone", 0.105, origin + Vector3(piece_x, 1.2, -2.6), gems[(display + ornament) % gems.size()])
			_cylinder("GoldSetting", 0.08, 0.05, origin + Vector3(piece_x, 1.12, -2.6), gold)
	_box("CashierCounter", Vector3(4.8, 1.0, 0.9), origin + Vector3(4.0, 0.5, -5.7), stone, true)
	_box("CounterVelvet", Vector3(4.9, 0.1, 1.0), origin + Vector3(4.0, 1.05, -5.7), velvet)
	for prize in range(5):
		var at := origin + Vector3(2.6 + float(prize) * 0.68, 1.25, -5.6)
		_cylinder("GoldDisplay", 0.16, 0.2, at, gold)
		_sphere("GoldDisplayGem", 0.105, at + Vector3.UP * 0.2, gems[prize % gems.size()])
	_box("SecurityCase", Vector3(1.7, 2.1, 0.45), origin + Vector3(-5.7, 1.05, -8.58), metal)
	_box("SecurityDoor", Vector3(1.42, 1.82, 0.07), origin + Vector3(-5.7, 1.05, -8.3), accent)
	_box("RearBrandPanel", Vector3(4.7, 0.75, 0.08), origin + Vector3(0.4, 3.55, -8.67), accent)
	_wall_label("RearBrandText", "JOYERÍA FARO", origin + Vector3(0.4, 3.56, -8.58), Color("f2ead6"))
	for wall_x in [-6.8, 6.8]:
		_box("WallMirror", Vector3(0.08, 2.0, 1.2), origin + Vector3(wall_x, 2.25, 2.3), stone)
		_box("WallMirrorInset", Vector3(0.09, 1.7, 0.9), origin + Vector3(wall_x + (0.05 if wall_x < 0 else -0.05), 2.25, 2.3), glass)


func _make_church(origin: Vector3, wood: Material, accent: Material, mats: SectorMaterials) -> void:
	var stone := mats.textured("church_stone", "rock020", Color("dbcfb8"), 2.0, 0.9)
	var gold := mats.plain("church_gold", Color("b99a60"), 0.4, 0.55)
	var red := mats.plain("church_red_glass", Color(0.72, 0.22, 0.21, 0.47), 0.13)
	red.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var blue := mats.plain("church_blue_glass", Color(0.18, 0.36, 0.65, 0.47), 0.13)
	blue.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_box("NaveRunner", Vector3(2.3, 0.04, 11.5), origin + Vector3(0, 0.02, 0.3), accent)
	for row in range(4):
		for side in [-1.0, 1.0]:
			var x: float = side * 3.6
			var z := -4.1 + row * 2.35
			_box("PewSeat", Vector3(3.7, 0.17, 0.68), origin + Vector3(x, 0.52, z), wood, true)
			_box("PewBack", Vector3(3.7, 0.85, 0.14), origin + Vector3(x, 1.02, z + 0.36), wood)
			for leg in [-1.55, 1.55]:
				_box("PewLeg", Vector3(0.15, 0.54, 0.55), origin + Vector3(x + leg, 0.27, z), wood)
	_box("AltarSteps", Vector3(10.2, 0.4, 2.2), origin + Vector3(0, 0.2, -7.4), stone, true)
	_box("Altar", Vector3(3.5, 1.1, 1.1), origin + Vector3(0, 0.95, -7.7), stone, true)
	_box("AltarCloth", Vector3(3.55, 0.08, 1.15), origin + Vector3(0, 1.53, -7.7), gold)
	_box("CrossVertical", Vector3(0.22, 2.1, 0.18), origin + Vector3(0, 2.9, -8.65), gold)
	_box("CrossHorizontal", Vector3(1.15, 0.22, 0.18), origin + Vector3(0, 3.25, -8.65), gold)
	for side in [-1.0, 1.0]:
		_box("StainedGlassRed", Vector3(1.2, 2.0, 0.07), origin + Vector3(side * 5.1, 2.4, 9.03), red)
		_box("StainedGlassBlue", Vector3(1.2, 2.0, 0.075), origin + Vector3(side * 3.3, 2.4, 9.04), blue)
	_box("CandleStand", Vector3(1.45, 0.75, 0.7), origin + Vector3(4.0, 0.37, -5.1), gold)
	for candle in range(5):
		_cylinder("Candle", 0.055, 0.34, origin + Vector3(3.45 + candle * 0.25, 0.91, -5.1), mats.plain("church_candle", Color("f3e7c9")))
	_wall_label("ChurchName", "ENCARNACIÓN", origin + Vector3(0, 3.65, -8.63), Color("eee1c8"))


func _make_mall(origin: Vector3, wood: Material, metal: Material, accent: Material, mats: SectorMaterials) -> void:
	var glass := mats.plain("mall_glass", Color(0.62, 0.81, 0.88, 0.27), 0.07)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var shop_colors := [
		mats.plain("mall_shop_coral", Color("a65e4e")),
		mats.plain("mall_shop_teal", Color("4a7480")),
		mats.plain("mall_shop_olive", Color("718268")),
	]
	_box("GalleryFloorStripe", Vector3(2.3, 0.02, 13.0), origin + Vector3(0, 0.02, -0.4), accent)
	for side in [-1.0, 1.0]:
		for stall in range(3):
			var z := -5.6 + float(stall) * 4.25
			var x: float = side * 5.9
			var color: Material = shop_colors[(stall + (0 if side < 0 else 1)) % shop_colors.size()]
			_box("BoutiqueFront", Vector3(0.16, 2.6, 3.7), origin + Vector3(x, 1.35, z), glass)
			_box("BoutiqueHeader", Vector3(0.25, 0.58, 3.8), origin + Vector3(x, 3.0, z), color)
			_box("BoutiqueDisplay", Vector3(0.75, 0.95, 1.0), origin + Vector3(x - side * 0.55, 0.48, z), wood)
			_box("BoutiqueProduct", Vector3(0.5, 0.7, 0.5), origin + Vector3(x - side * 0.55, 1.3, z), color)
	_box("FoodCounter", Vector3(3.4, 1.0, 0.8), origin + Vector3(4.0, 0.5, -5.1), wood, true)
	_box("FoodCounterTop", Vector3(3.5, 0.11, 0.85), origin + Vector3(4.0, 1.06, -5.1), accent)
	_box("InfoKiosk", Vector3(1.7, 1.1, 0.8), origin + Vector3(-3.4, 0.55, -5.6), metal)
	_box("InfoScreen", Vector3(1.4, 0.75, 0.08), origin + Vector3(-3.4, 1.48, -5.12), accent)
	_wall_label("MallGuide", "MODA  ·  LIBROS  ·  CAFÉ", origin + Vector3(0, 3.7, -8.6), Color("e4f0ec"))


func _glow(key: String, color: Color, energy: float = 1.6) -> StandardMaterial3D:
	if glow_materials.has(key):
		return glow_materials[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.resource_name = key
	mat.albedo_color = color.darkened(0.3)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	glow_materials[key] = mat
	return mat


## Casino: two roulette tables, a card table, a row of slot machines, a bar and
## a warm, dim light. Roulette at the counter, slots at the secondary point.
func _make_casino(origin: Vector3, wood: Material, metal: Material, mats: SectorMaterials) -> void:
	var felt := mats.textured("casino_felt", "plaster003", Color("1f5a3a"), 0.15, 0.95)
	var red := mats.textured("casino_red", "plaster003", Color("7a1f24"), 0.3, 0.8)
	var gold := mats.plain("casino_gold", Color("c9a44a"), 0.35, 0.8)
	_box("CasinoCarpet", Vector3(13.6, 0.02, 17.6), origin + Vector3(0, 0.01, 0), red)
	for table in range(2):
		var at := origin + Vector3(-3.5, 0, -3.8 + table * 5.0)
		_box("RouletteTable", Vector3(3.4, 0.85, 1.8), at + Vector3(0, 0.43, 0), wood, true)
		_box("RouletteFelt", Vector3(3.2, 0.03, 1.6), at + Vector3(0, 0.87, 0), felt)
		_cylinder("RouletteWheel", 0.42, 0.12, at + Vector3(-1.1, 0.95, 0), gold)
		_cylinder("RouletteCentre", 0.12, 0.2, at + Vector3(-1.1, 1.02, 0), wood)
		for chip in range(5):
			_cylinder("Chips", 0.05, 0.06 + chip * 0.02, at + Vector3(0.2 + chip * 0.22, 0.92, 0.3), red if chip % 2 == 0 else gold)
	_box("CardTable", Vector3(2.4, 0.8, 1.4), origin + Vector3(1.0, 0.4, 1.8), wood, true)
	_box("CardFelt", Vector3(2.2, 0.03, 1.2), origin + Vector3(1.0, 0.82, 1.8), felt)
	for slot in range(5):
		var at := origin + Vector3(-6.3, 0, -6.5 + slot * 1.3)
		_box("SlotMachine", Vector3(0.9, 1.7, 0.8), at + Vector3(0, 0.85, 0), metal, true)
		_box("SlotScreen", Vector3(0.05, 0.55, 0.6), at + Vector3(0.46, 1.25, 0), _glow("casino_slot_%d" % (slot % 3), [Color("ff4f6a"), Color("ffd24a"), Color("4ad8ff")][slot % 3]))
		_box("SlotTopper", Vector3(0.9, 0.25, 0.8), at + Vector3(0, 1.85, 0), gold)
	_box("CasinoBar", Vector3(4.5, 1.1, 0.9), origin + Vector3(4.0, 0.55, -5.5), wood, true)
	_box("CasinoBarTop", Vector3(4.6, 0.1, 1.0), origin + Vector3(4.0, 1.13, -5.5), gold)
	_box("CasinoNeon", Vector3(8.0, 0.35, 0.06), origin + Vector3(0, 3.7, -8.7), _glow("casino_neon", Color("ff5c8a"), 2.4))
	_wall_label("CasinoTitle", "CASINO COSTA TROPICAL", origin + Vector3(0, 3.1, -8.6), Color("ffe2a0"))


## Gun shop: counter, wall racks with the real weapon models, ammo crates.
func _make_gun_shop(origin: Vector3, wood: Material, metal: Material, accent: Material, mats: SectorMaterials) -> void:
	_box("GunCounter", Vector3(6.0, 1.05, 0.9), origin + Vector3(3.0, 0.53, -5.5), wood, true)
	_box("GunCounterGlass", Vector3(5.8, 0.06, 0.8), origin + Vector3(3.0, 1.08, -5.5), accent)
	_box("GunRack", Vector3(12.0, 2.6, 0.2), origin + Vector3(0, 1.9, -8.7), wood)
	var models := ["pistol", "smg_p90", "shotgun", "rifle", "revolver"]
	var scales := [0.03, 0.058, 0.135, 0.125, 0.045]
	for i in range(models.size()):
		var scene := load("res://assets/third_party/quaternius/weapons/%s.fbx" % models[i]) as PackedScene
		if scene == null:
			continue
		var gun := scene.instantiate() as Node3D
		gun.scale = Vector3.ONE * float(scales[i])
		gun.rotation.y = PI * 0.5 if models[i] in ["pistol", "revolver"] else 0.0
		var holder := Node3D.new()
		holder.name = "RackGun"
		holder.position = origin + Vector3(-4.8 + i * 2.3, 1.4 + (i % 2) * 0.9, -8.45)
		holder.rotation.y = -PI * 0.5
		holder.add_child(gun)
		room.add_child(holder)
		for node in gun.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).material_override = mats.plain("rack_gun_metal", Color("2e3033"), 0.4, 0.6)
	for crate in range(4):
		_box("AmmoCrate", Vector3(0.8, 0.45, 0.55), origin + Vector3(-5.8, 0.23 + (crate % 2) * 0.46, -2.0 + int(crate / 2) * 0.7), mats.plain("ammo_crate", Color("4d5a3a"), 0.8))
	_box("TargetBoard", Vector3(0.1, 1.6, 1.2), origin + Vector3(-6.7, 1.6, 2.5), mats.plain("target_paper", Color("e8e2d2"), 0.9))
	_wall_label("GunShopRules", "LICENCIA OBLIGATORIA  ·  NO SE ADMITEN DEVOLUCIONES", origin + Vector3(0, 3.8, -8.6), Color("e8e2d2"))


## Nightclub: dark room, lit dance floor tiles, DJ booth, coloured lights, bar.
func _make_nightclub(origin: Vector3, metal: Material, mats: SectorMaterials) -> void:
	var black := mats.plain("club_black", Color("121216"), 0.6)
	_box("ClubFloor", Vector3(13.6, 0.02, 17.6), origin + Vector3(0, 0.01, 0), black)
	var colors := [Color("ff3fa4"), Color("3fd2ff"), Color("ffd23f"), Color("7a3fff")]
	for x in range(4):
		for z in range(4):
			_box("DanceTile", Vector3(1.1, 0.03, 1.1), origin + Vector3(-3.6 + x * 1.2, 0.03, -2.0 + z * 1.2), _glow("club_tile_%d" % ((x + z) % 4), colors[(x + z) % 4], 1.2))
	_box("DJBooth", Vector3(3.2, 1.2, 1.0), origin + Vector3(-1.8, 0.6, -7.3), metal, true)
	_box("DJDecks", Vector3(2.4, 0.08, 0.6), origin + Vector3(-1.8, 1.24, -7.3), _glow("club_decks", Color("3fd2ff"), 0.8))
	for speaker in [-5.2, 1.6]:
		_box("Speaker", Vector3(1.0, 2.2, 0.9), origin + Vector3(speaker, 1.1, -7.8), black, true)
	_box("ClubBar", Vector3(4.5, 1.1, 0.9), origin + Vector3(4.0, 0.55, -5.5), metal, true)
	_box("ClubBarGlow", Vector3(4.5, 0.08, 0.95), origin + Vector3(4.0, 1.12, -5.5), _glow("club_bar", Color("ff3fa4"), 1.8))
	for i in range(3):
		var light := OmniLight3D.new()
		light.name = "ClubLight"
		light.position = origin + Vector3(-3.0 + i * 2.5, 3.6, -1.0)
		light.light_color = colors[i]
		light.light_energy = 2.5
		light.omni_range = 7.0
		room.add_child(light)
	_wall_label("ClubName", "LEVANTE", origin + Vector3(0, 3.4, -8.6), Color("ff8fd0"))
	for dancer in range(4):
		var person := Pedestrian.new()
		person.model_name = HumanModel.MODELS[(dancer * 3) % HumanModel.MODELS.size()]
		person.activity = "dance"
		person.activity_phase = dancer * 1.4
		person.name = "Dancer"
		person.position = origin + Vector3(-3.4 + dancer * 1.3, 0, -1.2 + (dancer % 2) * 1.5)
		person.rotation.y = dancer * 1.3
		room.add_child(person)


func _box(label: String, size: Vector3, at: Vector3, material: Material, solid: bool = false) -> void:
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.set_meta("detail_kind", label)
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = at
	visual.material_override = material
	room.add_child(visual)
	if label in ["ShopWindow", "GlassDoor", "StainedWindow", "ChurchDoor", "DisplayGlass", "BoutiqueFront"]:
		var pane := BreakableGlass.new()
		pane.name = label + "Shots"
		pane.configure(visual, size)
		room.add_child(pane, true)
	if solid:
		var body := StaticBody3D.new()
		body.name = label + "Collision"
		body.set_meta("detail_kind", label)
		body.position = at
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		collision.shape = box
		body.add_child(collision)
		room.add_child(body)


func _cylinder(label: String, radius: float, height: float, at: Vector3, material: Material) -> void:
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.set_meta("detail_kind", label)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	visual.mesh = mesh
	visual.position = at
	visual.material_override = material
	room.add_child(visual)


func _sphere(label: String, radius: float, at: Vector3, material: Material) -> void:
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.set_meta("detail_kind", label)
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	visual.mesh = mesh
	visual.position = at
	visual.material_override = material
	room.add_child(visual)


func _wall_label(label: String, content: String, at: Vector3, tint: Color) -> void:
	var letters := Label3D.new()
	letters.name = label
	letters.text = content
	letters.font_size = 48
	letters.pixel_size = 0.006
	letters.outline_size = 4
	letters.modulate = tint
	letters.position = at
	room.add_child(letters)
