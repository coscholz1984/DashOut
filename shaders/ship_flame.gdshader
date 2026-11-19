shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float intensity = 1.2; // Animated flicker intensity.
uniform float opacity = 0.55;  // Overall flame opacity.
uniform float overdrive = 0.0; // Blends the flame toward the overdrive colour.
uniform float radius = 0.14;   // Rest radius of the sphere in model space.
uniform vec3 flame_color = vec3(0.25, 0.5, 1.0);       // Base exhaust colour.
uniform vec3 overdrive_color = vec3(0.66, 0.33, 0.97); // Overdrive exhaust colour.

varying float v_t; // Normalized position along the flame: mouth (0) to tail (1).

void vertex() {
	// Calculate the gradient position in model space, before the
	// flame's stretch scale. The local +Z end is anchored at the
	// engine outlet, so the gradient runs in the negative Z direction.
	v_t = clamp(0.5 - VERTEX.z / radius * 0.5, 0.0, 1.0);
}

void fragment() {
	// Fade the silhouette as the surface turns away from the camera.
	float edge = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float body = smoothstep(0.0, 0.45, edge);
	// Blend the base exhaust colours toward the overdrive tint.
	vec3 hot = mix(
		flame_color * 0.55 + vec3(0.5),
		overdrive_color * 0.55 + vec3(0.45),
		overdrive
	);
	vec3 mid = mix(flame_color, overdrive_color, overdrive);
	vec3 col = mix(hot, mid, smoothstep(0.0, 0.4, v_t));
	// Fade the flame to transparency toward its tail.
	float fade = 1.0 - smoothstep(0.35, 1.0, v_t);
	ALBEDO = col * intensity;
	ALPHA = opacity * fade * body;
}