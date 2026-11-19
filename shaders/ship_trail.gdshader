shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, shadows_disabled;

uniform float intensity = 1.0; // Animated flicker brightness.
uniform float overdrive = 0.0; // Blends the lane colour from blue to purple.

varying float v_t; // Normalized position from wingtip (0) to tail (1).

void vertex() {
	// Map the box's local Z coordinate to the wingtip-to-tail gradient.
	v_t = clamp(0.5 + VERTEX.z / 1.4, 0.0, 1.0);
}

void fragment() {
	vec3 blue = vec3(0.13, 0.83, 0.93);
	vec3 purple = vec3(0.66, 0.33, 0.97);
	vec3 col = mix(blue, purple, clamp(overdrive, 0.0, 1.0));
	// Fade the light-lane toward transparency at its rear end.
	float fade = 1.0 - smoothstep(0.1, 1.0, v_t);
	ALBEDO = col * intensity;
	ALPHA = fade * 0.45;
}