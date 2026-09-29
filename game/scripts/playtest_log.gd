class_name PlaytestLog
extends Node

## Records a play session as evidence: mission stages with timestamps, police events,
## arrests, save/load/pause/restart, raw input device counts and a PerfMonitor summary.
## Unexported builds write to generated/playtests/; exported builds to user://playtests/.

var mode := "human"
var events: Array[Dictionary] = []
var input_counts := {"key": 0, "mouse_button": 0, "mouse_motion": 0, "joypad_button": 0, "joypad_motion": 0}
var started_unix := 0.0
var started_ticks := 0
var perf: PerfMonitor
var written_path := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	started_unix = Time.get_unix_time_from_system()
	started_ticks = Time.get_ticks_msec()
	record("session_started", {"build": str(ProjectSettings.get_setting("application/config/name"))})


func _input(event: InputEvent) -> void:
	# Physical device events only; simulated tests use Input.action_press instead.
	if event is InputEventKey and event.pressed and not event.echo:
		input_counts["key"] += 1
	elif event is InputEventMouseButton and event.pressed:
		input_counts["mouse_button"] += 1
	elif event is InputEventMouseMotion:
		input_counts["mouse_motion"] += 1
	elif event is InputEventJoypadButton and event.pressed:
		input_counts["joypad_button"] += 1
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		input_counts["joypad_motion"] += 1


func elapsed_seconds() -> float:
	return (Time.get_ticks_msec() - started_ticks) / 1000.0


func record(kind: String, data: Dictionary = {}) -> void:
	var entry := {"t": snappedf(elapsed_seconds(), 0.01), "event": kind}
	entry.merge(data)
	events.append(entry)


func output_directory() -> String:
	if OS.has_feature("template"):
		return "user://playtests"
	return ProjectSettings.globalize_path("res://").path_join("../generated/playtests").simplify_path()


func write_report(reason: String) -> String:
	record("report_written", {"reason": reason})
	var directory := output_directory()
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		push_error("Playtest log: cannot create %s (%d)" % [directory, error])
		return ""
	var stamp := Time.get_datetime_string_from_unix_time(int(started_unix)).replace(":", "-")
	var path := directory.path_join("session_%s_%s.json" % [stamp, mode])
	var report := {
		"version": 1,
		"mode": mode,
		"started": Time.get_datetime_string_from_unix_time(int(started_unix)),
		"duration_s": snappedf(elapsed_seconds(), 0.1),
		"input_counts": input_counts,
		"events": events,
		"performance": perf.summary() if perf != null else {},
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Playtest log: cannot write %s (%d)" % [path, FileAccess.get_open_error()])
		return ""
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	written_path = path
	print("PLAYTEST REPORT: " + path)
	return path
