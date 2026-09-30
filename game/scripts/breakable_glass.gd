class_name BreakableGlass
extends StaticBody3D

## Intact glazing blocks bodies and bullets. E still operates the closed entrance.
const SHOT_LAYER := 4
const INTACT_LAYERS := 1 | SHOT_LAYER
var broken := false
var visual: MeshInstance3D


func configure(mesh: MeshInstance3D, size: Vector3) -> void:
	visual = mesh
	position = mesh.position
	collision_layer = INTACT_LAYERS
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)
	add_to_group("breakable_glass")


func shatter() -> bool:
	if broken:
		return false
	set_broken(true)
	return true


func set_broken(value: bool) -> void:
	broken = value
	visual.visible = not value
	# Layer changes take effect immediately, including subsequent shotgun pellets.
	collision_layer = 0 if value else INTACT_LAYERS


func save_key() -> String:
	return str(get_path())
