class_name MissionMarkers
extends Node3D

## In-world guidance so the player always knows where to go: a glowing column at
## the current destination, a bobbing arrow over mission targets (the car to take
## or chase, the people to fight) and a floating letter over every contact who has
## a mission on offer.

const COLUMN_COLOR := Color(1.0, 0.78, 0.22, 0.30)
const LETTER_RANGE := 320.0

var mission: MissionController
var player: PlayerController
var column: MeshInstance3D
var arrows: Array[MeshInstance3D] = []
var letters: Dictionary = {}  # contact name -> Label3D
var clock := 0.0
var offers_timer := 0.0
var offers: Array = []


func _ready() -> void:
	var tube := CylinderMesh.new()
	tube.top_radius = 1.0
	tube.bottom_radius = 1.0
	tube.height = 1.0
	tube.radial_segments = 20
	tube.rings = 1
	tube.cap_top = false
	tube.cap_bottom = false
	column = MeshInstance3D.new()
	column.name = "ObjectiveColumn"
	column.mesh = tube
	column.material_override = _glow(COLUMN_COLOR)
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	column.visible = false
	add_child(column)


static func _glow(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	return mat


func _arrow(index: int) -> MeshInstance3D:
	while arrows.size() <= index:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.55
		cone.bottom_radius = 0.0
		cone.height = 0.9
		cone.radial_segments = 4
		cone.rings = 1
		var arrow := MeshInstance3D.new()
		arrow.name = "TargetArrow_%d" % arrows.size()
		arrow.mesh = cone
		arrow.material_override = _glow(Color(1.0, 0.78, 0.22, 0.9))
		arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(arrow)
		arrows.append(arrow)
	return arrows[index]


func _process(delta: float) -> void:
	if mission == null or player == null:
		return
	clock += delta
	offers_timer -= delta
	if offers_timer <= 0.0:
		offers_timer = 0.25
		offers = mission.offers()
	_update_column()
	_update_arrows()
	_update_letters()


func _update_column() -> void:
	column.visible = false
	if mission.completed or mission.objectives.is_empty():
		return
	var objective: Dictionary = mission.objectives[mission.stage]
	if str(objective.get("type", "")) != "reach_area" or objective.has("marker_target") or objective.has("marker_contact"):
		return
	var p := mission.resolve_marker(objective)
	if p == Vector3.INF:
		return
	var radius := clampf(float(objective.get("radius", 8.0)) * 0.35, 1.2, 3.2)
	var height := 9.0
	column.scale = Vector3(radius, height, radius)
	column.global_position = p + Vector3(0, height * 0.5 - 0.3, 0)
	var pulse := 0.22 + 0.1 * sin(clock * 3.0)
	(column.material_override as StandardMaterial3D).albedo_color.a = pulse
	column.visible = true


func _update_arrows() -> void:
	var targets := mission.objective_targets()
	if not mission.completed and not mission.objectives.is_empty():
		var objective: Dictionary = mission.objectives[mission.stage]
		if objective.has("marker_target") or objective.has("marker_contact"):
			var p := mission.resolve_marker(objective)
			if p != Vector3.INF:
				var holder := Node3D.new()  # position-only target
				holder.position = p
				targets.append(holder)
	var shown := 0
	for target in targets:
		if player.driving_vehicle != null and target == player.driving_vehicle:
			continue
		var enemy := target is Pedestrian and (target as Pedestrian).enemy
		if target is Pedestrian and (target as Pedestrian).defeated:
			continue
		var arrow := _arrow(shown)
		var base := target.global_position if target.is_inside_tree() else target.position
		var lift := 2.6 if target is Pedestrian else 3.0
		arrow.global_position = base + Vector3(0, lift + 0.25 * sin(clock * 4.0 + shown), 0)
		arrow.rotation.y = clock * 2.0
		(arrow.material_override as StandardMaterial3D).albedo_color = Color(0.92, 0.25, 0.22, 0.95) if enemy else Color(1.0, 0.78, 0.22, 0.95)
		arrow.visible = true
		shown += 1
	for i in range(shown, arrows.size()):
		arrows[i].visible = false
	for target in targets:
		if not target.is_inside_tree():
			target.free()


func _update_letters() -> void:
	var active := {}
	for offer in offers:
		var contact_name := str(offer["name"])
		active[contact_name] = true
		var label := letters.get(contact_name) as Label3D
		if label == null:
			label = Label3D.new()
			label.name = "Blip_" + contact_name
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.fixed_size = true
			label.pixel_size = 0.0022
			label.font_size = 40
			label.outline_size = 12
			label.outline_modulate = Color(0.05, 0.05, 0.05, 0.9)
			add_child(label)
			letters[contact_name] = label
		label.text = str(offer["letter"])
		label.modulate = offer["color"]
		var p: Vector3 = offer["position"]
		label.global_position = p + Vector3(0, 2.5 + 0.15 * sin(clock * 2.5), 0)
		label.visible = player.global_position.distance_to(p) < LETTER_RANGE
	for contact_name in letters:
		if not active.has(contact_name):
			(letters[contact_name] as Label3D).visible = false
