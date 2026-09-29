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
		for key in ["Idle", "Walk", "Run", "Jump"]:
			if str(animation_name).ends_with("_" + key):
				clips[key.to_lower()] = animation_name
				if key != "Jump":
					player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
	play_state("idle")


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
	if not grounded:
		play_state("jump")
	elif speed > 6.0:
		play_state("run", clampf(speed / 8.0, 0.8, 1.3))
	elif speed > 0.4:
		play_state("walk", clampf(speed / 1.6, 0.6, 1.6))
	else:
		play_state("idle")


## Skip skinning work for people the camera cannot meaningfully see.
func set_animation_active(active: bool) -> void:
	if player != null and player.active != active:
		player.active = active
