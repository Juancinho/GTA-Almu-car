extends Node3D

## What a big wanted level adds on top of patrol cars:
## - 3+ stars: roadblocks. Two patrol cars parked across the road ahead of the
##   player's direction of travel, with armed officers behind them.
## - 4+ stars: the police helicopter. It hovers above the player, keeps them in
##   sight over the rooftops (so hiding needs a roof or a tunnel), sweeps a
##   searchlight at night and its marksman takes shots.
## - 4+ stars: roadblocks also lay a stinger (spike strip) on the approach;
##   driving over it bursts the tyres (slow, wandering car until resprayed).
## - 5 stars: roadblocks come faster and up to three at a time.
## Everything here is removed when the wanted level clears.

const VehicleScript = preload("res://scripts/vehicle.gd")
const OfficerScript = preload("res://scripts/police_officer.gd")
const ROADBLOCK_EVERY := 35.0
const MAX_ROADBLOCKS := 2
const STRIP_LENGTH := 7.5
const HELI_ALTITUDE := 38.0
const HELI_SHOT_EVERY := 2.4

var wanted: Node  # WantedSystem
var player: PlayerController
var road_network: RoadNetwork
var roadblocks: Array = []  # each: {"cars": [], "officers": [], "at": Vector3}
var roadblock_timer := 8.0
var helicopter: Node3D
var heli_rotor: Node3D
var heli_tail_rotor: Node3D
var heli_light: SpotLight3D
var heli_beam: MeshInstance3D
var heli_audio: AudioStreamPlayer3D
var heli_shot_audio: AudioStreamPlayer3D
var heli_velocity := Vector3.ZERO
var heli_leaving := false
var heli_shot_timer := HELI_SHOT_EVERY
var rng := RandomNumberGenerator.new()


func configure(target_wanted: Node, target_player: PlayerController, network: RoadNetwork) -> void:
	wanted = target_wanted
	player = target_player
	road_network = network
	rng.seed = 5150
	wanted.connect("wanted_changed", _on_wanted_changed)


func _on_wanted_changed(level: int, _phase: String) -> void:
	if level == 0:
		clear()


func clear() -> void:
	for block in roadblocks:
		_free_block(block)
	roadblocks.clear()
	roadblock_timer = 8.0
	if helicopter != null:
		heli_leaving = true


func _physics_process(delta: float) -> void:
	if wanted == null or player == null:
		return
	var level := int(wanted.get("level"))
	var target := player.driving_vehicle.global_position if player.driving_vehicle != null else player.global_position
	_update_roadblocks(delta, level, target)
	_update_helicopter(delta, level, target)


# --- Roadblocks ----------------------------------------------------------------

func _update_roadblocks(delta: float, level: int, target: Vector3) -> void:
	for block in roadblocks.duplicate():
		var at: Vector3 = block["at"]
		var alive := false
		for car in block["cars"]:
			alive = alive or (is_instance_valid(car) and not (car as DriveableVehicle).destroyed)
		if at.distance_to(target) > 260.0 or not alive:
			_free_block(block)
			roadblocks.erase(block)
	if level < 3 or road_network == null or road_network.nodes.is_empty():
		return
	_check_strips()
	roadblock_timer -= delta
	if roadblock_timer > 0.0 or roadblocks.size() >= (MAX_ROADBLOCKS + 1 if level >= 5 else MAX_ROADBLOCKS):
		return
	roadblock_timer = ROADBLOCK_EVERY * (0.6 if level >= 5 else 1.0)
	var point := _point_ahead(target)
	if point != Vector3.INF:
		roadblocks.append(_place_roadblock(point))


