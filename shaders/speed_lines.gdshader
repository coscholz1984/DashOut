shader_type canvas_item;
render_mode blend_add;

uniform float intensity = 0.0; // Overall overlay strength.
uniform float overdrive = 0.0; // Blends the streaks toward purple.
uniform float aspect = 1.7777; // Viewport aspect ratio.

float hash11(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

void fragment() {
	vec2 c = UV - vec2(0.5);
	c.x *= aspect;
	float r = length(c);
	float ang = atan(c.y, c.x);
	// Gently distort the streak directions over time.
	ang += (sin(TIME * 1.7) * 0.012 + sin(TIME * 2.9 + 1.3) * 0.007)
		* (0.6 + 0.4 * sin(ang * 3.0 + TIME * 0.8));
	// Divide the screen into angular slices, each containing one streak.
	float cells = 120.0;
	float cellf = (ang / 6.28318 + 0.5) * cells;
	float id = floor(cellf);
	float rnd = hash11(id);
	// Animate each streak within its angular slice.
	float f = fract(cellf)
		+ 0.18 * sin(TIME * (0.3 + rnd * 0.4) + rnd * 9.0);
	float width = smoothstep(0.0, 0.25, f) * smoothstep(1.0, 0.75, f);
	// Animate pulses travelling outward from the centre.
	float pulse = fract(
		r * (3.0 + rnd * 4.0) - TIME * (1.2 + rnd * 1.8) - rnd * 7.0
	);
	float streak = smoothstep(0.5, 0.95, pulse) * smoothstep(1.0, 0.8, pulse);
	// Keep the central viewing area clear.
	float mask = smoothstep(0.28, 0.55, r);
	// Blend from ice blue to purple during overdrive.
	vec3 col = mix(vec3(0.75, 0.85, 1.0), vec3(0.72, 0.4, 1.0), overdrive);
	float a = streak * width * mask * intensity * 0.35;
	COLOR = vec4(col, a);
}