extends RefCounted

## Shared soft round sprite for smoke, flames and dust. Plain quads read as
## flat squares; a radial falloff makes each particle a puff, and the
## particles' colour ramp fades it out over its life.

static var _texture: GradientTexture2D
static var _materials: Dictionary = {}


static func texture() -> GradientTexture2D:
	if _texture == null:
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 1))
		ramp.set_color(1, Color(1, 1, 1, 0))
		ramp.add_point(0.45, Color(1, 1, 1, 0.55))
		_texture = GradientTexture2D.new()
		_texture.gradient = ramp
		_texture.fill = GradientTexture2D.FILL_RADIAL
		_texture.fill_from = Vector2(0.5, 0.5)
		_texture.fill_to = Vector2(0.5, 0.0)
		_texture.width = 64
		_texture.height = 64
	return _texture


## Billboard material tinted `color`; `glow` uses additive blending (flames).
static func material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var key := "%s_%s" % [color.to_html(), glow]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = texture()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_materials[key] = mat
	return mat
