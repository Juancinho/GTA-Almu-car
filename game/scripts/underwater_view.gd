class_name UnderwaterView
extends Node

var player: PlayerController
var active := false
var overlay: ColorRect
var surface_environment: Environment
var water_environment: Environment

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; void fragment(){ float wave = sin(UV.y*45.0+TIME*1.7)*sin(UV.x*32.0-TIME)*0.025; float edge = smoothstep(0.3,0.75,distance(UV,vec2(0.5))); COLOR=vec4(0.015+wave,0.22+wave,0.36+wave,0.18+edge*0.22); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	overlay.material = material
	overlay.visible = false
	layer.add_child(overlay)

func _process(_delta: float) -> void:
	if player == null or player.sector_data == null:
		return
	var at := player.camera.global_position
	var submerged := player.driving_vehicle == null and player.sector_data.surface_at(at.x, at.z) == "sea" and at.y < 0.03
	if submerged == active:
		return
	active = submerged
	overlay.visible = active
	if active:
		surface_environment = player.camera.environment
		var source := surface_environment if surface_environment != null else player.get_world_3d().environment
		water_environment = source.duplicate() as Environment
		water_environment.background_mode = Environment.BG_COLOR
		water_environment.background_color = Color("125c83")
		water_environment.fog_enabled = true
		water_environment.fog_light_color = Color("125c83")
		water_environment.fog_density = 0.09
		water_environment.fog_sky_affect = 1.0
		water_environment.ambient_light_color = Color("4d98b5")
		player.camera.environment = water_environment
	else:
		player.camera.environment = surface_environment
