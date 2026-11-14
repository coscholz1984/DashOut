
class_name ShipMaterials
extends Object
## Provides shared materials for player and traffic ships.
## Includes static glow materials for ship components and a
## velocity-reactive shader material for the player's hull.

## Hull plating — hard metal gloss with a faint cool rim.
static func hull(color: Color) -> Material:
	return Primitives.glow_mat(
		color, 0.65, 0.3,
		Color(0, 0, 0, 0), 0.0,
		Color("9be8f0"), 0.35
	)


## Upper ridge / wings — a touch glossier than the hull.
static func roof(color: Color) -> Material:
	return Primitives.glow_mat(
		color, 0.75, 0.25,
		Color(0, 0, 0, 0), 0.0,
		Color("9be8f0"), 0.3
	)


## Cockpit glass — translucent, high glint.
static func glass() -> Material:
	return Primitives.glow_mat(
		Color("a5d8ff"), 0.1, 0.15,
		Color(0, 0, 0, 0), 0.0,
		Color("ffffff"), 0.6,
		0.85
	)


## Engine blocks and dark trim — low gloss, subtle rim.
static func dark(color: Color) -> Material:
	return Primitives.glow_mat(
		color, 0.7, 0.3,
		Color(0, 0, 0, 0), 0.0,
		Color("9be8f0"), 0.2
	)


## Neon strips and signal lights — emissive accents with a
## matching rim glow. The energy parameter controls emission strength.
static func neon(color: Color, energy := 1.4) -> Material:
	return Primitives.glow_mat(
		color, 0.0, 1.0,
		color, energy,
		color, 1.2
	)


# =============================================================
# DYNAMIC HULL MATERIAL (player ship only)
# =============================================================

## Velocity-reactive hull shader for the player ship.
##
## The shader responds to three runtime parameters:
## - speed: controls the intensity of the hull effects.
## - overdrive: activates the purple rim and animated energy stripes.
## - flash: triggers a brief emission pulse during gunfire.
##
## Standard Godot lighting remains active, preserving the normal
## material response to scene lighting. Traffic ships use static
## glow materials instead.
const FX_OVERDRIVE_COLOR := Color("a855f7")

static var _fx_shader: Shader

static func _get_fx_shader() -> Shader:
	if _fx_shader == null:
		_fx_shader = Shader.new()
		_fx_shader.code = """
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
"""
	return _fx_shader


## Creates a dynamic hull material for the player ship.
## PlayerShip drives its speed, overdrive and flash uniforms.
## Optional external PBR textures are applied when available.
static func fx_mat(
		color: Color,
		accent: Color,
		metal := 0.65,
		rough := 0.3
) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _get_fx_shader()
	mat.set_shader_parameter("base_color", color)
	mat.set_shader_parameter("accent_color", accent)
	mat.set_shader_parameter("overdrive_color", FX_OVERDRIVE_COLOR)
	mat.set_shader_parameter("metal", metal)
	mat.set_shader_parameter("rough", rough)
	_apply_hull_textures(mat)
	return mat


## Shared cache of optional hull textures.
## Missing textures are cached as null to avoid repeated load attempts.
## The separate flag distinguishes an uninitialized cache from an empty one.
static var _hull_textures: Dictionary
static var _hull_textures_loaded := false


## Loads the optional external hull PBR textures into the shared cache
## and assigns available textures to the supplied material.
## Only textures that load successfully are enabled in the shader.
static func _apply_hull_textures(mat: ShaderMaterial) -> void:
	if not _hull_textures_loaded:
		_hull_textures_loaded = true
		_hull_textures = {
			"albedo": TextureManager.tex("ship_albedo.png"),
			"normal": TextureManager.tex("ship_normal.png"),
			"roughness": TextureManager.tex("ship_roughness.png"),
			"metallic": TextureManager.tex("ship_metallic.png"),
			"ao": TextureManager.tex("ship_ao.png"),
		}
	var pairs := {
		"albedo": "albedo_tex",
		"normal": "normal_tex",
		"roughness": "roughness_tex",
		"metallic": "metallic_tex",
		"ao": "ao_tex",
	}
	for kind in pairs:
		var texture: Texture2D = _hull_textures[kind]
		if texture != null:
			mat.set_shader_parameter(pairs[kind], texture)
			mat.set_shader_parameter("use_" + kind, 1.0)
