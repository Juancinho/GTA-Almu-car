extends Node3D

## Miradores: five real Almuñécar viewpoints, each with a coin-operated
## telescope and a wooden "MIRADOR · …" sign. Walking up to one on foot the
## first time (or pressing E next to it later) plays a short panorama: a
## temporary camera pans ~120° across the view for five seconds (E / Esc skip),
## with letterbox bars, while the player's controls are frozen. Each new mirador
## pays 200 €; all five pay a 2,000 € bonus. Saved as "miradores".

signal mirador_discovered(id: String, first_time: bool)

const REWARD := 200
const BONUS := 2000
const RADIUS := 2.5
const PAN_SECONDS := 5.0
const PAN_DEGREES := 120.0
const EYE_HEIGHT := 3.2
## Player standing point "at" [x, z] (walkable, checked by tests/miradores.gd)
## and the centre of the view "look" [x, y, z].
const SPOTS := [
	{"id": "castillo", "name": "Castillo de San Miguel", "at": [-190.0, 99.0], "look": [-160.0, 0.0, 400.0]},
	{"id": "penon", "name": "Peñón del Santo", "at": [-350.3, 350.3], "look": [-366.0, 18.0, 392.0]},
	{"id": "barrio_alto", "name": "Barrio Alto · Calle Trinidad", "at": [-64.2, -441.2], "look": [-40.0, 0.0, 300.0]},
	{"id": "altillo", "name": "Paseo del Altillo · Monumento Fenicio", "at": [26.0, 24.0], "look": [40.0, 0.0, 400.0]},
	{"id": "majuelo", "name": "Parque El Majuelo", "at": [-320.0, 0.0], "look": [-215.0, 36.0, 90.0]},
]

var player: PlayerController
var main: Node
var world: SectorWorld
var spots: Array = []  # {id, name, at: Vector3, look: Vector3, node: Node3D}
var found := {}  # id -> true
var cinematic := false
var camera: Camera3D
var active_index := -1
var _time := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _eye := Vector3.ZERO
var _frozen := {}  # node -> previous process_mode
var _previous_camera: Camera3D
var _bonus_banner := false
var banner_text := ""
var _grounded := false
var _bars: CanvasLayer
var _caption: Label
var _headline: Label  # "MIRADOR DESCUBIERTO" banner inside the letterbox
var _hud_was_visible := true


func configure(target_player: PlayerController, target_main: Node, target_world: SectorWorld) -> void:
	player = target_player
	main = target_main
	world = target_world
	for spec in SPOTS:
		var at: Array = spec["at"]
		var look: Array = spec["look"]
		var ground := Vector3(float(at[0]), world.height_at(float(at[0]), float(at[1])) + 0.1, float(at[1]))
		spots.append({"id": str(spec["id"]), "name": str(spec["name"]), "at": ground, "look": Vector3(float(look[0]), float(look[1]), float(look[2])), "node": null})
	_build_letterbox()


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	if not _grounded:
		_grounded = true  # one physics step in: road and terrain colliders are registered
		for spot in spots:
			spot["at"] = _ground(spot["at"])
			spot["node"] = _build_marker(spot)
		return
	if cinematic:
		return
	var index := nearby_index()
	if index >= 0 and not found.has(str(spots[index]["id"])) and _can_view():
		start_view(index)


## Index of the mirador the player stands at (on foot, within RADIUS), or -1.
func nearby_index() -> int:
	if player == null or player.driving_vehicle != null or player.dead or player.swimming:
		return -1
	for i in range(spots.size()):
		var at: Vector3 = spots[i]["at"]
		if Vector2(player.global_position.x - at.x, player.global_position.z - at.z).length() < RADIUS and absf(player.global_position.y - at.y) < 3.0:
			return i
	return -1


func _can_view() -> bool:
	var wanted: Node = main.get("wanted") if main != null else null
	if wanted != null and int(wanted.get("level")) > 0:
		return false
	var mission: Node = main.get("mission") if main != null else null
	if mission != null and bool(mission.call("mission_busy")):
		return false
	return true


func prompt_text() -> String:
	if cinematic:
		return "E / Esc · Saltar vista"
	var index := nearby_index()
	if index < 0:
		return ""
	return "E · Contemplar las vistas · Mirador %s" % str(spots[index]["name"])


func _unhandled_input(event: InputEvent) -> void:
	if cinematic or not event.is_action_pressed("interact"):
		return
	var index := nearby_index()
	if index < 0:
		return
	get_viewport().set_input_as_handled()
	if not _can_view():
		_say("Ahora no es momento de mirar el paisaje.")
		return
	start_view(index)


## While the panorama plays every key and click is swallowed; E or Escape skip it.
func _input(event: InputEvent) -> void:
	if not cinematic:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("pause"):
		finish_view()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()


