extends Node3D

const VehicleScript = preload("res://scripts/vehicle.gd")
const PedestrianScript = preload("res://scripts/pedestrian.gd")
const PalmScene = preload("res://assets/procedural/palm.glb")

var materials: Dictionary = {}
var rng := RandomNumberGenerator.new()
var sun_light: DirectionalLight3D
var road_network: RoadNetwork
var vehicle_spawns: Dictionary = {}


func _ready() -> void:
	rng.seed = 7401
	road_network = RoadNetwork.load_default()
	_create_light()
	_create_land()
	_create_roads()
	_create_buildings()
	_create_prom_and_beach()
	_create_landmarks()
	_create_vehicle()
	_create_people_and_traffic()


const TEXTURE_DIR := "res://assets/third_party/ambientcg/"


## Shared material cache. With texture_id, a CC0 ambientCG albedo/normal pair is
## applied in world-space triplanar mapping (tile_m metres per repeat), tinted by color.
func _material(key: String, color: Color, roughness: float = 0.9, texture_id: String = "", tile_m: float = 4.0) -> StandardMaterial3D:
	if materials.has(key):
		return materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if texture_id != "":
		mat.albedo_texture = load(TEXTURE_DIR + texture_id + "_color.png") as Texture2D
		mat.normal_enabled = true
		mat.normal_texture = load(TEXTURE_DIR + texture_id + "_normal.png") as Texture2D
		mat.normal_scale = 0.8
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3.ONE / tile_m
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	materials[key] = mat
	return mat


func _box(label: String, center: Vector3, size: Vector3, mat: Material, solid: bool = false) -> Node3D:
	var parent: Node3D
	if solid:
		var body := StaticBody3D.new()
		body.name = label
		body.position = center
		add_child(body)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		body.add_child(collider)
		parent = body
	else:
		parent = Node3D.new()
		parent.name = label
		parent.position = center
		add_child(parent)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = mat
	parent.add_child(visual)
	if label in ["Shutter", "BeachUmbrella", "PromenadeStripe"]:
		parent.add_to_group("detail")
	return parent


func _create_light() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("78aec5")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9cdd3")
	env.ambient_light_energy = 0.38
	environment.environment = env
	add_child(environment)
	sun_light = DirectionalLight3D.new()
	sun_light.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun_light.light_color = Color("ffe0b0")
	sun_light.light_energy = 0.92
	sun_light.shadow_enabled = true
	add_child(sun_light)


func apply_quality(level: int) -> void:
	sun_light.shadow_enabled = level >= 2
	for node in get_tree().get_nodes_in_group("detail"):
		if node is Node3D:
			(node as Node3D).visible = level >= 1


func _create_land() -> void:
	_box("TownGround", Vector3(0, -0.5, -87), Vector3(600, 1, 355), _material("ground", Color("c9c7a4"), 0.95, "ground037", 6.0), true)
	_box("Sea", Vector3(0, -0.28, 208), Vector3(900, 0.35, 214), _material("sea", Color("277f96"), 0.3))
	_box("Beach", Vector3(0, -0.04, 72), Vector3(600, 0.12, 58), _material("sand", Color("f2e2c0"), 0.95, "ground080", 4.0))
	for i in range(5):
		if i == 3:
			continue
		var x := -245.0 + i * 120.0
		var hill := SphereMesh.new()
		hill.radius = 1.0
		hill.height = 2.0
		var mound := MeshInstance3D.new()
		mound.mesh = hill
		mound.position = Vector3(x, 22, -330)
		mound.scale = Vector3(85, 33, 70)
		mound.material_override = _material("hill", Color("a6ad8c"), 0.95, "ground037", 10.0)
		add_child(mound)


func _create_roads() -> void:
	var asphalt := _material("asphalt", Color("b8b8b4"), 0.92, "asphalt010", 5.0)
	var curb := _material("curb", Color("f0e8d6"), 0.9, "pavingstones046", 2.0)
	var line := _material("line", Color("e6d9ab"))
	for road in road_network.roads:
		var start := float(road["from"])
		var finish := float(road["to"])
		var fixed := float(road["fixed"])
		var width := float(road["width"])
		var length := finish - start
		var middle := (start + finish) * 0.5
		var walk_offset := width * 0.5 + 2.0
		if str(road["axis"]) == "x":
			_box("EastWestRoad", Vector3(middle, 0.015, fixed), Vector3(length, 0.05, width), asphalt)
			_box("RoadLine", Vector3(middle, 0.046, fixed), Vector3(length, 0.008, 0.13), line)
			for side in [-1.0, 1.0]:
				_box("Walkway", Vector3(middle, 0.08, fixed + side * walk_offset), Vector3(length, 0.16, 4.0), curb)
		else:
			_box("NorthSouthRoad", Vector3(fixed, 0.025, middle), Vector3(width, 0.05, length), asphalt)
			_box("RoadLine", Vector3(fixed, 0.052, middle), Vector3(0.13, 0.008, length), line)
			for side in [-1.0, 1.0]:
				_box("Walkway", Vector3(fixed + side * walk_offset, 0.08, middle), Vector3(4.0, 0.16, length), curb)


