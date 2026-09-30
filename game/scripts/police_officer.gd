class_name PoliceOfficer
extends Pedestrian

## A local police officer who gets out of a patrol car near a wanted player.
## Level 1: closes in to arrest. From level 2, or when the player draws a gun,
## officers keep their distance and shoot; accuracy falls with range and speed.
## They can be punched, run over and shot like anyone else (it makes things worse).

const RUN := 5.6
const KEEP_DISTANCE := 11.0

var wanted: WantedSystem
var car: DriveableVehicle
var shoot_timer := 1.4
var aim_rng := RandomNumberGenerator.new()
var shot_audio: AudioStreamPlayer3D


func _ready() -> void:
	model_name = "male_suit"
	display_name = "Policía"
	super._ready()
	add_to_group("police_officers")
	aim_rng.seed = get_instance_id()
	shot_audio = AudioStreamPlayer3D.new()
	shot_audio.stream = load("res://assets/audio/pistol_shot.wav") as AudioStream
	shot_audio.bus = "SFX"
	shot_audio.max_distance = 140.0
	shot_audio.unit_size = 8.0
	add_child(shot_audio)
	_add_cap()


## Dark blue peaked cap so officers read as police at a glance.
func _add_cap() -> void:
	var skeletons := human.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var attach := BoneAttachment3D.new()
	attach.bone_name = "Head"
	(skeletons[0] as Skeleton3D).add_child(attach)
	var cap := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.13
	mesh.bottom_radius = 0.12
	mesh.height = 0.09
	mesh.radial_segments = 10
	cap.mesh = mesh
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color("1f3c7a")
	cap.material_override = cloth
	cap.scale = Vector3.ONE / HumanModel.MODEL_SCALE
	cap.position = Vector3(0, 0.2, 0) / HumanModel.MODEL_SCALE
	attach.add_child(cap)


func threatening() -> bool:
	if wanted == null:
		return false
	if wanted.level >= 2:
		return true
	var weapons := player.weapons if player != null else null
	return weapons != null and (bool(weapons.get("aiming")) or float(weapons.get("cooldown")) > 0.0 and bool(weapons.call("is_gun")))


func _physics_process(delta: float) -> void:
	if player == null:
		var people := get_tree().get_nodes_in_group("player")
		if not people.is_empty():
			player = people[0] as PlayerController
	if state == State.DOWN:
		_update_down(delta)
		if state != State.DOWN and not dead:
			state = State.FIGHT  # back on duty
		return
	if player == null or wanted == null or wanted.level == 0:
		velocity = Vector3.ZERO
		return
	var target := player.driving_vehicle.global_position if player.driving_vehicle != null else player.global_position
	var offset := target - global_position
	offset.y = 0.0
	var distance := offset.length()
	var shooting := threatening() and not player.dead
	var stop_at := KEEP_DISTANCE if shooting else 1.6
	if distance > stop_at:
		var direction := offset / maxf(distance, 0.01)
		velocity = Vector3(direction.x * RUN, -3.0, direction.z * RUN)
		move_and_slide()
		human.update_motion(RUN)
	else:
		velocity = Vector3.ZERO
		human.update_motion(0.0)
	rotation.y = lerp_angle(rotation.y, atan2(-offset.x, -offset.z), minf(1.0, 10.0 * delta))
	if not shooting:
		return
	shoot_timer -= delta
	if shoot_timer > 0.0 or distance > 55.0 or not _clear_line(target):
		return
	shoot_timer = aim_rng.randf_range(0.9, 1.5)
	human.hold_pose("punch", 0.26)
	if DisplayServer.get_name() != "headless":
		shot_audio.play()
	var moving := wanted.player_speed()
	var chance := clampf(0.8 - distance / 70.0 - moving * 0.035, 0.12, 0.8)
	if aim_rng.randf() < chance:
		if player.driving_vehicle != null:
			player.driving_vehicle.apply_damage(35.0)
		else:
			player.take_damage(7.0 + wanted.level, "police")


func _clear_line(target: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.5, target + Vector3.UP * 1.1)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == player or hit.get("collider") == player.driving_vehicle


## Officers never flee: a hit only knocks them down for a moment.
func flee_from(_location: Vector3) -> void:
	pass


func take_damage(amount: float, from: Vector3) -> void:
	super.take_damage(amount, from)
	if wanted != null:
		wanted.report_police_attack(global_position)


func take_hit(from: Vector3, impulse: float) -> void:
	super.take_hit(from, impulse)
	if wanted != null:
		wanted.report_police_attack(global_position)
