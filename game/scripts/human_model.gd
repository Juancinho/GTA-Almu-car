class_name HumanModel
extends Node3D

## Animated CC0 Quaternius person (see assets/third_party). Picks idle/walk/run/jump
## clips from movement and pauses animation when far from the camera.

const MODEL_DIR := "res://assets/third_party/quaternius/people/"
const MODELS := ["male_casual", "male_longsleeve", "male_shirt", "male_suit", "female_alternative", "female_casual", "female_dress", "female_tanktop"]
const MODEL_SCALE := 0.36
const ANIMATION_RANGE := 70.0

var model_name := "male_casual"
var player: AnimationPlayer
var clips: Dictionary = {}  # idle/walk/run/jump -> animation name
var current := ""
var action_timer := 0.0  # while > 0, a one-shot action (punch, knocked down) owns the pose
var grip_skeleton: Skeleton3D
var grip_active := false
var finger_rotations: Dictionary = {}
var swim_pose_active := false
var outfit := ""
static var swimwear_materials: Dictionary = {}

func change_model(chosen: String) -> void:
	if not MODELS.has(chosen) or chosen == model_name:
		return
	clear_weapon_pose()
	var old := get_node_or_null("Model")
	if old != null:
		old.free()
	model_name = chosen
	player = null
	grip_skeleton = null
	finger_rotations.clear()
	clips.clear()
	current = ""
	_ready()


func close_weapon_hand(side: String) -> void:
	if grip_skeleton == null or not clips.has("punch"):
		return
	if finger_rotations.is_empty():
		var clip := player.get_animation(clips["punch"])
		for track in range(clip.get_track_count()):
			if clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			var bone := str(clip.track_get_path(track)).get_slice(":", 1)
			if bone.begins_with("MiddleHand") or bone.begins_with("Fingers") or bone.begins_with("Thumb"):
				finger_rotations[bone] = clip.rotation_track_interpolate(track, 0.42)
	for index in range(grip_skeleton.get_bone_count()):
		var bone := grip_skeleton.get_bone_name(index)
		if not bone.ends_with("." + side) or not finger_rotations.has(bone):
			continue
		var pose := grip_skeleton.get_bone_pose(index)
		pose.basis = Basis(finger_rotations[bone])
		var parent := grip_skeleton.get_bone_parent(index)
		grip_skeleton.set_bone_global_pose_override(index, grip_skeleton.get_bone_global_pose(parent) * pose, 1.0, true)
	grip_active = true


## Upper-body-only two-bone solve; the walking animation still owns the legs.
func clear_weapon_pose() -> void:
	if grip_active and grip_skeleton != null:
		grip_skeleton.clear_bones_global_pose_override()
	grip_active = false


func place_hand(side: String, target_world: Vector3, elbow_world: Vector3) -> Vector3:
	if grip_skeleton == null:
		var rigs := find_children("*", "Skeleton3D", true, false)
		if rigs.is_empty():
			return target_world
		grip_skeleton = rigs[0] as Skeleton3D
	var upper := grip_skeleton.find_bone("UpperArm." + side)
	var lower := grip_skeleton.find_bone("LowerArm." + side)
	var hand := grip_skeleton.find_bone("Palm." + side)
	if mini(upper, mini(lower, hand)) < 0:
		return target_world
	var a := grip_skeleton.get_bone_global_pose(upper)
	var b := grip_skeleton.get_bone_global_pose(lower)
	var c := grip_skeleton.get_bone_global_pose(hand)
	var target := grip_skeleton.to_local(target_world)
	var pole := grip_skeleton.to_local(elbow_world) - a.origin
	var length_a := a.origin.distance_to(b.origin)
	var length_b := b.origin.distance_to(c.origin)
	var axis := (target - a.origin).normalized()
	var distance := clampf(a.origin.distance_to(target), absf(length_a - length_b) + 0.001, length_a + length_b - 0.001)
	target = a.origin + axis * distance
	var along := (length_a * length_a - length_b * length_b + distance * distance) / (2.0 * distance)
	var bend := (pole - axis * pole.dot(axis)).normalized()
	var elbow := a.origin + axis * along + bend * sqrt(maxf(0.0, length_a * length_a - along * along))
	var upper_rotation := Basis(Quaternion((b.origin - a.origin).normalized(), (elbow - a.origin).normalized()))
	var lower_rotation := Basis(Quaternion((c.origin - b.origin).normalized(), (target - elbow).normalized()))
	grip_skeleton.set_bone_global_pose_override(upper, Transform3D(upper_rotation * a.basis, a.origin), 1.0, true)
	grip_skeleton.set_bone_global_pose_override(lower, Transform3D(lower_rotation * b.basis, elbow), 1.0, true)
	grip_skeleton.set_bone_global_pose_override(hand, Transform3D(lower_rotation * c.basis, target), 1.0, true)
	grip_active = true
	return grip_skeleton.to_global(target)


func _init(chosen: String = "male_casual") -> void:
	model_name = chosen if MODELS.has(chosen) else "male_casual"


