shader_type spatial;
render_mode unshaded, shadows_disabled, cull_disabled, depth_prepass_alpha;

uniform vec4 chalk_color : source_color = vec4(1.0);
uniform float wear : hint_range(0.0, 1.0) = 0.9;
uniform float world_scale = 14.0;
uniform float wobble_m = 0.006;

varying vec3 v_world;


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}


float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.13 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}


void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n = noise(v_world.xz * 9.0);
	VERTEX += NORMAL * ((n - 0.5) * 2.0 * wobble_m * wear);
}


void fragment() {
	vec2 p = v_world.xz * world_scale;
	float blotch = fbm(p * 0.45);
	float grain = fbm(p * 2.8 + 8.0);
	float speck = noise(p * 22.0);

	float holes = smoothstep(wear * 0.38, wear * 0.38 + 0.12, blotch * 0.7 + grain * 0.3);
	float alpha = mix(1.0, holes * mix(0.75, 1.0, speck), wear);

	ALBEDO = chalk_color.rgb;
	ALPHA = chalk_color.a * alpha;
	ALPHA_SCISSOR_THRESHOLD = mix(0.02, 0.42, wear);
}
