shader_type canvas_item;

uniform float gradient_speed = 0.2;
uniform float gradient_cycles = 3.0;
uniform float sweep_strength = 0.85;

uniform vec3 cyan_color = vec3(0.133, 0.827, 0.933);
uniform vec3 magenta_color = vec3(0.35, 0.0, 0.50);

void fragment() {
	vec4 glyph = texture(TEXTURE, UV);

	// Periodic gradient travelling horizontally across the text.
	float phase = fract(
		SCREEN_UV.x * gradient_cycles - TIME * gradient_speed
	);

	float gradient_position =
		0.5 - 0.5 * cos(phase * 6.283185);

	vec3 gradient = mix(
		cyan_color,
		magenta_color,
		gradient_position
	);

	// Preserve the original label colour outside the glyph fill.
	vec3 base_color = COLOR.rgb;
	vec3 rgb = mix(
		base_color,
		gradient,
		glyph.a * sweep_strength
	);

	COLOR = vec4(rgb, COLOR.a);
}
