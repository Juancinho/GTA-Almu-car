extends Node3D

const AudioUtil = preload("res://scripts/audio_util.gd")

const SoftParticle = preload("res://scripts/soft_particle.gd")

## Grenades and Molotov cocktails. G throws the selected one along the camera
## (an arc, so aim a little high), H switches between them. Grenades bounce and
## go off after a fuse; Molotovs burst on impact and leave a pool of fire for a
## few seconds. Both hurt anyone nearby (the player too), set cars ablaze and are
## a crime the police take seriously.

const GRENADE_FUSE := 2.2
const BLAST_RADIUS := 7.5
const FIRE_RADIUS := 3.6
const FIRE_SECONDS := 7.0
const KINDS := ["grenade", "molotov"]
const NAMES := {"grenade": "Granada", "molotov": "Cóctel molotov"}
const SHORT := {"grenade": "Granada", "molotov": "Molotov"}

var player: PlayerController
var wanted: Node
var counts := {"grenade": 0, "molotov": 0}
var selected := "grenade"
var cooldown := 0.0
var fires: Array = []  # {at, time, node}
var boom_stream: AudioStream
var smash_stream: AudioStream
var whoosh_stream: AudioStream


func configure(target_player: PlayerController, target_wanted: Node) -> void:
	player = target_player
	wanted = target_wanted
	boom_stream = AudioUtil.stream("res://assets/audio/explosion.wav")
	smash_stream = AudioUtil.stream("res://assets/audio/molotov_smash.wav")
	whoosh_stream = AudioUtil.stream("res://assets/audio/throw_whoosh.wav")
	add_to_group("throwables")


func add(kind: String, amount: int) -> void:
	if not counts.has(kind):
		return
	counts[kind] = mini(int(counts[kind]) + amount, 10)
	if int(counts[selected]) == 0:
		selected = kind


func hud_text() -> String:
	var parts := []
	for kind in KINDS:
		if int(counts[kind]) > 0:
			parts.append(("▶ " if kind == selected else "") + "%s ×%d" % [SHORT[kind], counts[kind]])
	return "  ·  ".join(parts)


func _unhandled_input(event: InputEvent) -> void:
	if player == null or player.dead or player.driving_vehicle != null or player.swimming:
		return
	if event.is_action_pressed("throwable_switch"):
		selected = "molotov" if selected == "grenade" else "grenade"
	elif event.is_action_pressed("throwable"):
		throw()


## Throw the selected item along the camera's aim. Returns the projectile.
func throw() -> RigidBody3D:
	if cooldown > 0.0 or int(counts.get(selected, 0)) <= 0:
		return null
	cooldown = 0.8
	counts[selected] = int(counts[selected]) - 1
	var kind := selected
	if int(counts[selected]) == 0:
		selected = "molotov" if selected == "grenade" else "grenade"
	var aim := -player.camera.global_transform.basis.z
	var flat := Vector3(aim.x, 0, aim.z).normalized()
	var start := player.global_position + Vector3.UP * 1.6 + flat * 0.6
	var body := RigidBody3D.new()
	body.name = "Thrown_" + kind
	body.mass = 0.6
	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.09
	shape.shape = sphere
	body.add_child(shape)
	body.add_child(_projectile_mesh(kind))
	body.add_collision_exception_with(player)
	var world := get_tree().get_first_node_in_group("sector_world")
	(world if world != null else get_parent()).add_child(body)
	body.global_position = start
	body.linear_velocity = (aim + Vector3.UP * 0.35).normalized() * 17.0
	body.angular_velocity = Vector3(rng_spin(), rng_spin(), rng_spin())
	_play(whoosh_stream, start, -6.0)
	player.human.play_action("punch", 0.4)
	if kind == "grenade":
		get_tree().create_timer(GRENADE_FUSE, false).timeout.connect(func() -> void:
			if is_instance_valid(body):
				explode(body.global_position)
				body.queue_free())
	else:
		body.body_entered.connect(func(_other: Node) -> void:
			if is_instance_valid(body) and not body.is_queued_for_deletion():
				ignite(body.global_position)
				body.queue_free())
		get_tree().create_timer(4.0, false).timeout.connect(func() -> void:
			if is_instance_valid(body) and not body.is_queued_for_deletion():
				ignite(body.global_position)
				body.queue_free())
	return body


