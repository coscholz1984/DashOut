shader_type spatial;
render_mode cull_disabled, blend_add, unshaded;

uniform vec4 core_color : source_color =
	vec4(0.20, 0.45, 1.0, 0.4);
uniform vec4 rim_color : source_color =
	vec4(0.65, 0.90, 1.0, 1.0);
uniform float intensity = 1.0;

void fragment() {
	// Brighten the silhouette while keeping the backfaces consistent.
	float f = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);

	// Layered sine waves create animated turbulence inside the plasma.
	float t = TIME * 6.0;
	float turb = sin(VERTEX.x * 8.0 + t) * 0.5
		+ sin(VERTEX.y * 11.0 - t * 1.3) * 0.3
		+ sin((VERTEX.x + VERTEX.y) * 6.0 + t * 0.7) * 0.2;
	turb = 0.5 + 0.5 * turb;

	vec3 col = mix(core_color.rgb, rim_color.rgb, f);

	// Keep the interior visible while allowing the rim to become brighter.
	ALPHA = core_color.a * (0.45 + 0.55 * f)
		* (0.7 + 0.3 * turb) * intensity;
	EMISSION = col * (0.6 + 1.4 * f)
		* intensity * (0.8 + 0.4 * turb);
}