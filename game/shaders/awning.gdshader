// Canvas shop awnings (toldos). COLOR = canvas colour (MultiMesh instance colour);
// INSTANCE_CUSTOM.r = awning width / 10 m, .g > 0.5 = striped with off-white.
shader_type spatial;
render_mode cull_disabled;

varying float width_m;
varying float striped;

void vertex() {
	width_m = INSTANCE_CUSTOM.r * 10.0;
	striped = INSTANCE_CUSTOM.g;
}

void fragment() {
	float stripe = step(0.5, fract(UV.x * width_m / 0.42));
	vec3 canvas = mix(COLOR.rgb, vec3(0.95, 0.93, 0.88), stripe * step(0.5, striped));
	// Underside and valance read a little darker, like translucent canvas in shade.
	ALBEDO = canvas * (FRONT_FACING ? 1.0 : 0.72);
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
