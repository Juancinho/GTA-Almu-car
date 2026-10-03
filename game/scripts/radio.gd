extends Node

const AudioUtil = preload("res://scripts/audio_util.gd")

## Car radio. Getting into a car switches the radio on at the last station; Q
## cycles stations (and "apagada"). Stations play "live": each runs on the game
## clock, so tuning in lands mid-song, as on a real radio. A small caption shows
## the station and song for a few seconds. Boats have no radio.

const DATA_PATH := "res://data/radio.json"
const SHOW_SECONDS := 3.5

var player: PlayerController
var stations: Array = []
var station := 0  # index into stations; stations.size() means off
var playing_track := -1
var audio: AudioStreamPlayer
var caption: Label
var caption_timer := 0.0
var _was_driving := false
var _station_length: Array[float] = []


func configure(target_player: PlayerController) -> void:
	player = target_player
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if parsed is Dictionary:
		stations = parsed.get("stations", [])
	for s in stations:
		var length := 0.0
		for t in s["tracks"]:
			var stream := AudioUtil.stream(str(t["file"]))
			t["stream"] = stream
			t["length"] = stream.get_length() if stream != null else 60.0
			length += float(t["length"])
		_station_length.append(maxf(length, 1.0))
	audio = AudioStreamPlayer.new()
	audio.name = "RadioAudio"
	audio.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	audio.volume_db = -6.0
	audio.finished.connect(_on_finished)
	add_child(audio)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	caption = Label.new()
	caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	caption.position = Vector2(-300, 70)
	caption.custom_minimum_size = Vector2(600, 60)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 26)
	caption.add_theme_color_override("font_color", Color("ffd27a"))
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	caption.add_theme_constant_override("outline_size", 8)
	caption.visible = false
	layer.add_child(caption)


func is_on() -> bool:
	return audio != null and audio.playing


func current_name() -> String:
	return "APAGADA" if station >= stations.size() else str(stations[station]["name"])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("radio_next") and player != null and _in_radio_vehicle():
		station = (station + 1) % (stations.size() + 1)
		_tune()


func _in_radio_vehicle() -> bool:
	return player.driving_vehicle != null and not player.driving_vehicle.boat


func _process(delta: float) -> void:
	if player == null:
		return
	var driving := _in_radio_vehicle() and not player.dead
	if driving != _was_driving:
		_was_driving = driving
		if driving:
			_tune()
		else:
			audio.stop()
			playing_track = -1
	caption_timer -= delta
	caption.visible = caption_timer > 0.0
	if caption.visible:
		caption.modulate.a = clampf(caption_timer, 0.0, 1.0)


## Start the current station at its "live" position.
func _tune() -> void:
	audio.stop()
	playing_track = -1
	if station >= stations.size():
		_show("RADIO APAGADA")
		return
	var s: Dictionary = stations[station]
	var clock := fmod(Time.get_ticks_msec() / 1000.0 + station * 37.0, _station_length[station])
	for i in range((s["tracks"] as Array).size()):
		var t: Dictionary = s["tracks"][i]
		if clock < float(t["length"]):
			_play(i, clock)
			break
		clock -= float(t["length"])
	_show("%s\n%s" % [str(s["name"]), str(s["tracks"][maxi(playing_track, 0)]["title"])])


func _play(index: int, from: float) -> void:
	var t: Dictionary = stations[station]["tracks"][index]
	if t["stream"] == null:
		return
	playing_track = index
	audio.stream = t["stream"]
	if DisplayServer.get_name() != "headless":
		audio.play(from)


func _on_finished() -> void:
	if station >= stations.size() or not _was_driving:
		return
	var count := (stations[station]["tracks"] as Array).size()
	_play((playing_track + 1) % count, 0.0)
	_show("%s\n%s" % [str(stations[station]["name"]), str(stations[station]["tracks"][playing_track]["title"])])


func _show(text: String) -> void:
	caption.text = text
	caption_timer = SHOW_SECONDS
