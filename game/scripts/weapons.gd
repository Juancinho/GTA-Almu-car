class_name WeaponSystem
extends Node3D

## The player's arsenal (res://data/weapons.json): fists, bat, pistol and SMG.
## Right mouse / LT aims over the shoulder, left mouse / F / RB attacks, 1–4 or the
## wheel / D-pad switch weapons, R reloads. Shots are hitscan from the camera
## centre: pedestrians lose health (and can die), vehicles take damage, gunfire
## scares everyone nearby and witnesses call the police. Weapons are found as
## spinning pickups around town and respawn after a while.

signal fired(weapon: String, hit: Object)
signal inventory_changed

const DATA_PATH := "res://data/weapons.json"

var player: PlayerController
var world: SectorWorld
var wanted: WantedSystem
var defs: Dictionary = {}
var order: Array[String] = ["fists"]
var owned: Dictionary = {"fists": true}
var clip: Dictionary = {}
var reserve: Dictionary = {}
var current := "fists"
var cooldown := 0.0
var reload_timer := 0.0
var aiming := false
var pickups: Array[Dictionary] = []  # {weapon, ammo, node, respawn_s, timer}
var sounds: Dictionary = {}
var flash: OmniLight3D
var flash_timer := 0.0
var tracer: MeshInstance3D
var tracer_mesh: ImmediateMesh
var tracer_timer := 0.0
var gun_visual: MeshInstance3D
var rng := RandomNumberGenerator.new()


func configure(target_player: PlayerController, target_world: SectorWorld, target_wanted: WantedSystem) -> void:
	player = target_player
	world = target_world
	wanted = target_wanted
	rng.seed = 7420
	add_to_group("weapon_system")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary:
		push_error("WeaponSystem: invalid " + DATA_PATH)
		return
	defs = parsed["weapons"]
	order.clear()
	for id in parsed["order"]:
		order.append(str(id))
	for spec in parsed.get("pickups", []):
		_add_pickup(spec)
	for id in ["pistol_shot", "smg_shot", "bat_hit", "dry_click", "reload"]:
		var audio := AudioStreamPlayer3D.new()
		audio.name = "Sound_" + id
		audio.stream = load("res://assets/audio/%s.wav" % id) as AudioStream
		audio.bus = "SFX"
		audio.max_distance = 140.0
		audio.unit_size = 8.0
		player.add_child(audio)
		sounds[id] = audio
	flash = OmniLight3D.new()
	flash.light_color = Color("ffd28a")
	flash.light_energy = 0.0
	flash.omni_range = 6.0
	flash.top_level = true
	add_child(flash)
	tracer_mesh = ImmediateMesh.new()
	tracer = MeshInstance3D.new()
	tracer.mesh = tracer_mesh
	tracer.top_level = true
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var line := StandardMaterial3D.new()
	line.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.albedo_color = Color(1.0, 0.9, 0.6, 0.85)
	line.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tracer.material_override = line
	add_child(tracer)
	_build_gun_visual()


## A simple dark pistol/SMG shape held in the right hand.
func _build_gun_visual() -> void:
	var skeletons := player.human.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var attach := BoneAttachment3D.new()
	attach.name = "RightHandWeapon"
	attach.bone_name = "Palm.R"
	(skeletons[0] as Skeleton3D).add_child(attach)
	gun_visual = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.13, 0.26)
	gun_visual.mesh = box
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("222426")
	metal.metallic = 0.6
	metal.roughness = 0.35
	gun_visual.material_override = metal
	# The skeleton sits inside the 0.36-scaled model; undo that so the gun keeps real size.
	gun_visual.scale = Vector3.ONE / HumanModel.MODEL_SCALE
	gun_visual.position = Vector3(0, 0.12, 0.1) / HumanModel.MODEL_SCALE
	gun_visual.visible = false
	attach.add_child(gun_visual)


func definition() -> Dictionary:
	return defs.get(current, {})


func is_gun() -> bool:
	return str(definition().get("kind", "")) == "gun"


func display_name() -> String:
	return str(definition().get("name", current))


