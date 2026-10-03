extends Node3D

const AudioUtil = preload("res://scripts/audio_util.gd")

## Weather on the Costa Tropical: mostly clear, sometimes a grey sky, and now and
## then a rain shower. Clouds dim the sun and haze the distance (DayNight reads
## `overcast`), rain falls around the camera with its own sound, the roads get
## dark and glossy while wet and dry slowly afterwards, and wet asphalt gives
## cars less grip (DriveableVehicle.wet_grip). Storms add wind-driven rain,
## lightning and thunder; the levante is a dry, gusty east wind (louder wind,
## slanted rain if it rains). In the rain most strollers and all bathers go
## home: they fade out of sight far from the camera and come back when it dries.

const SPELL_MIN := 240.0
const SPELL_MAX := 540.0
const STATES := {"clear": 0.0, "cloudy": 0.55, "rain": 1.0, "storm": 1.0, "levante": 0.25}
const WIND := {"clear": 0.06, "cloudy": 0.1, "rain": 0.12, "storm": 0.5, "levante": 0.42}
const SHELTER_DISTANCE := 35.0

var player: PlayerController
var day_night: Node
var world: SectorWorld
var state := "clear"
var overcast := 0.0
var wet := 0.0
var timer := SPELL_MIN
var rng := RandomNumberGenerator.new()
var rain: CPUParticles3D
var rain_audio: AudioStreamPlayer
var _asphalt: StandardMaterial3D
var _asphalt_color := Color.WHITE
var _paving: StandardMaterial3D
var _paving_roughness := 0.9
var _paving_color := Color.WHITE
var wind := 0.06
var lightning: DirectionalLight3D
var thunder_audio: AudioStreamPlayer
var flash := 0.0
var _flash_time := -1.0
var _next_strike := 8.0
var _thunder_in := -1.0
var strikes := 0
var sheltered: Dictionary = {}  # Pedestrian -> previous collision layer
var _shelter_timer := 0.0
var _ambience: AudioStreamPlayer
var _ambience_db := -11.0


