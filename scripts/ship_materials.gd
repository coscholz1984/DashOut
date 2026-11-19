
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

const FX_SHADER: Shader = preload("res://shaders/ship_hull.gdshader")

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
	mat.shader = FX_SHADER
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