func _is_near_north_south_road(x: float, margin: float) -> bool:
	for road in road_network.roads:
		if str(road["axis"]) == "z" and absf(x - float(road["fixed"])) < margin:
			return true
	return false


const FLOOR_HEIGHT := 3.2
const BUILDING_DEPTH := 15.0
const AWNING_COLORS := [Color("bd755e"), Color("e9e1cc"), Color("2d7784"), Color("a66845")]

var facade_rng := RandomNumberGenerator.new()
var facade_parts: Dictionary = {}  # part name -> Array[Transform3D]
var awning_colors: PackedColorArray = PackedColorArray()


func _create_buildings() -> void:
	var walls := [Color("eee4ca"), Color("eadac1"), Color("ddc3a4"), Color("e0b3a0"), Color("f1e9d7")]
	var roof := _material("roof", Color("e0b8a0"), 0.85, "roofingtiles006", 2.5)
	# Façade details use their own seed so the building layout (rng) stays stable.
	facade_rng.seed = 7402
	for part in ["window", "shutter", "door", "shop_window", "awning", "balcony_slab", "balcony_rail", "sill"]:
		facade_parts[part] = [] as Array[Transform3D]
	for x in range(-256, 270, 24):
		if _is_near_north_south_road(float(x), 17.0):
			continue
		for z in [-33.0, -54.0, -110.0, -132.0, -190.0]:
			if x > 0 and z == -190.0:
				continue
			var floors := rng.randi_range(2, 4)
			var height := floors * FLOOR_HEIGHT
			var width := rng.randf_range(16, 21)
			var color: Color = walls[rng.randi_range(0, walls.size() - 1)]
			var center := Vector3(x, 0, z)
			_box("Casa_%d_%d" % [x, int(z)], Vector3(x, height * 0.5, z), Vector3(width, height, BUILDING_DEPTH), _material("wall_%s" % color.to_html(), color, 0.92, "plaster003", 3.0), true)
			_box("Roof", Vector3(x, height + 0.17, z), Vector3(width + 0.6, 0.34, BUILDING_DEPTH + 0.6), roof)
			var street_normal := Vector3(0, 0, signf(_nearest_east_west_road(z) - z))
			_facade(center + street_normal * BUILDING_DEPTH * 0.5, street_normal, width, floors, true)
			_facade(center - street_normal * BUILDING_DEPTH * 0.5, -street_normal, width, floors, false)
			for side in [-1.0, 1.0]:
				var side_x: float = float(x) + side * width * 0.5
				if _faces_north_south_road(side_x, side):
					_facade(Vector3(side_x, 0, z), Vector3(side, 0, 0), BUILDING_DEPTH, floors, false)
	_add_instances("Windows", Vector3(1.4, 1.6, 0.10), _material("glass", Color("577b84"), 0.25), facade_parts["window"])
	_add_instances("Shutters", Vector3(0.35, 1.7, 0.12), _material("shutters", Color("5c766e")), facade_parts["shutter"], true)
	_add_instances("Sills", Vector3(1.7, 0.12, 0.28), _material("sill", Color("e9e1cc")), facade_parts["sill"], true)
	_add_instances("Doors", Vector3(1.3, 2.4, 0.14), _material("door", Color("5a3b2a")), facade_parts["door"])
	_add_instances("ShopWindows", Vector3(2.6, 2.1, 0.10), _material("shop_glass", Color("3d5a60"), 0.2), facade_parts["shop_window"])
	_add_instances("Awnings", Vector3(3.0, 0.12, 1.3), _vertex_color_material("awning"), facade_parts["awning"], true, awning_colors)
	_add_instances("BalconySlabs", Vector3(2.4, 0.16, 0.95), _material("balcony", Color("e9e1cc")), facade_parts["balcony_slab"], true)
	_add_instances("BalconyRails", Vector3(2.4, 0.95, 0.05), _material("iron", Color("394c5d"), 0.6), facade_parts["balcony_rail"], true)


