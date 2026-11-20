shader_type spatial;
render_mode cull_disabled, blend_add, unshaded;

uniform vec4 shell_color : source_color =
	vec4(0.13, 0.83, 1.0, 0.5);
uniform float intensity = 1.0;
uniform float wobble = 0.02;
uniform float ripple = 0.0;

void vertex() {
	// Breathing wobble: the surface ripples gently along y.
	VERTEX += NORMAL * sin(TIME * 5.0 + VERTEX.y * 4.0) * wobble;
}

void fragment() {
	// Fresnel edge: bright at the silhouette, invisible head-on.
	// abs() because cull_disabled also renders backfaces, whose
	// NORMAL points the other way.
	float f = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);

	// Collision / near-miss ripple: a rapid pulsing SURGE layered
	// on the steady glow while the ripple decays.
	float surge = 1.0 + ripple * (1.5 + 1.5 * sin(TIME * 24.0));

	ALPHA = shell_color.a * f * intensity * surge;
	ALBEDO = shell_color.rgb;
	EMISSION = shell_color.rgb * f * intensity * surge;
}