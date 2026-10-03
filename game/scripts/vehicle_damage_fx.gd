class_name VehicleDamageFx
extends Node3D

const SoftParticle = preload("res://scripts/soft_particle.gd")

## Smoke, fire and explosion visuals for a damaged vehicle (CPU particles, which the
## Compatibility renderer supports everywhere). State only; damage rules live in vehicle.gd.

var smoke: CPUParticles3D
var fire: CPUParticles3D
var fire_light: OmniLight3D


func _ready() -> void:
	position = Vector3(0, 0.9, -1.4)  # engine bay at the front (-Z)
	smoke = _emitter("Smoke", Color(0.25, 0.25, 0.25, 0.55), 0.55, 1.6, 18, 2.2)
	fire = _emitter("Fire", Color(1.0, 0.45, 0.1, 0.9), 0.35, 0.8, 24, 3.5)
	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.55, 0.2)
	fire_light.omni_range = 7.0
	fire_light.light_energy = 0.0
	add_child(fire_light)


func _emitter(label: String, color: Color, size: float, lifetime: float, amount: int, speed: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = label
	particles.emitting = false
	particles.amount = amount
	particles.lifetime = lifetime
	particles.direction = Vector3.UP
	particles.spread = 18.0
	particles.initial_velocity_min = speed * 0.6
	particles.initial_velocity_max = speed
	particles.gravity = Vector3(0, 0.6, 0)
	particles.scale_amount_min = size
	particles.scale_amount_max = size * 2.2
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = SoftParticle.material(color)
	particles.mesh = quad
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	particles.color_ramp = fade
	add_child(particles)
	return particles


## 0 = fine, 1 = smoking, 2 = burning, 3 = wreck (light smoke only).
func set_stage(stage: int) -> void:
	smoke.emitting = stage >= 1
	fire.emitting = stage == 2
	fire_light.light_energy = 1.6 if stage == 2 else 0.0


## One-shot fireball: expanding unshaded sphere and a flash of light that fade out.
func explode() -> void:
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	ball.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.2, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball.material_override = mat
	add_child(ball)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.3)
	flash.omni_range = 18.0
	flash.light_energy = 6.0
	add_child(flash)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ball, "scale", Vector3.ONE * 5.0, 0.6)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tween.tween_property(flash, "light_energy", 0.0, 0.8)
	tween.chain().tween_callback(ball.queue_free)
	tween.tween_callback(flash.queue_free)
