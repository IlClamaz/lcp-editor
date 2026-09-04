shader_type spatial;
render_mode unshaded, shadows_disabled, cull_disabled, blend_mix, depth_draw_opaque;

uniform vec4 chalk_color : source_color = vec4(1,1,1,1);
uniform float chalk_alpha : hint_range(0.0, 1.0) = 0.8;
uniform float wear : hint_range(0.0, 1.0) = 1;
uniform float world_scale = 1;
uniform float wobble_m = 0.005;

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
	float n = noise(v_world.xz * 8.0);
	float w1 = noise(v_world.xz * 4.6);
	float w2 = noise(v_world.xz * 4.6 + 17.0);
	VERTEX += vec3(w1 - 0.5, 0.0, w2 - 0.5) * 1.8 * wobble_m * wear;
	VERTEX += NORMAL * ((n - 0.5) * 2.0 * wobble_m * wear);
}


void fragment() {
	vec2 p = v_world.xz * world_scale;

	// Pressure: thick piled chalk vs a light pass that lets the floor through.
	float pressure = fbm(p * 1.05);
	float pressure2 = fbm(p * 2.4 + 5.0);

	// Dragged-stick scumble (parallel chalk passes, not a solid fill).
	float scumble = fbm(vec2(p.x * 3.4, p.y * 14.0));
	float scumble2 = fbm(vec2(p.x * 11.0 + 2.0, p.y * 4.1 + 3.3));

	// Powder / grit of chalk dust on a rough floor.
	float dust = fbm(p * 16.0);
	float speckle = noise(p * 48.0);
	float crumbs = noise(p * 92.0);

	// Fine grit only — small pits, not large blotches that erase the stroke.
	float holes_n = speckle * 0.5 + crumbs * 0.35 + noise(p * 140.0) * 0.15;

	// Wear 0 = no holes. Wear 1 = denser pinholes, stroke body still there.
	float hole_bar = wear * 0.42;
	float chalk_mask = smoothstep(hole_bar, hole_bar + 0.14, holes_n);

	float alpha = chalk_mask * mix(0.5, 0.36, wear);
	alpha *= mix(1.0, mix(0.84, 1.0, scumble * 0.6 + scumble2 * 0.4), wear * 0.45);

	// Incoming color is only a tint. Brighter chalk, still not neon-solid.
	vec3 base = chalk_color.rgb;
	float luma = dot(base, vec3(0.299, 0.587, 0.114));
	vec3 desat = mix(base, vec3(luma), 0.35);
	desat *= 0.82;
	desat = min(desat, vec3(0.86, 0.87, 0.88));

	vec3 dusty = desat * mix(0.58, 0.82, dust);
	vec3 piled = desat * mix(0.92, 1.12, pressure);
	float tone = clamp(pressure * 0.4 + pressure2 * 0.2 + dust * 0.4, 0.0, 1.0);
	vec3 col = mix(dusty, piled, tone);
	col *= mix(0.82, 1.0, speckle);

	ALBEDO = col;
	// Smooth transparency (no alpha-scissor cutout).
	ALPHA = chalk_color.a * chalk_alpha * alpha;
}
