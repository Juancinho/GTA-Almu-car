class_name WeaponSystem
extends Node3D

## Data-defined arsenal. Camera aim chooses a target, then shared ballistics casts
## from the physical muzzle, with cover and glass attenuation for every shooter.
## Pedestrians react, vehicles/props receive damage or impulses and witnesses
## report gunfire. Pickups respawn; inventory/ammunition persist with the save.

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
const SUPPLIES := ["armor", "health", "grenade", "molotov"]
var pickups: Array[Dictionary] = []  # {weapon, ammo, node, respawn_s, timer}
var sounds: Dictionary = {}
var flash: OmniLight3D
var flash_timer := 0.0
var tracer: MeshInstance3D
var tracer_mesh: ImmediateMesh
var tracer_timer := 0.0
var gun_visual: MeshInstance3D
var rng := RandomNumberGenerator.new()
var ballistics: Ballistics
const MAX_IMPACT_EFFECTS := 12
var active_impacts := 0
var impact_mesh: SphereMesh
var glass_shard_mesh: ArrayMesh
var impact_materials: Dictionary = {}
static var gun_materials: Dictionary = {}
const MAX_REMOTE_SOUNDS := 8
var remote_sounds := 0
## Holdups: aim a gun at the counter of a shop, café or restaurant for a few
## seconds and the staff empty the till. Two stars, and the shop needs time.
const HOLDUP_KINDS := ["supermarket", "mall", "cafe", "restaurant", "palm_restaurant", "bank"]
const HOLDUP_SECONDS := 4.0
var holdup_progress := 0.0
var holdup_venue := ""
var holdup_cooldowns: Dictionary = {}  # venue kind -> msec when it can be robbed again


func configure(target_player: PlayerController, target_world: SectorWorld, target_wanted: WantedSystem) -> void:
	process_priority = 50  # pose after character animation and camera updates
	player = target_player
	world = target_world
	wanted = target_wanted
	ballistics = Ballistics.new()
	ballistics.name = "Ballistics"
	ballistics.wanted = wanted
	add_child(ballistics)
	ballistics.impact.connect(_impact)
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


## Colours for the CC0 Quaternius gun materials (the FBX import leaves them white).
const GUN_COLORS := {
	"Metal": ["5a5d61", 0.7, 0.35], "DarkMetal": ["2e3033", 0.6, 0.4], "DarkerMetal": ["232427", 0.6, 0.4],
	"Black": ["1b1c1e", 0.2, 0.6], "Wood": ["6b3f22", 0.0, 0.7], "LightWood": ["9b6a3c", 0.0, 0.7],
	"DarkWood": ["4a2a16", 0.0, 0.7], "Magazine": ["26282a", 0.4, 0.5], "Muzzle": ["2e3033", 0.6, 0.4],
	"Trigger": ["202224", 0.5, 0.5], "Barrels": ["3a3c40", 0.7, 0.35], "BulletYellow": ["b8912f", 0.8, 0.3],
	"BulletRed": ["9a2a22", 0.2, 0.5], "BulletOrange": ["c0762a", 0.8, 0.3], "BulletTip": ["b87333", 0.8, 0.3],
	"Material.001": ["2b2d30", 0.3, 0.5], "Material.003": ["1c1d1f", 0.3, 0.5], "Material.004": ["6d6f73", 0.5, 0.4],
}

var gun_holder: Node3D
var gun_models: Dictionary = {}  # weapon id -> Node3D


## Real weapon models (CC0 Quaternius) held by the player: raised to the eye
## when aiming, lowered along the body otherwise.
func _build_gun_visual() -> void:
	gun_holder = Node3D.new()
	gun_holder.name = "HeldWeapon"
	player.visual.add_child(gun_holder)
	for id in defs:
		if defs[id].has("model"):
			var model := weapon_model(id)
			if model != null:
				model.visible = false
				gun_holder.add_child(model)
				gun_models[id] = model
	gun_visual = null


