shader_type spatial;
render_mode cull_disabled, unshaded;

uniform float strength = 0.98;

void fragment() {
	// Use black as the base colour so the unshaded disc darkens the
	// surface rather than appearing as a white light.
	ALBEDO = vec3(0.0);
	float d = length(UV - vec2(0.5, 0.5));
	ALPHA = strength * (1.0 - smoothstep(0.3, 0.5, d));
}