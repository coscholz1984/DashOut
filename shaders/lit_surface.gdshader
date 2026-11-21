shader_type spatial;
render_mode cull_disabled;

uniform vec4 surface_color : source_color =
	vec4(0.12, 0.15, 0.19, 1.0);
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
// Controls how strongly the albedo texture blends over the base colour.
uniform float tex_strength = 0.75;

varying vec2 obj_uv;

void vertex() {
	// Object-space coordinates keep the texture aligned with each
	// chunk as it moves through the world.
	obj_uv = VERTEX.xz / tex_scale;
}

void fragment() {
	vec2 uv = obj_uv;
	vec3 col = surface_color.rgb;
	if (use_albedo > 0.5) {
		// Blend the texture over the base colour rather than multiplying it,
		// which would make the dark road palette too dark.
		col = mix(col, texture(albedo_tex, uv).rgb, tex_strength);
	}
	ALBEDO = col;
	float rough = 0.9;
	if (use_roughness > 0.5) {
		// Standard PBR roughness maps store values in the GREEN channel.
		rough = texture(roughness_tex, uv).g;
	}
	ROUGHNESS = rough;
	if (use_normal > 0.5) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = 1.0;
	}
}