## A correctly oriented (barrel along -Z, grip down), scaled and coloured model.
func weapon_model(id: String) -> Node3D:
	var spec: Dictionary = defs.get(id, {})
	if not spec.has("model"):
		return null
	var scene := load(str(spec["model"])) as PackedScene
	if scene == null:
		return null
	var pivot := Node3D.new()
	pivot.name = "Model_" + id
	var model := scene.instantiate() as Node3D
	var scale := float(spec.get("model_scale", 0.05))
	model.scale = Vector3.ONE * scale
	model.rotation.y = deg_to_rad(float(spec.get("model_yaw", 0.0)))
	pivot.add_child(model)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in range(mesh.mesh.get_surface_count()):
			var source := mesh.mesh.surface_get_material(surface)
			var look: Array = GUN_COLORS.get(source.resource_name if source != null else "", ["303236", 0.5, 0.45])
			var material_key := str(look)
			if not gun_materials.has(material_key):
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color(str(look[0]))
				mat.metallic = float(look[1])
				mat.roughness = float(look[2])
				gun_materials[material_key] = mat
			# Keep shared overrides alive when pursuing officers despawn; the
			# renderer can still query an instance during its deferred teardown.
			mesh.set_surface_override_material(surface, gun_materials[material_key])
	# The FBXs are skinned: a mesh AABB is in bind space, not the rendered pose.
	# Author the grip relative to their trigger bone, never the mesh centre.
	for node in model.find_children("*", "Skeleton3D", true, false):
		var rig := node as Skeleton3D
		var trigger := rig.find_bone("Trigger")
		if trigger < 0:
			continue
		var transform_to_pivot := rig.transform
		var ancestor := rig.get_parent() as Node3D
		while ancestor != pivot and ancestor != null:
			transform_to_pivot = ancestor.transform * transform_to_pivot
			ancestor = ancestor.get_parent() as Node3D
		var offset: Array = spec.get("grip_from_trigger", [0.0, -0.04, 0.035])
		model.position = -(transform_to_pivot * rig.get_bone_global_pose(trigger)).origin - Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
		break
	return pivot


func _pose_gun(_delta: float) -> void:
	if gun_holder == null:
		return
	player.human.clear_weapon_pose()
	for id in gun_models:
		(gun_models[id] as Node3D).visible = id == current and player.driving_vehicle == null and not player.swimming and not player.dead
	if not gun_models.has(current) or player.driving_vehicle != null or player.swimming or player.dead:
		return
	var long := bool(definition().get("long", false))
	var body := player.visual.global_transform.basis.orthonormalized()
	var grip := _bone_position("MiddleHand.R")
	var shoulder := _bone_position("UpperArm.R")
	if grip == Vector3.INF or shoulder == Vector3.INF:
		grip = player.visual.global_position + body * Vector3(0.2, 1.3, -0.4)
		shoulder = player.visual.global_position + body * Vector3(0.2, 1.45, 0.0)
	var raised := aiming or cooldown > 0.0
	var basis := body * Basis(Vector3.RIGHT, player.camera_pitch if raised else deg_to_rad(-30.0 if long else -65.0))
	if raised or long:
		var target := shoulder + basis * (Vector3(-0.035, -0.11 if raised else -0.25, -0.18) if long else Vector3(0.025, -0.16, -0.39))
		player.human.place_hand("R", target, shoulder + body * Vector3(0.32, -0.45, 0.03))
		player.human.close_weapon_hand("R")
		grip = _bone_position("MiddleHand.R")
		if long:
			var support: Array = definition().get("support_grip", [-0.035, 0.025, -0.23])
			var support_target := grip + basis * Vector3(float(support[0]), float(support[1]), float(support[2]))
			var elbow := shoulder + body * Vector3(-0.5, -0.5, -0.1)
			player.human.place_hand("L", support_target, elbow)
			player.human.close_weapon_hand("L")
			var hand_offset := _bone_position("MiddleHand.L") - _bone_position("Palm.L")
			player.human.place_hand("L", support_target - hand_offset, elbow)
			player.human.close_weapon_hand("L")
	else:
		# Closing the carrying hand requires the skeleton even before the first aim.
		if player.human.grip_skeleton == null:
			player.human.grip_skeleton = _skeleton
		player.human.close_weapon_hand("R")
		grip = _bone_position("MiddleHand.R")
	gun_holder.global_transform = Transform3D(basis, grip)


