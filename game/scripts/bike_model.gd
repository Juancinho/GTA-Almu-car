extends RefCounted

## Procedural motorbikes ("moto": naked roadster) and scooters ("scooter": Vespa-style
## step-through with a front apron), built from primitive meshes because the project
## has no licensed bike models. Gameplay forward is -Z and the tyres touch y = 0.
##
## Each kind is merged once into a shared body mesh (seven surfaces, one per
## material, like the cars) plus a shared two-surface wheel; build() only creates:
##   CarVisual > Lean > Body, FrontWheel, RearWheel
## The vehicle rolls "Lean" into turns and spins the wheels about their X axle.
## Surfaces named "Paint" take the bike's colour; "Headlights"/"TailLights" glow at
## night through DriveableVehicle.set_headlights().

static var bodies := {}  # kind -> ArrayMesh
static var wheels := {}  # kind -> ArrayMesh
static var materials := {}  # name -> StandardMaterial3D

## Geometry per kind: wheel radius, axle positions, the grips and the rider's hip
## joint, forward pitch, thigh drop, shin swing (feet forward) and knee spread.
const KINDS := {
	"moto": {"radius": 0.31, "front_z": -0.72, "rear_z": 0.7, "grip": Vector3(0.3, 1.1, -0.43), "hip": Vector3(0.0, 0.98, 0.2), "pitch": -0.38, "thigh_drop": 0.0, "shin_swing": 0.0, "spread": 0.42},
	"scooter": {"radius": 0.22, "front_z": -0.6, "rear_z": 0.58, "grip": Vector3(0.3, 1.12, -0.4), "hip": Vector3(0.0, 0.93, 0.13), "pitch": -0.3, "thigh_drop": 0.0, "shin_swing": 0.32, "spread": 0.16},
}


static func geometry(kind: String) -> Dictionary:
	return KINDS.get(kind, KINDS["moto"])


static func build(kind: String) -> Node3D:
	var info := geometry(kind)
	var root := Node3D.new()
	var lean := Node3D.new()
	lean.name = "Lean"
	root.add_child(lean)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = body_mesh(kind)
	lean.add_child(body)
	for wheel_name in ["FrontWheel", "RearWheel"]:
		var wheel := MeshInstance3D.new()
		wheel.name = wheel_name
		wheel.mesh = wheel_mesh(kind)
		wheel.position = Vector3(0.0, float(info["radius"]), float(info["front_z"] if wheel_name == "FrontWheel" else info["rear_z"]))
		lean.add_child(wheel)
	return root


static func material(key: String) -> StandardMaterial3D:
	if materials.has(key):
		return materials[key]
	var spec: Array = {
		"Paint": [Color("c3614c"), 0.3, 0.25],
		"Frame": [Color("1d1e21"), 0.55, 0.3],
		"Chrome": [Color("c4c8cd"), 0.22, 0.85],
		"Engine": [Color("4a4b4f"), 0.45, 0.6],
		"Seat": [Color("191513"), 0.85, 0.0],
		"Rubber": [Color("161616"), 0.95, 0.0],
		"Headlights": [Color("e9e6d6"), 0.12, 0.2],
		"TailLights": [Color("8a1712"), 0.2, 0.0],
	}.get(key, [Color.WHITE, 0.7, 0.0])
	var mat := StandardMaterial3D.new()
	mat.resource_name = key
	mat.albedo_color = spec[0]
	mat.roughness = spec[1]
	mat.metallic = spec[2]
	materials[key] = mat
	return mat


## Part list: material name -> SurfaceTool, committed in a fixed order.
class Parts:
	var tools := {}
	var order: Array[String] = []

	func add(mat: String, mesh: Mesh, xf: Transform3D) -> void:
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
			order.append(mat)
		(tools[mat] as SurfaceTool).append_from(mesh, 0, xf)

	func box(mat: String, size: Vector3, at: Vector3, pitch := 0.0, roll := 0.0) -> void:
		var mesh := BoxMesh.new()
		mesh.size = size
		add(mat, mesh, Transform3D(Basis.from_euler(Vector3(pitch, 0.0, roll)), at))

	## Ellipsoid with the given full extents.
	func blob(mat: String, size: Vector3, at: Vector3, pitch := 0.0) -> void:
		var mesh := SphereMesh.new()
		mesh.radius = 0.5
		mesh.height = 1.0
		mesh.radial_segments = 14
		mesh.rings = 8
		add(mat, mesh, Transform3D(Basis.from_euler(Vector3(pitch, 0.0, 0.0)).scaled_local(size), at))

	## Cylinder from a to b.
	func tube(mat: String, a: Vector3, b: Vector3, radius: float, sides := 8) -> void:
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = a.distance_to(b)
		mesh.radial_segments = sides
		mesh.rings = 1
		var axis := (b - a).normalized()
		add(mat, mesh, Transform3D(Basis(Quaternion(Vector3.UP, axis)), (a + b) * 0.5))

	## Flat disc facing along `axis`.
	func disc(mat: String, at: Vector3, radius: float, depth: float, axis: Vector3, sides := 16) -> void:
		tube(mat, at - axis * depth * 0.5, at + axis * depth * 0.5, radius, sides)

	## Both sides at once (x mirrored).
	func tube_pair(mat: String, a: Vector3, b: Vector3, radius: float) -> void:
		tube(mat, a, b, radius)
		tube(mat, Vector3(-a.x, a.y, a.z), Vector3(-b.x, b.y, b.z), radius)

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for mat in order:
			(tools[mat] as SurfaceTool).commit(mesh)
		return mesh