func start_view(index: int) -> void:
	if cinematic or index < 0 or index >= spots.size():
		return
	var spot: Dictionary = spots[index]
	var id := str(spot["id"])
	var first := not found.has(id)
	active_index = index
	if first:
		found[id] = true
		if main != null and main.has_method("add_money"):
			main.add_money(REWARD)
			if found.size() == spots.size():
				main.add_money(BONUS)
				_bonus_banner = true
	# The banner lives in the letterbox (the HUD is hidden for a clean view).
	banner_text = ("MIRADOR DESCUBIERTO\n%s · %d/%d · +%d €" % [str(spot["name"]).get_slice(" · ", 0), found.size(), spots.size(), REWARD]) if first else ""
	_headline.text = banner_text
	# Freeze the player (and its weapons) instead of editing their input code.
	_frozen.clear()
	for node in [player, main.get("weapons") if main != null else null]:
		if node != null and is_instance_valid(node):
			_frozen[node] = (node as Node).process_mode
			(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
	player.velocity = Vector3.ZERO
	_previous_camera = get_viewport().get_camera_3d()
	camera = Camera3D.new()
	camera.name = "MiradorCamera"
	camera.fov = 68.0
	camera.far = 3000.0
	add_child(camera)
	var at: Vector3 = spot["at"]
	var look: Vector3 = spot["look"]
	_eye = at + Vector3(0, EYE_HEIGHT, 0)
	var flat := Vector2(look.x - _eye.x, look.z - _eye.z)
	_yaw = atan2(-flat.x, -flat.y)
	_pitch = clampf(atan2(look.y - _eye.y, flat.length()), -0.3, 0.32)
	_time = 0.0
	cinematic = true
	_place_camera(0.0)
	camera.make_current()
	_caption.text = "MIRADOR · %s\nE / Esc saltar" % str(spot["name"]).to_upper()
	_bars.visible = true
	var hud := main.get("hud") as CanvasLayer if main != null else null
	if hud != null:
		_hud_was_visible = hud.visible
		hud.visible = false
	mirador_discovered.emit(id, first)
	var recorder: Node = main.get("playtest_log") if main != null else null
	if recorder != null:
		recorder.call("record", "mirador", {"id": id, "first": first})


func _process(delta: float) -> void:
	if not cinematic:
		return
	_time += delta
	_place_camera(clampf(_time / PAN_SECONDS, 0.0, 1.0))
	if _time >= PAN_SECONDS:
		finish_view()


func _place_camera(t: float) -> void:
	var k := smoothstep(0.0, 1.0, t)
	var yaw := _yaw + deg_to_rad(PAN_DEGREES) * (0.5 - k)  # sweep left → right
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(_pitch, yaw, 0.0)), _eye)


func finish_view() -> void:
	if not cinematic:
		return
	cinematic = false
	for node in _frozen:
		if is_instance_valid(node):
			(node as Node).process_mode = _frozen[node]
	_frozen.clear()
	if _previous_camera != null and is_instance_valid(_previous_camera):
		_previous_camera.make_current()
	elif player != null:
		player.camera.make_current()
	if camera != null:
		camera.queue_free()
		camera = null
	_bars.visible = false
	var hud := main.get("hud") as CanvasLayer if main != null else null
	if hud != null:
		hud.visible = _hud_was_visible
	if banner_text != "" and _time < 2.5:  # skipped early: still show what was found
		_banner("MIRADOR %d/%d\n+%d €" % [found.size(), spots.size(), REWARD], Color("7fe0f0"))
	banner_text = ""
	active_index = -1
	if _bonus_banner:
		_bonus_banner = false
		_banner("¡TODOS LOS MIRADORES!\n+%d €" % BONUS, Color("f2c14e"))
		_say("Has visto Almuñécar desde todos sus miradores. La Costa Tropical no tiene secretos para ti.")


func _banner(text: String, color: Color) -> void:
	var hud: Node = main.get("hud") if main != null else null
	if hud != null:
		hud.call("show_banner", text, color)


func _say(text: String) -> void:
	var mission: Node = main.get("mission") if main != null else null
	if mission != null:
		mission.call("_show_dialogue", text)


func _ground(p: Vector3) -> Vector3:
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 30.0, p.z), Vector3(p.x, p.y - 30.0, p.z)))
	return Vector3(p.x, float(hit["position"].y), p.z) if not hit.is_empty() else p


# ------------------------------------------------------------------ markers