func muzzle_position() -> Vector3:
	var socket: Array = definition().get("muzzle", [0.0, 0.08, -0.25])
	return gun_holder.to_global(Vector3(float(socket[0]), float(socket[1]), float(socket[2])))


var _skeleton: Skeleton3D


func _bone_position(bone: String) -> Vector3:
	if not is_instance_valid(_skeleton):
		var skeletons := player.human.find_children("*", "Skeleton3D", true, false)
		if skeletons.is_empty():
			return Vector3.INF
		_skeleton = skeletons[0] as Skeleton3D
	var index := _skeleton.find_bone(bone)
	if index < 0:
		return Vector3.INF
	return (_skeleton.global_transform * _skeleton.get_bone_global_pose(index)).origin


func _impact(at: Vector3, color: Color, amount: int) -> void:
	if active_impacts >= MAX_IMPACT_EFFECTS or player.global_position.distance_squared_to(at) > 80.0 * 80.0:
		return
	active_impacts += 1
	var puff := CPUParticles3D.new()
	puff.one_shot = true
	puff.amount = amount
	puff.lifetime = 0.4
	puff.explosiveness = 1.0
	puff.direction = Vector3.UP
	puff.spread = 70.0
	puff.initial_velocity_min = 1.0
	puff.initial_velocity_max = 3.0
	puff.gravity = Vector3(0, -9.0, 0)
	puff.scale_amount_min = 0.05
	puff.scale_amount_max = 0.1
	if impact_mesh == null:
		impact_mesh = SphereMesh.new()
		impact_mesh.radius = 0.5
		impact_mesh.height = 1.0
		impact_mesh.radial_segments = 4
		impact_mesh.rings = 2
	var glass := color == Color("bbdfed")
	if glass and glass_shard_mesh == null:
		glass_shard_mesh = ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, -0.4, 0), Vector3(0.5, -0.4, 0), Vector3(0.2, 0.6, 0)])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
		glass_shard_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	puff.mesh = glass_shard_mesh if glass else impact_mesh
	if glass:
		puff.lifetime = 0.65
		puff.scale_amount_min = 0.1
		puff.scale_amount_max = 0.22
		puff.angular_velocity_min = -240.0
		puff.angular_velocity_max = 240.0
	if not impact_materials.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		impact_materials[color] = mat
	puff.material_override = impact_materials[color]
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puff.visibility_range_end = 80.0
	puff.top_level = true
	add_child(puff)
	puff.global_position = at
	puff.emitting = true
	get_tree().create_timer(1.0, false).timeout.connect(func() -> void:
		active_impacts -= 1
		puff.queue_free())


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
	_pose_gun(delta)
	if is_gun() and bool(definition().get("auto", false)) and InputMap.has_action("attack") and Input.is_action_pressed("attack") and player.driving_vehicle == null:
		fire()
	_update_pickups(delta)
	_update_holdup(delta)


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
	var reach := float(spec.get("range", 100.0))
	var target: Object = null
	var end := Vector3.ZERO
	_pose_gun(0.0)
	var muzzle := muzzle_position()
	var body_origin := player.global_position + Vector3.UP * 1.3
	var barrel_query := PhysicsRayQueryParameters3D.create(body_origin, muzzle, Ballistics.SHOT_MASK, [player.get_rid()])
	var barrel_blocked := not player.get_world_3d().direct_space_state.intersect_ray(barrel_query).is_empty()
	for pellet in range(int(spec.get("pellets", 1))):
		var direction := (-camera.global_transform.basis.z).rotated(camera.global_transform.basis.x, rng.randf_range(-spread, spread)).rotated(Vector3.UP, rng.randf_range(-spread, spread)).normalized()
		var origin := camera.global_position
		# Start the ray at the player's depth so walls between camera and player don't block it.
		origin += direction * maxf(0.0, (player.global_position - origin).dot(direction))
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * reach, Ballistics.SHOT_MASK)
		query.exclude = [player.get_rid()]
		var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
		var aim_point: Vector3 = hit["position"] if not hit.is_empty() else origin + direction * reach
		# The camera selects the aim point; only the muzzle's path can inflict damage.
		var shot_origin := body_origin if barrel_blocked else muzzle
		var shot_direction := (muzzle - body_origin).normalized() if barrel_blocked else (aim_point - muzzle).normalized()
		var shot_reach := body_origin.distance_to(muzzle) if barrel_blocked else reach
		var shot := ballistics.shoot(shot_origin, shot_direction, shot_reach,
			float(spec.get("damage", 30.0)), float(spec.get("vehicle_damage", 50.0)), player)
		end = shot["position"]
		var struck: Object = shot["collider"]
		if target == null or struck is Pedestrian or struck is DriveableVehicle:
			target = struck
	_tracer(muzzle, end)
	flash.global_position = muzzle
	flash_timer = 0.05
	_play(str(spec.get("sound", "pistol_shot")))
	player.camera_pitch = clampf(player.camera_pitch + 0.012, -1.1, 0.55)
	_scare(player.global_position, 45.0)
	wanted.report_crime("disparos", player.global_position)
	fired.emit(current, target)
	inventory_changed.emit()
	return target