## One merged mesh, its surfaces carrying the shared bike materials.
static func _finish(p: Parts) -> ArrayMesh:
	var mesh := p.commit()
	for i in range(p.order.size()):
		mesh.surface_set_material(i, material(p.order[i]))
	return mesh


static func wheel_mesh(kind: String) -> ArrayMesh:
	if wheels.has(kind):
		return wheels[kind]
	var r := float(geometry(kind)["radius"])
	var p := Parts.new()
	var axle := Basis(Vector3.BACK, PI * 0.5)  # torus/cylinder Y axis -> X axle
	var tyre := TorusMesh.new()
	var thickness := 0.11 if kind == "moto" else 0.09
	tyre.inner_radius = r - thickness
	tyre.outer_radius = r
	tyre.rings = 20
	tyre.ring_segments = 8
	p.add("Rubber", tyre, Transform3D(axle.scaled_local(Vector3(1.0, 1.25, 1.0)), Vector3.ZERO))
	if kind == "moto":
		var rim := TorusMesh.new()
		rim.inner_radius = r - thickness - 0.025
		rim.outer_radius = r - thickness + 0.012
		rim.rings = 20
		rim.ring_segments = 6
		p.add("Engine", rim, Transform3D(axle, Vector3.ZERO))
		for k in range(5):  # five cast spokes: the spin reads at a glance
			var angle := TAU * k / 5.0
			var tip := Vector3(0.0, cos(angle), sin(angle)) * (r - thickness - 0.01)
			p.tube("Engine", Vector3.ZERO, tip, 0.016, 6)
		p.disc("Engine", Vector3(0.05, 0.0, 0.0), r * 0.55, 0.008, Vector3.RIGHT, 18)  # brake disc
		p.disc("Engine", Vector3.ZERO, 0.045, 0.12, Vector3.RIGHT, 10)
	else:
		p.disc("Chrome", Vector3.ZERO, r - thickness + 0.012, 0.07, Vector3.RIGHT, 18)
		p.disc("Rubber", Vector3.ZERO, 0.05, 0.1, Vector3.RIGHT, 10)
		for k in range(4):  # rim bolts: show the wheel turning
			var angle := TAU * k / 4.0
			p.disc("Rubber", Vector3(0.0, cos(angle), sin(angle)) * 0.07, 0.014, 0.085, Vector3.RIGHT, 6)
	wheels[kind] = _finish(p)
	return wheels[kind]


static func body_mesh(kind: String) -> ArrayMesh:
	if bodies.has(kind):
		return bodies[kind]
	var p := Parts.new()
	if kind == "scooter":
		_scooter(p)
	else:
		_moto(p)
	bodies[kind] = _finish(p)
	return bodies[kind]


