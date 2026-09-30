class_name InteractiveProp
extends RigidBody3D

## Small movable street furniture; simulation sleeps outside the active district.
var home := Vector3.ZERO
var gate_timer := 0.0

func _ready() -> void:
	add_to_group("interactive_props")
	mass = 5.0
	linear_damp = 1.2
	angular_damp = 2.0
	continuous_cd = true
	sleeping = true
	home = global_position

func _physics_process(delta: float) -> void:
	gate_timer -= delta
	if gate_timer > 0.0:
		return
	gate_timer = 0.5
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	freeze = global_position.distance_squared_to(players[0].global_position) > 60.0 * 60.0
	if global_position.y < -20.0:
		global_position = home
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO

func bullet_push(direction: Vector3, point: Vector3, power: float) -> void:
	freeze = false
	sleeping = false
	apply_impulse(direction.normalized() * clampf(power * 0.25, 2.0, 12.0), point - global_position)
