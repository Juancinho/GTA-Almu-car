// Façade details (windows, shutters, rejas, doors, shops) from the generated atlas.
// INSTANCE_CUSTOM.r = cell index / 16. Alpha: 0 wall (discard), ~0.78 opaque, 1 glass.
shader_type spatial;
render_mode cull_back;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform vec2 grid = vec2(4.0, 4.0);
uniform float night_glow = 0.0;
varying float glass_bias;

void vertex() {
	float cell = floor(INSTANCE_CUSTOM.r * 16.0 + 0.5);
	vec2 offset = vec2(mod(cell, grid.x), floor(cell / grid.x));
	UV = (UV + offset) / grid;
	glass_bias = INSTANCE_CUSTOM.g;
}

void fragment() {
	vec4 texel = texture(atlas, UV);
	if (texel.a < 0.3) {
		discard;
	}
	float glass = step(0.9, texel.a);
	ALBEDO = texel.rgb;
	ROUGHNESS = mix(0.85, 0.12, glass);
	SPECULAR = mix(0.4, 0.9, glass);
	EMISSION = texel.rgb * glass * night_glow * (0.4 + 0.6 * glass_bias);
}
