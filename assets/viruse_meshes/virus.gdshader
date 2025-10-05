shader_type spatial;

render_mode depth_draw_always, shadows_disabled, blend_mix;
varying vec3 normal;

uniform float sway_speed = 1.0;
uniform float sway_strength = 0.05;
uniform float sway_phase_len = 8.0;


void vertex() {
	vec3 decoded = normalize(INSTANCE_CUSTOM.rgb * 2.0 - vec3(1.0));
	NORMAL = decoded;
	
	float strength = COLOR.r * sway_strength;
    VERTEX.x += sin(VERTEX.x * sway_phase_len * 1.123 + TIME * sway_speed) * strength;
    VERTEX.y += sin(VERTEX.y * sway_phase_len + TIME * sway_speed * 1.12412) * strength;
    VERTEX.z += sin(VERTEX.z * sway_phase_len * 0.9123 + TIME * sway_speed * 1.3123) * strength;
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
