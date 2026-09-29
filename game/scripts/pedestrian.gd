class_name Pedestrian
extends CharacterBody3D

enum State { IDLE, WANDER, FLEE }

var display_name := "Vecina"
var mission_contact := false
var shirt_color := Color("b77f62")
var state := State.WANDER
var home := Vector3.ZERO
var destination := Vector3.ZERO
var think_timer := 0.0
var rng := RandomNumberGenerator.new()
var player: PlayerController


func _ready() -> void:
	add_to_group("pedestrians")
	if mission_contact:
		add_to_group("mission_contacts")
	home = global_position
	destination = home
	rng.seed = int(absf(home.x * 237.0 + home.z * 83.0)) + 91
	_build_visual()


func _build_visual() -> void:
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.7
	collider.shape = shape
	collider.position.y = 0.85
	add_child(collider)
	_part("Torso", Vector3(0, 1.1, 0), Vector3(0.58, 0.65, 0.31), shirt_color)
	_part("Trousers", Vector3(0, 0.52, 0), Vector3(0.5, 0.69, 0.3), Color("4f5e65"))
	_part("Head", Vector3(0, 1.66, 0), Vector3(0.38, 0.4, 0.36), Color("b88a67"))
	_part("Hair", Vector3(0, 1.88, 0), Vector3(0.42, 0.12, 0.38), Color("3c3938"))


func _part(label: String, at: Vector3, size: Vector3, color: Color) -> void:
	var visual := MeshInstance3D.new()
	visual.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	visual.material_override = material
	add_child(visual)


func _physics_process(delta: float) -> void:
	if player == null:
		var people := get_tree().get_nodes_in_group("player")
		if not people.is_empty():
			player = people[0] as PlayerController
	if player != null and global_position.distance_squared_to(player.global_position) > 90.0 * 90.0:
		return
	if mission_contact:
		velocity = Vector3.ZERO
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


func flee_from(location: Vector3) -> void:
	state = State.FLEE
	var away := global_position - location
	away.y = 0
	destination = global_position + away.normalized() * 15.0
	think_timer = 4.0