## A road node 90–160 m ahead of the player's travel, preferring straight on.
func _point_ahead(target: Vector3) -> Vector3:
	var heading: Vector3 = wanted.call("_player_heading")
	var best := Vector3.INF
	var best_score := -INF
	for i in range(road_network.nodes.size()):
		var node: Vector3 = road_network.nodes[i]
		var offset := Vector3(node.x - target.x, 0, node.z - target.z)
		var distance := offset.length()
		if distance < 90.0 or distance > 160.0:
			continue
		var score := offset.normalized().dot(heading) * 2.0 - absf(distance - 120.0) / 60.0
		var busy := false
		for block in roadblocks:
			busy = busy or (block["at"] as Vector3).distance_to(node) < 40.0
		if busy:
			continue
		# Only on a carriageway, never in a pedestrian lane or plaza.
		var lane: Dictionary = road_network.nearest(node, true)
		if lane.is_empty() or Vector2((lane["point"] as Vector3).x - node.x, (lane["point"] as Vector3).z - node.z).length() > 1.5:
			continue
		if score > best_score:
			best_score = score
			best = node
	return best if best_score > 0.6 else Vector3.INF


func _place_roadblock(point: Vector3) -> Dictionary:
	var block := {"cars": [], "officers": [], "at": point}
	var node := road_network.nearest_node(point)
	var outgoing: Array = road_network.edges.get(node, [])
	var along := Vector3.FORWARD
	if not outgoing.is_empty():
		var next: Vector3 = road_network.nodes[int(outgoing[0])]
		along = Vector3(next.x - point.x, 0, next.z - point.z).normalized()
	var across := Vector3(-along.z, 0, along.x)
	var world := get_tree().get_first_node_in_group("sector_world")
	if world == null:
		world = get_parent()
	for side: float in [-1.0, 1.0]:
		var car := VehicleScript.new() as DriveableVehicle
		car.name = "Control_%d" % rng.randi()
		car.variant = "police_suv" if side > 0.0 else "police_local"
		var spot := point + across * side * 2.4
		var ground: float = player.sector_data.height_at(spot.x, spot.z) if player.sector_data != null else spot.y
		car.position = Vector3(spot.x, ground + 0.6, spot.z)
		# Parked across the carriageway, noses toward each other.
		car.rotation.y = atan2(-across.x * side, -across.z * side) + 0.35 * side
		car.road_network = road_network
		world.add_child(car)
		car.pursuing = false
		car.beacon = true
		(block["cars"] as Array).append(car)
		var officer := OfficerScript.new() as Pedestrian
		officer.name = "OfficerBlock_%d" % rng.randi()
		officer.set("wanted", wanted)
		officer.set("car", car)
		var stand := spot - along * 2.6
		officer.position = Vector3(stand.x, ground + 0.2, stand.z)
		world.add_child(officer)
		officer.state = Pedestrian.State.FIGHT
		(block["officers"] as Array).append(officer)
		(wanted.get("officers") as Array).append(officer)
	if int(wanted.get("level")) >= 4:
		var toward := player.global_position - point
		toward.y = 0.0
		var approach := along if along.dot(toward) > 0.0 else -along
		var strip_at := point + approach * 16.0
		var ground: float = player.sector_data.height_at(strip_at.x, strip_at.z) if player.sector_data != null else strip_at.y
		block["strip"] = _spike_strip(world, Vector3(strip_at.x, ground, strip_at.z), across)
	return block


## A police stinger: a dark band with a row of spikes across the carriageway.
func _spike_strip(world: Node, at: Vector3, across: Vector3) -> Node3D:
	var strip := Node3D.new()
	strip.name = "SpikeStrip_%d" % rng.randi()
	world.add_child(strip)
	strip.global_transform = Transform3D(Basis.looking_at(across.cross(Vector3.UP), Vector3.UP), at)
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color("1d1f22")
	var spike_mat := StandardMaterial3D.new()
	spike_mat.albedo_color = Color("c9cdd2")
	spike_mat.metallic = 0.8
	spike_mat.roughness = 0.35
	var band := MeshInstance3D.new()
	var band_mesh := BoxMesh.new()
	band_mesh.size = Vector3(STRIP_LENGTH, 0.05, 0.45)
	band.mesh = band_mesh
	band.material_override = base_mat
	band.position.y = 0.03
	strip.add_child(band)
	var spike_mesh := PrismMesh.new()
	spike_mesh.size = Vector3(0.1, 0.12, 0.1)
	for i in range(18):
		var spike := MeshInstance3D.new()
		spike.mesh = spike_mesh
		spike.material_override = spike_mat
		spike.position = Vector3(-STRIP_LENGTH * 0.5 + 0.2 + i * (STRIP_LENGTH - 0.4) / 17.0, 0.11, 0.1 if i % 2 == 0 else -0.1)
		strip.add_child(spike)
	return strip