## Naked roadster: teardrop tank, exposed engine and tubular frame, round headlamp.
static func _moto(p: Parts) -> void:
	var front := Vector3(0.0, 0.31, -0.72)
	var rear := Vector3(0.0, 0.31, 0.7)
	# Fork, triple clamp and bars.
	p.tube_pair("Chrome", Vector3(0.085, 1.0, -0.5), Vector3(0.085, 0.62, -0.63), 0.026)
	p.tube_pair("Frame", Vector3(0.085, 0.66, -0.62), front + Vector3(0.085, 0.0, 0.0), 0.034)
	p.box("Frame", Vector3(0.26, 0.05, 0.1), Vector3(0.0, 1.0, -0.5))
	p.tube_pair("Frame", Vector3(0.07, 1.02, -0.49), Vector3(0.09, 1.1, -0.45), 0.016)
	p.tube("Chrome", Vector3(-0.27, 1.1, -0.43), Vector3(0.27, 1.1, -0.43), 0.014)
	p.tube("Seat", Vector3(-0.36, 1.1, -0.43), Vector3(-0.25, 1.1, -0.43), 0.024)
	p.tube("Seat", Vector3(0.25, 1.1, -0.43), Vector3(0.36, 1.1, -0.43), 0.024)
	p.box("Frame", Vector3(0.15, 0.07, 0.09), Vector3(0.0, 1.09, -0.52), 0.5)  # clocks
	# Mirrors.
	p.tube_pair("Chrome", Vector3(0.24, 1.1, -0.43), Vector3(0.3, 1.27, -0.45), 0.009)
	for side: float in [-1.0, 1.0]:
		p.blob("Frame", Vector3(0.11, 0.065, 0.025), Vector3(0.31 * side, 1.29, -0.455))
	# Round headlamp.
	p.blob("Frame", Vector3(0.21, 0.21, 0.17), Vector3(0.0, 0.93, -0.62))
	p.disc("Headlights", Vector3(0.0, 0.93, -0.7), 0.088, 0.02, Vector3.BACK, 18)
	p.disc("Chrome", Vector3(0.0, 0.93, -0.692), 0.098, 0.012, Vector3.BACK, 18)
	# Front mudguard hugging the tyre.
	p.box("Paint", Vector3(0.12, 0.025, 0.24), Vector3(0.0, 0.66, -0.66), -0.42)
	p.box("Paint", Vector3(0.12, 0.025, 0.2), Vector3(0.0, 0.6, -0.9), 0.55)
	# Frame spars, down tubes and swingarm.
	p.tube_pair("Frame", Vector3(0.06, 0.98, -0.47), Vector3(0.13, 0.74, 0.2), 0.028)
	p.tube_pair("Frame", Vector3(0.05, 0.86, -0.53), Vector3(0.1, 0.3, -0.22), 0.026)
	p.tube_pair("Frame", Vector3(0.1, 0.3, -0.22), Vector3(0.12, 0.42, 0.2), 0.024)
	p.tube_pair("Frame", Vector3(0.12, 0.45, 0.18), rear + Vector3(0.1, 0.0, 0.0), 0.03)
	p.tube_pair("Chrome", rear + Vector3(0.12, 0.03, -0.06), Vector3(0.12, 0.8, 0.43), 0.022)
	# Engine: crankcase, finned cylinder, side cover.
	p.box("Engine", Vector3(0.3, 0.28, 0.42), Vector3(0.0, 0.47, -0.04))
	p.box("Engine", Vector3(0.26, 0.24, 0.2), Vector3(0.0, 0.7, -0.22), -0.35)
	for k in range(3):
		p.box("Frame", Vector3(0.29, 0.012, 0.23), Vector3(0.0, 0.64 + k * 0.05, -0.2 - k * 0.018), -0.35)
	p.disc("Chrome", Vector3(-0.16, 0.45, 0.02), 0.11, 0.03, Vector3.RIGHT, 16)
	p.disc("Chrome", Vector3(0.16, 0.48, -0.12), 0.08, 0.03, Vector3.RIGHT, 14)
	# Tank, seat, tail.
	p.blob("Paint", Vector3(0.34, 0.25, 0.58), Vector3(0.0, 0.96, -0.2), 0.08)
	p.disc("Chrome", Vector3(0.0, 1.08, -0.24), 0.04, 0.02, Vector3.UP, 12)
	p.box("Paint", Vector3(0.24, 0.16, 0.26), Vector3(0.0, 0.73, 0.24))
	var seat := CapsuleMesh.new()
	seat.radius = 0.14
	seat.height = 0.64
	seat.radial_segments = 12
	seat.rings = 4
	p.add("Seat", seat, Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.08).scaled_local(Vector3(1.0, 1.0, 0.42)), Vector3(0.0, 0.85, 0.26)))
	p.box("Paint", Vector3(0.18, 0.09, 0.28), Vector3(0.0, 0.88, 0.58), -0.14)
	p.box("TailLights", Vector3(0.12, 0.045, 0.03), Vector3(0.0, 0.9, 0.725), -0.14)
	p.box("Frame", Vector3(0.03, 0.03, 0.18), Vector3(0.0, 0.8, 0.82), 0.6)
	p.box("Chrome", Vector3(0.17, 0.12, 0.012), Vector3(0.0, 0.7, 0.88), -0.25)
	# Exhaust and pegs.
	p.tube("Chrome", Vector3(0.12, 0.62, -0.28), Vector3(0.17, 0.3, -0.1), 0.03)
	p.tube("Chrome", Vector3(0.17, 0.3, -0.1), Vector3(0.19, 0.38, 0.38), 0.032)
	p.tube("Chrome", Vector3(0.19, 0.38, 0.36), Vector3(0.2, 0.52, 0.8), 0.058, 12)
	p.tube("Frame", Vector3(-0.25, 0.4, 0.12), Vector3(0.25, 0.4, 0.12), 0.016)


