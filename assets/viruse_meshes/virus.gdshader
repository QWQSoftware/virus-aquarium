shader_type spatial;

render_mode depth_draw_always, shadows_disabled, blend_mix;
varying vec3 normal;
void vertex() {
	vec3 decoded = normalize(INSTANCE_CUSTOM.rgb * 2.0 - vec3(1.0));
	NORMAL = decoded;
}

void fragment() {
	// Called for every pixel the material is visible on.
	//
	ALBEDO = COLOR.rgb;
	//ALPHA = COLOR.a;
	ALPHA = 0.999;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
