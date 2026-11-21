shader_type spatial;
render_mode cull_disabled;

uniform vec4 near_ground_color : source_color =
	vec4(0.04, 0.05, 0.08, 1.0);

uniform vec4 horizon_ground_color : source_color =
	vec4(0.08, 0.08, 0.16, 1.0);

uniform float gradient_start = 35.0;
uniform float gradient_end = 240.0;

// Optional PBR textures, sampled in world space.
uniform sampler2D albedo_tex : source_color,
	filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex :
	filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_tex :
	filter_linear_mipmap, repeat_enable;
uniform float use_albedo = 0.0;
uniform float use_normal = 0.0;
uniform float use_roughness = 0.0;
// World-space size of one texture tile, in metres.
uniform float tex_scale = 4.0;
// Offsets the texture to keep it aligned with the scrolling road.
// The ground plane stays stationary; only its texture moves.
uniform float scroll_offset = 0.0;
// Controls how strongly the albedo texture blends over the gradient.
uniform float tex_strength = 0.75;

varying vec3 world_position;


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	// Calculate horizontal distance from the camera for the radial gradient.
	float horizontal_distance = length(
		world_position.xz - CAMERA_POSITION_WORLD.xz
	);

	float blend_factor = smoothstep(
		gradient_start,
		max(gradient_end, gradient_start + 0.001),
		horizontal_distance
	);

	vec3 ground_color = mix(
		near_ground_color.rgb,
		horizon_ground_color.rgb,
		blend_factor
	);

	// Offset the texture by the travelled distance to match road movement.
	vec2 uv = (
		world_position.xz - vec2(0.0, scroll_offset)
	) / tex_scale;
	if (use_albedo > 0.5) {
		ground_color = mix(
			ground_color,
			texture(albedo_tex, uv).rgb,
			tex_strength
		);
	}

	ALBEDO = ground_color;
	if (use_normal > 0.5) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = 1.0;
	}
	if (use_roughness > 0.5) {
		// Standard PBR roughness maps store roughness in the green channel.
		ROUGHNESS = texture(roughness_tex, uv).g;
	} else {
		ROUGHNESS = 1.0;
	}
}