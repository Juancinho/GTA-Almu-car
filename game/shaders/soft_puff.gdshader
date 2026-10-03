shader_type spatial;
// Soft smoke puff for small particle spheres: opaque towards the centre of the
// silhouette and fading to nothing at the rim, tinted by the particle colour.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.88, 0.88, 0.9, 0.5);

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	ALBEDO = tint.rgb * COLOR.rgb;
	ALPHA = tint.a * COLOR.a * facing * facing;
}
