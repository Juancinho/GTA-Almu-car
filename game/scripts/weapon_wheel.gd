extends CanvasLayer

## Weapon wheel: hold TAB (or d-pad up) on foot. Time slows
## down, every weapon you own and the grenades/Molotovs sit on a ring, the mouse
## or right stick points at one and releasing TAB equips it.

const SLOW := 0.3
const RADIUS := 150.0

var player: PlayerController
var weapons: Node
var throwables: Node
var open := false
var aim := Vector2.ZERO
var entries: Array = []  # {id, kind ("weapon"|"throwable"), label}
var highlighted := -1
var _saved_scale := 1.0
var root: Control
var slots: Array[Panel] = []
var title: Label


func configure(target_player: PlayerController, target_weapons: Node, target_throwables: Node) -> void:
	player = target_player
	weapons = target_weapons
	throwables = target_throwables
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.visible = false
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	title = Label.new()
	_centre(title, Vector2.ZERO, Vector2(260, 40))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("f2c14e"))
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	root.add_child(title)


func _input(event: InputEvent) -> void:
	if player == null:
		return
	if not open:
		if event.is_action_pressed("weapon_wheel") and _can_open():
			show_wheel()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_released("weapon_wheel"):
		close_wheel(true)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		point((aim + (event as InputEventMouseMotion).relative).limit_length(120.0))
	elif event is InputEventJoypadMotion:
		var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
		if stick.length() > 0.4:
			point(stick * 120.0)
	get_viewport().set_input_as_handled()  # no camera, shooting or punching while choosing


func _can_open() -> bool:
	return not player.dead and player.driving_vehicle == null and not get_tree().paused


func show_wheel() -> void:
	entries.clear()
	for id in weapons.get("order"):
		if (weapons.get("owned") as Dictionary).has(id):
			var def: Dictionary = (weapons.get("defs") as Dictionary).get(id, {})
			var label := str(def.get("name", id))
			if str(def.get("kind", "")) == "gun":
				label += "\n%d" % (int((weapons.get("clip") as Dictionary).get(id, 0)) + int((weapons.get("reserve") as Dictionary).get(id, 0)))
			entries.append({"id": id, "kind": "weapon", "label": label})
	if throwables != null:
		for kind in ["grenade", "molotov"]:
			var count := int((throwables.get("counts") as Dictionary)[kind])
			if count > 0:
				entries.append({"id": kind, "kind": "throwable", "label": "%s\n×%d" % [throwables.NAMES[kind], count]})
	_build_slots()
	open = true
	root.visible = true
	_saved_scale = Engine.time_scale
	Engine.time_scale = SLOW
	aim = Vector2.ZERO
	highlighted = -1
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		if (entry["kind"] == "weapon" and entry["id"] == str(weapons.get("current"))):
			highlighted = i
	_refresh()


func close_wheel(apply: bool) -> void:
	if not open:
		return
	open = false
	root.visible = false
	Engine.time_scale = _saved_scale if _saved_scale > 0.0 else 1.0
	if apply and highlighted >= 0 and highlighted < entries.size():
		choose(highlighted)


## Equip entry `index` (weapons become the hand weapon, a throwable becomes the G item).
func choose(index: int) -> void:
	var entry: Dictionary = entries[index]
	if entry["kind"] == "weapon":
		weapons.call("select", entry["id"])
	elif throwables != null:
		throwables.set("selected", entry["id"])


## Point the selector in screen space (pixels from the centre).
func point(direction: Vector2) -> void:
	aim = direction
	if aim.length() < 30.0 or entries.is_empty():
		_refresh()
		return
	var angle := fposmod(aim.angle() + PI * 0.5, TAU)  # 0 at the top, clockwise
	highlighted = int(round(angle / (TAU / entries.size()))) % entries.size()
	_refresh()


func _build_slots() -> void:
	for slot in slots:
		slot.queue_free()
	slots.clear()
	for i in range(entries.size()):
		var slot := Panel.new()
		var angle := -PI * 0.5 + TAU * float(i) / float(entries.size())
		_centre(slot, Vector2(cos(angle), sin(angle)) * RADIUS, Vector2(118, 64))
		var label := Label.new()
		label.text = str(entries[i]["label"])
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 17)
		slot.add_child(label)
		root.add_child(slot)
		slots.append(slot)


## Anchor `control` to the screen centre, its middle `offset` pixels away.
func _centre(control: Control, offset: Vector2, size: Vector2) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 0.5
	control.anchor_bottom = 0.5
	control.offset_left = offset.x - size.x * 0.5
	control.offset_right = offset.x + size.x * 0.5
	control.offset_top = offset.y - size.y * 0.5
	control.offset_bottom = offset.y + size.y * 0.5


func _refresh() -> void:
	for i in range(slots.size()):
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(10)
		style.bg_color = Color(0.95, 0.76, 0.3, 0.92) if i == highlighted else Color(0.06, 0.08, 0.1, 0.78)
		style.border_color = Color("f2c14e")
		style.set_border_width_all(2 if i == highlighted else 0)
		slots[i].add_theme_stylebox_override("panel", style)
		(slots[i].get_child(0) as Label).add_theme_color_override("font_color", Color("101418") if i == highlighted else Color("f4ecd8"))
	title.text = str(entries[highlighted]["label"]).split("\n")[0].to_upper() if highlighted >= 0 and highlighted < entries.size() else "ARMAS"


func _process(_delta: float) -> void:
	if open and (player.dead or player.driving_vehicle != null):
		close_wheel(false)
