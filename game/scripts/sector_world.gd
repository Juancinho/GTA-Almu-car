class_name SectorWorld
extends Node3D

## The playable world: central Almuñécar at 1:1 generated from
## res://data/world/sector_center.json (OSM ODbL + provisional design terrain).
## Builds terrain, streets, buildings, landmarks and dressing, then populates it
## with the mission car, Alba, pedestrians on real lanes and traffic on the graph.

const VehicleScript = preload("res://scripts/vehicle.gd")
const PedestrianScript = preload("res://scripts/pedestrian.gd")
const WorkshopScript = preload("res://scripts/workshop_interior.gd")
const VenueScript = preload("res://scripts/venue_interior.gd")
const ApartmentScript = preload("res://scripts/apartment_block.gd")
const TownDressingScript = preload("res://scripts/sector/town_dressing_builder.gd")
const TRAFFIC_COUNT := 16
const PEDESTRIAN_COUNT := 56

var data: SectorData
var road_network: RoadNetwork
var mats := SectorMaterials.new()
var sun_light: DirectionalLight3D
var environment_node: WorldEnvironment
var vehicle_spawns: Dictionary = {}
var restricted_zones: Array = []
var landmark_info: Dictionary = {}
var build_stats: Dictionary = {}
var workshop: WorkshopInterior
var venues: Dictionary = {}
var apartments: Dictionary = {}  # block id -> apartment_block.gd (walk-in residential blocks)
var beach_bars: Array[BeachBarService] = []


func _ready() -> void:
	var started := Time.get_ticks_msec()
	add_to_group("sector_world")
	data = SectorData.load_default()
	road_network = RoadNetwork.new()
	road_network.load_sector(data.raw)
	restricted_zones = data.raw.get("restricted_zones", [])
	_create_environment()
	TerrainBuilder.build(self, data, mats)
	RoadBuilder.build(self, data, road_network, mats)
	build_stats = BuildingBuilder.build(self, data, mats)
	landmark_info = LandmarkBuilder.build(self, data, mats)
	build_stats.merge(DressingBuilder.build(self, data, road_network, mats))
	build_stats.merge(CommerceBuilder.build(self, data, road_network, mats))
	build_stats.merge(TownDressingScript.build(self, data, road_network, mats))
	var beach_bar_result := BeachBarsBuilder.build(self, data, road_network, mats)
	for service in beach_bar_result["services"]:
		beach_bars.append(service as BeachBarService)
	beach_bar_result.erase("services")
	build_stats.merge(beach_bar_result)
	_create_workshop()
	_create_venues()
	_create_apartments()
	_create_vehicle()
	_create_parked_bikes()
	_create_boats()
	_create_people()
	_create_traffic(TRAFFIC_COUNT)
	build_stats["build_ms"] = Time.get_ticks_msec() - started
	print("SECTOR BUILT: %s buildings, %s façade details, %d ms" % [build_stats["buildings"], build_stats["details"], build_stats["build_ms"]])


func _create_workshop() -> void:
	workshop = WorkshopScript.new()
	workshop.name = "TallerPoniente"
	add_child(workshop)
	workshop.configure(data, mats)


func _create_venues() -> void:
	for kind in VenueScript.SPECS:
		var venue := VenueScript.new() as VenueInterior
		venue.name = "Venue_" + kind
		add_child(venue)
		if venue.configure(kind, data, mats):
			venues[kind] = venue


func _create_apartments() -> void:
	for id in ApartmentScript.Catalog.SPECS:
		var block := ApartmentScript.new()
		block.name = "Block_" + str(id)
		add_child(block)
		if block.configure(str(id), data, mats):
			apartments[str(id)] = block


func anchor(name: String) -> Vector3:
	return data.anchor(name)


func height_at(x: float, z: float) -> float:
	return data.height_at(x, z)


func _create_environment() -> void:
	environment_node = WorldEnvironment.new()
	var env := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("3f78b0")
	sky_material.sky_horizon_color = Color("c4d6da")
	sky_material.ground_horizon_color = Color("b9d2dc")
	sky_material.ground_bottom_color = Color("56707a")
	sky_material.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.ambient_light_sky_contribution = 0.45
	env.ambient_light_color = Color("e3d8c6")
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color("bfd0da")
	env.fog_density = 0.00018
	env.fog_sky_affect = 0.25
	environment_node.environment = env
	add_child(environment_node)
	sun_light = DirectionalLight3D.new()
	sun_light.name = "Sun"
	sun_light.rotation_degrees = Vector3(-40.0, -30.0, 0.0)  # afternoon sun from the south-south-west: the seafront faces it
	sun_light.light_color = Color("ffe3bd")
	sun_light.light_energy = 1.25
	sun_light.shadow_enabled = true
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun_light.directional_shadow_max_distance = 150.0
	add_child(sun_light)


