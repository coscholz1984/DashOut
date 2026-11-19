shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 glow_color : source_color = vec3(0.65, 0.3, 1.0);
uniform float intensity = 0.0; // Runtime visibility, driven by overdrive.

varying vec3 v_pos; // Model-space position used to anchor the animated bands.

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	// Fresnel effect: transparent head-on, brighter at the silhouette.
	// abs() handles the backfaces rendered by cull_disabled.
	float f = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.5);
	// Two moving model-space waves create the interference pattern.
	float band = sin(v_pos.y * 7.0 + v_pos.x * 5.0 + TIME * 2.5)
		* sin(v_pos.z * 6.0 - TIME * 1.7);
	float shine = 0.5 + 0.5 * band;
	float glow = f * (0.7 + 0.3 * shine) + 0.06 * shine;
	ALBEDO = glow_color * glow;
	ALPHA = clamp(intensity, 0.0, 1.0) * glow * 0.7;
}