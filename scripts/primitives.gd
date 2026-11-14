
class_name Primitives
extends Object
## Shared factory for procedural meshes, materials and visual effects.
## Used by the game's world, ships, pickups and projectiles.

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

## Shared blob-shadow shader, compiled once and reused by all instances.
static var _blob_shader: Shader

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
	if _blob_shader == null:
		_blob_shader = Shader.new()
		_blob_shader.code = """
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
"""
	var mat := ShaderMaterial.new()
	mat.shader = _blob_shader

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


## Shared energy-shell shader, compiled once and reused by all instances.
static var _shell_shader: Shader

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
	if _shell_shader == null:
		_shell_shader = Shader.new()
		_shell_shader.code = """
shader_type spatial;
render_mode cull_disabled, blend_add, unshaded;

uniform vec4 shell_color : source_color =
	vec4(0.13, 0.83, 1.0, 0.5);
uniform float intensity = 1.0;
uniform float wobble = 0.02;
uniform float ripple = 0.0;

void vertex() {
	// Breathing wobble: the surface ripples gently along y.
	VERTEX += NORMAL * sin(TIME * 5.0 + VERTEX.y * 4.0) * wobble;
}

void fragment() {
	// Fresnel edge: bright at the silhouette, invisible head-on.
	// abs() because cull_disabled also renders backfaces, whose
	// NORMAL points the other way.
	float f = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);
	// Collision / near-miss ripple: a rapid pulsing SURGE layered
	// on the steady glow while the ripple decays (main.gd drives
	// it from crashes, shielded rams and traffic flybys).
	float surge = 1.0 + ripple * (1.5 + 1.5 * sin(TIME * 24.0));
	ALPHA = shell_color.a * f * intensity * surge;
	ALBEDO = shell_color.rgb;
	EMISSION = shell_color.rgb * f * intensity * surge;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _shell_shader
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


## Shared plasma-wave shader, compiled once and reused by all instances.
static var _wave_shader: Shader

## Creates the plasma projectile used by SUPER SHOT.
##
## Unlike the energy shell, this shader produces a visible,
## semi-transparent interior with animated turbulence and a
## bright Fresnel rim.
##
## The projectile never casts shadows. Its scale can be animated
## by the entity manager as it travels.
static func plasma_wave(parent: Node, pos: Vector3) -> MeshInstance3D:
	if _wave_shader == null:
		_wave_shader = Shader.new()
		_wave_shader.code = """
shader_type spatial;
render_mode cull_disabled, blend_add, unshaded;

uniform vec4 core_color : source_color =
	vec4(0.20, 0.45, 1.0, 0.4);
uniform vec4 rim_color : source_color =
	vec4(0.65, 0.90, 1.0, 1.0);
uniform float intensity = 1.0;

void fragment() {
	// Brighten the silhouette while keeping the backfaces consistent.
	float f = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	// Layered sine waves create animated turbulence inside the plasma.
	float t = TIME * 6.0;
	float turb = sin(VERTEX.x * 8.0 + t) * 0.5
		+ sin(VERTEX.y * 11.0 - t * 1.3) * 0.3
		+ sin((VERTEX.x + VERTEX.y) * 6.0 + t * 0.7) * 0.2;
	turb = 0.5 + 0.5 * turb;
	vec3 col = mix(core_color.rgb, rim_color.rgb, f);
	// Keep the interior visible while allowing the rim to become brighter.
	ALPHA = core_color.a * (0.45 + 0.55 * f)
		* (0.7 + 0.3 * turb) * intensity;
	EMISSION = col * (0.6 + 1.4 * f)
		* intensity * (0.8 + 0.4 * turb);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _wave_shader
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

## Shared plasma-bolt shader, compiled once and reused by all instances.
static var _bolt_shader: Shader

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
	if _bolt_shader == null:
		_bolt_shader = Shader.new()
		_bolt_shader.code = """
shader_type spatial;
render_mode cull_disabled, blend_add, unshaded;

uniform vec4 core_color : source_color =
	vec4(0.45, 0.15, 1.0, 0.6);
uniform vec4 rim_color : source_color =
	vec4(0.85, 0.6, 1.0, 1.0);
uniform float intensity = 1.0;

void fragment() {
	// Brighten the silhouette while keeping the backfaces consistent.
	float f = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	// Fast, small-scale turbulence makes the projectile visibly churn.
	float t = TIME * 9.0;
	float turb = sin(VERTEX.x * 14.0 + t) * 0.5
		+ sin(VERTEX.y * 17.0 - t * 1.4) * 0.5;
	turb = 0.5 + 0.5 * turb;
	// Fade the rear of the projectile so it dissolves toward its tail.
	// Fade emission as well as transparency to darken the tail.
	float tail = 1.0 - smoothstep(0.0, 1.0, VERTEX.z);
	vec3 col = mix(core_color.rgb, rim_color.rgb, f);
	ALPHA = core_color.a * (0.5 + 0.5 * f)
		* (0.7 + 0.3 * turb) * tail * intensity;
	EMISSION = col * (0.7 + 1.3 * f)
		* intensity * (0.8 + 0.4 * turb) * tail;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _bolt_shader
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