func rng_spin() -> float:
	return randf_range(-8.0, 8.0)


func _process(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)


func _physics_process(delta: float) -> void:
	for fire in fires.duplicate():
		fire["time"] = float(fire["time"]) - delta
		var at: Vector3 = fire["at"]
		if float(fire["time"]) <= 0.0:
			(fire["node"] as Node).queue_free()
			fires.erase(fire)
			continue
		fire["tick"] = float(fire.get("tick", 0.0)) - delta
		if float(fire["tick"]) > 0.0:
			continue
		fire["tick"] = 0.5
		for node in get_tree().get_nodes_in_group("pedestrians"):
			var person := node as Pedestrian
			if person != null and not person.dead and person.global_position.distance_to(at) < FIRE_RADIUS:
				person.take_damage(14.0, at)
				person.flee_from(at)
		if player.driving_vehicle == null and player.global_position.distance_to(at) < FIRE_RADIUS:
			player.take_damage(6.0, "fire")
		for node in get_tree().get_nodes_in_group("vehicles"):
			var car := node as DriveableVehicle
			if car != null and not car.destroyed and car.global_position.distance_to(at) < FIRE_RADIUS + 1.0:
				car.apply_damage(60.0)


func explode(at: Vector3) -> void:
	_fireball(at, 1.0)
	_play(boom_stream, at, 4.0)
	for node in get_tree().get_nodes_in_group("pedestrians"):
		var person := node as Pedestrian
		if person == null or person.dead:
			continue
		var d := person.global_position.distance_to(at)
		if d < BLAST_RADIUS:
			person.take_damage(130.0 * (1.0 - d / BLAST_RADIUS) + 25.0, at)
			person.knock_down(at, 9.0)
		elif d < BLAST_RADIUS * 3.0:
			person.flee_from(at)
	var pd := player.global_position.distance_to(at)
	if pd < BLAST_RADIUS and player.driving_vehicle == null:
		player.take_damage(85.0 * (1.0 - pd / BLAST_RADIUS) + 10.0, "explosion")
	for node in get_tree().get_nodes_in_group("vehicles"):
		var car := node as DriveableVehicle
		if car == null or car.destroyed:
			continue
		var d := car.global_position.distance_to(at)
		if d < BLAST_RADIUS:
			car.apply_damage(700.0 * (1.0 - d / BLAST_RADIUS) + 200.0)
	for glass in get_tree().get_nodes_in_group("breakable_glass"):
		if (glass as Node3D).global_position.distance_to(at) < BLAST_RADIUS and glass.has_method("shatter"):
			glass.call("shatter")
	_report("explosión", at)


func ignite(at: Vector3) -> void:
	var ground := at
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 4.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		ground = hit["position"]
	_play(smash_stream, ground, 0.0)
	_fireball(ground, 0.45)
	var node := _fire_pool(ground)
	fires.append({"at": ground, "time": FIRE_SECONDS, "node": node, "tick": 0.0})
	_report("incendio provocado", ground)


func _report(kind: String, at: Vector3) -> void:
	if wanted != null and wanted.has_method("report_crime"):
		wanted.call("report_crime", kind, at)


func _projectile_mesh(kind: String) -> Node3D:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	if kind == "grenade":
		var egg := SphereMesh.new()
		egg.radius = 0.07
		egg.height = 0.16
		mesh.mesh = egg
		mat.albedo_color = Color("3d4a2e")
	else:
		var bottle := CylinderMesh.new()
		bottle.top_radius = 0.025
		bottle.bottom_radius = 0.05
		bottle.height = 0.26
		mesh.mesh = bottle
		mat.albedo_color = Color(0.35, 0.55, 0.3, 0.8)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var rag := MeshInstance3D.new()
		var flame := SphereMesh.new()
		flame.radius = 0.04
		flame.height = 0.08
		rag.mesh = flame
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(1.0, 0.6, 0.2)
		glow.emission_enabled = true
		glow.emission = Color(1.0, 0.5, 0.1)
		glow.emission_energy_multiplier = 3.0
		rag.material_override = glow
		rag.position.y = 0.16
		root.add_child(rag)
	mesh.material_override = mat
	root.add_child(mesh)
	return root


