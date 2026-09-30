class_name NpcFirearm
extends Node3D

var actor: Pedestrian
var gun: Node3D
var model: Node3D

func _process(_delta: float) -> void:
	pose()

func pose() -> void:
	if actor == null or actor.human == null or actor.player == null:
		return
	visible = actor.is_visible_in_tree() and not actor.dead and actor.state != Pedestrian.State.DOWN and actor.global_position.distance_squared_to(actor.player.global_position) < 70.0 * 70.0
	if not visible:
		actor.human.clear_weapon_pose()
		return
	if gun == null:
		var systems := get_tree().get_nodes_in_group("weapon_system")
		if systems.is_empty():
			return
		gun = Node3D.new()
		gun.name = "Grip"
		add_child(gun)
		model = systems[0].weapon_model("pistol")
		gun.add_child(model)
	var human := actor.human
	human.clear_weapon_pose()
	if human.grip_skeleton == null:
		var rigs := human.find_children("*", "Skeleton3D", true, false)
		if rigs.is_empty():
			return
		human.grip_skeleton = rigs[0] as Skeleton3D
	var rig := human.grip_skeleton
	var shoulder := rig.to_global(rig.get_bone_global_pose(rig.find_bone("UpperArm.R")).origin)
	var target := actor.player.global_position + Vector3.UP * 1.1
	var direction := (target - shoulder).normalized()
	if direction.length_squared() < 0.01:
		return
	var basis := Basis.looking_at(direction, Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP)
	human.place_hand("R", shoulder + basis * Vector3(0.025,-0.16,-0.39), shoulder + actor.global_basis * Vector3(0.32,-0.45,0.03))
	human.close_weapon_hand("R")
	var grip := rig.to_global(rig.get_bone_global_pose(rig.find_bone("MiddleHand.R")).origin)
	gun.global_transform = Transform3D(basis, grip)

func muzzle_position() -> Vector3:
	return gun.to_global(Vector3(0,0.085,-0.22)) if gun != null else actor.global_position + Vector3.UP * 1.5
