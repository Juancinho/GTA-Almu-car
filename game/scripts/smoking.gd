class_name SmokingSystem
extends Node3D

## Tobacco: packs are bought (or stolen) at the estancos. Press X on foot to
## light a cigarette: it sits in the right hand with a glowing tip and a thin
## trail of smoke, lasts about twelve seconds and calms the nerves a little
## (a few health points). Aiming, fighting, swimming or getting in a car puts it out.

const DURATION := 12.0
const HEAL := 6.0

var player: PlayerController
var main: Node
var smoking := false
var time_left := 0.0
var cigarette: Node3D
var smoke: CPUParticles3D
var _skeleton: Skeleton3D


func configure(target_player: PlayerController, target_main: Node) -> void:
	player = target_player
	main = target_main
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
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 6
	puff.rings = 3
	smoke.mesh = puff
	var haze := StandardMaterial3D.new()
	haze.albedo_color = Color(0.82, 0.82, 0.82, 0.35)
	haze.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	haze.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke.material_override = haze
	smoke.position = Vector3(0, 0, -0.05)
	smoke.emitting = false
	cigarette.add_child(smoke)


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
	cigarette.visible = true
	smoke.emitting = true
	return true


func stop() -> void:
	smoking = false
	cigarette.visible = false
	smoke.emitting = false


func _process(delta: float) -> void:
	if not smoking or player == null:
		return
	var weapons: Node = player.weapons
	var busy := player.dead or player.driving_vehicle != null or player.swimming or (weapons != null and bool(weapons.get("aiming")))
	if busy:
		stop()
		return
	time_left -= delta
	var hand := _hand()
	var body := player.visual.global_transform.basis.orthonormalized()
	var held := Transform3D(body * Basis(Vector3.RIGHT, deg_to_rad(-20.0)), hand + body.y * 0.02 - body.z * 0.03)
	# The body is drawn interpolated between physics ticks: follow the drawn hand.
	cigarette.global_transform = player.visual.get_global_transform_interpolated() * (player.visual.global_transform.affine_inverse() * held)
	if time_left <= 0.0:
		player.heal(HEAL)
		stop()


func _hand() -> Vector3:
	if _skeleton == null:
		var skeletons := player.human.find_children("*", "Skeleton3D", true, false)
		if skeletons.is_empty():
			return player.global_position + Vector3(0.25, 0.95, 0)
		_skeleton = skeletons[0] as Skeleton3D
	var bone := _skeleton.find_bone("Palm.R")
	return (_skeleton.global_transform * _skeleton.get_bone_global_pose(bone)).origin
