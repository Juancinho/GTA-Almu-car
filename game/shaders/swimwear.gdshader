// Original two-piece textile pattern on the CC0 adult female_tanktop fitted mesh.
shader_type spatial;
uniform vec4 skin_tint : source_color = vec4(0.72,0.47,0.32,1.0);
uniform vec4 cloth_tint : source_color = vec4(0.08,0.40,0.53,1.0);
uniform bool lower_piece = false;
uniform sampler2D fabric : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 bind_position;
void vertex() { bind_position = VERTEX; }
void fragment() {
	float h = bind_position.z;
	float coverage = lower_piece ? step(0.0205,h) : step(0.0315,h)*step(h,0.0358);
	// Narrow shoulder straps keep the upper garment a complete two-piece outfit.
	if (!lower_piece) { coverage = max(coverage, step(0.0025,abs(bind_position.x))*step(0.035,h)); }
	float stripe = 0.84 + 0.16 * step(0.5,fract(h*2000.0));
	vec3 textile = cloth_tint.rgb * stripe * (0.9 + texture(fabric,UV*4.0).r*0.1);
	ALBEDO = mix(skin_tint.rgb,textile,coverage);
	ROUGHNESS = 0.82;
}