func apply_quality(level: int) -> void:
	sun_light.shadow_enabled = level >= 1
	sun_light.directional_shadow_max_distance = [0.0, 65.0, 120.0][level]
	for venue in venues.values():
		venue.visibility_distance = [20.0, 28.0, 45.0][level]
	for node in find_children("Facade_*", "MultiMeshInstance3D", false, false):
		(node as GeometryInstance3D).visibility_range_end = [140.0, 230.0, 320.0][level]


## Car parked on the Paseo del Altillo, aligned with the nearest road.
func _create_vehicle() -> void:
	var car := VehicleScript.new()
	car.name = "FirstCar"
	car.variant = "mission_red"
	var spot := anchor("first_car")
	car.position = spot + Vector3(0, 0.4, 0)
	car.rotation.y = _road_heading(spot)
	add_child(car)
	vehicle_spawns[car.name] = car.transform


## Motorbikes and scooters parked on the paseo paving west of the start, ready to
## steal: [x, z, yaw, variant, palette index]. Kept off the player's first steps.
const PARKED_BIKES := [
	[-13.6, 31.2, 0.25, "scooter", 0],
	[-15.0, 31.5, 0.25, "moto_naked", 0],
	[-16.4, 31.8, 0.25, "scooter", 3],
	[-17.8, 32.1, 0.25, "moto_naked", 1],
]


func _create_parked_bikes() -> void:
	for i in range(PARKED_BIKES.size()):
		var spec: Array = PARKED_BIKES[i]
		var bike := VehicleScript.new() as DriveableVehicle
		bike.name = "MotoAparcada_%d" % i
		bike.variant = str(spec[3])
		bike.body_color = DriveableVehicle.palette_color(bike.variant, int(spec[4]))
		bike.position = Vector3(float(spec[0]), data.height_at(float(spec[0]), float(spec[1])) + 0.35, float(spec[1]))
		bike.rotation.y = float(spec[2])
		add_child(bike)
		vehicle_spawns[bike.name] = bike.transform


## Boats moored just off the Puerta del Mar and Altillo beaches, bows to the sea.
const MOORINGS := [[-80.0, 130.0, "rib"], [130.0, 128.0, "fishing_boat"], [190.0, 146.0, "fishing_boat"]]


func _create_boats() -> void:
	for i in range(MOORINGS.size()):
		var spec: Array = MOORINGS[i]
		var boat := VehicleScript.new() as DriveableVehicle
		boat.name = "Barca_%d" % i
		boat.variant = str(spec[2])
		boat.position = Vector3(float(spec[0]), DriveableVehicle.WATER_Y, float(spec[1]))
		boat.rotation.y = PI  # bow south, toward open water
		add_child(boat)


func _road_heading(at: Vector3) -> float:
	var node := road_network.nearest_node(at)
	var outgoing: Array = road_network.edges.get(node, [])
	if outgoing.is_empty():
		return 0.0
	var next: Vector3 = road_network.nodes[int(outgoing[0])]
	return atan2(-(next.x - at.x), -(next.z - at.z))


## Returns a mission vehicle to its authored spawn (used after an arrest or death).
func reset_vehicle(vehicle_name: String) -> void:
	var car := get_node_or_null(vehicle_name) as DriveableVehicle
	if car == null or not vehicle_spawns.has(vehicle_name):
		return
	car.driver = null
	car.speed = 0.0
	car.velocity = Vector3.ZERO
	car.transform = vehicle_spawns[vehicle_name]
	if car.destroyed or car.health < DriveableVehicle.MAX_HEALTH:
		car.repair()


