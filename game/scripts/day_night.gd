class_name DayNightCycle
extends Node

## 24-hour cycle (one game day = 48 real minutes by default). The sun rises in the
## east over the Peñón, crosses the south above the sea and sets in the west; at
## night a pale moon takes over, windows light up, street lamps glow and a small
## pool of real lights follows the player through the nearest lamps.

const DAY_MINUTES := 48.0  # real minutes per game day
const LAMP_LIGHTS := 6
const SUNRISE := 7.0
const SUNSET := 21.0

var world: SectorWorld
var player: PlayerController
var hours := 16.5
var paused_clock := false
var sky: ProceduralSkyMaterial
var env: Environment
var lamp_positions := PackedVector3Array()
var lamp_lights: Array[OmniLight3D] = []
var lamp_timer := 0.0
var lamp_material: StandardMaterial3D
var night := 0.0  # 0 day … 1 full night


func configure(target_world: SectorWorld, target_player: PlayerController) -> void:
	world = target_world
	player = target_player
	env = world.environment_node.environment
	sky = env.sky.sky_material as ProceduralSkyMaterial
	lamp_positions = world.get_meta("lamp_positions", PackedVector3Array())
	lamp_material = world.mats.cache.get("lamp_head") as StandardMaterial3D
	for i in range(LAMP_LIGHTS):
		var light := OmniLight3D.new()
		light.name = "StreetLamp_%d" % i
		light.light_color = Color("ffc98a")
		light.omni_range = 13.0
		light.omni_attenuation = 1.4
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.visible = false
		world.add_child(light)
		lamp_lights.append(light)
	apply()


func clock_text() -> String:
	var minutes := int(hours * 60.0) % (24 * 60)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func _process(delta: float) -> void:
	if world == null:
		return
	if not paused_clock:
		hours = fmod(hours + delta * 24.0 / (DAY_MINUTES * 60.0), 24.0)
	apply()
	lamp_timer -= delta
	if lamp_timer <= 0.0:
		lamp_timer = 0.5
		_place_lamp_lights()


## Sun/moon direction and colour, sky, fog, ambient, window glow and lamps.
func apply() -> void:
	# Costa Tropical summer: sunrise about 07:00 in the east, sunset about 21:00 in the west.
	var t := (hours - SUNRISE) / (SUNSET - SUNRISE)
	var a := deg_to_rad((t - 0.5) * 180.0)
	var elevation := sin(t * PI) * deg_to_rad(64.0)
	if t < 0.0 or t > 1.0:
		var dark := fposmod(hours - SUNSET, 24.0) / (24.0 - SUNSET + SUNRISE)
		elevation = -sin(dark * PI) * deg_to_rad(40.0)
	var is_day := elevation > deg_to_rad(-4.0)
	var e := elevation if is_day else -elevation * 0.6 + deg_to_rad(25.0)  # the moon rides opposite
	var az := a if is_day else a + PI
	var from := Vector3(-sin(az) * cos(e), sin(e), cos(az) * cos(e))
	var sun := world.sun_light
	sun.look_at_from_position(from * 100.0, Vector3.ZERO, Vector3.UP if absf(from.y) < 0.98 else Vector3.FORWARD)
	var height := clampf(elevation / deg_to_rad(25.0), 0.0, 1.0)  # 0 at the horizon, 1 in daylight
	night = clampf(1.0 - (elevation + deg_to_rad(8.0)) / deg_to_rad(14.0), 0.0, 1.0)
	var dusk := clampf(1.0 - absf(elevation) / deg_to_rad(14.0), 0.0, 1.0)  # golden hour
	if is_day:
		sun.light_color = Color("ffe3bd").lerp(Color("ff9a55"), dusk * 0.8)
		sun.light_energy = lerpf(0.15, 1.25, height)
		sun.shadow_enabled = player != null and height > 0.05 and _shadows_allowed()
	else:
		sun.light_color = Color("9fb4d8")
		sun.light_energy = 0.18
		sun.shadow_enabled = false
	var day_top := Color("3f78b0")
	var day_horizon := Color("c4d6da")
	var dusk_top := Color("2d4570")
	var dusk_horizon := Color("f0a36b")
	var night_top := Color("070b18")
	var night_horizon := Color("1c2438")
	var top := day_top.lerp(dusk_top, dusk).lerp(night_top, night)
	var horizon := day_horizon.lerp(dusk_horizon, dusk * (1.0 - night)).lerp(night_horizon, night)
	sky.sky_top_color = top
	sky.sky_horizon_color = horizon
	sky.ground_horizon_color = horizon.darkened(0.1)
	sky.ground_bottom_color = Color("56707a").lerp(Color("0b1018"), night)
	env.ambient_light_energy = lerpf(0.75, 0.22, night)
	env.ambient_light_color = Color("e3d8c6").lerp(Color("6f82a8"), night)
	env.fog_light_color = Color("bfd0da").lerp(Color("e8a878"), dusk * 0.5 * (1.0 - night)).lerp(Color("141a28"), night)
	var facade := world.mats.facade_detail()
	facade.set_shader_parameter("night_glow", night * 1.6)
	if lamp_material != null:
		lamp_material.emission_enabled = night > 0.05
		lamp_material.emission = Color("ffd29a")
		lamp_material.emission_energy_multiplier = night * 3.0


func _shadows_allowed() -> bool:
	var main := world.get_parent()
	return main == null or not ("quality_level" in main) or int(main.quality_level) >= 1


## The few real lights follow the lamps nearest to the player.
func _place_lamp_lights() -> void:
	if player == null or lamp_positions.is_empty():
		return
	var on := night > 0.3
	var here := player.global_position
	var nearest: Array = []
	if on:
		for p in lamp_positions:
			var d := p.distance_squared_to(here)
			if d < 90.0 * 90.0:
				nearest.append([d, p])
		nearest.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for i in range(lamp_lights.size()):
		var light := lamp_lights[i]
		light.visible = on and i < nearest.size()
		if light.visible:
			light.global_position = (nearest[i][1] as Vector3) + Vector3(0, 5.6, 0)
			light.light_energy = 2.2 * night


var _car_timer := 0.0


func _physics_process(delta: float) -> void:
	_car_timer -= delta
	if _car_timer > 0.0 or world == null:
		return
	_car_timer = 1.0
	var on := night > 0.35
	for node in get_tree().get_nodes_in_group("vehicles"):
		(node as DriveableVehicle).set_headlights(on)
