class_name SmokingSystem
extends Node3D

## Tobacco: packs are bought (or stolen) at the estancos. Press X on foot to
## light a cigarette: it sits between the fingers of the right hand with a
## glowing tip and a thin trail of smoke. Every few seconds the arm brings it to
## the lips for a drag (the ember flares) and a puff of smoke is breathed out of
## the mouth. Lasts about twelve seconds and calms the nerves a little (a few
## health points). Aiming, fighting, swimming or getting in a car puts it out.

const SoftParticle = preload("res://scripts/soft_particle.gd")

const DURATION := 12.0
const HEAL := 6.0

var player: PlayerController
var main: Node
var smoking := false
var time_left := 0.0
var cigarette: Node3D
var smoke: CPUParticles3D
var _skeleton: Skeleton3D
var exhale: CPUParticles3D
var ember_material: StandardMaterial3D
const DRAG_EVERY := 3.6
const DRAG_LENGTH := 1.5
var next_drag := 1.2
var drag_time := -1.0  # >= 0 while the cigarette is being brought to the lips
var exhale_left := 0.0
var drags := 0


func configure(target_player: PlayerController, target_main: Node) -> void:
	player = target_player
	main = target_main
	process_priority = 60  # after the weapon pose has cleared the arm overrides
	cigarette = Node3D.new()
	cigarette.name = "Cigarette"
	cigarette.top_level = true
	cigarette.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # placed every rendered frame
	cigarette.visible = false
	add_child(cigarette)
	var paper := MeshInstance3D.new()
	var stick := CylinderMesh.new()
	stick.top_radius = 0.006
	stick.bottom_radius = 0.006
	stick.height = 0.085
	stick.radial_segments = 6
	stick.rings = 1
	paper.mesh = stick
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("f2efe6")
	paper.material_override = white
	paper.rotation.x = PI * 0.5
	cigarette.add_child(paper)
	var tip := MeshInstance3D.new()
	var ember := SphereMesh.new()
	ember.radius = 0.008
	ember.height = 0.016
	tip.mesh = ember
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("ff6a1a")
	glow.emission_enabled = true
	glow.emission = Color("ff5a10")
	glow.emission_energy_multiplier = 3.0
	tip.material_override = glow
	ember_material = glow
	tip.position = Vector3(0, 0, -0.045)
	cigarette.add_child(tip)
	smoke = CPUParticles3D.new()
	smoke.amount = 14
	smoke.lifetime = 1.8
	smoke.direction = Vector3.UP
	smoke.spread = 12.0
	smoke.gravity = Vector3(0, 0.35, 0)
	smoke.initial_velocity_min = 0.12
	smoke.initial_velocity_max = 0.25
	smoke.scale_amount_min = 0.03
	smoke.scale_amount_max = 0.07
	smoke.mesh = _puff_mesh(Color(0.85, 0.85, 0.85, 0.4))
	smoke.scale_amount_min = 0.05
	smoke.scale_amount_max = 0.11
	smoke.color_ramp = _fade()
	smoke.local_coords = false
	smoke.position = Vector3(0, 0, -0.05)
	smoke.emitting = false
	cigarette.add_child(smoke)
	# Breath: a puff out of the mouth after each drag, drifting forward and up.
	exhale = CPUParticles3D.new()
	exhale.name = "Exhale"
	exhale.top_level = true
	exhale.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	exhale.amount = 30
	exhale.lifetime = 2.2
	exhale.local_coords = false
	exhale.spread = 18.0
	exhale.gravity = Vector3(0, 0.22, 0)
	exhale.initial_velocity_min = 0.45
	exhale.initial_velocity_max = 0.8
	exhale.damping_min = 0.25
	exhale.damping_max = 0.4
	exhale.scale_amount_min = 0.07
	exhale.scale_amount_max = 0.14
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.6))
	exhale.scale_amount_curve = grow
	exhale.mesh = _puff_mesh(Color(0.9, 0.9, 0.92, 0.45))
	exhale.color_ramp = _fade()
	exhale.emitting = false
	add_child(exhale)


## A small sphere whose rim fades out (no billboard: tiny billboards lost their
## per-particle scale here and drew as one big dark disc).
func _puff_mesh(color: Color) -> Mesh:
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 8
	puff.rings = 4
	var haze := ShaderMaterial.new()
	haze.shader = load("res://shaders/soft_puff.gdshader") as Shader
	haze.set_shader_parameter("tint", color)
	puff.material = haze
	return puff


func _fade() -> Gradient:
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0))
	return fade


func packs_text() -> String:
	var count := int(main.get("cigarettes")) if main != null and "cigarettes" in main else 0
	return "Tabaco %d" % count if count > 0 else ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("smoke"):
		if smoking:
			stop()
		else:
			light()


