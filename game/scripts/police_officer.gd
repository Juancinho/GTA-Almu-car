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
	armed = true
	equip_firearm()
	add_to_group("police_officers")
	aim_rng.seed = get_instance_id()
	shot_audio = AudioStreamPlayer3D.new()
	shot_audio.stream = load("res://assets/audio/pistol_shot.wav") as AudioStream
	shot_audio.bus = "SFX"
	shot_audio.max_distance = 140.0
	shot_audio.unit_size = 8.0
	add_child(shot_audio)
	_add_cap()


## Policía Local look: navy uniform, light-blue shirt, yellow badge details and a
## peaked cap with a chequered band. The skeleton sits inside a 0.36-scaled model
## whose FBX armature is itself scaled ×100, so attachments must undo the
## skeleton's real global scale (a fixed factor made the cap a giant disc in the sky).
const UNIFORM := {"Shirt": "1d2b4f", "Pants": "18223d", "TieTexture": "9ec0e6", "Details": "d8c94a"}


func _add_cap() -> void:
	for node in human.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in range(mesh.mesh.get_surface_count()):
			var source := mesh.mesh.surface_get_material(surface)
			var key := source.resource_name if source != null else ""
			if UNIFORM.has(key):
				var cloth := StandardMaterial3D.new()
				cloth.albedo_color = Color(str(UNIFORM[key]))
				cloth.roughness = 0.8
				mesh.set_surface_override_material(surface, cloth)
	var skeletons := human.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	var attach := BoneAttachment3D.new()
	attach.bone_name = "Head"
	skeleton.add_child(attach)
	var undo := 1.0 / maxf(skeleton.global_transform.basis.get_scale().x, 0.001)
	var cap := Node3D.new()
	cap.name = "PoliceCap"
	cap.scale = Vector3.ONE * undo
	cap.position = Vector3(0, 0.19, 0.01) * undo
	attach.add_child(cap)
	var navy := StandardMaterial3D.new()
	navy.albedo_color = Color("16223f")
	var band := StandardMaterial3D.new()
	band.albedo_color = Color("e9edf2")
	var crown := MeshInstance3D.new()
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.13
	crown_mesh.bottom_radius = 0.115
	crown_mesh.height = 0.08
	crown_mesh.radial_segments = 12
	crown.mesh = crown_mesh
	crown.material_override = navy
	cap.add_child(crown)
	var ring := MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.118
	ring_mesh.bottom_radius = 0.118
	ring_mesh.height = 0.035
	ring_mesh.radial_segments = 12
	ring.mesh = ring_mesh
	ring.material_override = band
	ring.position.y = -0.045
	cap.add_child(ring)
	var visor := MeshInstance3D.new()
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.2, 0.015, 0.09)
	visor.mesh = visor_mesh
	visor.material_override = navy
	visor.position = Vector3(0, -0.06, -0.13)  # model faces -Z after HumanModel's flip? adjusted by bone
	cap.add_child(visor)


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
		if is_on_wall():
			CharacterStep.climb(self, Vector3(velocity.x,0,velocity.z) * delta, 0.42)
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
	var moving := wanted.player_speed()
	get_tree().call_group("weapon_system", "fire_remote", self, target + Vector3.UP * 1.1,
		7.0 + wanted.level, 35.0, 0.006 + distance * 0.0004 + moving * 0.001, aim_rng, "police")


func _clear_line(target: Vector3) -> bool:
	# Glass is penetrable; masonry and vehicles still block the officer's view.
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.5, target + Vector3.UP * 1.1, 1)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") is BreakableGlass or hit.get("collider") == player or hit.get("collider") == player.driving_vehicle


## Officers never flee: a hit only knocks them down for a moment.
func flee_from(_location: Vector3) -> void:
	pass


func take_damage(amount: float, from: Vector3, by_player: bool = true) -> void:
	super.take_damage(amount, from, by_player)
	if wanted != null and by_player:
		wanted.report_police_attack(global_position)


func take_hit(from: Vector3, impulse: float) -> void:
	super.take_hit(from, impulse)
	if wanted != null:
		wanted.report_police_attack(global_position)
