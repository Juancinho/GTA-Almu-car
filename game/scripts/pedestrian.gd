class_name Pedestrian
extends CharacterBody3D

enum State { IDLE, WANDER, FLEE, DOWN }

var display_name := "Vecina"
var mission_contact := false
var shirt_color := Color("b77f62")
var state := State.WANDER
var home := Vector3.ZERO
var destination := Vector3.ZERO
var think_timer := 0.0
var rng := RandomNumberGenerator.new()
var player: PlayerController
var human: HumanModel
var model_name := ""
var collider: CollisionShape3D
var down_timer := 0.0
var knocked_from := Vector3.ZERO


func _ready() -> void:
	add_to_group("pedestrians")
	if mission_contact:
		add_to_group("mission_contacts")
	home = global_position
	destination = home
	rng.seed = int(absf(home.x * 237.0 + home.z * 83.0)) + 91
	_build_visual()


func _build_visual() -> void:
	collider = CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.7
	collider.shape = shape
	collider.position.y = 0.85
	add_child(collider)
	if model_name == "":
		model_name = HumanModel.model_for_seed(rng.seed)
	human = HumanModel.new(model_name)
	human.name = "Human"
	add_child(human)


func _physics_process(delta: float) -> void:
	if player == null:
		var people := get_tree().get_nodes_in_group("player")
		if not people.is_empty():
			player = people[0] as PlayerController
	var far := player != null and global_position.distance_squared_to(player.global_position) > HumanModel.ANIMATION_RANGE * HumanModel.ANIMATION_RANGE
	human.set_animation_active(not far)
	if player != null and global_position.distance_squared_to(player.global_position) > 90.0 * 90.0:
		return
	if state == State.DOWN:
		_update_down(delta)
		return
	if mission_contact:
		velocity = Vector3.ZERO
		human.update_motion(0.0)
		return
	think_timer -= delta
	if think_timer <= 0.0:
		think_timer = rng.randf_range(2.5, 5.0)
		if state == State.FLEE:
			state = State.WANDER
		elif state == State.WANDER:
			destination = home + Vector3(rng.randf_range(-9.0, 9.0), 0, rng.randf_range(-4.0, 4.0))
	var offset := destination - global_position
	offset.y = 0
	if offset.length() > 0.7:
		var direction := offset.normalized()
		velocity.x = direction.x * (5.0 if state == State.FLEE else 1.3)
		velocity.z = direction.z * (5.0 if state == State.FLEE else 1.3)
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(1.0, 6.0 * delta))
	else:
		velocity.x = 0
		velocity.z = 0
	velocity.y = -3.0
	move_and_slide()
	human.update_motion(Vector2(velocity.x, velocity.z).length())


func flee_from(location: Vector3) -> void:
	if state == State.DOWN:
		return
	state = State.FLEE
	var away := global_position - location
	away.y = 0
	destination = global_position + away.normalized() * 15.0
	think_timer = 4.0


## Hit by a car or punched: slide back, lie on the ground, then get up and flee.
func knock_down(from: Vector3, impulse: float) -> void:
	if state == State.DOWN or mission_contact:
		return
	state = State.DOWN
	down_timer = 7.0
	knocked_from = from
	var away := global_position - from
	away.y = 0.0
	velocity = (away.normalized() if away.length() > 0.01 else Vector3.FORWARD) * minf(impulse, 9.0)
	collider.set_deferred("disabled", true)
	human.play_action("death", 7.0)
	for node in get_tree().get_nodes_in_group("pedestrians"):
		var other := node as Pedestrian
		if other != null and other != self and not other.mission_contact and other.state != State.DOWN and other.global_position.distance_to(global_position) < 18.0:
			other.flee_from(global_position)


func _update_down(delta: float) -> void:
	down_timer -= delta
	velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
	global_position += Vector3(velocity.x, 0.0, velocity.z) * delta
	if down_timer <= 0.0:
		collider.set_deferred("disabled", false)
		human.action_timer = 0.0
		state = State.WANDER
		flee_from(knocked_from)