func _faces_north_south_road(side_x: float, side: float) -> bool:
	for road in road_network.roads:
		var gap := float(road["fixed"]) - side_x
		if str(road["axis"]) == "z" and absf(gap) < 25.0 and signf(gap) == side:
			return true
	return false


func _nearest_east_west_road(z: float) -> float:
	var best := z
	var best_distance := INF
	for road in road_network.roads:
		if str(road["axis"]) == "x" and absf(float(road["fixed"]) - z) < best_distance:
			best_distance = absf(float(road["fixed"]) - z)
			best = float(road["fixed"])
	return best


## Lays out bays on one façade plane. Street façades get a door, shopfronts with
## awnings and occasional balconies; back and side façades get windows only.
func _facade(plane_center: Vector3, normal: Vector3, face_width: float, floors: int, street: bool) -> void:
	var face_basis := Basis(Vector3.UP, atan2(normal.x, normal.z))
	var tangent := face_basis.x
	var bays := maxi(2, int(face_width / 4.2))
	var spacing := face_width / bays
	var door_bay := facade_rng.randi_range(0, bays - 1)
	var has_shops := street and facade_rng.randf() < 0.6
	for bay in range(bays):
		var along := -face_width * 0.5 + spacing * (bay + 0.5)
		var base := plane_center + tangent * along
		for floor_index in range(floors):
			var y := floor_index * FLOOR_HEIGHT
			if floor_index == 0 and street:
				if bay == door_bay:
					_part("door", base + Vector3(0, 1.2, 0) + normal * 0.06, face_basis)
				elif has_shops:
					_part("shop_window", base + Vector3(0, 1.35, 0) + normal * 0.05, face_basis)
					_part("awning", base + Vector3(0, 2.75, 0) + normal * 0.65, face_basis)
					awning_colors.append(AWNING_COLORS[facade_rng.randi_range(0, AWNING_COLORS.size() - 1)])
				else:
					_window(base, y, normal, face_basis)
				continue
			_window(base, y, normal, face_basis)
			if street and floor_index >= 1 and facade_rng.randf() < 0.3:
				_part("balcony_slab", base + Vector3(0, y + 0.3, 0) + normal * 0.48, face_basis)
				_part("balcony_rail", base + Vector3(0, y + 0.85, 0) + normal * 0.93, face_basis)


func _window(base: Vector3, y: float, normal: Vector3, face_basis: Basis) -> void:
	var center := base + Vector3(0, y + 1.85, 0)
	_part("window", center + normal * 0.05, face_basis)
	_part("sill", center + Vector3(0, -0.86, 0) + normal * 0.12, face_basis)
	var tangent := face_basis.x
	for side in [-1.0, 1.0]:
		_part("shutter", center + tangent * side * 0.9 + normal * 0.08, face_basis)


func _part(kind: String, at: Vector3, face_basis: Basis) -> void:
	(facade_parts[kind] as Array).append(Transform3D(face_basis, at))


func _vertex_color_material(key: String) -> StandardMaterial3D:
	if materials.has(key):
		return materials[key]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	materials[key] = mat
	return mat