## NPC shots use the same collision/damage path, including misses striking cover.
func fire_remote(shooter: Pedestrian, target: Vector3, damage: float, vehicle_damage: float,
		spread: float, shot_rng: RandomNumberGenerator, source: String) -> Dictionary:
	var origin := shooter.global_position + Vector3.UP * 1.5
	if shooter.firearm != null:
		shooter.firearm.pose()
		origin = shooter.firearm.muzzle_position()
	var body_origin := shooter.global_position + Vector3.UP * 1.3
	var barrel_probe := PhysicsRayQueryParameters3D.create(body_origin, origin, Ballistics.SHOT_MASK, [shooter.get_rid()])
	if not shooter.get_world_3d().direct_space_state.intersect_ray(barrel_probe).is_empty():
		var obstruction := ballistics.shoot(body_origin, (origin - body_origin).normalized(), body_origin.distance_to(origin), damage, vehicle_damage, shooter, source)
		play_remote_shot(body_origin)
		return obstruction
	var direction := (target - origin).normalized()
	direction = direction.rotated(Vector3.UP, shot_rng.randf_range(-spread, spread))
	direction = direction.rotated(shooter.global_basis.x, shot_rng.randf_range(-spread, spread))
	var shot := ballistics.shoot(origin, direction, 65.0, damage, vehicle_damage, shooter, source)
	_tracer(origin, shot["position"])
	play_remote_shot(origin)
	return shot


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
			if not _melee_clear(person):
				continue
			person.provoked_by_player = true
			person.take_damage(float(spec.get("damage", 45.0)), player.global_position)
			_play("bat_hit")
			player.assaulted.emit(person)
			return
	for node in get_tree().get_nodes_in_group("vehicles"):
		var car := node as DriveableVehicle
		if car != null and car.global_position.distance_to(player.global_position) < reach + 1.4 and (car.global_position - player.global_position).normalized().dot(forward) > 0.2:
			if not _melee_clear(car):
				continue
			car.apply_damage(float(spec.get("vehicle_damage", 60.0)))
			_play("bat_hit")
			return


func _melee_clear(target: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP,
		target.global_position + Vector3.UP)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == target


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
		if person != null and not person.mission_contact and not person.enemy and person.global_position.distance_squared_to(at) < radius * radius:
			person.flee_from(at)


