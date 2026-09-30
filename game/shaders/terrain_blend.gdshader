// Ground of the generated sector: six surface classes blended by per-vertex
// weights (COLOR = beach, urban, park, natural; UV2 = promenade, sea bed) with a
// world-space noise so borders between paving, sand and grass read as organic
// edges instead of the 4 m terrain grid. Planar XZ sampling (the sector is
// mostly gentle), one albedo + normal pair per texture.
shader_type spatial;
render_mode cull_back;

uniform sampler2D gravel_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paving_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paving_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tiles_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tiles_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint_beach : source_color = vec3(0.43, 0.42, 0.41);
uniform vec3 tint_seabed : source_color = vec3(0.29, 0.35, 0.37);
uniform vec3 tint_urban : source_color = vec3(0.93, 0.90, 0.84);
uniform vec3 tint_park : source_color = vec3(0.66, 0.75, 0.49);
uniform vec3 tint_natural : source_color = vec3(0.60, 0.63, 0.39);
uniform vec3 tint_promenade : source_color = vec3(0.92, 0.87, 0.78);

varying vec3 world_pos;
varying vec4 weights_a;
varying vec2 weights_b;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	weights_a = COLOR;
	weights_b = UV2;
}

void fragment() {
	vec2 p = world_pos.xz;
	float n = value_noise(p * 0.28) * 0.65 + value_noise(p * 1.1) * 0.35;
	// Each class gets its own phase of the noise so borders wander.
	float beach = weights_a.r * (0.55 + n);
	float urban = weights_a.g * (0.55 + (1.0 - n));
	float park = weights_a.b * (0.55 + n);
	float natural = weights_a.a * (0.55 + value_noise(p * 0.5 + 17.0));
	float promenade = weights_b.x * (0.55 + (1.0 - n));
	float seabed = weights_b.y;
	vec4 wa = pow(vec4(beach, urban, park, natural), vec4(4.0));
	vec2 wb = pow(vec2(promenade, seabed), vec2(4.0));
	float total = max(wa.x + wa.y + wa.z + wa.w + wb.x + wb.y, 1e-4);
	wa /= total;
	wb /= total;
	vec3 gravel = texture(gravel_albedo, p / 2.5).rgb;
	vec3 paving = texture(paving_albedo, p / 2.2).rgb;
	vec3 grass = texture(grass_albedo, p / 6.0).rgb;
	vec3 tiles = texture(tiles_albedo, p / 2.6).rgb;
	vec3 albedo = gravel * (tint_beach * wa.x + tint_seabed * wb.y)
		+ paving * tint_urban * wa.y
		+ grass * (tint_park * wa.z + tint_natural * wa.w)
		+ tiles * tint_promenade * wb.x;
	// Faint large-scale tone variation breaks up repeated tiles over big squares.
	albedo *= 0.93 + 0.12 * value_noise(p * 0.045);
	vec3 normal_mix = texture(gravel_normal, p / 2.5).rgb * (wa.x + wb.y)
		+ texture(paving_normal, p / 2.2).rgb * wa.y
		+ texture(grass_normal, p / 6.0).rgb * (wa.z + wa.w)
		+ texture(tiles_normal, p / 2.6).rgb * wb.x;
	ALBEDO = albedo;
	NORMAL_MAP = normal_mix;
	NORMAL_MAP_DEPTH = 0.7;
	ROUGHNESS = 0.97 - 0.12 * (wa.y + wb.x);
}