func _create_people() -> void:
	var alba := PedestrianScript.new()
	alba.name = "Alba"
	alba.display_name = "Alba"
	alba.mission_contact = true
	alba.model_name = "female_casual"
	alba.position = anchor("alba") + Vector3(0, 0.1, 0)
	add_child(alba)
	var marina := PedestrianScript.new()
	marina.name = "Marina"
	marina.display_name = "Marina · Jaime Playa"
	marina.mission_contact = true
	marina.model_name = "female_casual"
	marina.position = anchor("jaime_staff") + Vector3(0, 0.1, 0)
	add_child(marina)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7407
	var spots: Array[Vector3] = []
	var promenade_first := []
	for road in road_network.roads:
		if road["driveable"] or (road["points"] as PackedVector3Array).size() < 2:
			continue
		var weight := 3 if str(road["name"]).begins_with("Paseo") or road["class"] == "pedestrian" else 1
		for k in range(weight):
			promenade_first.append(road)
	var attempts := 0
	while spots.size() < PEDESTRIAN_COUNT and attempts < 800:
		attempts += 1
		var road: Dictionary = promenade_first[rng.randi_range(0, promenade_first.size() - 1)]
		var points: PackedVector3Array = road["points"]
		var p := points[rng.randi_range(0, points.size() - 1)]
		var near_spawn := p.distance_to(anchor("player_spawn")) < 160.0
		if not near_spawn and rng.randf() < 0.55:
			continue  # bias the crowd toward the seafront start, keep some in the old town
		var ok := true
		for other in spots:
			if other.distance_to(p) < 6.0:
				ok = false
		if ok and p.distance_to(anchor("alba")) > 5.0:
			spots.append(p)
	# Residents in each restricted zone of the old town: they are the witnesses.
	for zone in restricted_zones:
		var center := Vector3(float(zone["x"]), 0, float(zone["z"]))
		var placed := 0
		for road in road_network.roads:
			if road["driveable"] or placed >= 4:
				continue
			for p in road["points"]:
				if placed < 4 and Vector2(p.x - center.x, p.z - center.z).length() < float(zone["radius"]) * 0.8 and spots.all(func(o: Vector3) -> bool: return o.distance_to(p) > 8.0):
					spots.append(p)
					placed += 1
	var closest_spots := spots.duplicate()
	closest_spots.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(anchor("player_spawn")) < b.distance_squared_to(anchor("player_spawn")))
	for i in range(spots.size()):
		var person := PedestrianScript.new()
		person.name = "Paseante_%02d" % i
		person.position = spots[i] + Vector3(0, 0.1, 0)
		if closest_spots.find(spots[i]) < 4:
			person.activity = "skate"
			person.display_name = "Patinador" if i % 2 == 0 else "Patinadora"
		add_child(person)
	var beach_count := 0
	for z in range(48, 140, 12):
		for x in range(-48, 120, 24):
			if beach_count >= 6 or data.surface_at(x, z) != "beach" or data.height_at(x, z) < 0.3:
				continue
			var person := PedestrianScript.new()
			person.name = "BeachResident_%d" % beach_count
			person.display_name = "Bañista adulta"
			person.model_name = "female_tanktop"
			person.outfit = "adult_swimwear"
			person.position = Vector3(x, data.height_at(x, z) + 0.1, z)
			add_child(person)
			beach_count += 1
	build_stats["beach_residents"] = beach_count


## Traffic starts on random graph edges in the right-hand lane.
func _create_traffic(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7403
	var variants := DriveableVehicle.traffic_variants()
	var bikes := DriveableVehicle.traffic_bike_variants()
	var used: Array[Vector3] = []
	var created := 0
	var attempts := 0
	while created < count and attempts < 2000:
		attempts += 1
		var from_node := rng.randi_range(0, road_network.nodes.size() - 1)
		var outgoing: Array = road_network.edges[from_node]
		if outgoing.is_empty():
			continue
		var to_node: int = outgoing[rng.randi_range(0, outgoing.size() - 1)]
		var a := road_network.nodes[from_node]
		var b := road_network.nodes[to_node]
		if Vector2(a.x - b.x, a.z - b.z).length() < 14.0:
			continue
		var direction := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var lane := road_network.lane_offset if road_network.is_two_way(from_node, to_node) else 0.0
		var spot := a.lerp(b, 0.5) + Vector3(-direction.z, 0, direction.x) * lane
		var clear := spot.distance_to(anchor("first_car")) > 30.0 and spot.distance_to(anchor("player_spawn")) > 30.0
		for other in used:
			if other.distance_to(spot) < 25.0:
				clear = false
		if not clear:
			continue
		used.append(spot)
		var car := VehicleScript.new()
		car.name = "Traffic_%02d" % created
		if not variants.is_empty():
			car.variant = str(variants[created % variants.size()])
		if not bikes.is_empty() and created % 7 == 5:  # ~15% of traffic rides two wheels
			car.variant = str(bikes[created / 7 % bikes.size()])
			car.body_color = DriveableVehicle.palette_color(car.variant, created)
		car.position = Vector3(spot.x, data.height_at(spot.x, spot.z) + 0.4, spot.z)
		car.rotation.y = atan2(-direction.x, -direction.z)
		add_child(car)
		car.start_traffic(road_network, from_node, to_node, 7403 + created)
		car.set_occupant(HumanModel.model_for_seed(7403 + created * 13))
		created += 1
