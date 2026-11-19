shader_type spatial;
render_mode cull_disabled;

uniform vec4 base_color : source_color = vec4(0.6, 0.2, 0.2, 1.0);
uniform vec4 accent_color : source_color = vec4(0.2, 0.8, 1.0, 1.0);
uniform vec4 overdrive_color : source_color = vec4(0.66, 0.33, 0.97, 1.0);
uniform float metal = 0.65;
uniform float rough = 0.3;
uniform float speed = 0.0;
uniform float overdrive = 0.0;
uniform float flash = 0.0;

// Optional external PBR textures, shared across all dynamic hull materials.
// Each texture is enabled only when its corresponding file is available.
// UV scaling controls the size of the texture pattern on the hull.
uniform sampler2D albedo_tex : source_color,
	filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex :
	filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_tex :
	filter_linear_mipmap, repeat_enable;
uniform sampler2D metallic_tex :
	filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_tex :
	filter_linear_mipmap, repeat_enable;
uniform float use_albedo = 0.0;
uniform float use_normal = 0.0;
uniform float use_roughness = 0.0;
uniform float use_metallic = 0.0;
uniform float use_ao = 0.0;
uniform float tex_scale = 0.5;
// Controls how strongly texture maps influence the material.
// The albedo texture is blended with the skin colour, not substituted.
uniform float tex_strength = 0.7;

varying vec3 hull_pos;

void vertex() {
	hull_pos = VERTEX;
}

void fragment() {
	vec2 tuv = UV * tex_scale;
	vec3 albedo = base_color.rgb;
	float metal_val = metal;
	float rough_val = rough;

	if (use_albedo > 0.5) {
		// Blend the texture with the skin colour to preserve the hull's paint.
		vec3 tex = texture(albedo_tex, tuv).rgb;
		albedo = mix(albedo, albedo * tex * 2.0, tex_strength);
	}
	if (use_ao > 0.5) {
		// Ambient occlusion is stored in the RED channel.
		albedo *= mix(1.0, texture(ao_tex, tuv).r, tex_strength);
	}
	if (use_metallic > 0.5) {
		// ORM texture sets store metallic values in the BLUE channel.
		metal_val = mix(
			metal_val, texture(metallic_tex, tuv).b, tex_strength
		);
	}
	if (use_roughness > 0.5) {
		// Standard PBR roughness maps store values in the GREEN channel.
		rough_val = mix(
			rough_val, texture(roughness_tex, tuv).g, tex_strength
		);
	}

	ALBEDO = albedo;
	METALLIC = metal_val;
	ROUGHNESS = rough_val;
	if (use_normal > 0.5) {
		NORMAL_MAP = texture(normal_tex, tuv).rgb;
		NORMAL_MAP_DEPTH = 1.0;
	}

	// Rim: blends the accent colour toward the overdrive colour
	// and brightens the hull silhouette.
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);
	vec3 rim = mix(accent_color.rgb, overdrive_color.rgb, overdrive);
	EMISSION = rim * (fres * (0.35 + speed * 0.9) + overdrive * 1.4);

	// Cruise: a gentle uniform emission pulse that fades during overdrive.
	float pulse = 0.5 + 0.5 * sin(TIME * (1.2 + speed * 1.6));
	EMISSION += rim * pulse * (0.06 + speed * 0.22) * (1.0 - overdrive);

	// Overdrive: animated stripes travel along the hull, accelerating
	// with speed and becoming stronger as overdrive increases.
	float band = smoothstep(0.72, 1.0,
		sin(hull_pos.z * 3.0 - TIME * (18.0 + speed * 14.0)));
	EMISSION += rim * band * overdrive * (0.6 + speed * 0.4);

	// Gunfire: briefly increases hull emission and brightness.
	EMISSION += rim * flash * 2.5;
	ALBEDO += vec3(0.15) * flash;
}