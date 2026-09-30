extends RefCounted

## The surveyed casino has a public lobby, a real staircase and an office floor.
## Stairs render individual treads but use one smooth convex ramp for traversal.
static func build(venue: VenueInterior, origin: Vector3, floor_mat: Material, wall: Material, wood: Material, metal: Material, mats: SectorMaterials) -> void:
	venue.mission_points = {"landing": Vector3(5.1, 4.7, -2.8), "ledger": Vector3(-3.6, 4.7, -5.3), "stash": Vector3(-5.6, 4.7, 7.1)}
	venue._box("UpperFloor", Vector3(10.8, 0.25, 18), origin + Vector3(-1.6, 4.375, 0), floor_mat, true)
	venue._box("UpperLanding", Vector3(3.2, 0.25, 7), origin + Vector3(5.4, 4.375, -5.5), floor_mat, true)
	venue._box("UpperFrontLanding", Vector3(3.2, 0.25, 1), origin + Vector3(5.4, 4.375, 8.5), floor_mat, true)
	venue._box("Ceiling", Vector3(14, 0.25, 18), origin + Vector3(0, 8.95, 0), wall, true)
	for x in [-7.0, 7.0]:
		venue._box("UpperWall", Vector3(0.35, 4.5, 18), origin + Vector3(x, 6.75, 0), wall, true)
	for z in [-9.0, 9.0]:
		venue._box("UpperWall", Vector3(14, 4.5, 0.35), origin + Vector3(0, 6.75, z), wall, true)
	# Office doorway at x=0, spacious enough for the character capsule.
	venue._box("OfficePartition", Vector3(5.4, 3.8, 0.2), origin + Vector3(-4.1, 6.4, -3.8), wall, true)
	venue._box("OfficePartition", Vector3(2.5, 3.8, 0.2), origin + Vector3(2.5, 6.4, -3.8), wall, true)
	venue._box("OfficeLintel", Vector3(2.6, 0.65, 0.2), origin + Vector3(0, 7.98, -3.8), wood, true)
	venue._box("OfficeDesk", Vector3(2.6, 0.8, 1.0), origin + Vector3(-3.6, 4.9, -6.5), wood, true)
	venue._box("Ledger", Vector3(0.42, 0.07, 0.32), origin + Vector3(-3.6, 5.35, -6.3), mats.textured("ledger_cover", "plaster003", Color("36544d"), 0.15))
	for i in range(3):
		venue._box("Archive", Vector3(1.1, 2.1, 0.55), origin + Vector3(-5.6 + i * 1.3, 5.55, -8.4), metal, true)
	venue._box("LobbySofa", Vector3(3.2, 0.5, 0.85), origin + Vector3(-3.0, 4.75, 3.5), wood, true)
	venue._box("LobbySofaBack", Vector3(3.2, 0.7, 0.2), origin + Vector3(-3.0, 5.2, 3.8), wood)
	venue._box("LobbyTable", Vector3(1.6, 0.5, 0.8), origin + Vector3(-3.0, 4.75, 1.6), wood, true)
	# An unmarked archive behind the lounge, reached through a side doorway.
	venue._box("ArchivePartition", Vector3(5.6, 3.0, 0.2), origin + Vector3(-1.8, 6.0, 5.5), wall, true)
	venue._box("ArchiveDoorJamb", Vector3(0.6, 3.0, 0.2), origin + Vector3(-6.7, 6.0, 5.5), wood, true)
	venue._box("ArchiveShelf", Vector3(0.45, 1.0, 1.8), origin + Vector3(-6.5, 5.0, 7.2), wood, true)
	venue._box("SecretEnvelope", Vector3(0.25, 0.06, 0.35), origin + Vector3(-6.4, 5.55, 7.1), mats.textured("secret_envelope", "plaster003", Color("d7b779"), 0.18))
	venue._wall_label("OfficeSign", "01  ·  ADMINISTRACIÓN", origin + Vector3(0, 7.55, -3.65), Color("ffe2a0"))
	venue._wall_label("StairSign", "VESTÍBULO  →  ESCALERAS", origin + Vector3(3.6, 2.5, 7.8), Color("ffe2a0"))
	venue._wall_label("LedgerLabel", "LIBRO DE CUENTAS", origin + Vector3(-3.6, 5.9, -6.6), Color("ffe2a0"))
	(venue.room.get_node("LedgerLabel") as Label3D).pixel_size = 0.003
	# Eight metres of run for 4.5 metres of rise; bottom at z=7, top at z=-1.
	for i in range(25):
		var height := (i + 1) * 4.5 / 25.0
		venue._box("StairTread", Vector3(2.5, 0.10, 8.0 / 25.0), origin + Vector3(5.25, height - 0.12, 7.0 - (i + 0.5) * 8.0 / 25.0), floor_mat)
	var points := PackedVector3Array()
	for x in [4.0, 6.5]:
		for yz in [Vector2(-0.15, 7), Vector2(-0.15, -3), Vector2(4.5, -3), Vector2(4.5, -1)]:
			points.append(Vector3(x, yz.x, yz.y))
	var body := StaticBody3D.new()
	body.name = "StairRamp"
	body.position = origin
	var collider := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	collider.shape = shape
	body.add_child(collider)
	venue.room.add_child(body)
	venue._box("StairTopLanding", Vector3(2.5, 0.25, 1.1), origin + Vector3(5.25, 4.375, -1.5), floor_mat)
	# Solid balustrade along the upper opening; bottom/top remain open.
	venue._box("Balustrade", Vector3(0.14, 1.0, 10), origin + Vector3(3.8, 5.0, 3), wood, true)
	for i in range(9):
		venue._box("StairPost", Vector3(0.065, 0.9, 0.065), origin + Vector3(6.55, i * 4.5 / 8.0 + 0.45, 7.0 - i), metal)
	var rail := MeshInstance3D.new()
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.08, 0.08, Vector2(8, 4.5).length())
	rail.mesh = rail_mesh
	rail.material_override = metal
	rail.position = origin + Vector3(6.55, 3.15, 3)
	rail.rotation.x = atan2(4.5, 8)
	venue.room.add_child(rail)
	for at in [Vector3(0, 7.8, -5.5), Vector3(0, 7.8, 4)]:
		var light := OmniLight3D.new()
		light.position = origin + at
		light.omni_range = 10.0
		light.light_color = Color("ffe0b0")
		light.light_energy = 1.4
		venue.room.add_child(light)
