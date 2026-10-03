extends Node3D

## Unique stunt jumps on the beaches: wooden ramps with a clear run-up and sand
## to land on. Hit one fast enough, fly at least 14 m and land: the game slows
## time while you are in the air and pays 250 € the first time each is done.

signal jump_done(index: int, distance: float, first_time: bool)

const CANDIDATE_X := [30.0, 110.0, 190.0, 270.0, 470.0, 560.0, -40.0]
const MAX_JUMPS := 5
const RAMP_LENGTH := 5.5
const RAMP_HEIGHT := 1.7
const MIN_SPEED := 12.0
const MIN_DISTANCE := 14.0
const REWARD := 250

var player: PlayerController
var main: Node
var data: SectorData
var ramps: Array = []  # {top: Vector3, dir: Vector3, node: Node3D}
var done := {}  # index -> best distance
var _armed := -1
var _takeoff := Vector3.ZERO
var _air := 0.0
var _placed := false
var _slowmo := false


func configure(target_player: PlayerController, target_main: Node, sector: SectorData) -> void:
	player = target_player
	main = target_main
	data = sector


func _physics_process(delta: float) -> void:
	if player == null:
		return
	if not _placed:
		_placed = true  # one physics step in: colliders are registered for the clearance checks
		_place_ramps()
		return
	var car := player.driving_vehicle
	if car == null or car.destroyed:
		_end_slowmo()
		_armed = -1
		return
	if _armed < 0:
		for i in range(ramps.size()):
			var ramp: Dictionary = ramps[i]
			var top: Vector3 = ramp["top"]
			var forward := -car.global_transform.basis.z * signf(car.speed)
			if car.global_position.distance_to(top) < 3.2 and absf(car.speed) > MIN_SPEED and forward.dot(ramp["dir"]) > 0.7:
				_armed = i
				_takeoff = car.global_position
				_air = 0.0
				break
		return
	if not car.is_on_floor():
		_air += delta
		if _air > 0.15:
			Engine.time_scale = 0.45
			_slowmo = true
	elif _air > 0.15 or car.global_position.distance_to(_takeoff) > 60.0:
		var flown := Vector2(car.global_position.x - _takeoff.x, car.global_position.z - _takeoff.z).length()
		_finish(_armed, flown)
		_armed = -1
	elif car.global_position.distance_to(_takeoff) > 12.0:
		_armed = -1  # rolled off without flying
	if _air > 3.0:
		_end_slowmo()


func _finish(index: int, flown: float) -> void:
	_end_slowmo()
	if flown < MIN_DISTANCE or _air < 0.4:
		return
	var first := not done.has(index)
	done[index] = maxf(float(done.get(index, 0.0)), flown)
	if first and main != null and main.has_method("add_money"):
		main.add_money(REWARD)
	if main != null and "hud" in main and main.hud != null:
		main.hud.show_banner(("SALTO ÚNICO %d/%d  +%d €" % [done.size(), ramps.size(), REWARD]) if first else ("SALTO  %.0f m" % flown), Color("f2c14e"))
	jump_done.emit(index, flown, first)


func _end_slowmo() -> void:
	if _slowmo:  # only undo our own slow motion (the weapon wheel uses it too)
		_slowmo = false
		Engine.time_scale = 1.0


func _place_ramps() -> void:
	var space := get_world_3d().direct_space_state
	for x: float in CANDIDATE_X:
		if ramps.size() >= MAX_JUMPS:
			break
		var a := _beach_centre(x - 25.0)
		var b := _beach_centre(x + 25.0)
		var c := _beach_centre(x)
		if a == Vector3.INF or b == Vector3.INF or c == Vector3.INF:
			continue
		var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var side := Vector3(-dir.z, 0, dir.x)
		for shift: float in [0.0, 5.0, -5.0, 9.0]:
			var centre := c + side * shift
			if _corridor_clear(space, centre, dir):
				ramps.append(_build_ramp(centre, dir))
				break


func _beach_centre(x: float) -> Vector3:
	var first := INF
	var last := -INF
	var z := data.z0
	while z < data.z0 + data.rows * data.cell:
		if data.surface_at(x, z) == "beach":
			first = minf(first, z)
			last = maxf(last, z)
		z += data.cell
	if first == INF or last - first < 16.0:
		return Vector3.INF
	var mid := (first + last) * 0.5
	return Vector3(x, data.height_at(x, mid), mid)


## 40 m of run-up and 45 m of landing with nothing solid in the way.
func _corridor_clear(space: PhysicsDirectSpaceState3D, centre: Vector3, dir: Vector3) -> bool:
	for along in range(-40, 46, 5):
		var p := centre + dir * float(along)
		if data.surface_at(p.x, p.z) == "sea":
			return false
		var q := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4.5, 2.0, 4.5)
		q.shape = box
		q.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, data.height_at(p.x, p.z) + 1.4, p.z))
		for hit in space.intersect_shape(q, 4):
			var body := hit["collider"] as Node
			if body is DriveableVehicle or body is Pedestrian or body.is_in_group("terrain"):
				continue
			return false
	return true


func _build_ramp(centre: Vector3, dir: Vector3) -> Dictionary:
	var node := Node3D.new()
	node.name = "StuntRamp_%d" % ramps.size()
	add_child(node)
	var start := centre - dir * RAMP_LENGTH * 0.5
	var top := centre + dir * RAMP_LENGTH * 0.5
	start.y = data.height_at(start.x, start.z) - 0.05
	top.y = data.height_at(top.x, top.z) + RAMP_HEIGHT
	var run := top - start
	var direction := run.normalized()
	var side := direction.cross(Vector3.UP).normalized()
	var up := side.cross(direction)
	var basis := Basis(side, up, -direction)
	var body := StaticBody3D.new()
	body.name = "RampCollision"
	node.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.6, 0.3, run.length())
	shape.shape = box
	shape.transform = Transform3D(basis, (start + top) * 0.5 - up * 0.15)
	body.add_child(shape)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("9a6b3e")
	wood.roughness = 0.85
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color("f2c14e")
	var deck := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(3.6, 0.3, run.length())
	deck.mesh = deck_mesh
	deck.material_override = wood
	deck.transform = shape.transform
	node.add_child(deck)
	for i in range(4):
		var band := MeshInstance3D.new()
		var band_mesh := BoxMesh.new()
		band_mesh.size = Vector3(3.62, 0.31, 0.35)
		band.mesh = band_mesh
		band.material_override = stripe
		var along := run.length() * (0.15 + i * 0.22)
		band.transform = Transform3D(basis, start + direction * along - up * 0.149)
		node.add_child(band)
	# Supports under the high end.
	for s: float in [-1.5, 1.5]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.2, RAMP_HEIGHT, 0.2)
		post.mesh = post_mesh
		post.material_override = wood
		post.position = top - dir * 0.3 + side * s - Vector3(0, RAMP_HEIGHT * 0.5 + 0.1, 0)
		node.add_child(post)
	var label := Label3D.new()
	label.text = "SALTO ÚNICO"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.outline_size = 10
	label.pixel_size = 0.008
	label.modulate = Color("f2c14e")
	label.position = top + Vector3(0, 1.6, 0)
	label.visibility_range_end = 60.0
	node.add_child(label)
	return {"top": top, "dir": dir, "node": node}


func to_save() -> Dictionary:
	var out := {}
	for k in done:
		out[str(k)] = done[k]
	return out


func from_save(value: Dictionary) -> void:
	done.clear()
	for k in value:
		done[int(k)] = float(value[k])
