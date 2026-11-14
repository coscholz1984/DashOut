
class_name TextureManager
extends Object
## Loads optional external PBR textures and creates textured materials.
## Missing textures generate a warning and fall back to plain materials,
## allowing the game to run without the texture library.

const BASE_DIR := "res://textures/"

## Loads a texture from BASE_DIR, returning null if it is unavailable.
## Missing files generate a warning.
static func tex(file_name: String) -> Texture2D:
	if file_name == "":
		return null
	var path := BASE_DIR + file_name
	if not ResourceLoader.exists(path):
		push_warning("[TextureManager] missing texture: " + path)
		return null
	return load(path)


## Creates a StandardMaterial3D using optional external PBR textures.
## Missing albedo textures fall back to the plain colour material.
##
## The supplied colour tints the albedo texture. Its brightness is
## adjusted toward white to compensate for darker source textures.
static func surface_mat(
		color: Color,
		metal := 0.7,
		rough := 0.35,
		albedo_file := "",
		normal_file := "",
		roughness_file := "",
		uv_scale := Vector3.ONE,
		metallic_file := "",
		ao_file := ""
) -> Material:
	var albedo := tex(albedo_file)
	if albedo == null:
		return Primitives.mat(color, metal, rough)

	var material := StandardMaterial3D.new()
	material.albedo_texture = albedo
	material.albedo_color = color.lerp(Color.WHITE, 0.45)
	material.metallic = metal
	material.roughness = rough
	# Apply the same UV scaling to all textures using the UV1 transform.
	material.uv1_scale = uv_scale

	var normal := tex(normal_file)
	if normal != null:
		material.normal_enabled = true
		material.normal_texture = normal
		material.normal_scale = 1.0

	var roughness := tex(roughness_file)
	if roughness != null:
		material.roughness_texture = roughness
		# Standard PBR roughness maps use the GREEN channel.
		material.roughness_texture_channel = (
			BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		)

	# ORM texture sets store metallic values in the BLUE channel.
	# This is also Godot's default metallic texture channel.
	var metallic := tex(metallic_file)
	if metallic != null:
		material.metallic_texture = metallic
		material.metallic_texture_channel = (
			BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		)

	# Optional AO map adds shading to creases and recessed details.
	var ao := tex(ao_file)
	if ao != null:
		material.ao_enabled = true
		material.ao_texture = ao

	return material