func _build_marker(spot: Dictionary) -> Node3D:
	var at: Vector3 = spot["at"]
	var look: Vector3 = spot["look"]
	var forward := Vector3(look.x - at.x, 0.0, look.z - at.z).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var root := Node3D.new()
	root.name = "Mirador_" + str(spot["id"])
	add_child(root)
	var metal := _mat(Color("2f6b62"), 0.45, 0.6)
	var dark := _mat(Color("22282b"), 0.5, 0.4)
	var brass := _mat(Color("c9a250"), 0.35, 0.8)
	var wood := _mat(Color("8a5a32"), 0.85, 0.0)
	var board := _mat(Color("5b3a1f"), 0.8, 0.0)
	# Coin-operated telescope one metre towards the view.
	var stand := at + forward * 1.1
	var yaw := atan2(-forward.x, -forward.z)
	var scope := Node3D.new()
	scope.name = "Telescopio"
	scope.position = stand
	scope.rotation.y = yaw
	root.add_child(scope)
	_part(scope, _cyl(0.26, 0.3, 0.08), Vector3(0, 0.04, 0), Vector3.ZERO, dark)
	_part(scope, _cyl(0.06, 0.07, 1.05), Vector3(0, 0.58, 0), Vector3.ZERO, metal)
	_part(scope, _box(Vector3(0.22, 0.26, 0.2)), Vector3(0, 1.18, 0), Vector3.ZERO, metal)  # coin box / housing
	_part(scope, _box(Vector3(0.06, 0.03, 0.01)), Vector3(0.0, 1.24, 0.105), Vector3.ZERO, brass)  # coin slot
	for side in [-0.065, 0.065]:
		_part(scope, _cyl(0.05, 0.065, 0.42), Vector3(side, 1.36, -0.06), Vector3(PI * 0.5 - 0.12, 0, 0), metal)  # barrels to the view
		_part(scope, _cyl(0.035, 0.035, 0.06), Vector3(side, 1.34, 0.17), Vector3(PI * 0.5 - 0.12, 0, 0), dark)  # eyepieces
	_part(scope, _box(Vector3(0.36, 0.05, 0.16)), Vector3(0, 1.43, -0.04), Vector3(-0.12, 0, 0), brass)  # visor
	var body := StaticBody3D.new()
	body.name = "TelescopioCollision"
	body.position = stand + Vector3(0, 0.7, 0)
	root.add_child(body)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.22
	cylinder.height = 1.4
	shape.shape = cylinder
	body.add_child(shape)
	# Wooden sign to one side, facing back along the path.
	var sign_at := at + right * 1.7 + forward * 0.6
	var plaque := Node3D.new()
	plaque.name = "Letrero"
	plaque.position = sign_at
	plaque.rotation.y = yaw + PI + 0.35
	root.add_child(plaque)
	for x in [-0.82, 0.82]:
		_part(plaque, _box(Vector3(0.1, 1.95, 0.1)), Vector3(x, 0.975, 0), Vector3.ZERO, wood)
	_part(plaque, _box(Vector3(2.0, 0.86, 0.06)), Vector3(0, 1.5, 0), Vector3.ZERO, board)
	_part(plaque, _box(Vector3(2.08, 0.07, 0.09)), Vector3(0, 1.96, 0), Vector3.ZERO, wood)
	var title := "MIRADOR\n" + str(spot["name"]).to_upper()
	for back in [false, true]:
		var label := Label3D.new()
		label.text = title
		label.font_size = 34
		label.outline_size = 3
		label.outline_modulate = Color(0.18, 0.1, 0.04)
		label.modulate = Color("fbefd2")
		label.pixel_size = 0.0042
		label.width = 430.0
		label.line_spacing = -4.0
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.double_sided = false
		label.position = Vector3(0, 1.5, -0.035 if back else 0.035)
		label.rotation.y = PI if back else 0.0
		label.visibility_range_end = 45.0
		label.visibility_range_end_margin = 5.0
		label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		plaque.add_child(label)
	return root


func _mat(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


func _cyl(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 12
	return mesh


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _part(parent: Node3D, mesh: Mesh, at: Vector3, euler: Vector3, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	part.rotation = euler
	part.visibility_range_end = 120.0
	parent.add_child(part)
	return part


# ------------------------------------------------------------------ letterbox

func _build_letterbox() -> void:
	_bars = CanvasLayer.new()
	_bars.name = "MiradorLetterbox"
	_bars.layer = 8
	_bars.visible = false
	add_child(_bars)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.92)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.anchor_bottom = 0.11 if top else 1.0
		bar.anchor_top = 0.0 if top else 0.89
		bar.offset_top = 0.0
		bar.offset_bottom = 0.0
		_bars.add_child(bar)
	_caption = Label.new()
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.anchor_top = 0.89
	_caption.offset_top = 0.0
	_caption.offset_bottom = 0.0
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 18)
	_caption.add_theme_color_override("font_color", Color("e8f6f4"))
	_bars.add_child(_caption)
	_headline = Label.new()
	_headline.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_headline.anchor_top = 0.15
	_headline.anchor_bottom = 0.45
	_headline.offset_top = 0.0
	_headline.offset_bottom = 0.0
	_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_headline.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_headline.add_theme_font_size_override("font_size", 40)
	_headline.add_theme_color_override("font_color", Color("7fe0f0"))
	_headline.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_headline.add_theme_constant_override("outline_size", 9)
	_headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bars.add_child(_headline)


# ------------------------------------------------------------------ save

func to_save() -> Dictionary:
	return {"found": found.keys()}


func from_save(value: Variant) -> void:
	if cinematic:
		finish_view()
	found.clear()
	if value is Dictionary:
		for id in (value as Dictionary).get("found", []):
			for spot in spots:
				if str(spot["id"]) == str(id):
					found[str(id)] = true