func ammo_text() -> String:
	if not is_gun():
		return ""
	return "%d / %d" % [int(clip.get(current, 0)), int(reserve.get(current, 0))]


func give(id: String, ammo: int) -> void:
	if not defs.has(id):
		return
	var first := not owned.has(id)
	owned[id] = true
	if str(defs[id].get("kind", "")) == "gun":
		reserve[id] = int(reserve.get(id, 0)) + ammo
		if first or int(clip.get(id, 0)) == 0:
			_refill(id)
	if first:
		select(id)
	inventory_changed.emit()


func select(id: String) -> void:
	if not owned.has(id) or reload_timer > 0.0:
		return
	current = id
	cooldown = 0.2
	if gun_visual != null:
		gun_visual.visible = is_gun()
		(gun_visual.mesh as BoxMesh).size = Vector3(0.05, 0.13, 0.36) if id == "smg" else Vector3(0.05, 0.13, 0.26)
	inventory_changed.emit()


func cycle(step: int) -> void:
	var index := order.find(current)
	for k in range(1, order.size() + 1):
		var candidate := order[posmod(index + step * k, order.size())]
		if owned.has(candidate):
			select(candidate)
			return


func _refill(id: String) -> void:
	var size := int(defs[id].get("clip", 0))
	var need := size - int(clip.get(id, 0))
	var moved := mini(need, int(reserve.get(id, 0)))
	clip[id] = int(clip.get(id, 0)) + moved
	reserve[id] = int(reserve.get(id, 0)) - moved


func start_reload() -> void:
	if not is_gun() or reload_timer > 0.0 or int(reserve.get(current, 0)) <= 0 or int(clip.get(current, 0)) >= int(definition().get("clip", 0)):
		return
	reload_timer = float(definition().get("reload_s", 1.4))
	_play("reload")


func _unhandled_input(event: InputEvent) -> void:
	if player == null or player.dead or player.driving_vehicle != null:
		return
	for k in range(order.size()):
		if event.is_action_pressed("weapon_%d" % (k + 1)):
			select(order[k])
	if event.is_action_pressed("weapon_next"):
		cycle(1)
	elif event.is_action_pressed("weapon_prev"):
		cycle(-1)
	elif event.is_action_pressed("reload"):
		start_reload()
	elif event.is_action_pressed("attack") and current == "bat":
		swing()
	elif event.is_action_pressed("attack") and is_gun() and not bool(definition().get("auto", false)):
		fire()


func _process(delta: float) -> void:
	if player == null:
		return
	cooldown = maxf(0.0, cooldown - delta)
	if reload_timer > 0.0:
		reload_timer -= delta
		if reload_timer <= 0.0:
			reload_timer = 0.0
			_refill(current)
			inventory_changed.emit()
	flash_timer -= delta
	flash.light_energy = 2.5 if flash_timer > 0.0 else 0.0
	tracer_timer -= delta
	tracer.visible = tracer_timer > 0.0
	var can_aim := is_gun() and player.driving_vehicle == null and not player.dead and not player.swimming
	aiming = can_aim and InputMap.has_action("aim") and Input.is_action_pressed("aim")
	player.aiming = aiming
	if gun_visual != null:
		gun_visual.visible = is_gun() and player.driving_vehicle == null
	if aiming:
		player.human.hold_pose("punch", 0.26)
	if is_gun() and bool(definition().get("auto", false)) and InputMap.has_action("attack") and Input.is_action_pressed("attack") and player.driving_vehicle == null:
		fire()
	_update_pickups(delta)


