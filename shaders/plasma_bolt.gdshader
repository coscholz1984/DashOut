shader_type spatial;
render_mode cull_disabled, blend_add, unshaded;

uniform vec4 core_color : source_color =
	vec4(0.45, 0.15, 1.0, 0.6);
uniform vec4 rim_color : source_color =
	vec4(0.85, 0.6, 1.0, 1.0);
uniform float intensity = 1.0;

void fragment() {
	// Brighten the silhouette while keeping the backfaces consistent.
	float f = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);

	// Fast, small-scale turbulence makes the projectile visibly churn.
	float t = TIME * 9.0;
	float turb = sin(VERTEX.x * 14.0 + t) * 0.5
		+ sin(VERTEX.y * 17.0 - t * 1.4) * 0.5;
	turb = 0.5 + 0.5 * turb;

	// Fade the rear of the projectile so it dissolves toward its tail.
	// Fade emission as well as transparency to darken the tail.
	float tail = 1.0 - smoothstep(0.0, 1.0, VERTEX.z);

	vec3 col = mix(core_color.rgb, rim_color.rgb, f);

	ALPHA = core_color.a * (0.5 + 0.5 * f)
		* (0.7 + 0.3 * turb) * tail * intensity;
	EMISSION = col * (0.7 + 1.3 * f)
		* intensity * (0.8 + 0.4 * turb) * tail;
}