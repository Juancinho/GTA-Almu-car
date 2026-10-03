extends Node3D

## Hidden packages, Almuñécar style: 30 Phoenician amphorae (the town was the
## Phoenician colony of Sexi) hidden along stairways, alleys, beaches, the castle
## and the Peñón. Each pays 100 €; every ten unlock a reward. Positions are
## deterministic from the street data, so saves stay valid.

signal collected(count: int, total: int)

const TOTAL := 30
const PICKUP_RADIUS := 1.7
const MIN_SPACING := 55.0

var player: PlayerController
var main: Node
var spots: Array[Vector3] = []
var found := {}  # index -> true
var pieces: Array[Node3D] = []
var _timer := 0.0
var _spin := 0.0


func configure(target_player: PlayerController, target_main: Node, world: SectorWorld) -> void:
	player = target_player
	main = target_main
	_choose_spots(world)
	var clay := StandardMaterial3D.new()
	clay.albedo_color = Color("b9643a")
	clay.roughness = 0.85
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.85, 0.45, 0.35)
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	for i in range(spots.size()):
		var piece := _amphora(clay, glow)
		piece.name = "Amphora_%02d" % i
		add_child(piece)
		piece.global_position = spots[i]
		pieces.append(piece)


func _choose_spots(world: SectorWorld) -> void:
	var data := world.data
	var candidates: Array[Vector3] = []
	# Pedestrian ways first (stairs, alleys, promenades), then a few landmarks.
	for road in world.road_network.roads:
		if road["driveable"]:
			continue
		var points: PackedVector3Array = road["points"]
		if points.size() < 2:
			continue
		var p := points[points.size() / 2]
		candidates.append(Vector3(p.x, data.height_at(p.x, p.z) + 0.12, p.z))
	for name in ["castle_drop", "jaime_playa", "old_town_target"]:
		var a := world.anchor(name)
		candidates.append(a + Vector3(2.0, 0.12, 1.5))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1712
	var order := range(candidates.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: int = order[i]
		order[i] = order[j]
		order[j] = t
	for index in order:
		var p: Vector3 = candidates[index]
		if data.surface_at(p.x, p.z) == "sea":
			continue
		var spaced := true
		for q in spots:
			spaced = spaced and q.distance_to(p) > MIN_SPACING
		if spaced:
			spots.append(p)
		if spots.size() >= TOTAL:
			break


func _amphora(clay: Material, glow: Material) -> Node3D:
	var root := Node3D.new()
	var shapes := [[0.10, 0.06, 0.18, 0.09], [0.18, 0.10, 0.22, 0.29], [0.20, 0.18, 0.14, 0.47], [0.07, 0.10, 0.22, 0.65]]
	for spec in shapes:
		var part := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = spec[0]
		mesh.bottom_radius = spec[1]
		mesh.height = spec[2]
		mesh.radial_segments = 10
		mesh.rings = 1
		part.mesh = mesh
		part.material_override = clay
		part.position.y = spec[3]
		part.visibility_range_end = 120.0
		root.add_child(part)
	for side: float in [-1.0, 1.0]:
		var handle := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.05
		torus.outer_radius = 0.09
		torus.rings = 8
		torus.ring_segments = 6
		handle.mesh = torus
		handle.material_override = clay
		handle.position = Vector3(side * 0.13, 0.66, 0)
		handle.rotation.z = PI * 0.5
		handle.visibility_range_end = 120.0
		root.add_child(handle)
	var halo := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.55
	sphere.height = 1.1
	sphere.radial_segments = 12
	sphere.rings = 6
	halo.mesh = sphere
	halo.material_override = glow
	halo.position.y = 0.4
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.visibility_range_end = 60.0
	root.add_child(halo)
	return root


func _process(delta: float) -> void:
	if player == null:
		return
	_spin += delta
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.1
	var here := player.global_position
	for i in range(pieces.size()):
		if found.has(i):
			continue
		var piece := pieces[i]
		var gap := piece.global_position.distance_to(here)
		if gap < 60.0:
			piece.rotation.y = _spin * 1.4
		if gap < PICKUP_RADIUS and player.driving_vehicle == null:
			collect(i)


func collect(index: int) -> void:
	if found.has(index) or index < 0 or index >= pieces.size():
		return
	found[index] = true
	pieces[index].visible = false
	var count := found.size()
	if main != null and main.has_method("add_money"):
		main.add_money(100)
	var reward := ""
	var weapons: Node = main.get("weapons") if main != null else null
	match count:
		10:
			reward = "  ·  RECOMPENSA: subfusil y 150 balas"
			if weapons != null:
				weapons.call("give", "smg", 150)
		20:
			reward = "  ·  RECOMPENSA: fusil y 90 balas"
			if weapons != null:
				weapons.call("give", "rifle", 90)
		TOTAL:
			reward = "  ·  ¡TODAS! 10.000 € del museo arqueológico"
			if main != null and main.has_method("add_money"):
				main.add_money(10000)
	if main != null and "hud" in main and main.hud != null:
		main.hud.show_banner("ÁNFORA FENICIA %d/%d  +100 €%s" % [count, TOTAL, reward], Color("e3a65a"))
	collected.emit(count, TOTAL)


func to_save() -> Array:
	return found.keys()


func from_save(list: Array) -> void:
	for i in range(pieces.size()):
		pieces[i].visible = true
	found.clear()
	for value in list:
		var index := int(value)
		if index >= 0 and index < pieces.size():
			found[index] = true
			pieces[index].visible = false