func _ready() -> void:
	var scene := load(MODEL_DIR + model_name + ".fbx") as PackedScene
	if scene == null:
		push_error("HumanModel: missing %s%s.fbx" % [MODEL_DIR, model_name])
		return
	var model := scene.instantiate() as Node3D
	model.name = "Model"
	model.scale = Vector3.ONE * MODEL_SCALE
	model.rotation.y = PI  # Quaternius characters face +Z; gameplay forward is -Z.
	add_child(model)
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).visibility_range_end = 160.0
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_error("HumanModel: no AnimationPlayer in %s" % model_name)
		return
	player = players[0] as AnimationPlayer
	for animation_name in player.get_animation_list():
		for key in ["Idle", "Walk", "Run", "Jump", "Sitting", "Death", "Punch", "SwordSlash"]:
			if str(animation_name).ends_with("_" + key):
				clips[key.to_lower()] = animation_name
				if key in ["Idle", "Walk", "Run", "Sitting"]:
					player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
	play_state("idle")
	if outfit == "adult_swimwear":
		_apply_swimwear(model)


func _apply_swimwear(model: Node3D) -> void:
	for item in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := item as MeshInstance3D
		var skin := Color("b9896b")
		for surface in range(mesh.mesh.get_surface_count()):
			var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if source != null and source.resource_name == "Skin":
				skin = source.albedo_color
		for surface in range(mesh.mesh.get_surface_count()):
			var source := mesh.mesh.surface_get_material(surface)
			if source == null or source.resource_name not in ["Shirt", "Pants"]:
				continue
			var key := source.resource_name + skin.to_html()
			if not swimwear_materials.has(key):
				var material := ShaderMaterial.new()
				material.shader = preload("res://shaders/swimwear.gdshader")
				material.set_shader_parameter("skin_tint", skin)
				material.set_shader_parameter("lower_piece", source.resource_name == "Pants")
				material.set_shader_parameter("fabric", load("res://assets/third_party/ambientcg/plaster003_color.png"))
				swimwear_materials[key] = material
			mesh.set_surface_override_material(surface, swimwear_materials[key])


func _process(delta: float) -> void:
	action_timer = maxf(0.0, action_timer - delta)


## One-shot clip that movement updates will not interrupt for `seconds`.
func play_action(state: String, seconds: float) -> void:
	if player == null or not clips.has(state):
		return
	action_timer = seconds
	current = state
	player.speed_scale = 1.0
	player.play(clips[state], 0.1)


## Freeze a clip at `at_seconds` (the punch's extended arm doubles as the aiming pose).
func hold_pose(state: String, at_seconds: float) -> void:
	if player == null or not clips.has(state):
		return
	action_timer = 0.15
	if current != state or player.is_playing():
		current = state
		player.play(clips[state], 0.0)  # no cross-fade: a paused blend would freeze half-way
		player.seek(at_seconds, true)
		player.pause()


static func model_for_seed(seed_value: int) -> String:
	return MODELS[absi(seed_value) % MODELS.size()]


func play_state(state: String, speed_scale: float = 1.0) -> void:
	if player == null or not clips.has(state):
		return
	player.speed_scale = speed_scale
	if current == state:
		return
	current = state
	player.play(clips[state], 0.2)


## speed in m/s on the ground plane.
func update_motion(speed: float, grounded: bool = true) -> void:
	if action_timer > 0.0:
		return
	if not grounded:
		play_state("jump")
	elif speed > 6.0:
		play_state("run", clampf(speed / 8.0, 0.8, 1.3))
	elif speed > 0.4:
		play_state("walk", clampf(speed / 1.6, 0.6, 1.6))
	else:
		play_state("idle")


## Procedural strokes on the existing licensed rig; no airborne jump pose at sea.
func update_swim(phase: float, speed: float, diving: bool) -> void:
	if grip_skeleton == null:
		var rigs := find_children("*", "Skeleton3D", true, false)
		if rigs.is_empty():
			return
		grip_skeleton = rigs[0] as Skeleton3D
	clear_weapon_pose()
	action_timer = 0.0
	play_state("idle")
	var stroke := 0.85 if speed > 0.1 or diving else 0.3
	for side in ["L", "R"]:
		var cycle := phase + (PI if side == "R" else 0.0)
		for limb in ["UpperArm", "LowerArm", "UpperLeg", "LowerLeg"]:
			var index := grip_skeleton.find_bone(limb + "." + side)
			if index < 0:
				continue
			var pose := grip_skeleton.get_bone_pose(index)
			var swing := sin(cycle) * stroke if limb == "UpperArm" else -0.45 if limb == "LowerArm" else sin(cycle * 2.0) * 0.22 if limb == "UpperLeg" else 0.15
			pose.basis = Basis(Vector3.RIGHT, swing) * pose.basis
			var parent := grip_skeleton.get_bone_parent(index)
			grip_skeleton.set_bone_global_pose_override(index, grip_skeleton.get_bone_global_pose(parent) * pose, 1.0, true)
	swim_pose_active = true


func clear_swim_pose() -> void:
	if swim_pose_active and grip_skeleton != null:
		grip_skeleton.clear_bones_global_pose_override()
	swim_pose_active = false


## Skip skinning work for people the camera cannot meaningfully see.
func set_animation_active(active: bool) -> void:
	if player != null and player.active != active:
		player.active = active