## The player's car over a stinger bursts its tyres.
func _check_strips() -> void:
	var car := player.driving_vehicle
	if car == null or car.tyres_burst:
		return
	for block in roadblocks:
		var strip: Node3D = block.get("strip")
		if strip == null or not is_instance_valid(strip):
			continue
		var local := strip.global_transform.affine_inverse() * car.global_position
		if absf(local.x) < STRIP_LENGTH * 0.5 + 0.6 and absf(local.z) < 1.6 and absf(local.y) < 2.0:
			car.burst_tyres()
			var main_node := wanted.get_parent()
			if main_node != null and "hud" in main_node and main_node.get("hud") != null:
				main_node.get("hud").call("show_banner", "¡PINCHAZO!  Ruedas reventadas", Color("ff6b5a"))


func _free_block(block: Dictionary) -> void:
	var strip: Node3D = block.get("strip")
	if strip != null and is_instance_valid(strip):
		strip.queue_free()
	for car in block["cars"]:
		if is_instance_valid(car) and (car as DriveableVehicle).driver == null:
			car.queue_free()
	for officer in block["officers"]:
		if is_instance_valid(officer):
			officer.queue_free()


# --- Helicopter ----------------------------------------------------------------

func _update_helicopter(delta: float, level: int, target: Vector3) -> void:
	if level >= 4 and helicopter == null:
		_spawn_helicopter(target)
	if helicopter == null:
		return
	if level < 4:
		heli_leaving = true
	var ground := target.y
	var desired := target + Vector3(sin(Time.get_ticks_msec() * 0.0004) * 22.0, HELI_ALTITUDE, cos(Time.get_ticks_msec() * 0.0004) * 22.0)
	if heli_leaving:
		desired = helicopter.global_position + Vector3(0, 30.0, -120.0)
	var to := desired - helicopter.global_position
	heli_velocity = heli_velocity.lerp(to.limit_length(24.0), minf(1.0, 1.4 * delta))
	helicopter.global_position += heli_velocity * delta
	helicopter.global_position.y = maxf(helicopter.global_position.y, ground + 24.0)
	# Nose into the direction of travel, banked into turns.
	var flat := Vector3(heli_velocity.x, 0, heli_velocity.z)
	if flat.length() > 1.0:
		var yaw := atan2(-flat.x, -flat.z)
		helicopter.rotation.y = lerp_angle(helicopter.rotation.y, yaw, minf(1.0, 1.5 * delta))
	helicopter.rotation.x = lerpf(helicopter.rotation.x, -clampf(flat.length() / 60.0, 0.0, 0.25), minf(1.0, 2.0 * delta))
	heli_rotor.rotate_y(delta * 38.0)
	heli_tail_rotor.rotate_x(delta * 45.0)
	if heli_leaving:
		if helicopter.global_position.distance_to(target) > 260.0:
			helicopter.queue_free()
			helicopter = null
			heli_leaving = false
		return
	var night := 0.0
	var main := get_tree().current_scene
	if main != null and "day_night" in main and main.day_night != null:
		night = float(main.day_night.get("night"))
	heli_light.visible = night > 0.3
	var beam := target - heli_light.global_position
	if beam.length_squared() > 1.0:
		heli_light.look_at(target, Vector3.FORWARD if absf(beam.normalized().y) > 0.95 else Vector3.UP)
		# A faint visible cone, as the searchlight cuts through the night haze.
		heli_beam.visible = heli_light.visible
		if heli_beam.visible:
			var length := beam.length()
			heli_beam.global_transform = Transform3D(Basis.looking_at(beam.normalized(), Vector3.FORWARD if absf(beam.normalized().y) > 0.95 else Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5), heli_light.global_position + beam * 0.5)
			heli_beam.scale = Vector3(1.0, length, 1.0)
	var sees := _heli_sees(target)
	if sees:
		wanted.call("notify_sighting", target)
	heli_shot_timer -= delta
	if sees and heli_shot_timer <= 0.0:
		heli_shot_timer = HELI_SHOT_EVERY + rng.randf_range(-0.5, 0.8)
		if DisplayServer.get_name() != "headless":
			heli_shot_audio.play()
		var moving := float(wanted.call("player_speed"))
		if rng.randf() < clampf(0.45 - moving * 0.02, 0.12, 0.45):
			if player.driving_vehicle != null:
				player.driving_vehicle.apply_damage(30.0)
			else:
				player.take_damage(9.0, "police")


