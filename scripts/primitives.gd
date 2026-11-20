
class_name Primitives
extends Object
## Shared factory for procedural meshes, materials and visual effects.
## Used by the game's world, ships, pickups and projectiles.

const BLOB_SHADER: Shader = preload("res://shaders/blob_shadow.gdshader")
const SHELL_SHADER: Shader = preload("res://shaders/energy_shell.gdshader")
const WAVE_SHADER: Shader = preload("res://shaders/plasma_wave.gdshader")
const BOLT_SHADER: Shader = preload("res://shaders/plasma_bolt.gdshader")

## Creates a StandardMaterial3D with optional metallic, emission
## and transparency properties.
static func mat(color: Color, metal := 0.0, rough := 1.0,
		emiss := Color(0, 0, 0, 0), ei := 0.0, opacity := -1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	if emiss.a > 0.0:
		m.emission_enabled = true
		m.emission = emiss
		m.emission_energy_multiplier = ei
	if opacity >= 0.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(color.r, color.g, color.b, opacity)
	return m

## Creates a StandardMaterial3D with optional emission and rim glow.
## Retains the standard lighting and shadow behaviour of mat().
## The rim effect is enabled when rim_color has a non-zero alpha.
static func glow_mat(color: Color, metal := 0.0, rough := 1.0,
		emiss := Color(0, 0, 0, 0), ei := 0.0,
		rim_color := Color(0, 0, 0, 0), rim_energy := 0.0,
		opacity := -1.0
) -> StandardMaterial3D:
	var m := mat(color, metal, rough, emiss, ei, opacity)
	if rim_color.a > 0.0:
		m.rim_enabled = true
		m.rim_color = rim_color
		m.rim = rim_energy
	return m

static func box(size: Vector3, m: Material, pos: Vector3, parent: Node,
		ry := 0.0, rz := 0.0, rx := 0.0, cast := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation = Vector3(rx, ry, rz)
	mi.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if cast
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	parent.add_child(mi)
	return mi

static func cyl(radii: Vector2, h: float, m: Material, pos: Vector3,
		parent: Node, rx := 0.0, cast := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radii.x
	cm.bottom_radius = radii.y
	cm.height = h
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	mi.rotation.x = rx
	mi.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if cast
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	parent.add_child(mi)
	return mi

static func sphere(r: float, m: Material, pos: Vector3, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

## Creates a soft radial shadow beneath an object.
##
## Blob shadows are used when full real-time shadows for entities
## are disabled. They remain independent of the scene's directional
## lighting and shadow pipeline.
##
## apply_shadow_mode() controls the visibility of the blob according
## to the selected shadow mode.
static func shadow_blob(
		parent: Node,
		size: Vector2,
		local_y: float
) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = BLOB_SHADER

	var mesh := PlaneMesh.new()
	mesh.size = size

	var blob := MeshInstance3D.new()
	blob.name = "BlobShadow"
	blob.mesh = mesh
	blob.material_override = mat
	# Keep the shadow slightly above the road surface to avoid z-fighting.
	blob.position.y = local_y
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(blob)
	return blob

## Applies the selected shadow mode to an entity.
##
## Full shadows enables real shadow casting on the entity's meshes
## and hides its blob shadow. Otherwise, real shadow casting is
## disabled and the blob represents the entity's shadow.
##
## The WorldSun remains enabled in both modes, so buildings and
## scenery continue to cast shadows independently of this setting.
static func apply_shadow_mode(root: Node3D, full_shadows: bool) -> void:
	var mode: GeometryInstance3D.ShadowCastingSetting = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if full_shadows
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	# Visual effects and transparent overlays must not cast shadows.
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if (
			mi.name != "BlobShadow"
			and mi.name != "EnergyShell"
			and mi.name != "PlasmaWave"
			and mi.name != "Outline"
			and mi.name != "GlassSkin"
		):
			(mi as GeometryInstance3D).cast_shadow = mode

	var blob := root.find_child("BlobShadow", true, false)
	if blob is GeometryInstance3D:
		(blob as GeometryInstance3D).visible = not full_shadows

## Creates a translucent energy shell around a model.
##
## The shared shader produces a view-angle-dependent rim glow and
## a subtle animated surface wobble. Colour, intensity and ripple
## are controlled through per-instance shader parameters.
##
## Energy shells never cast shadows.
static func energy_shell(
		parent: Node,
		scale3d: Vector3,
		color: Color,
		wobble := 0.02
) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = SHELL_SHADER
	mat.set_shader_parameter("shell_color", color)
	mat.set_shader_parameter("wobble", wobble)

	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 24
	mesh.rings = 16

	var shell := MeshInstance3D.new()
	shell.name = "EnergyShell"
	shell.mesh = mesh
	shell.material_override = mat
	shell.scale = scale3d
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(shell)
	return shell


## Sets the emission intensity of an energy shell.
static func set_shell_energy(
		shell: MeshInstance3D,
		intensity: float
) -> void:
	if shell == null:
		return
	var mat := shell.material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("intensity", intensity)


## Sets the collision and near-miss ripple strength of an energy shell.
## The value is clamped to the range 0..1.
static func set_shell_ripple(
		shell: MeshInstance3D,
		value: float
) -> void:
	if shell == null:
		return
	var mat := shell.material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("ripple", clampf(value, 0.0, 1.0))

## Creates the plasma projectile used by SUPER SHOT.
##
## Unlike the energy shell, this shader produces a visible,
## semi-transparent interior with animated turbulence and a
## bright Fresnel rim.
##
## The projectile never casts shadows. Its scale can be animated
## by the entity manager as it travels.
static func plasma_wave(parent: Node, pos: Vector3) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = WAVE_SHADER
	mat.set_shader_parameter("core_color", Color(0.20, 0.45, 1.0, 0.4))
	mat.set_shader_parameter("rim_color", Color(0.65, 0.90, 1.0, 1.0))
	mat.set_shader_parameter("intensity", 1.0)

	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 24
	mesh.rings = 16

	var wave := MeshInstance3D.new()
	wave.name = "PlasmaWave"
	wave.mesh = mesh
	wave.material_override = mat
	# Match the projectile's initial dimensions to the entity manager
	# so its first update does not introduce a visible size jump.
	wave.scale = Vector3(3.0, 1.4, 1.0)
	wave.position = pos
	wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(wave)
	return wave

## Creates the projectile used by the normal blaster.
##
## The shader produces a semi-transparent plasma body with animated
## turbulence, a bright Fresnel rim and a fading tail.
## The supplied colour controls the projectile's core and rim tint.
##
## The bolt travels along local -Z, with its tail extending toward +Z.
static func plasma_bullet(
	parent: Node, pos: Vector3,
	color := Color(0.45, 0.15, 1.0)
) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = BOLT_SHADER

	# Tint the core with the selected effect colour and lighten it for the rim.
	mat.set_shader_parameter("core_color", Color(color, 0.6))
	mat.set_shader_parameter("rim_color", color.lightened(0.4))
	mat.set_shader_parameter("intensity", 1.0)

	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.radial_segments = 12
	mesh.rings = 8

	var bolt := MeshInstance3D.new()
	bolt.name = "PlasmaBolt"
	bolt.mesh = mesh
	bolt.material_override = mat
	# Stretch the sphere along the flight axis; local -Z is forward.
	bolt.scale = Vector3(1.0, 1.0, 2.2)
	bolt.position = pos
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(bolt)
	return bolt
