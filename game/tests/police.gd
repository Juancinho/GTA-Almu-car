extends SceneTree

## Wanted levels 1–5: reinforcements per star, officers leaving their car near a
## player on foot, officers shooting back, attacking police raising the level,
## and the Taller Poniente respray clearing it.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	for i in range(10):
		await physics_frame
	var world := root.get_node("District_Altillo") as SectorWorld
	var player := root.get_node("Player") as PlayerController
	var wanted := root.get_node("WantedSystem") as WantedSystem
	var weapons := root.get_node("Weapons") as WeaponSystem
	wanted.report_police_attack(player.global_position)
	if wanted.level != 3 or wanted.police_cars.is_empty():
		return _fail("attacking the police should give three stars (got %d)" % wanted.level)
	for i in range(60 * 11):
		await physics_frame
	var active := wanted.police_cars.filter(func(c: DriveableVehicle) -> bool: return is_instance_valid(c)).size()
	if active < 3:
		return _fail("three stars should bring three patrol cars (got %d)" % active)
	# Bring a patrol right next to the player standing still.
	var car := wanted.police_cars[0]
	car.global_position = player.global_position + Vector3(8, 0.5, 0)
	car.speed = 0.0
	for i in range(20):
		await physics_frame
	if wanted.officers.is_empty():
		return _fail("no officers left the car next to a player on foot")
	var health_before := player.health
	for i in range(60 * 8):
		await physics_frame
		if player.dead or player.health < health_before:
			break
	if player.health >= health_before and not player.dead:
		return _fail("officers did not shoot at a three-star player")
	player.heal_full()
	if wanted.officers.is_empty():
		return _fail("officers vanished")
	var officer := wanted.officers[0] as PoliceOfficer
	officer.take_damage(200.0, player.global_position)
	if not officer.dead or wanted.level < 4:
		return _fail("killing an officer should raise the level (level %d)" % wanted.level)
	# Respray: in a car at the workshop, out of sight, with money.
	wanted.level = 2
	wanted.phase = "search"
	root.set("money", 200)
	var first := world.get_node("FirstCar") as DriveableVehicle
	player.global_position = first.global_position + first.global_transform.basis.x * 2.2
	player._interact()
	for c in wanted.police_cars:
		if is_instance_valid(c):
			c.global_position += Vector3(0, 0, 400)  # far away, out of sight
	first.global_position = world.workshop.exterior_entry + Vector3(0, 0.6, 0)
	wanted.phase = "search"
	for i in range(3):
		await physics_frame
	if wanted.level != 0 or int(root.get("money")) != 50:
		return _fail("respray did not clear the wanted level (level %d money %d)" % [wanted.level, int(root.get("money"))])
	print("POLICE PASS: 3-star reinforcements, officers deploy and shoot, officer kill -> %d+ stars, respray clears" % 4)
	root.queue_free()
	await process_frame
	quit(0)


func _fail(reason: String) -> void:
	push_error("POLICE FAIL: " + reason)
	quit(1)
