class_name Ballistics
extends Node3D

## All shooters share occlusion, glass penetration and damage. No projectile ticks.
signal impact(at: Vector3, tint: Color, amount: int)
const SHOT_MASK := 1 | BreakableGlass.SHOT_LAYER
const MAX_GLASS_HITS := 8
const MAX_MARKS := 48
var wanted: WantedSystem
var marks: Array[MeshInstance3D] = []
var mark_cursor := 0
var mark_mesh: QuadMesh
var mark_material: StandardMaterial3D


func shoot(origin: Vector3, direction: Vector3, reach: float, damage: float,
		vehicle_damage: float, shooter: CollisionObject3D, source: String = "bullet") -> Dictionary:
	var end := origin + direction.normalized() * reach
	var excludes: Array[RID] = [shooter.get_rid()]
	var result := {"collider": null, "position": end, "glass_hits": 0}
	var power := 1.0
	for layer in range(MAX_GLASS_HITS + 1):
		var query := PhysicsRayQueryParameters3D.create(origin, end, SHOT_MASK, excludes)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			result["position"] = end
			return result
		var target: Object = hit["collider"]
		var at: Vector3 = hit["position"]
		result["collider"] = target
		result["position"] = at
		if target is BreakableGlass:
			var pane := target as BreakableGlass
			if pane.shatter():
				impact.emit(at, Color("bbdfed"), 12)
			result["glass_hits"] = int(result["glass_hits"]) + 1
			excludes.append(pane.get_rid())
			power *= 0.8
			continue
		if target is PlayerController:
			(target as PlayerController).take_damage(damage * power, source)
		elif target is Pedestrian:
			var person := target as Pedestrian
			person.take_damage(damage * power, shooter.global_position, shooter is PlayerController)
			if shooter is PlayerController and not person.mission_contact and wanted != null:
				wanted.report_crime("agresión armada", person.global_position)
		elif target is DriveableVehicle:
			(target as DriveableVehicle).apply_damage(vehicle_damage * power)
			if shooter is PlayerController and wanted != null and wanted.police_cars.has(target):
				wanted.report_police_attack((target as Node3D).global_position)
		elif target is InteractiveProp:
			(target as InteractiveProp).bullet_push(direction, at, damage * power)
		else:
			_mark(at, hit["normal"])
		var tint := Color("8c1820") if target is Pedestrian or target is PlayerController else Color("ffd080") if target is DriveableVehicle else Color("9e9485")
		impact.emit(at, tint, 5)
		return result
	return result


func _mark(at: Vector3, normal: Vector3) -> void:
	if normal.length_squared() < 0.5:
		return
	if mark_mesh == null:
		mark_mesh = QuadMesh.new()
		mark_mesh.size = Vector2(0.055, 0.055)
		mark_material = StandardMaterial3D.new()
		mark_material.albedo_color = Color("3b342d")
		mark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mark_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mark: MeshInstance3D
	if marks.size() < MAX_MARKS:
		mark = MeshInstance3D.new()
		mark.mesh = mark_mesh
		mark.material_override = mark_material
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mark.visibility_range_end = 60.0
		add_child(mark)
		marks.append(mark)
	else:
		mark = marks[mark_cursor]
		mark_cursor = (mark_cursor + 1) % MAX_MARKS
	mark.global_position = at + normal * 0.008
	mark.look_at(mark.global_position - normal, Vector3.FORWARD if absf(normal.dot(Vector3.UP)) > 0.95 else Vector3.UP)


func glass_to_save() -> Array[String]:
	var broken: Array[String] = []
	for node in get_tree().get_nodes_in_group("breakable_glass"):
		var pane := node as BreakableGlass
		if pane.broken:
			broken.append(pane.save_key())
	return broken


func glass_from_save(keys: Array) -> void:
	for node in get_tree().get_nodes_in_group("breakable_glass"):
		var pane := node as BreakableGlass
		pane.set_broken(keys.has(pane.save_key()))