func _fireball(at: Vector3, size: float) -> void:
	var holder := Node3D.new()
	holder.top_level = true
	add_child(holder)
	holder.global_position = at + Vector3.UP * 0.6
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	ball.mesh = sphere
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.72, 0.28, 0.95)
	mat.albedo_texture = SoftParticle.texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var flare := QuadMesh.new()
	flare.size = Vector2(2.0, 2.0)
	ball.mesh = flare
	ball.material_override = mat
	ball.scale = Vector3.ONE * 1.2 * size
	holder.add_child(ball)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.3)
	flash.omni_range = 20.0 * size
	flash.light_energy = 7.0
	holder.add_child(flash)
	var burst := _particles(Color(1.0, 0.62, 0.18, 0.95), 28, 0.6, 1.3 * size, 7.0 * size)
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.spread = 180.0
	burst.gravity = Vector3(0, 2.0, 0)
	burst.emitting = true
	holder.add_child(burst)
	var smoke := _particles(Color(0.16, 0.15, 0.14, 0.7), 26, 2.8, 1.5 * size, 2.6)
	smoke.one_shot = true
	smoke.explosiveness = 0.85
	smoke.spread = 60.0
	holder.add_child(smoke)
	get_tree().create_timer(0.15, false).timeout.connect(func() -> void:
		if is_instance_valid(smoke):
			smoke.emitting = true)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ball, "scale", Vector3.ONE * 7.0 * size, 0.22)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.45).set_delay(0.12)
	tween.tween_property(flash, "light_energy", 0.0, 0.8)
	tween.chain().tween_interval(3.0)
	tween.chain().tween_callback(holder.queue_free)


func _fire_pool(at: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.top_level = true
	add_child(holder)
	holder.global_position = at
	var flames := _particles(Color(1.0, 0.5, 0.12, 0.85), 40, 0.9, 0.7, 1.6)
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = FIRE_RADIUS * 0.6
	flames.emitting = true
	holder.add_child(flames)
	var smoke := _particles(Color(0.15, 0.15, 0.15, 0.45), 16, 2.5, 1.4, 2.0)
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = FIRE_RADIUS * 0.5
	smoke.emitting = true
	holder.add_child(smoke)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.omni_range = 9.0
	light.light_energy = 2.5
	light.position.y = 1.0
	holder.add_child(light)
	return holder


func _particles(color: Color, amount: int, lifetime: float, size: float, speed: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.direction = Vector3.UP
	particles.spread = 25.0
	particles.initial_velocity_min = speed * 0.5
	particles.initial_velocity_max = speed
	particles.gravity = Vector3(0, 0.8, 0)
	particles.scale_amount_min = size
	particles.scale_amount_max = size * 2.0
	var quad := QuadMesh.new()
	quad.material = SoftParticle.material(color)
	particles.mesh = quad
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	particles.color_ramp = fade
	return particles


func _play(stream: AudioStream, at: Vector3, volume: float) -> void:
	if stream == null or DisplayServer.get_name() == "headless":
		return
	var sound := AudioStreamPlayer3D.new()
	sound.stream = stream
	sound.bus = "SFX"
	sound.unit_size = 18.0
	sound.max_distance = 400.0
	sound.volume_db = volume
	sound.top_level = true
	add_child(sound)
	sound.global_position = at
	sound.finished.connect(sound.queue_free)
	sound.play()


func to_save() -> Dictionary:
	return counts.duplicate()


func from_save(value: Dictionary) -> void:
	for kind in KINDS:
		counts[kind] = clampi(int(value.get(kind, 0)), 0, 10)
