shader_type spatial;

render_mode shadows_disabled, depth_draw_always;

uniform vec4 color : source_color;
//uniform sampler2D noise_texture;
//
//uniform vec3 weights = vec3(1.,1.,1.);
//uniform vec3 triplanar_pos = vec3(1.,1.,1.);
//
//varying vec3 uv1_triplanar_pos;
//
//uniform float uv1_blend_sharpness : hint_range(0.0, 150.0, 0.001);
//varying vec3 uv1_power_normal;
//
//uniform vec3 uv1_scale;
//uniform vec3 uv1_offset;

//void vertex() {
	//vec3 normal = NORMAL;
//
	//TANGENT = vec3(0.0, 0.0, -1.0) * abs(normal.x);
	//TANGENT += vec3(1.0, 0.0, 0.0) * abs(normal.y);
	//TANGENT += vec3(1.0, 0.0, 0.0) * abs(normal.z);
	//TANGENT = normalize(TANGENT);
//
	//BINORMAL = vec3(0.0, 1.0, 0.0) * abs(normal.x);
	//BINORMAL += vec3(0.0, 0.0, -1.0) * abs(normal.y);
	//BINORMAL += vec3(0.0, 1.0, 0.0) * abs(normal.z);
	//BINORMAL = normalize(BINORMAL);
//
	//// UV1 Triplanar: Enabled
	//uv1_power_normal = pow(abs(NORMAL), vec3(uv1_blend_sharpness));
	//uv1_triplanar_pos = VERTEX * uv1_scale + uv1_offset;
	//uv1_power_normal /= dot(uv1_power_normal, vec3(1.0));
	//uv1_triplanar_pos *= vec3(1.0, -1.0, 1.0);
//}
//
//vec4 triplanar_texture(sampler2D p_sampler, vec3 p_weights, vec3 p_triplanar_pos) {
	//vec4 samp = vec4(0.0);
	//samp += texture(p_sampler, p_triplanar_pos.xy) * p_weights.z;
	//samp += texture(p_sampler, p_triplanar_pos.xz) * p_weights.y;
	//samp += texture(p_sampler, p_triplanar_pos.zy * vec2(-1.0, 1.0)) * p_weights.x;
	//return samp;
//}

void fragment() {
	// Called for every pixel the material is visible on.
	//ALBEDO = normalize(NORMAL);
	ALBEDO = color.rgb ;//* triplanar_texture(noise_texture, weights, triplanar_pos).rgb;
	ALPHA = color.a;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