## Someone else's gunshot (gunmen): a sound at their position and a scared crowd.
func play_remote_shot(at: Vector3) -> void:
	_scare(at, 35.0)
	if DisplayServer.get_name() == "headless" or not sounds.has("pistol_shot") or remote_sounds >= MAX_REMOTE_SOUNDS:
		return
	remote_sounds += 1
	var shot := AudioStreamPlayer3D.new()
	shot.stream = (sounds["pistol_shot"] as AudioStreamPlayer3D).stream
	shot.bus = "SFX"
	shot.max_distance = 140.0
	shot.unit_size = 8.0
	shot.top_level = true
	add_child(shot)
	shot.global_position = at
	shot.finished.connect(func() -> void:
		remote_sounds -= 1
		shot.queue_free())
	shot.play()


func _play(id: String) -> void:
	if sounds.has(id) and DisplayServer.get_name() != "headless":
		(sounds[id] as AudioStreamPlayer3D).play()


func _update_holdup(delta: float) -> void:
	var venue := _holdup_target() if aiming else null
	if venue == null:
		holdup_progress = maxf(0.0, holdup_progress - delta * 2.0)
		if holdup_progress == 0.0:
			holdup_venue = ""
		return
	if venue.kind != holdup_venue:
		holdup_progress = 0.0
		holdup_venue = venue.kind
	holdup_progress += delta
	if holdup_progress >= HOLDUP_SECONDS:
		holdup_progress = 0.0
		holdup_venue = ""
		holdup_cooldowns[venue.kind] = Time.get_ticks_msec() + 240000
		var bank := venue.kind == "bank"
		var cash := rng.randi_range(900, 1600) if bank else rng.randi_range(180, 460)
		var main := get_parent()
		if main != null and main.has_method("add_money"):
			main.add_money(cash)
			if "hud" in main:
				main.hud.show_banner("ATRACO  +%d €" % cash, Color("f2d36b"))
		wanted.raise_to(4 if bank else 2, player.global_position)
		get_tree().call_group("mission_controller", "_show_dialogue", "Cajero: ¡Llévese la caja fuerte, pero no dispare! La alarma va directa a comisaría." if bank else "Dependiente: ¡Tome, tome, pero no dispare! (La alarma ya ha saltado.)")
		get_tree().call_group("mission_controller", "notify_event", "holdup_bank" if bank else "holdup")


## The shop counter the player is aiming at, if a holdup is possible there.
func _holdup_target() -> VenueInterior:
	if world == null:
		return null
	var forward := -player.camera.global_transform.basis.z
	for kind in HOLDUP_KINDS:
		var venue := world.venues.get(kind) as VenueInterior
		if venue == null or not venue.contains_player(player.global_position):
			continue
		if Time.get_ticks_msec() < int(holdup_cooldowns.get(kind, 0)):
			return null
		var to_counter := venue.service_point - player.global_position
		if to_counter.length() < 11.0 and forward.normalized().dot(to_counter.normalized()) > 0.75:
			return venue
	return null


func holdup_text() -> String:
	if holdup_progress <= 0.0:
		return ""
	return "ATRACO " + "■".repeat(int(holdup_progress / HOLDUP_SECONDS * 10.0)) + "□".repeat(10 - int(holdup_progress / HOLDUP_SECONDS * 10.0))


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
	var body: Node3D = null if str(spec["weapon"]) in SUPPLIES else weapon_model(str(spec["weapon"]))
	if str(spec["weapon"]) in SUPPLIES:
		body = _supply_model(str(spec["weapon"]))
	elif body == null:  # the bat: a simple turned-wood shape
		var bat := MeshInstance3D.new()
		var shape := CylinderMesh.new()
		shape.top_radius = 0.035
		shape.bottom_radius = 0.018
		shape.height = 0.85
		bat.mesh = shape
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color("b98a55")
		bat.material_override = wood
		bat.rotation.z = PI * 0.5
		body = Node3D.new()
		body.add_child(bat)
	body.scale = Vector3.ONE * (1.8 if str(spec["weapon"]) in ["pistol"] else 1.2)
	body.position.y = 0.9
	node.add_child(body)
	node.move_child(body, 0)
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
	label.text = {"armor": "CHALECO", "health": "BOTIQUÍN", "grenade": "GRANADAS", "molotov": "MOLOTOV"}.get(str(spec["weapon"]), str(defs.get(str(spec["weapon"]), {}).get("name", spec["weapon"])).to_upper())
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.outline_size = 10
	label.pixel_size = 0.006
	label.position.y = 1.6
	label.modulate = Color("f2c14e")
	label.visibility_range_end = 45.0
	node.add_child(label)
	pickups.append({"weapon": str(spec["weapon"]), "ammo": int(spec.get("ammo", 0)), "node": node, "respawn_s": float(spec.get("respawn_s", 90.0)), "timer": 0.0})


