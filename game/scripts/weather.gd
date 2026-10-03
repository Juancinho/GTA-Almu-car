extends Node3D

## Weather on the Costa Tropical: mostly clear, sometimes a grey sky, and now and
## then a rain shower. Clouds dim the sun and haze the distance (DayNight reads
## `overcast`), rain falls around the camera with its own sound, the roads get
## dark and glossy while wet and dry slowly afterwards, and wet asphalt gives
## cars less grip (DriveableVehicle.wet_grip).

const SPELL_MIN := 240.0
const SPELL_MAX := 540.0
const STATES := {"clear": 0.0, "cloudy": 0.55, "rain": 1.0}

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
	rain_audio.stream = load("res://assets/audio/rain_loop.wav") as AudioStream
	if rain_audio.stream is AudioStreamWAV:
		(rain_audio.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(rain_audio.stream as AudioStreamWAV).loop_end = int((rain_audio.stream as AudioStreamWAV).get_length() * (rain_audio.stream as AudioStreamWAV).mix_rate)
	rain_audio.volume_db = -60.0
	add_child(rain_audio)


## Change the weather; `instant` skips the gradual change (tests, loading).
func set_weather(kind: String, instant: bool = false) -> void:
	if not STATES.has(kind):
		return
	state = kind
	timer = rng.randf_range(SPELL_MIN, SPELL_MAX)
	if instant:
		overcast = STATES[kind]
		if kind == "rain":
			wet = 1.0


func _process(delta: float) -> void:
	if player == null:
		return
	if get_tree().current_scene != null:  # random spells only in the real game
		timer -= delta
		if timer <= 0.0:
			var roll := rng.randf()
			set_weather("rain" if roll < 0.15 else "cloudy" if roll < 0.4 else "clear")
	overcast = move_toward(overcast, float(STATES[state]), delta / 25.0)
	var raining := state == "rain" and overcast > 0.75
	wet = move_toward(wet, 1.0 if raining else 0.0, delta / (30.0 if raining else 150.0))
	day_night.set("overcast", overcast)
	var camera := player.camera
	if camera != null:
		rain.global_position = camera.global_position + Vector3(0, 11.0, 0) - camera.global_transform.basis.z * 6.0
	var indoors := bool(player.get("interior_camera"))  # under a roof: no rain on screen
	rain.emitting = raining and not indoors
	_update_audio(delta, raining and not indoors)
	_apply_wet()
	DriveableVehicle.wet_grip = 1.0 - 0.3 * wet


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


func to_save() -> Dictionary:
	return {"state": state, "wet": wet}


func from_save(value: Dictionary) -> void:
	set_weather(str(value.get("state", "clear")), true)
	wet = clampf(float(value.get("wet", wet)), 0.0, 1.0)