## Vespa-style scooter: rounded rear cowls, step-through floor and a tall front apron.
static func _scooter(p: Parts) -> void:
	var front := Vector3(0.0, 0.22, -0.6)
	# Floor, apron and the tunnel to the engine cowls.
	p.box("Frame", Vector3(0.36, 0.05, 0.6), Vector3(0.0, 0.3, -0.08))
	p.box("Seat", Vector3(0.3, 0.012, 0.5), Vector3(0.0, 0.33, -0.08))
	p.box("Paint", Vector3(0.44, 0.66, 0.05), Vector3(0.0, 0.62, -0.42), 0.2)
	p.box("Paint", Vector3(0.05, 0.62, 0.12), Vector3(0.22, 0.6, -0.38), 0.2)
	p.box("Paint", Vector3(0.05, 0.62, 0.12), Vector3(-0.22, 0.6, -0.38), 0.2)
	p.box("Chrome", Vector3(0.09, 0.16, 0.035), Vector3(0.0, 0.78, -0.475), 0.2)  # horn grille
	p.box("Paint", Vector3(0.2, 0.22, 0.34), Vector3(0.0, 0.42, 0.12))
	# Rear cowls (bulbous sides) and seat.
	p.blob("Paint", Vector3(0.5, 0.42, 0.66), Vector3(0.0, 0.52, 0.4))
	p.blob("Paint", Vector3(0.36, 0.2, 0.5), Vector3(0.0, 0.64, 0.34))
	var seat := CapsuleMesh.new()
	seat.radius = 0.15
	seat.height = 0.66
	seat.radial_segments = 12
	seat.rings = 4
	p.add("Seat", seat, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled_local(Vector3(1.0, 1.0, 0.5)), Vector3(0.0, 0.79, 0.29)))
	p.tube("Chrome", Vector3(-0.12, 0.8, 0.66), Vector3(0.12, 0.8, 0.66), 0.012)  # grab rail
	p.box("TailLights", Vector3(0.14, 0.06, 0.04), Vector3(0.0, 0.68, 0.73), -0.3)
	p.box("Chrome", Vector3(0.16, 0.11, 0.012), Vector3(0.0, 0.52, 0.76), -0.2)
	# Front mudguard over the small wheel, single-sided fork and steering column.
	p.blob("Paint", Vector3(0.17, 0.12, 0.44), Vector3(0.0, 0.47, -0.61), -0.12)
	p.tube("Frame", Vector3(0.08, 0.36, -0.58), front + Vector3(0.08, 0.0, 0.0), 0.03)
	p.tube("Frame", Vector3(0.0, 0.42, -0.58), Vector3(0.0, 0.6, -0.53), 0.035)  # the rest hides behind the apron
	p.tube("Frame", Vector3(0.0, 0.92, -0.38), Vector3(0.0, 1.08, -0.41), 0.035)
	p.tube("Paint", Vector3(-0.22, 0.94, -0.355), Vector3(0.22, 0.94, -0.355), 0.03)  # rounded apron edge
	# Headset with the lamp, bars and mirrors.
	p.blob("Paint", Vector3(0.22, 0.13, 0.24), Vector3(0.0, 1.1, -0.42))
	p.disc("Headlights", Vector3(0.0, 1.1, -0.535), 0.06, 0.02, Vector3.BACK, 16)
	p.disc("Chrome", Vector3(0.0, 1.1, -0.528), 0.07, 0.012, Vector3.BACK, 16)
	p.tube("Paint", Vector3(-0.26, 1.12, -0.4), Vector3(0.26, 1.12, -0.4), 0.026)
	p.tube("Seat", Vector3(-0.35, 1.12, -0.4), Vector3(-0.25, 1.12, -0.4), 0.024)
	p.tube("Seat", Vector3(0.25, 1.12, -0.4), Vector3(0.35, 1.12, -0.4), 0.024)
	p.tube_pair("Chrome", Vector3(0.2, 1.13, -0.4), Vector3(0.27, 1.3, -0.42), 0.009)
	for side: float in [-1.0, 1.0]:
		p.blob("Chrome", Vector3(0.1, 0.07, 0.025), Vector3(0.28 * side, 1.32, -0.425))
	# Exhaust under the right cowl.
	p.tube("Chrome", Vector3(0.12, 0.26, 0.3), Vector3(0.17, 0.3, 0.66), 0.04, 10)
