class_name Pedestrian
extends CharacterBody3D

enum State { IDLE, WANDER, FLEE, DOWN, FIGHT }

const FAR_STEP_M := 45.0
var lod_tick := randi() % 3
var display_name := "Vecina"
var mission_contact := false
var shirt_color := Color("b77f62")
var state := State.WANDER
var home := Vector3.ZERO
var destination := Vector3.ZERO
var think_timer := 0.0
var rng := RandomNumberGenerator.new()
var player: PlayerController
var human: HumanModel
var model_name := ""
var collider: CollisionShape3D
var down_timer := 0.0
var knocked_from := Vector3.ZERO
var temperament := 0.0
var conversation_count := 0
var conversation_timer := 0.0
var fight_timer := 0.0
var strike_timer := 0.0
var provoked_by_player := false
## Mission enemies attack on sight, take several punches and never give up until beaten.
var enemy := false
var toughness := 3  # punches before going down
var hits := 0
var defeated := false
var health := 100.0
var armed := false  # mission gunmen keep their distance and shoot
var gun_timer := 1.5
var air_speed := 0.0  # vertical speed while thrown by a car or an explosion
var dead := false
var activity := ""
var outfit := ""
var activity_phase := 0.0
var firearm: NpcFirearm
const AmbientPose = preload("res://scripts/ambient_pose.gd")


func _ready() -> void:
	add_to_group("pedestrians")
	if mission_contact:
		add_to_group("mission_contacts")
	home = global_position
	destination = home
	rng.seed = int(absf(home.x * 237.0 + home.z * 83.0)) + 91
	temperament = rng.randf()
	_build_visual()


func _build_visual() -> void:
	collider = CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.7
	collider.shape = shape
	collider.position.y = 0.85
	add_child(collider)
	if model_name == "":
		model_name = HumanModel.model_for_seed(rng.seed)
	human = HumanModel.new(model_name)
	human.outfit = outfit
	human.name = "Human"
	add_child(human)
	if activity == "skate":
		AmbientPose.skates(human)
		human.position.y = 0.09


func _physics_process(delta: float) -> void:
	if player == null:
		var people := get_tree().get_nodes_in_group("player")
		if not people.is_empty():
			player = people[0] as PlayerController
	var far := player != null and global_position.distance_squared_to(player.global_position) > HumanModel.ANIMATION_RANGE * HumanModel.ANIMATION_RANGE
	var visible_nearby := not far and is_visible_in_tree()
	human.set_animation_active(visible_nearby)
	if activity in ["work", "dance"] and state in [State.IDLE, State.WANDER] and not visible_nearby:
		return
	if player != null and global_position.distance_squared_to(player.global_position) > 90.0 * 90.0:
		return
	if armed and firearm == null:
		equip_firearm()
	if state == State.DOWN:
		_update_down(delta)
		return
	if mission_contact:
		velocity = Vector3.ZERO
		human.update_motion(0.0)
		return
	conversation_timer = maxf(0.0, conversation_timer - delta)
	if conversation_timer <= 0.0:
		conversation_count = 0
	if state == State.FIGHT:
		human.clear_swim_pose()
		_fight(delta)
		return
	if state == State.FLEE or state == State.DOWN:
		human.clear_swim_pose()
	elif activity in ["work", "dance"]:
		velocity = Vector3(0, -3.0, 0)
		move_and_slide()
		activity_phase += delta * (4.0 if activity == "dance" else 1.6)
		AmbientPose.update(human, activity, activity_phase)
		return
	# Far strollers move at a third of the tick rate with three ticks' worth of
	# motion each time: ~90 civilians were the biggest physics cost, and at that
	# distance the interpolated walk still reads smoothly.
	if state != State.FLEE and player != null and global_position.distance_squared_to(player.global_position) > FAR_STEP_M * FAR_STEP_M:
		lod_tick = (lod_tick + 1) % 3
		if lod_tick != 0:
			return
		delta *= 3.0
	think_timer -= delta
	if think_timer <= 0.0:
		think_timer = rng.randf_range(2.5, 5.0)
		if state == State.FLEE:
			state = State.WANDER
		elif state == State.WANDER:
			destination = home + Vector3(rng.randf_range(-9.0, 9.0), 0, rng.randf_range(-4.0, 4.0))
	var offset := destination - global_position
	offset.y = 0
	if offset.length() > 0.7:
		var direction := offset.normalized()
		var pace := 5.0 if state == State.FLEE else 3.2 if activity == "skate" else 1.3
		velocity.x = direction.x * pace
		velocity.z = direction.z * pace
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(1.0, 6.0 * delta))
	else:
		velocity.x = 0
		velocity.z = 0
	velocity.y = -3.0
	if is_on_wall():
		CharacterStep.climb(self, Vector3(velocity.x,0,velocity.z) * delta, 0.42)
	move_and_slide()
	human.update_motion(Vector2(velocity.x, velocity.z).length())
	if activity == "skate":
		if state != State.FLEE:
			activity_phase += delta * 3.0
			AmbientPose.update(human, activity, activity_phase)
		AmbientPose.place_skates(human)