func _add_instances(label: String, size: Vector3, mat: Material, transforms: Array, detail: bool = false, colors: PackedColorArray = PackedColorArray()) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = not colors.is_empty()
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in range(transforms.size()):
		multi.set_instance_transform(i, transforms[i])
		if multi.use_colors:
			multi.set_instance_color(i, colors[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = label
	instance.multimesh = multi
	instance.material_override = mat
	add_child(instance)
	if detail:
		instance.add_to_group("detail")


func _create_prom_and_beach() -> void:
	_box("Promenade", Vector3(0, 0.06, 28), Vector3(590, 0.18, 26), _material("prom", Color("e6d6bb"), 0.85, "tiles040", 3.0), true)
	for i in range(-11, 12):
		var x := i * 24.0
		_box("PromenadeStripe", Vector3(x, 0.159, 28), Vector3(0.45, 0.01, 25), _material("tile", Color("9d9a85")))
		if i % 2 == 0:
			_palm(Vector3(x + 9.0, 0.0, 37.0))
			_box("Bench", Vector3(x + 2.0, 0.55, 22), Vector3(2.5, 0.25, 0.75), _material("bench", Color("835e43")))
	for i in range(-8, 9):
		_box("BeachUmbrella", Vector3(i * 30.0, 1.25, 65 + (i % 3) * 5), Vector3(3.2, 0.12, 3.2), _material("umbrella_%d" % (i % 3), [Color("d97060"), Color("e6dfb9"), Color("5697a0")][i % 3]))


func _palm(at: Vector3) -> void:
	var palm := PalmScene.instantiate() as Node3D
	palm.name = "Palm"
	palm.position = at
	add_child(palm)


func _create_landmarks() -> void:
	var stone := _material("stone", Color("d9b98f"), 0.95, "plaster003", 4.0)
	_create_penon(Vector3(230, 0, 135))
	_create_castle_mound(Vector3(125, 0, -228))
	_box("CastleBase", Vector3(125, 16, -228), Vector3(70, 33, 45), stone)
	for x in [91.0, 112.0, 138.0, 160.0]:
		_box("CastleTower", Vector3(x, 38, -228), Vector3(11, 24, 11), stone)
		_box("CastleParapet", Vector3(x, 50.5, -228), Vector3(12, 1.6, 12), stone)
	_box("CastleWall", Vector3(125, 36.0, -213), Vector3(80, 14, 5), stone)


func _create_castle_mound(at: Vector3) -> void:
	var rings := [Vector3(75, -1, 55), Vector3(63, 8, 45), Vector3(54, 20, 34)]
	var sides := 12
	var material := _material("castle_hill", Color("a9b08a"), 0.95, "ground037", 8.0)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	var collision_points := PackedVector3Array()
	for ring_index in range(rings.size()):
		for side in range(sides):
			collision_points.append(_hill_vertex(rings[ring_index], side, sides))
	for ring_index in range(rings.size() - 1):
		for side in range(sides):
			var next := (side + 1) % sides
			var a := _hill_vertex(rings[ring_index], side, sides)
			var b := _hill_vertex(rings[ring_index], next, sides)
			var c := _hill_vertex(rings[ring_index + 1], side, sides)
			var d := _hill_vertex(rings[ring_index + 1], next, sides)
			surface.add_vertex(a)
			surface.add_vertex(c)
			surface.add_vertex(b)
			surface.add_vertex(b)
			surface.add_vertex(c)
			surface.add_vertex(d)
	for side in range(sides):
		surface.add_vertex(_hill_vertex(rings[-1], side, sides))
		surface.add_vertex(Vector3(0, 20, 0))
		surface.add_vertex(_hill_vertex(rings[-1], (side + 1) % sides, sides))
	surface.generate_normals()
	var body := StaticBody3D.new()
	body.name = "CastleHill"
	body.position = at
	add_child(body)
	var visual := MeshInstance3D.new()
	visual.mesh = surface.commit()
	body.add_child(visual)
	var collider := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = collision_points
	collider.shape = shape
	body.add_child(collider)


func _hill_vertex(ring: Vector3, side: int, sides: int) -> Vector3:
	var angle := TAU * side / sides
	var irregular := 0.95 + 0.06 * sin(float(side * 5 + int(ring.y)))
	return Vector3(cos(angle) * ring.x * irregular, ring.y, sin(angle) * ring.z * irregular)


func _create_penon(at: Vector3) -> void:
	var rock := _material("rock", Color("c9cbc2"), 0.95, "rock020", 8.0)
	var rings := [Vector3(25, -2.5, 23), Vector3(22, 6, 20), Vector3(15, 17, 15), Vector3(7, 27, 7)]
	var sides := 11
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(rock)
	for ring_index in range(rings.size() - 1):
		for side in range(sides):
			var next := (side + 1) % sides
			var a := _rock_vertex(rings[ring_index], side, sides)
			var b := _rock_vertex(rings[ring_index], next, sides)
			var c := _rock_vertex(rings[ring_index + 1], side, sides)
			var d := _rock_vertex(rings[ring_index + 1], next, sides)
			surface.add_vertex(a)
			surface.add_vertex(c)
			surface.add_vertex(b)
			surface.add_vertex(b)
			surface.add_vertex(c)
			surface.add_vertex(d)
	for side in range(sides):
		surface.add_vertex(_rock_vertex(rings[-1], side, sides))
		surface.add_vertex(Vector3(1.0, 30.0, -2.0))
		surface.add_vertex(_rock_vertex(rings[-1], (side + 1) % sides, sides))
	surface.generate_normals()
	var penon := MeshInstance3D.new()
	penon.name = "PenonDelSanto"
	penon.mesh = surface.commit()
	penon.position = at
	add_child(penon)
	var white := _material("cross", Color("e5dfd0"))
	_box("Mirador", at + Vector3(0, 30.5, -2), Vector3(7, 1.0, 7), _material("stone", Color("d9b98f"), 0.95, "plaster003", 4.0))
	_box("CrossPost", at + Vector3(0, 34.5, -2), Vector3(0.6, 7.0, 0.6), white)
	_box("CrossBeam", at + Vector3(0, 35.6, -2), Vector3(4.2, 0.55, 0.6), white)


func _rock_vertex(ring: Vector3, side: int, sides: int) -> Vector3:
	var angle := TAU * side / sides
	var irregular := 0.88 + 0.16 * sin(float(side * 7 + int(ring.y)) * 1.7)
	return Vector3(cos(angle) * ring.x * irregular, ring.y + sin(angle * 3.0) * 0.9, sin(angle) * ring.z * irregular)


func _create_vehicle() -> void:
	var car := VehicleScript.new()
	car.name = "FirstCar"
	car.variant = "mission_red"
	car.position = Vector3(112, 0.5, 8)
	car.rotation.y = PI * 0.5
	add_child(car)
	vehicle_spawns[car.name] = car.transform


## Returns a mission vehicle to its authored spawn (used after an arrest).
func reset_vehicle(vehicle_name: String) -> void:
	var car := get_node_or_null(vehicle_name) as DriveableVehicle
	if car == null or not vehicle_spawns.has(vehicle_name):
		return
	car.driver = null
	car.speed = 0.0
	car.velocity = Vector3.ZERO
	car.transform = vehicle_spawns[vehicle_name]


func _create_people_and_traffic() -> void:
	var alba := PedestrianScript.new()
	alba.name = "Alba"
	alba.display_name = "Alba"
	alba.mission_contact = true
	alba.shirt_color = Color("b26e58")
	alba.model_name = "female_casual"
	alba.position = Vector3(103, 0.15, 27)
	add_child(alba)
	for i in range(12):
		var person := PedestrianScript.new()
		person.name = "Paseante_%02d" % i
		person.position = Vector3(-220 + i * 38, 0.1, 23 + (i % 3) * 4)
		person.shirt_color = [Color("d0b88f"), Color("6d8d80"), Color("ba796b"), Color("8e91aa")][i % 4]
		add_child(person)
	for i in range(2):
		var witness := PedestrianScript.new()
		witness.name = "CascoAntiguo_%02d" % i
		witness.position = Vector3(51 + i * 20, 0.1, -69)
		witness.shirt_color = Color("a0a486")
		add_child(witness)
	_create_traffic(12)


## Traffic cars start on random road-graph edges in the right-hand lane.
func _create_traffic(count: int) -> void:
	var traffic_rng := RandomNumberGenerator.new()
	traffic_rng.seed = 7403
	var variants := DriveableVehicle.traffic_variants()
	var used: Array[Vector3] = []
	var created := 0
	var attempts := 0
	while created < count and attempts < 400:
		attempts += 1
		var from_node := traffic_rng.randi_range(0, road_network.nodes.size() - 1)
		var neighbours: Array = road_network.edges[from_node]
		var to_node: int = neighbours[traffic_rng.randi_range(0, neighbours.size() - 1)]
		var a := road_network.nodes[from_node]
		var b := road_network.nodes[to_node]
		if a.distance_to(b) < 40.0:
			continue
		var direction := (b - a).normalized()
		var spot := a + direction * traffic_rng.randf_range(15.0, a.distance_to(b) - 25.0) + Vector3(-direction.z, 0, direction.x) * road_network.lane_offset
		var clear := spot.distance_to(Vector3(112, 0, 8)) > 25.0 and spot.distance_to(Vector3(92, 0, 30)) > 25.0
		for other in used:
			if other.distance_to(spot) < 18.0:
				clear = false
		if not clear:
			continue
		used.append(spot)
		var car := VehicleScript.new()
		car.name = "Traffic_%02d" % created
		if not variants.is_empty():
			car.variant = str(variants[created % variants.size()])
		car.position = spot + Vector3(0, 0.2, 0)
		car.rotation.y = atan2(-direction.x, -direction.z)
		add_child(car)
		car.start_traffic(road_network, from_node, to_node, 7403 + created)
		car.set_occupant(HumanModel.model_for_seed(7403 + created * 13))
		created += 1
