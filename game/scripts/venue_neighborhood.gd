extends RefCounted

const AudioUtil = preload("res://scripts/audio_util.gd")

## Reusable textured furnishings; physical circulation remains free of counters.
static func build(v: VenueInterior, o: Vector3, wood: Material, metal: Material, accent: Material, mats: SectorMaterials) -> void:
	v._box("ServiceCounter", Vector3(4.5, 1.0, 0.8), o + Vector3(4, 0.5, -5.5), wood, true)
	match v.kind:
		"bakery", "pharmacy", "record_shop":
			for x in [-4.8, -1.8]:
				v._box("DisplayCabinet", Vector3(2.4, 0.7, 3.2), o + Vector3(x, 0.35, -1), wood, true)
				for z in range(5):
					for row in range(2):
						var size := Vector3(0.5, 0.18, 0.3) if v.kind == "bakery" else Vector3(0.12, 0.44, 0.44) if v.kind == "record_shop" else Vector3(0.3, 0.4, 0.2)
						v._box("Stock", size, o + Vector3(x - 0.5 + row, 0.94, -2.2 + z * 0.55), accent)
			v._wall_label("Department", {"bakery": "PAN DEL DÍA · MASA MADRE", "pharmacy": "PRIMEROS AUXILIOS", "record_shop": "SESIONES LOCALES · MÚSICA ORIGINAL"}[v.kind], o + Vector3(0, 3.5, -8.6), Color("f8eedb"))
		"barber":
			for x in [-4.4, -1.2, 2.0]:
				v._box("SalonChair", Vector3(1.2, 0.65, 1.1), o + Vector3(x, 0.6, 0), accent, true)
				v._box("ChairBack", Vector3(1.2, 1.0, 0.2), o + Vector3(x, 1.15, 0.5), wood, true)
				v._box("MirrorFrame", Vector3(2.2, 2.4, 0.15), o + Vector3(x, 2.1, -3.4), metal, true)
				v._box("Mirror", Vector3(1.9, 2.1, 0.08), o + Vector3(x, 2.1, -3.3), mats.textured("salon_mirror", "tiles040", Color("99b4bd"), 2.0, 0.12))
		"gym":
			for x in [-4.5, -1.2, 2.1]:
				v._box("TrainingBench", Vector3(1.2, 0.55, 3), o + Vector3(x, 0.35, 0), accent, true)
				v._box("BenchFrame", Vector3(1.4, 1.6, 0.15), o + Vector3(x, 0.8, -1.7), metal, true)
				v._box("WeightBar", Vector3(2.2, 0.12, 0.12), o + Vector3(x, 1.35, -1.7), metal)
				for side in [-1, 1]:
					v._box("Weights", Vector3(0.2, 0.5, 0.5), o + Vector3(x + side, 1.35, -1.7), wood)
			v._wall_label("TrainingBoard", "FUERZA · MOVILIDAD · DESCANSO", o + Vector3(0, 3.5, -8.6), Color("f8eedb"))
		"clothing":
			for x in [-4.6, -1.5]:
				v._box("ClothesRack", Vector3(2.2, 1.8, 0.5), o + Vector3(x, 0.9, -1.2), wood, true)
				for item in range(6):
					v._box("FoldedClothes", Vector3(0.29, 0.12, 0.4), o + Vector3(x - 0.85 + item * 0.34, 1.86, -1.2), accent)
			v._wall_label("FittingRoom", "PROBADORES →", o + Vector3(-4.8, 2.6, -8.6), Color("f8eedb"))
	if v.kind == "record_shop":
		var audio := AudioStreamPlayer3D.new()
		audio.name = "ListeningStation"
		audio.stream = AudioUtil.stream("res://assets/audio/coastal_session.wav")
		audio.max_distance = 14.0
		audio.volume_db = -13.0
		audio.position = o + Vector3(4, 1.2, -5.5)
		v.room.add_child(audio)

static func residential(v: VenueInterior, o: Vector3, floor_mat: Material, wall: Material, wood: Material, metal: Material, mats: SectorMaterials) -> void:
	# The same broad, walkable stair structure as the casino, with apartment doors
	# instead of its archive/office. Upper furniture is rebuilt for domestic use.
	preload("res://scripts/venue_upper_floor.gd").build(v, o, floor_mat, wall, wood, metal, mats)
	v.mission_points.clear()
	for item in v.room.get_children():
		var label := str(item.get_meta("detail_kind", item.name))
		if label.begins_with("Office") or label.begins_with("Archive") or label in ["Ledger", "LedgerLabel", "SecretEnvelope"]:
			item.free()
	v._box("HallBench", Vector3(3.2, 0.55, 0.7), o + Vector3(-4, 0.28, 4), wood, true)
	for i in range(6):
		v._box("Mailbox", Vector3(0.65, 0.5, 0.12), o + Vector3(-6.7, 1.1 + (i / 3) * 0.6, -1.5 + (i % 3) * 0.8), metal)
	v._wall_label("HallSign", "VESTÍBULO · APARTAMENTOS ↑", o + Vector3(-1.0, 2.7, -8.6), Color("f7e5c4"))
	# Two accessible flats across a common corridor; wide physical doorways.
	for z in [-1.5, 4.0]:
		v._box("ApartmentPartition", Vector3(5.0, 3.6, 0.18), o + Vector3(-4.2, 6.3, z), wall, true)
		v._box("ApartmentJamb", Vector3(0.35, 3.6, 0.18), o + Vector3(2.5, 6.3, z), wall, true)
		v._box("ApartmentLintel", Vector3(4.0, 0.65, 0.18), o + Vector3(0.2, 7.77, z), wood, true)
	for i in range(2):
		var z := -6.1 if i == 0 else 6.4
		var kitchen_z := z - 1.1 if i == 0 else 8.0
		v._box("BedFrame", Vector3(2.2, 0.5, 2.8), o + Vector3(-4.1, 4.75, z), wood, true)
		v._box("Mattress", Vector3(2.0, 0.2, 2.6), o + Vector3(-4.1, 5.1, z), mats.textured("apartment_linen", "plaster003", Color("c4cbbf"), 0.6))
		v._box("Pillow", Vector3(1.5, 0.16, 0.55), o + Vector3(-4.1, 5.26, z - 0.9), floor_mat)
		v._box("KitchenCabinet", Vector3(2.3, 0.95, 0.6), o + Vector3(0.2, 4.97, kitchen_z), wood, true)
		v._box("KitchenWorktop", Vector3(2.4, 0.1, 0.65), o + Vector3(0.2, 5.49, kitchen_z), floor_mat)
		v._box("Wardrobe", Vector3(1.1, 2.5, 0.55), o + Vector3(-6.3, 5.75, z + 1.0), wood, true)
		v._wall_label("ApartmentNumber", "01 · ESTUDIO" if i == 0 else "02 · ESTUDIO", o + Vector3(0.2, 7.5, -1.35 if i == 0 else 4.15), Color("f7e5c4"))
	v.mission_points["bed"] = Vector3(-2.3, 4.7, -6.0)
	v.mission_points["bed_two"] = Vector3(-2.3, 4.7, 6.4)
