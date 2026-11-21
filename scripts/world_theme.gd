
class_name WorldTheme
extends RefCounted

## Builds the shared environment used by the race world and garage preview.
## Includes the sky, ground, fog and lighting, using the selected track palette.


## Tracks all active ground materials so their textures scroll together.
## Weak references allow materials from freed worlds to be discarded.
static var _ground_materials: Array[WeakRef] = []


static func build(parent: Node, track: Dictionary) -> void:
	var sky_color: Color = Color(str(track.get("sky", "0a0a14")))
	var fog_color: Color = Color(str(track.get("fog", "14142a")))
	var ground_color: Color = Color(str(track.get("grass2", "10131f")))
	var accent_color: Color = Color(str(track.get("line", "00f5ff")))

	_build_sky(parent, sky_color, fog_color, ground_color)
	_build_ground(parent, ground_color, fog_color)
	_build_lighting(parent, sky_color, accent_color)


# ------------------------------------------------------------
# SKY
# ------------------------------------------------------------

static func _build_sky(
	parent: Node,
	sky_color: Color,
	fog_color: Color,
	ground_color: Color
) -> void:
	var sky_material := ProceduralSkyMaterial.new()

	# Darken the sky toward the zenith and blend its horizon
	# toward the fog colour for a seamless transition.
	sky_material.sky_top_color = sky_color.darkened(0.9)
	sky_material.sky_horizon_color = sky_color.lightened(
		0.20
	).lerp(fog_color, 0.40)

	# sky_curve — tunes the details of the gradient
	sky_material.sky_curve = 0.18
	sky_material.sky_energy_multiplier = 1.0

	# Keep the sky's lower hemisphere consistent with the ground plane.
	sky_material.ground_horizon_color = fog_color.lerp(
		ground_color, 0.45
	)
	sky_material.ground_bottom_color = ground_color.darkened(0.25)
	sky_material.ground_curve = 0.20
	sky_material.ground_energy_multiplier = 1.0

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky

	# Ambient illumination.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = sky_color.lerp(
		Color(0.35, 0.38, 0.55), 0.35
	)
	environment.ambient_light_energy = 0.7

	# Fog softens distant scenery and hides the appearance of newly
	# spawned road segments near the horizon.
	environment.fog_enabled = true
	environment.fog_light_color = fog_color
	environment.fog_density = 0.0065

	# Blend the fog colour into the sky to soften the horizon
	# and reduce the visibility of the sky gradient.
	environment.fog_sky_affect = 0.8

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	parent.add_child(world_environment)


# ------------------------------------------------------------
# GROUND
# ------------------------------------------------------------

static func _build_ground(
	parent: Node,
	ground_color: Color,
	fog_color: Color
) -> void:
	# A real, horizontal ground plane.
	# PlaneMesh is horizontal by default; do not rotate it.
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(4000.0, 4000.0)
	ground_mesh.subdivide_width = 1
	ground_mesh.subdivide_depth = 1

	var ground := MeshInstance3D.new()
	ground.name = "WorldGround"
	ground.mesh = ground_mesh

	# Lower the ground slightly to avoid z-fighting with the road.
	ground.position = Vector3(0.0, -0.15, 0.0)

	var ground_material := ShaderMaterial.new()
	ground_material.shader = _create_ground_shader()

	ground_material.set_shader_parameter(
		"near_ground_color",
		ground_color.darkened(0.12)
	)
	ground_material.set_shader_parameter(
		"horizon_ground_color",
		ground_color.lerp(fog_color, 0.8)
	)

	# Set the distance range for the ground-to-horizon gradient.
	ground_material.set_shader_parameter(
		"gradient_start",
		35.0
	)
	ground_material.set_shader_parameter(
		"gradient_end",
		240.0
	)

	# Load optional ground textures. The gradient remains the fallback
	# when any texture is unavailable.
	var ground_albedo := TextureManager.tex("ground_albedo.png")
	if ground_albedo != null:
		ground_material.set_shader_parameter("albedo_tex", ground_albedo)
		ground_material.set_shader_parameter("use_albedo", 1.0)
	var ground_normal := TextureManager.tex("ground_normal.png")
	if ground_normal != null:
		ground_material.set_shader_parameter("normal_tex", ground_normal)
		ground_material.set_shader_parameter("use_normal", 1.0)
	var ground_roughness := TextureManager.tex(
		"ground_roughness.png"
	)
	if ground_roughness != null:
		ground_material.set_shader_parameter(
			"roughness_tex", ground_roughness
		)
		ground_material.set_shader_parameter("use_roughness", 1.0)

	ground.material_override = ground_material
	parent.add_child(ground)

	# Register every ground material so race and preview textures
	# stay synchronised with the scrolling world.
	_ground_materials.append(weakref(ground_material))
	_ground_materials.append(weakref(ground_material))


## Updates the texture offset of every active ground material.
## Removes references to materials whose worlds have been freed.
static func update_ground_scroll(distance: float) -> void:
	var alive: Array[WeakRef] = []
	for ref in _ground_materials:
		var material := ref.get_ref() as ShaderMaterial
		if material != null:
			material.set_shader_parameter(
				"scroll_offset",
				distance
			)
			alive.append(ref)
	_ground_materials = alive


static func _create_ground_shader() -> Shader:
	var shader := Shader.new()
	shader = load("res://shaders/ground.gdshader")

	return shader


# ------------------------------------------------------------
# LIGHTING
# ------------------------------------------------------------

static func _build_lighting(
	parent: Node,
	sky_color: Color,
	accent_color: Color
) -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "WorldSun"
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)

	sun.light_color = sky_color.lerp(
		Color(0.72, 0.78, 1.0), 0.45
	)
	sun.light_energy = 0.9

	# Keep directional shadows always enabled for buildings and scenery.
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0

	parent.add_child(sun)

	var neon := OmniLight3D.new()
	neon.name = "TrackAccentLight"
	neon.position = Vector3(0.0, 6.0, -30.0)
	neon.omni_range = 60.0
	neon.light_color = accent_color
	neon.light_energy = 1.0
	parent.add_child(neon)