func equip_firearm() -> void:
	if firearm != null:
		return
	firearm = NpcFirearm.new()
	firearm.name = "HeldFirearm"
	firearm.actor = self
	add_child(firearm)


func flee_from(location: Vector3) -> void:
	if state == State.DOWN:
		return
	state = State.FLEE
	var away := global_position - location
	away.y = 0
	destination = global_position + away.normalized() * 15.0
	think_timer = 4.0


func speak() -> String:
	if state == State.DOWN:
		return ""
	conversation_count = conversation_count + 1 if conversation_timer > 0.0 else 1
	conversation_timer = 8.0
	if enemy:
		return "¡Lárgate de aquí!"
	if state == State.FIGHT:
		return "¡Déjame en paz!"
	if temperament > 0.72 and conversation_count >= 3:
		state = State.FIGHT
		fight_timer = 12.0
		return "Te he dicho que me dejes tranquilo."
	if temperament > 0.72:
		return "Ahora mismo no tengo ganas de hablar."
	if temperament > 0.35:
		return "Buenas. El paseo está animado hoy."
	return "Hola. Si buscas el centro, sigue hacia Calle Real."


func start_fight(seconds: float) -> void:
	if state == State.DOWN:
		return
	state = State.FIGHT
	fight_timer = seconds
	strike_timer = 0.8


func _armed_fight(delta: float) -> void:
	var target := player.driving_vehicle.global_position if player.driving_vehicle != null else player.global_position
	var offset := target - global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance > 9.0:
		var direction := offset / maxf(distance, 0.01)
		velocity = Vector3(direction.x * 4.5, -3.0, direction.z * 4.5)
		move_and_slide()
		human.update_motion(4.5)
	else:
		velocity = Vector3.ZERO
		human.update_motion(0.0)
	rotation.y = lerp_angle(rotation.y, atan2(-offset.x, -offset.z), minf(1.0, 10.0 * delta))
	gun_timer -= delta
	if gun_timer > 0.0 or distance > 45.0:
		return
	gun_timer = rng.randf_range(1.1, 1.8)
	human.hold_pose("punch", 0.26)
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.5, target + Vector3.UP * 1.1)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not (hit.is_empty() or hit.get("collider") is BreakableGlass or hit.get("collider") == player or hit.get("collider") == player.driving_vehicle):
		return
	var moving := Vector2(player.velocity.x, player.velocity.z).length() if player.driving_vehicle == null else absf(player.driving_vehicle.speed)
	get_tree().call_group("weapon_system", "fire_remote", self, target + Vector3.UP * 1.1,
		6.0, 30.0, 0.008 + distance * 0.0005 + moving * 0.001, rng, "gunman")


## Weapon damage. Heavy hits knock people down; at zero health they stay down.
func take_damage(amount: float, from: Vector3, by_player: bool = true) -> void:
	if mission_contact or dead:
		return
	health -= amount
	provoked_by_player = by_player
	if health <= 0.0:
		die(from)
	elif amount >= 40.0 or (enemy and not armed):
		if state == State.DOWN:
			return
		knock_down(from, 3.0)
	elif armed and enemy:
		start_fight(18.0)
	elif by_player and temperament > 0.78 and amount < 30.0:
		start_fight(18.0)
	else:
		flee_from(from)


func die(from: Vector3) -> void:
	if dead:
		return
	if state != State.DOWN:
		knock_down(from, 4.0)
	dead = true
	defeated = true
	health = 0.0
	down_timer = INF
	remove_from_group("mission_contacts")
	get_tree().create_timer(1.2, false).timeout.connect(_blood_pool)
	get_tree().create_timer(45.0, false).timeout.connect(queue_free)


## A small dark pool that spreads under the body (stylised, not gory).
func _blood_pool() -> void:
	if not is_inside_tree():
		return
	var pool := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.01
	disc.radial_segments = 14
	pool.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.02, 0.03)
	mat.roughness = 0.15
	pool.material_override = mat
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pool)
	pool.position = Vector3(0, 0.02, 0)
	pool.top_level = true
	pool.global_position = global_position + Vector3(0, 0.02, 0) + global_transform.basis.z * 0.3
	pool.scale = Vector3(0.2, 1.0, 0.25)
	var grow := create_tween()
	grow.tween_property(pool, "scale", Vector3(1.5, 1.0, 1.2), 5.0).set_ease(Tween.EASE_OUT)