## One shot along the camera's centre line. Returns what it hit (or null).
func fire() -> Object:
	if cooldown > 0.0 or reload_timer > 0.0 or player.dead or player.driving_vehicle != null or player.swimming:
		return null
	var spec := definition()
	if int(clip.get(current, 0)) <= 0:
		cooldown = 0.3
		if int(reserve.get(current, 0)) > 0:
			start_reload()
		else:
			_play("dry_click")
		return null
	clip[current] = int(clip[current]) - 1
	cooldown = float(spec.get("interval", 0.3))
	var camera := player.camera
	var spread := deg_to_rad(float(spec.get("spread_aim" if aiming else "spread_hip", 2.0)))
	var direction := (-camera.global_transform.basis.z).rotated(camera.global_transform.basis.x, rng.randf_range(-spread, spread)).rotated(Vector3.UP, rng.randf_range(-spread, spread)).normalized()
	var origin := camera.global_position
	# Start the ray at the player's depth so walls between camera and player don't block it.
	origin += direction * maxf(0.0, (player.global_position - origin).dot(direction))
	var reach := float(spec.get("range", 100.0))
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * reach)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	var end := origin + direction * reach
	var target: Object = null
	if not hit.is_empty():
		end = hit["position"]
		target = hit["collider"]
		_apply_hit(target, spec, end)
	var muzzle := player.global_position + Vector3(0, 1.35, 0) + (-camera.global_transform.basis.z) * 0.6 + camera.global_transform.basis.x * 0.25
	_tracer(muzzle, end)
	flash.global_position = muzzle
	flash_timer = 0.05
	_play(str(spec.get("sound", "pistol_shot")))
	player.human.hold_pose("punch", 0.26)
	player.camera_pitch = clampf(player.camera_pitch + 0.012, -1.1, 0.55)
	_scare(player.global_position, 45.0)
	wanted.report_crime("disparos", player.global_position)
	fired.emit(current, target)
	inventory_changed.emit()
	return target


func _apply_hit(target: Object, spec: Dictionary, at: Vector3) -> void:
	if target is Pedestrian:
		var person := target as Pedestrian
		if not person.mission_contact:
			person.take_damage(float(spec.get("damage", 30.0)), player.global_position)
			wanted.report_crime("agresión armada", person.global_position)
	elif target is DriveableVehicle:
		(target as DriveableVehicle).apply_damage(float(spec.get("vehicle_damage", 50.0)))
		if wanted.police_cars.has(target):
			wanted.report_police_attack((target as Node3D).global_position)


## Bat swing: hits the first person or car in front after the wind-up.
func swing() -> void:
	if cooldown > 0.0:
		return
	var spec := definition()
	cooldown = float(spec.get("interval", 0.75))
	player.human.play_action("swordslash", 0.55)
	get_tree().create_timer(0.28, false).timeout.connect(_land_swing)


func _land_swing() -> void:
	if player.dead or player.driving_vehicle != null or current != "bat":
		return
	var spec := definition()
	var forward := -player.visual.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var reach := float(spec.get("range", 2.5))
	for node in get_tree().get_nodes_in_group("pedestrians"):
		var person := node as Pedestrian
		if person == null or person.mission_contact or person.state == Pedestrian.State.DOWN:
			continue
		var offset := person.global_position - player.global_position
		offset.y = 0.0
		if offset.length() < reach and offset.normalized().dot(forward) > 0.3:
			person.provoked_by_player = true
			person.take_damage(float(spec.get("damage", 45.0)), player.global_position)
			_play("bat_hit")
			player.assaulted.emit(person)
			return
	for node in get_tree().get_nodes_in_group("vehicles"):
		var car := node as DriveableVehicle
		if car != null and car.global_position.distance_to(player.global_position) < reach + 1.4 and (car.global_position - player.global_position).normalized().dot(forward) > 0.2:
			car.apply_damage(float(spec.get("vehicle_damage", 60.0)))
			_play("bat_hit")
			return


func _tracer(from: Vector3, to: Vector3) -> void:
	tracer_mesh.clear_surfaces()
	tracer_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	tracer_mesh.surface_add_vertex(from)
	tracer_mesh.surface_add_vertex(to)
	tracer_mesh.surface_end()
	tracer.global_transform = Transform3D.IDENTITY
	tracer_timer = 0.045


func _scare(at: Vector3, radius: float) -> void:
	for node in get_tree().get_nodes_in_group("pedestrians"):
		var person := node as Pedestrian
		if person != null and not person.mission_contact and not person.enemy and person.global_position.distance_to(at) < radius:
			person.flee_from(at)


