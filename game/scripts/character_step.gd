class_name CharacterStep
extends RefCounted

## Sweep up, forward and down before accepting a low static step. Never teleport
## through a wall/ceiling or step onto another character, vehicle or movable prop.
static func climb(body: CharacterBody3D, motion: Vector3, height: float) -> bool:
	if not body.is_on_floor() or motion.length_squared() < 0.000001:
		return false
	var contact := KinematicCollision3D.new()
	if not body.test_move(body.global_transform, motion, contact):
		return false
	var wall := false
	for i in range(contact.get_collision_count()):
		wall = wall or contact.get_normal(i).y < 0.65
	if not wall or body.test_move(body.global_transform, Vector3.UP * height):
		return false
	var raised := body.global_transform
	raised.origin.y += height
	# A capsule can touch the vertical lip while its foot is still outside the
	# tread. Use 40 cm clearance when per-tick motion is shorter than the tread.
	var forward := motion.normalized() * maxf(motion.length(), 0.4)
	if body.test_move(raised, forward):
		return false
	raised.origin += forward
	var landing := KinematicCollision3D.new()
	if not body.test_move(raised, Vector3.DOWN * (height + 0.05), landing):
		return false
	if not landing.get_collider() is StaticBody3D or landing.get_normal().y < 0.7:
		return false
	var rise := height + landing.get_travel().y
	if rise <= 0.015 or rise > height:
		return false
	body.global_position = raised.origin + landing.get_travel() + Vector3.UP * 0.003
	return true