## A punch from the player: tough (mission) people stagger before going down.
func take_hit(from: Vector3, impulse: float) -> void:
	if state == State.DOWN or mission_contact:
		return
	hits += 1
	health -= 16.0
	var away := global_position - from
	away.y = 0.0
	if away.length() > 0.01:
		velocity = away.normalized() * 2.2
		global_position += away.normalized() * 0.3
	if health <= 0.0:
		die(from)
		return
	if hits >= toughness:
		hits = 0
		knock_down(from, impulse)
		return
	human.play_action("punch", 0.3)  # reels back, then answers or runs
	if enemy or temperament > 0.5:
		if state != State.FIGHT:
			start_fight(18.0)
	else:
		flee_from(from)


func _fight(delta: float) -> void:
	if armed and player != null and not player.dead:
		_armed_fight(delta)
		return
	if enemy and player != null and not player.dead and player.driving_vehicle != null:
		velocity = Vector3.ZERO
		human.update_motion(0.0)
		return
	if player == null or player.dead or player.driving_vehicle != null:
		state = State.FLEE
		think_timer = 4.0
		return
	fight_timer -= delta
	strike_timer = maxf(0.0, strike_timer - delta)
	if fight_timer <= 0.0:
		flee_from(player.global_position)
		return
	var offset := player.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance > 1.5:
		var direction := offset.normalized()
		velocity = Vector3(direction.x * 3.2, -3.0, direction.z * 3.2)
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(1.0, 8.0 * delta))
		if is_on_wall():
			CharacterStep.climb(self, Vector3(velocity.x,0,velocity.z) * delta, 0.42)
		move_and_slide()
		human.update_motion(3.2)
	elif strike_timer <= 0.0:
		velocity = Vector3.ZERO
		strike_timer = 1.4
		human.play_action("punch", 0.55)
		var probe := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, player.global_position + Vector3.UP)
		probe.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(probe)
		if hit.is_empty() or hit.get("collider") == player:
			player.take_damage(7.0, "civilian_fight")


## Hit by a car or punched: slide back, lie on the ground, then get up and flee.
func knock_down(from: Vector3, impulse: float) -> void:
	if state == State.DOWN or mission_contact:
		return
	state = State.DOWN
	defeated = true
	down_timer = 7.0
	knocked_from = from
	var away := global_position - from
	away.y = 0.0
	velocity = (away.normalized() if away.length() > 0.01 else Vector3.FORWARD) * minf(impulse, 9.0)
	# Hard hits (cars, explosions) throw the body up; it arcs and lands on the real ground.
	air_speed = clampf((impulse - 6.0) * 0.45, 0.0, 6.5)
	collider.set_deferred("disabled", true)
	human.play_action("death", 7.0)
	for node in get_tree().get_nodes_in_group("pedestrians"):
		var other := node as Pedestrian
		if other != null and other != self and not other.mission_contact and other.state != State.DOWN and other.global_position.distance_to(global_position) < 18.0:
			other.flee_from(global_position)


## Keeps a fallen body on the actual surface (terrain, road, steps, promenade):
## no floating over slopes and no sinking through them.
func _settle_on_ground(delta: float) -> void:
	var from := global_position + Vector3.UP * 1.2
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var ground: float = (hit["position"] as Vector3).y
	if air_speed != 0.0 or global_position.y > ground + 0.05:
		air_speed -= 16.0 * delta
		global_position.y += air_speed * delta
		if global_position.y <= ground:
			global_position.y = ground
			air_speed = 0.0
			velocity *= 0.35  # the landing kills most of the slide
	else:
		global_position.y = ground


func _update_down(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
	var slide := Vector3(velocity.x, 0.0, velocity.z) * delta
	if slide.length() > 0.001:
		var probe := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.5, global_position + Vector3.UP * 0.5 + slide.normalized() * (slide.length() + 0.4))
		probe.exclude = [get_rid()]
		if get_world_3d().direct_space_state.intersect_ray(probe).is_empty():
			global_position += slide  # never slide through walls, cars or palms
		else:
			velocity = Vector3.ZERO
	_settle_on_ground(delta)
	if dead:
		human.action_timer = 1.0  # stay in the final pose
		return
	down_timer -= delta
	if down_timer <= 0.0:
		collider.set_deferred("disabled", false)
		human.action_timer = 0.0
		if provoked_by_player and temperament > 0.55:
			state = State.FIGHT
			fight_timer = 18.0
			strike_timer = 0.8
		else:
			state = State.WANDER
			flee_from(knocked_from)
		provoked_by_player = false
