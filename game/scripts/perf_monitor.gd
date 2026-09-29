class_name PerfMonitor
extends CanvasLayer

## In-game frame-time recorder and optional overlay (F2).
## Frames are grouped by gameplay context (on_foot, driving, pursuit) so a play
## session reports average FPS and 1% lows for each situation, not a static view.

const MAX_FRAMES_PER_CONTEXT := 200000
const WARMUP_SECONDS := 2.0

var context_provider: Callable
var extra_info: Dictionary = {}
var frames: Dictionary = {}  # context -> PackedFloat32Array of frame ms
var draw_calls: Dictionary = {}  # context -> [sum, max]
var primitives: Dictionary = {}  # context -> [sum, max]
var elapsed := 0.0
var overlay: Label
var overlay_timer := 0.0
var recent_ms := PackedFloat32Array()
var window_seconds: Dictionary = {}


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay = Label.new()
	overlay.name = "PerfOverlay"
	overlay.position = Vector2(18, 184)
	overlay.add_theme_font_size_override("font_size", 16)
	overlay.add_theme_color_override("font_color", Color("f3ecd6"))
	overlay.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	overlay.add_theme_constant_override("outline_size", 4)
	overlay.visible = false
	add_child(overlay)


func toggle_overlay() -> void:
	overlay.visible = not overlay.visible


func _process(delta: float) -> void:
	elapsed += delta
	if get_tree().paused or elapsed < WARMUP_SECONDS:
		return
	var context := "gameplay"
	if DisplayServer.get_name() != "headless":
		# Seconds spent at each real window size (the player may toggle F11).
		var window := DisplayServer.window_get_size()
		var key := "%dx%d" % [window.x, window.y]
		window_seconds[key] = float(window_seconds.get(key, 0.0)) + delta
	if context_provider.is_valid():
		context = str(context_provider.call())
	var ms := delta * 1000.0
	if not frames.has(context):
		frames[context] = PackedFloat32Array()
		draw_calls[context] = [0.0, 0.0]
		primitives[context] = [0.0, 0.0]
	var bucket: PackedFloat32Array = frames[context]
	if bucket.size() < MAX_FRAMES_PER_CONTEXT:
		bucket.append(ms)
		frames[context] = bucket
		var calls := float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		var prims := float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		draw_calls[context] = [draw_calls[context][0] + calls, maxf(draw_calls[context][1], calls)]
		primitives[context] = [primitives[context][0] + prims, maxf(primitives[context][1], prims)]
	recent_ms.append(ms)
	if recent_ms.size() > 120:
		recent_ms.remove_at(0)
	overlay_timer -= delta
	if overlay.visible and overlay_timer <= 0.0:
		overlay_timer = 0.25
		_update_overlay(context)


func _update_overlay(context: String) -> void:
	var stats := _stats(recent_ms)
	overlay.text = "FPS %.0f · %.2f ms · 1%% bajo %.0f\nDraw calls %d · primitivas %d\nContexto %s · F2 ocultar · F6 guardar informe" % [
		stats["average_fps"], stats["average_ms"], stats["one_percent_low_fps"],
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		context]


static func _stats(values: PackedFloat32Array) -> Dictionary:
	if values.is_empty():
		return {"frames": 0, "average_fps": 0.0, "average_ms": 0.0, "one_percent_low_fps": 0.0, "p99_ms": 0.0, "max_ms": 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted:
		total += value
	var average := total / sorted.size()
	var p99 := sorted[mini(sorted.size() - 1, int(sorted.size() * 0.99))]
	return {
		"frames": sorted.size(),
		"seconds": snappedf(total / 1000.0, 0.01),
		"average_fps": snappedf(1000.0 / maxf(average, 0.001), 0.1),
		"average_ms": snappedf(average, 0.01),
		"one_percent_low_fps": snappedf(1000.0 / maxf(p99, 0.001), 0.1),
		"p99_ms": snappedf(p99, 0.01),
		"max_ms": snappedf(sorted[sorted.size() - 1], 0.01),
	}


func summary() -> Dictionary:
	var contexts := {}
	var all := PackedFloat32Array()
	for context in frames:
		var bucket: PackedFloat32Array = frames[context]
		var stats := _stats(bucket)
		if bucket.size() > 0:
			stats["average_draw_calls"] = snappedf(draw_calls[context][0] / bucket.size(), 0.1)
			stats["max_draw_calls"] = draw_calls[context][1]
			stats["average_primitives"] = snappedf(primitives[context][0] / bucket.size(), 1.0)
			stats["max_primitives"] = primitives[context][1]
		contexts[context] = stats
		all.append_array(bucket)
	var windows := {}
	for key in window_seconds:
		windows[key] = snappedf(window_seconds[key], 0.1)
	return {"overall": _stats(all), "contexts": contexts, "window_seconds": windows, "environment": environment_info()}


func environment_info() -> Dictionary:
	var logical := get_viewport().get_visible_rect().size
	var headless := DisplayServer.get_name() == "headless"
	var window: Vector2i = DisplayServer.window_get_size() if not headless else Vector2i.ZERO
	var render: Vector2 = get_viewport().get_texture().get_size() if not headless else Vector2.ZERO
	var info := {
		"godot": Engine.get_version_info().get("string", ""),
		"os": OS.get_name() + " " + OS.get_version(),
		"cpu": OS.get_processor_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"graphics_api": RenderingServer.get_video_adapter_api_version(),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		"display_server": DisplayServer.get_name(),
		"logical_viewport": [int(logical.x), int(logical.y)],
		"window_size": [window.x, window.y],
		"render_size": [int(render.x), int(render.y)],
		"screen_size": [DisplayServer.screen_get_size().x, DisplayServer.screen_get_size().y] if not headless else [0, 0],
		"window_mode": DisplayServer.window_get_mode() if not headless else -1,
		"vsync_mode": DisplayServer.window_get_vsync_mode() if not headless else -1,
		"refresh_rate": DisplayServer.screen_get_refresh_rate() if not headless else -1.0,
	}
	info.merge(extra_info, true)
	return info
