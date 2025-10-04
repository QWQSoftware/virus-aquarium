shader_type spatial;

render_mode depth_draw_always, shadows_disabled, blend_mix;
varying vec3 normal;
void vertex() {
	// Called for every vertex the material is visible on.
	//vec3 z_axis_world = normalize(MODEL_MATRIX[2].xyz);
	//NORMAL = z_axis_world;
	// INSTANCE_CUSTOM stores the instance-local normal encoded into [0,1]
	vec3 decoded = normalize(INSTANCE_CUSTOM.rgb * 2.0 - vec3(1.0));
	NORMAL = decoded;
}

void fragment() {
	// Called for every pixel the material is visible on.
	//
	//ALBEDO = COLOR.rgb;
	//ALPHA = COLOR.a;
	//NORMAL = normalize(normal);
	//ALBEDO = normalize(normal);
	
	ALPHA = 0.99;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