## Someone else's gunshot (gunmen): a sound at their position and a scared crowd.
func play_remote_shot(at: Vector3) -> void:
	_scare(at, 35.0)
	if DisplayServer.get_name() == "headless" or not sounds.has("pistol_shot"):
		return
	var shot := AudioStreamPlayer3D.new()
	shot.stream = (sounds["pistol_shot"] as AudioStreamPlayer3D).stream
	shot.bus = "SFX"
	shot.max_distance = 140.0
	shot.unit_size = 8.0
	shot.top_level = true
	add_child(shot)
	shot.global_position = at
	shot.finished.connect(shot.queue_free)
	shot.play()


func _play(id: String) -> void:
	if sounds.has(id) and DisplayServer.get_name() != "headless":
		(sounds[id] as AudioStreamPlayer3D).play()


# --- Pickups --------------------------------------------------------------------

func _add_pickup(spec: Dictionary) -> void:
	var at: Array = spec["at"]
	var point := Vector3(float(at[0]), 0, float(at[1]))
	var walk := world.road_network.nearest(point, false)
	if not walk.is_empty() and float(walk["distance"]) < 25.0:
		point = walk["point"]
	point.y = world.height_at(point.x, point.z)
	var node := Node3D.new()
	node.name = "Pickup_%s_%d" % [spec["weapon"], pickups.size()]
	node.top_level = true
	add_child(node)
	node.global_position = point
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.22, 0.55) if str(spec["weapon"]) != "bat" else Vector3(0.1, 0.1, 0.9)
	body.mesh = box
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("2a2c2e")
	glow.emission_enabled = true
	glow.emission = Color("f2c14e")
	glow.emission_energy_multiplier = 0.6
	body.material_override = glow
	body.position.y = 0.9
	node.add_child(body)
	var halo := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.45
	ring.outer_radius = 0.55
	halo.mesh = ring
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.albedo_color = Color(1.0, 0.8, 0.3, 0.7)
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo.material_override = halo_mat
	halo.position.y = 0.08
	node.add_child(halo)
	var label := Label3D.new()
	label.text = str(defs.get(str(spec["weapon"]), {}).get("name", spec["weapon"])).to_upper()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.outline_size = 10
	label.pixel_size = 0.006
	label.position.y = 1.6
	label.modulate = Color("f2c14e")
	label.visibility_range_end = 45.0
	node.add_child(label)
	pickups.append({"weapon": str(spec["weapon"]), "ammo": int(spec.get("ammo", 0)), "node": node, "respawn_s": float(spec.get("respawn_s", 90.0)), "timer": 0.0})


func _update_pickups(delta: float) -> void:
	for pickup in pickups:
		var node := pickup["node"] as Node3D
		if not node.visible:
			pickup["timer"] = float(pickup["timer"]) - delta
			if float(pickup["timer"]) <= 0.0:
				node.visible = true
			continue
		(node.get_child(0) as Node3D).rotation.y += delta * 2.0
		if player.driving_vehicle == null and not player.dead and node.global_position.distance_to(player.global_position) < 1.7:
			node.visible = false
			pickup["timer"] = float(pickup["respawn_s"])
			give(str(pickup["weapon"]), int(pickup["ammo"]))
			_play("reload")
			get_tree().call_group("mission_controller", "_show_dialogue", "Has cogido: %s%s" % [str(defs[pickup["weapon"]].get("name", "")), (" (+%d balas)" % int(pickup["ammo"])) if int(pickup["ammo"]) > 0 else ""])


# --- Save -----------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"owned": owned.keys(), "clip": clip, "reserve": reserve, "current": current}


func from_save(data: Dictionary) -> void:
	owned = {"fists": true}
	for id in data.get("owned", []):
		if defs.has(str(id)):
			owned[str(id)] = true
	clip = {}
	reserve = {}
	for id in (data.get("clip", {}) as Dictionary):
		clip[str(id)] = int(data["clip"][id])
	for id in (data.get("reserve", {}) as Dictionary):
		reserve[str(id)] = int(data["reserve"][id])
	reload_timer = 0.0
	select(str(data.get("current", "fists")) if owned.has(str(data.get("current", "fists"))) else "fists")