func light() -> bool:
	if player == null or player.dead or player.driving_vehicle != null or player.swimming or smoking:
		return false
	if int(main.get("cigarettes")) <= 0:
		get_tree().call_group("mission_controller", "_show_dialogue", "No te queda tabaco. En los estancos venden (o se puede... coger).")
		return false
	main.set("cigarettes", int(main.get("cigarettes")) - 1)
	smoking = true
	time_left = DURATION
	next_drag = 0.6
	drag_time = -1.0
	cigarette.visible = true
	smoke.emitting = true
	return true


func stop() -> void:
	smoking = false
	cigarette.visible = false
	smoke.emitting = false
	drag_time = -1.0
	if player != null:
		player.human.clear_weapon_pose()


func _process(delta: float) -> void:
	if not smoking or player == null:
		return
	var weapons: Node = player.weapons
	var busy := player.dead or player.driving_vehicle != null or player.swimming or (weapons != null and bool(weapons.get("aiming")))
	if busy:
		stop()
		return
	time_left -= delta
	var body := player.visual.global_transform.basis.orthonormalized()
	var rest_hand := _bone("Palm.R")
	var head := _bone("Head")
	if head == Vector3.INF:
		head = player.global_position + Vector3(0, 1.6, 0)
	var mouth := head + body * Vector3(0.0, -0.02, -0.11)
	# Drag cycle: raise to the lips, hold while the ember flares, lower, exhale.
	next_drag -= delta
	if drag_time < 0.0 and next_drag <= 0.0:
		drag_time = 0.0
	var raise := 0.0
	if drag_time >= 0.0:
		drag_time += delta
		raise = smoothstep(0.0, 0.4, drag_time) * (1.0 - smoothstep(DRAG_LENGTH - 0.4, DRAG_LENGTH, drag_time))
		if drag_time >= DRAG_LENGTH:
			drag_time = -1.0
			next_drag = DRAG_EVERY
			exhale_left = 1.0
			drags += 1
	ember_material.emission_energy_multiplier = 3.0 + 6.0 * smoothstep(0.35, 0.6, raise)
	var hand := rest_hand
	if raise > 0.001 and rest_hand != Vector3.INF:
		var shoulder := _bone("UpperArm.R")
		var at_lips := mouth + body * Vector3(0.05, -0.05, -0.02)
		hand = player.human.place_hand("R", rest_hand.lerp(at_lips, raise), shoulder + body * Vector3(0.3, -0.35, 0.15))
		player.human.close_weapon_hand("R")
	elif rest_hand == Vector3.INF:
		hand = player.global_position + body * Vector3(0.25, 0.95, 0.0)
	# In the fingers it points forward; at the lips the filter touches the mouth.
	var rest_basis := body * Basis(Vector3.RIGHT, deg_to_rad(-20.0))
	var lips_basis := body * Basis(Vector3.UP, deg_to_rad(-35.0)) * Basis(Vector3.RIGHT, deg_to_rad(-12.0))
	var basis := Basis(rest_basis.get_rotation_quaternion().slerp(lips_basis.get_rotation_quaternion(), raise))
	var rest_origin := hand + body.y * 0.02 - body.z * 0.03
	var lips_origin := mouth - lips_basis.z * 0.045
	var held := Transform3D(basis, rest_origin.lerp(lips_origin, smoothstep(0.5, 1.0, raise)))
	# The body is drawn interpolated between physics ticks: follow the drawn body.
	var drawn := player.visual.get_global_transform_interpolated() * player.visual.global_transform.affine_inverse()
	cigarette.global_transform = drawn * held
	exhale.global_transform = Transform3D(Basis.looking_at(-body.z + Vector3(0, -0.25, 0), Vector3.UP), drawn * mouth)
	exhale_left -= delta
	exhale.emitting = exhale_left > 0.0 and exhale_left < 0.85
	if time_left <= 0.0:
		player.heal(HEAL)
		stop()


func _bone(bone_name: String) -> Vector3:
	if _skeleton == null:
		var skeletons := player.human.find_children("*", "Skeleton3D", true, false)
		if skeletons.is_empty():
			return Vector3.INF
		_skeleton = skeletons[0] as Skeleton3D
	var bone := _skeleton.find_bone(bone_name)
	if bone < 0:
		return Vector3.INF
	return (_skeleton.global_transform * _skeleton.get_bone_global_pose(bone)).origin


func _hand() -> Vector3:
	if _skeleton == null:
		var skeletons := player.human.find_children("*", "Skeleton3D", true, false)
		if skeletons.is_empty():
			return player.global_position + Vector3(0.25, 0.95, 0)
		_skeleton = skeletons[0] as Skeleton3D
	var bone := _skeleton.find_bone("Palm.R")
	return (_skeleton.global_transform * _skeleton.get_bone_global_pose(bone)).origin