func configure(target_player: PlayerController, target_day_night: Node, target_world: SectorWorld) -> void:
	player = target_player
	day_night = target_day_night
	world = target_world
	rng.seed = 7311
	_asphalt = world.mats.road_asphalt()
	_asphalt_color = _asphalt.albedo_color
	_paving = world.mats.cache.get("lane_paving") as StandardMaterial3D
	if _paving != null:
		_paving_roughness = _paving.roughness
		_paving_color = _paving.albedo_color
	rain = CPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = 1400
	rain.lifetime = 0.8
	rain.emitting = false
	rain.local_coords = false
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(15, 1, 15)
	rain.direction = Vector3(0.08, -1, 0.04)
	rain.spread = 2.0
	rain.gravity = Vector3(0, -9.0, 0)
	rain.initial_velocity_min = 16.0
	rain.initial_velocity_max = 20.0
	var streak := QuadMesh.new()
	streak.size = Vector2(0.022, 0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.84, 0.9, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	streak.material = mat
	rain.mesh = streak
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)
	rain_audio = AudioStreamPlayer.new()
	rain_audio.name = "RainAudio"
	rain_audio.bus = "Ambience"
	rain_audio.stream = AudioUtil.stream("res://assets/audio/rain_loop.wav")
	if rain_audio.stream is AudioStreamWAV:
		(rain_audio.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(rain_audio.stream as AudioStreamWAV).loop_end = int((rain_audio.stream as AudioStreamWAV).get_length() * (rain_audio.stream as AudioStreamWAV).mix_rate)
	rain_audio.volume_db = -60.0
	add_child(rain_audio)
	lightning = DirectionalLight3D.new()
	lightning.name = "Lightning"
	lightning.light_color = Color("dfe6ff")
	lightning.light_energy = 0.0
	lightning.shadow_enabled = false
	lightning.visible = false
	lightning.rotation = Vector3(deg_to_rad(-70.0), deg_to_rad(30.0), 0.0)
	add_child(lightning)
	thunder_audio = AudioStreamPlayer.new()
	thunder_audio.name = "Thunder"
	thunder_audio.bus = "Ambience"
	thunder_audio.stream = AudioUtil.stream("res://assets/audio/thunder.wav")
	add_child(thunder_audio)


## Change the weather; `instant` skips the gradual change (tests, loading).
func set_weather(kind: String, instant: bool = false) -> void:
	if not STATES.has(kind):
		return
	var heavy := kind == "storm"
	if heavy != (state == "storm"):
		rain.amount = 2400 if heavy else 1400  # restarts the emitter: only on change
	state = kind
	timer = rng.randf_range(SPELL_MIN, SPELL_MAX) * (0.5 if kind == "storm" else 1.0)
	_next_strike = rng.randf_range(4.0, 9.0)
	if instant:
		overcast = STATES[kind]
		wind = WIND[kind]
		if kind == "rain" or kind == "storm":
			wet = 1.0


func _process(delta: float) -> void:
	if player == null:
		return
	if get_tree().current_scene != null:  # random spells only in the real game
		timer -= delta
		if timer <= 0.0:
			var roll := rng.randf()
			set_weather("storm" if roll < 0.05 else "rain" if roll < 0.17 else "levante" if roll < 0.27 else "cloudy" if roll < 0.47 else "clear")
	overcast = move_toward(overcast, float(STATES[state]), delta / 25.0)
	wind = move_toward(wind, float(WIND[state]), delta / 20.0)
	var raining := (state == "rain" or state == "storm") and overcast > 0.75
	wet = move_toward(wet, 1.0 if raining else 0.0, delta / (30.0 if raining else 150.0))
	day_night.set("overcast", overcast)
	var camera := player.camera
	if camera != null:
		rain.global_position = camera.global_position + Vector3(0, 11.0, 0) - camera.global_transform.basis.z * 6.0
	var indoors := bool(player.get("interior_camera"))  # under a roof: no rain on screen
	rain.emitting = raining and not indoors
	rain.direction = Vector3(wind, -1.0, wind * 0.4)
	_update_audio(delta, raining and not indoors)
	_update_wind_audio(delta)
	_update_lightning(delta)
	_apply_wet()
	DriveableVehicle.wet_grip = 1.0 - 0.3 * wet
	_shelter_timer -= delta
	if _shelter_timer <= 0.0:
		_shelter_timer = 2.0
		_update_shelter(raining and wet > 0.3)


## Storm lightning: two quick flashes light the whole town, thunder follows
## after a delay (distance) at a random loudness.
func _update_lightning(delta: float) -> void:
	if state == "storm" and overcast > 0.8:
		_next_strike -= delta
		if _next_strike <= 0.0:
			strike()
	if _flash_time >= 0.0:
		var first := _flash_time == 0.0
		_flash_time += minf(delta, 0.05)  # slow frames still show both flashes
		var t := _flash_time
		flash = 1.0 if first else maxf(0.0, 1.0 - t / 0.08) + (maxf(0.0, 0.7 - absf(t - 0.18) / 0.06) if t > 0.12 else 0.0)
		if t > 0.35:
			_flash_time = -1.0
			flash = 0.0
	lightning.visible = flash > 0.01
	lightning.light_energy = flash * 3.5
	day_night.set("flash", flash)
	if _thunder_in >= 0.0:
		_thunder_in -= delta
		if _thunder_in < 0.0 and DisplayServer.get_name() != "headless" and thunder_audio.stream != null:
			thunder_audio.volume_db = rng.randf_range(-10.0, 0.0)
			thunder_audio.pitch_scale = rng.randf_range(0.8, 1.1)
			thunder_audio.play()


func strike() -> void:
	_next_strike = rng.randf_range(6.0, 16.0)
	_flash_time = 0.0
	_thunder_in = rng.randf_range(0.6, 3.0)
	strikes += 1


func _update_wind_audio(delta: float) -> void:
	if _ambience == null:
		_ambience = get_parent().get_node_or_null("SeaWindAmbience") as AudioStreamPlayer
		if _ambience == null:
			return
		_ambience_db = _ambience.volume_db
	_ambience.volume_db = move_toward(_ambience.volume_db, _ambience_db + 14.0 * clampf((wind - 0.1) / 0.4, 0.0, 1.0), delta * 4.0)


## In the rain bathers and most strollers leave; they disappear (and reappear
## when it dries) only while out of the camera's close range, so nobody pops.
func _update_shelter(raining: bool) -> void:
	var eye := player.camera.global_position if player.camera != null else player.global_position
	if raining:
		for node in get_tree().get_nodes_in_group("pedestrians"):
			var person := node as Pedestrian
			if person == null or sheltered.has(person) or not _shelters(person):
				continue
			if person.global_position.distance_to(eye) < SHELTER_DISTANCE:
				continue
			sheltered[person] = person.collision_layer
			person.visible = false
			person.process_mode = Node.PROCESS_MODE_DISABLED
			person.collision_layer = 0
	else:
		for person in sheltered.keys():
			if not is_instance_valid(person):
				sheltered.erase(person)
				continue
			if (person as Node3D).global_position.distance_to(eye) < SHELTER_DISTANCE:
				continue
			(person as Pedestrian).visible = true
			(person as Pedestrian).process_mode = Node.PROCESS_MODE_INHERIT
			(person as Pedestrian).collision_layer = int(sheltered[person])
			sheltered.erase(person)


func _shelters(person: Pedestrian) -> bool:
	if person is PoliceOfficer or person.mission_contact or person.enemy or person.armed or person.dead:
		return false
	if person.state != Pedestrian.State.WANDER and person.state != Pedestrian.State.IDLE:
		return false
	if person.outfit == "adult_swimwear":
		return true  # bathers leave the beach
	if person.activity in ["work", "dance"]:
		return false  # under awnings or indoors already
	return person.get_instance_id() % 3 != 0  # two in three strollers go home


func _update_audio(delta: float, on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var target := -12.0 if on else -60.0
	rain_audio.volume_db = move_toward(rain_audio.volume_db, target, delta * 15.0)
	if rain_audio.volume_db > -59.0 and not rain_audio.playing:
		rain_audio.play()
	elif rain_audio.volume_db <= -59.0 and rain_audio.playing:
		rain_audio.stop()


## Wet asphalt and paving: darker and glossy.
func _apply_wet() -> void:
	_asphalt.roughness = lerpf(0.94, 0.38, wet)
	_asphalt.albedo_color = _asphalt_color.lerp(_asphalt_color * Color(0.62, 0.64, 0.68), wet)
	if _paving != null:
		_paving.roughness = lerpf(_paving_roughness, 0.45, wet)
		_paving.albedo_color = _paving_color.lerp(_paving_color * Color(0.7, 0.7, 0.74), wet)


func shelter_count() -> int:
	return sheltered.size()


func to_save() -> Dictionary:
	return {"state": state, "wet": wet}


func from_save(value: Dictionary) -> void:
	set_weather(str(value.get("state", "clear")), true)
	wet = clampf(float(value.get("wet", wet)), 0.0, 1.0)