func _heli_sees(target: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(helicopter.global_position, target + Vector3.UP * 1.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == player or hit.get("collider") == player.driving_vehicle


func _spawn_helicopter(target: Vector3) -> void:
	heli_leaving = false
	helicopter = Node3D.new()
	helicopter.name = "PoliceHelicopter"
	var world := get_tree().get_first_node_in_group("sector_world")
	(world if world != null else get_parent()).add_child(helicopter)
	helicopter.global_position = target + Vector3(140.0, HELI_ALTITUDE + 20.0, 80.0)
	heli_velocity = Vector3.ZERO
	var navy := StandardMaterial3D.new()
	navy.albedo_color = Color("1d2f55")
	navy.roughness = 0.4
	navy.metallic = 0.3
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("e8ecef")
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.25, 0.35, 0.42, 0.75)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("202326")
	var body := _part(CapsuleMesh.new(), navy, Vector3(0, 0, 0), Vector3(1.0, 1.0, 1.0))
	(body.mesh as CapsuleMesh).radius = 1.1
	(body.mesh as CapsuleMesh).height = 4.6
	body.rotation.x = PI * 0.5
	var stripe := _part(BoxMesh.new(), white, Vector3(0, -0.15, 0.2), Vector3(2.25, 0.35, 3.2))
	stripe.name = "Stripe"
	var canopy := _part(SphereMesh.new(), glass, Vector3(0, 0.25, -1.55), Vector3(1.9, 1.5, 1.8))
	(canopy.mesh as SphereMesh).radius = 0.6
	(canopy.mesh as SphereMesh).height = 1.2
	var boom := _part(CylinderMesh.new(), navy, Vector3(0, 0.35, 3.4), Vector3.ONE)
	(boom.mesh as CylinderMesh).top_radius = 0.18
	(boom.mesh as CylinderMesh).bottom_radius = 0.32
	(boom.mesh as CylinderMesh).height = 3.6
	boom.rotation.x = PI * 0.5
	var fin := _part(BoxMesh.new(), navy, Vector3(0, 0.95, 5.0), Vector3(0.12, 1.2, 0.7))
	fin.name = "Fin"
	for side: float in [-0.75, 0.75]:
		var skid := _part(CylinderMesh.new(), dark, Vector3(side, -1.35, 0.0), Vector3.ONE)
		(skid.mesh as CylinderMesh).top_radius = 0.06
		(skid.mesh as CylinderMesh).bottom_radius = 0.06
		(skid.mesh as CylinderMesh).height = 3.4
		skid.rotation.x = PI * 0.5
		for z: float in [-0.9, 0.9]:
			var strut := _part(BoxMesh.new(), dark, Vector3(side * 0.85, -1.0, z), Vector3(0.06, 0.7, 0.06))
			strut.name = "Strut"
	heli_rotor = Node3D.new()
	heli_rotor.name = "Rotor"
	heli_rotor.position = Vector3(0, 1.35, 0)
	helicopter.add_child(heli_rotor)
	var mast := _part(CylinderMesh.new(), dark, Vector3(0, 1.15, 0), Vector3.ONE)
	(mast.mesh as CylinderMesh).top_radius = 0.1
	(mast.mesh as CylinderMesh).bottom_radius = 0.14
	(mast.mesh as CylinderMesh).height = 0.5
	for angle in [0.0, PI * 0.5]:
		var blade := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(11.0, 0.05, 0.32)
		blade.mesh = box
		blade.material_override = dark
		blade.rotation.y = angle
		heli_rotor.add_child(blade)
	heli_tail_rotor = Node3D.new()
	heli_tail_rotor.name = "TailRotor"
	heli_tail_rotor.position = Vector3(0.22, 0.95, 5.25)
	helicopter.add_child(heli_tail_rotor)
	for angle in [0.0, PI * 0.5]:
		var blade := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.04, 1.6, 0.18)
		blade.mesh = box
		blade.material_override = dark
		blade.rotation.x = angle
		heli_tail_rotor.add_child(blade)
	var label := Label3D.new()
	label.text = "POLICÍA"
	label.font_size = 64
	label.pixel_size = 0.012
	label.position = Vector3(1.16, -0.1, 0.4)
	label.rotation.y = PI * 0.5
	label.modulate = Color("f4f6f8")
	helicopter.add_child(label)
	heli_light = SpotLight3D.new()
	heli_light.name = "Searchlight"
	heli_light.light_color = Color("e8f0ff")
	heli_light.light_energy = 9.0
	heli_light.spot_range = 90.0
	heli_light.spot_angle = 9.0
	heli_light.position = Vector3(0, -1.2, -1.6)
	heli_light.visible = false
	helicopter.add_child(heli_light)
	heli_beam = MeshInstance3D.new()
	heli_beam.name = "SearchlightBeam"
	var cone := CylinderMesh.new()
	cone.top_radius = 6.5  # ground end (the mesh is turned so +Y points at the target)
	cone.bottom_radius = 0.35
	cone.height = 1.0
	cone.radial_segments = 16
	cone.cap_top = false
	cone.cap_bottom = false
	heli_beam.mesh = cone
	var haze := StandardMaterial3D.new()
	haze.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	haze.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	haze.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	haze.cull_mode = BaseMaterial3D.CULL_DISABLED
	haze.albedo_color = Color(0.55, 0.62, 0.75, 0.10)
	heli_beam.material_override = haze
	heli_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	heli_beam.top_level = true
	heli_beam.visible = false
	helicopter.add_child(heli_beam)
	heli_audio = AudioStreamPlayer3D.new()
	heli_audio.stream = load("res://assets/audio/engine_loop.wav") as AudioStream
	if heli_audio.stream is AudioStreamWAV:
		(heli_audio.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	heli_audio.pitch_scale = 0.45
	heli_audio.unit_size = 30.0
	heli_audio.max_distance = 400.0
	heli_audio.volume_db = -2.0
	heli_audio.bus = "SFX"
	helicopter.add_child(heli_audio)
	heli_shot_audio = AudioStreamPlayer3D.new()
	heli_shot_audio.stream = load("res://assets/audio/pistol_shot.wav") as AudioStream
	heli_shot_audio.unit_size = 25.0
	heli_shot_audio.max_distance = 300.0
	heli_shot_audio.bus = "SFX"
	helicopter.add_child(heli_shot_audio)
	if DisplayServer.get_name() != "headless":
		heli_audio.play()


func _part(mesh: Mesh, material: Material, at: Vector3, scale_value: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	part.scale = scale_value
	helicopter.add_child(part)
	return part