## Vest (navy block with a front plate) or first-aid kit (white box, red cross);
## grenades are an olive crate, Molotovs a bottle with a rag.
func _supply_model(kind: String) -> Node3D:
	var root := Node3D.new()
	if kind == "grenade" or kind == "molotov":
		var item := MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		if kind == "grenade":
			var egg := SphereMesh.new()
			egg.radius = 0.12
			egg.height = 0.28
			item.mesh = egg
			mat.albedo_color = Color("4a5a36")
		else:
			var bottle := CylinderMesh.new()
			bottle.top_radius = 0.04
			bottle.bottom_radius = 0.08
			bottle.height = 0.4
			item.mesh = bottle
			mat.albedo_color = Color("5f8a4a")
		item.material_override = mat
		root.add_child(item)
		return root
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 0.6, 0.18) if kind == "armor" else Vector3(0.45, 0.32, 0.2)
	box.mesh = mesh
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("27406a") if kind == "armor" else Color("f2f2ee")
	box.material_override = paint
	root.add_child(box)
	var mark_colour := Color("c9d3df") if kind == "armor" else Color("d0302a")
	var sizes: Array = [Vector3(0.34, 0.24, 0.02)] if kind == "armor" else [Vector3(0.22, 0.07, 0.02), Vector3(0.07, 0.22, 0.02)]
	for size in sizes:
		var mark := MeshInstance3D.new()
		var plate := BoxMesh.new()
		plate.size = size
		mark.mesh = plate
		var mat := StandardMaterial3D.new()
		mat.albedo_color = mark_colour
		mark.material_override = mat
		mark.position = Vector3(0, 0.02 if kind == "armor" else 0.0, 0.1)
		root.add_child(mark)
	return root


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
			var kind := str(pickup["weapon"])
			if kind == "grenade" or kind == "molotov":
				var thrown := get_tree().get_first_node_in_group("throwables")
				if thrown == null or int(thrown.get("counts")[kind]) >= 10:
					continue
				node.visible = false
				pickup["timer"] = float(pickup["respawn_s"])
				thrown.call("add", kind, int(pickup["ammo"]))
				_play("reload")
				get_tree().call_group("mission_controller", "_show_dialogue", "Has cogido: %d %s (G para lanzar, H para cambiar)" % [int(pickup["ammo"]), "granadas" if kind == "grenade" else "cócteles molotov"])
				continue
			if kind == "armor" or kind == "health":
				# Like any open-world pickup: left in place if you do not need it.
				if (kind == "armor" and player.armor >= PlayerController.MAX_ARMOR) or (kind == "health" and player.health >= PlayerController.MAX_HEALTH):
					continue
				node.visible = false
				pickup["timer"] = float(pickup["respawn_s"])
				if kind == "armor":
					player.armor = PlayerController.MAX_ARMOR
				else:
					player.heal(PlayerController.MAX_HEALTH)
				_play("reload")
				get_tree().call_group("mission_controller", "_show_dialogue", "Chaleco antibalas puesto." if kind == "armor" else "Botiquín: salud recuperada.")
				continue
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
