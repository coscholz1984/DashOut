
class_name PlayerShip
extends Node3D
## The player craft — a procedurally generated ship (classic) or an 
## imported external model, selected in the garage's SHIP MODELS tab. 

var skin: Dictionary
var preview_mode := false
var hull := Node3D.new()
var flames: Array[MeshInstance3D] = []
## Current exhaust intensity (0..1), updated by update_craft().
## The flicker animation reads this independently, so flames keep
## animating while the race is paused and in the garage preview.
var flame_intensity := 0.0
var trails: Array[MeshInstance3D] = []
var puffs: Array[Dictionary] = []
var last_spawn := 0.0
var target_x := 0.0
## Smoothed lane-change roll, animated independently of lane movement.
var bank := 0.0
## Controls the geometry of lane-change banking.
## The ship rotates around a pivot below its belly, while BANK_LIFT
## raises it during the turn to keep the wingtips clear of the road.
const ROLL_PIVOT_Y := -0.1
const BANK_LIFT := 0.3
## Overall opacity of the exhaust flame body.
## Lower values make the flame more transparent.
const FLAME_OPACITY := 0.55
## Directional exhaust shader shared by player and traffic flames.
##
## Shapes the stretched sphere into a soft jet with a colour gradient
## from the engine outlet toward the tail. The rear fades to
## transparency, while the soft silhouette avoids a hard spherical
## outline.
##
## Additive blending preserves the bright emissive appearance.
## Intensity and overdrive are animated at runtime; flame colour
## and opacity are supplied by the owning ship.
const FLAME_SHADER: Shader = preload("res://shaders/ship_flame.gdshader")

## Creates a flame material using the shared exhaust shader.
## Each ship gets its own material instance so its exhaust animation
## remains independent of other ships.
static func flame_material(
		op: float,
		flame_color := Color(0.25, 0.5, 1.0),
		overdrive_color := Color(0.66, 0.33, 0.97)
) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FLAME_SHADER
	mat.set_shader_parameter("opacity", op)
	mat.set_shader_parameter("radius", 0.14)
	mat.set_shader_parameter("flame_color", flame_color)
	mat.set_shader_parameter("overdrive_color", overdrive_color)
	return mat

var trail_x := 0.0  # Smoothed horizontal position of the wing light-lanes.

## Dynamic hull materials driven by update_craft().
## Their speed, overdrive and gunfire uniforms are updated together.
var fx_materials: Array[ShaderMaterial] = []

## Duplicated materials belonging to the imported hull.
## They receive the same runtime effects as the procedural hull
## materials while retaining the imported textures.
var import_materials: Array[StandardMaterial3D] = []

var fx_overdrive := 0.0
var fx_flash := 0.0

## Player-selected effect colours loaded from SaveManager.
## Used by the exhaust flames and overdrive effects on the hull.
var effect_flame := Color(0.25, 0.5, 1.0)
var effect_overdrive := Color(0.66, 0.33, 0.97)

## Per-hull anchor positions for shared engine and race effects.
## Hull builders configure these values before the effect builders run.
## This allows different ship designs to reuse the same effect logic.
var engine_anchors: Array = [-0.38, 0.38]
var engine_flame_y := 0.32

## Longitudinal position of the exhaust outlets in ship-local space.
var engine_flame_z := 1.86

## Horizontal anchor positions for the wing light-lanes.
var wing_anchors: Array = [-0.85, 0.85]

func _init(craft_skin: Dictionary, as_preview: bool = false) -> void:
	skin = craft_skin
	preview_mode = as_preview
	# Ensure all hull builders have the colour keys they require.
	# White defaults preserve the original model colours.
	if not skin.has("body"): skin["body"] = "ffffff"
	if not skin.has("roof"): skin["roof"] = "ffffff"
	if not skin.has("accent"): skin["accent"] = "00f5ff"
	# Load the player's selected exhaust and overdrive colours.
	effect_flame = SaveManager.effect_color("effect_flame")
	effect_overdrive = SaveManager.effect_color("effect_overdrive")

func _ready() -> void:
	hull.rotation.y = PI
	add_child(hull)

	# Build the selected hull, falling back to the classic
	# procedural design if the model is unknown or unavailable.
	match str(skin.get("model", "slim")):
		"levdart":
			_build_lev_dart_hull()
		"catamaran":
			_build_catamaran_hull()
		"twinfin":
			_build_twinfin_hull()
		"slim":
			_build_slim_hull()
		"dispatcher":
			_build_dispatcher_hull()
		"striker":
			_build_striker_hull()
		_:
			_build_classic_hull()

	# Wrap only the completed hull. Engine and race effects are
	# added afterwards and remain outside the glass skin.
	_add_glass_skin(hull)

	# Apply the player's selected overdrive colour to all dynamic
	# hull materials.
	for m in fx_materials:
		m.set_shader_parameter("overdrive_color", effect_overdrive)

	_build_engine_effects()
	_build_race_effects()


## Imported Slimline racer.
## Uses its own materials and textures, with the selected body colour
## applied as an albedo tint.
## Falls back to the classic procedural hull if the model is unavailable.
const SLIM_MODEL_PATH := "res://models/player_slim.glb"
## Scale correction for the imported model.
const SLIM_MODEL_SCALE := Vector3.ONE * 0.6
const SLIM_MODEL_ROTATION := Vector3.ZERO
const SLIM_MODEL_LIFT := 0.0
## Local light for the imported hull.
## A dedicated render layer restricts illumination to the ship's
## own meshes, preventing light spill onto the road and other objects.
const HULL_LIGHT_RANGE := 4.5
const HULL_LIGHT_ENERGY := 1.6

## Render layer shared by the hull meshes and their local light.
const HULL_LIGHT_LAYER := 21

## Local position of the hull light, adjusted for the ship's
## orientation so its world-space direction matches the scene lighting.
const HULL_LIGHT_OFFSET := Vector3(-0.7, 2.0, 1.2)
## Emission strengths for overdrive and gunfire effects on imported
## hull materials. Kept deliberately subtle to preserve texture detail.
const IMPORT_OVERDRIVE_GLOW := 0.1
const IMPORT_FLASH_GLOW := 0.45


## Additive transparent shell around the ship hull.
## Each hull mesh receives a slightly enlarged duplicate using a
## shared Fresnel shader, producing a glow along the silhouette.
##
## The shell's intensity follows the overdrive level, with an
## additional contribution from gunfire flashes. It remains
## effectively invisible during normal driving.
const GLASS_SKIN_SCALE := 1.06
const GLASS_SKIN_COLOR := Color(0.65, 0.3, 1.0)
const GLASS_SKIN_SHADER: Shader = preload("res://shaders/ship_glass_skin.gdshader")

## Shared material for all glass-skin meshes.
## A common intensity keeps the entire shell synchronized.
var glass_material: ShaderMaterial

func _add_glass_skin(root: Node3D) -> void:
	glass_material = ShaderMaterial.new()
	glass_material.shader = GLASS_SKIN_SHADER
	glass_material.set_shader_parameter("glow_color", effect_overdrive)

	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		var shell := MeshInstance3D.new()
		shell.name = "GlassSkin"
		shell.mesh = (mesh as MeshInstance3D).mesh

		# Child of the mesh itself: inherits its full transform, so
		# the shell hugs the part and only adds the wrap margin.
		shell.scale = Vector3.ONE * GLASS_SKIN_SCALE
		shell.material_override = glass_material
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(mesh as MeshInstance3D).add_child(shell)


## Gradient shader for the wingtip light-lanes.
## The glow starts at the wingtip and fades toward the rear of the
## streak. Its colour blends from blue to purple during overdrive.
##
## Intensity is animated at runtime to create a subtle flicker.
## Additive blending preserves the emissive appearance.
const TRAIL_SHADER: Shader = preload("res://shaders/ship_trail.gdshader")

static func trail_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TRAIL_SHADER
	return mat


func _build_slim_hull() -> void:
	var model := _load_imported_hull(
		SLIM_MODEL_PATH, SLIM_MODEL_SCALE, SLIM_MODEL_ROTATION, SLIM_MODEL_LIFT
	)
	if model == null:
		_build_classic_hull()
		return
	_tint_imported_hull(
		model, Color.WHITE, Color.WHITE, effect_overdrive
	)

	# Configure the shared effects for the Slimline's exhaust outlets
	# and wingtip positions.
	engine_anchors = [-0.26, 0.26]
	engine_flame_y = 0.27
	engine_flame_z = 2.5
	wing_anchors = [-0.85, 0.85]

	_add_hull_light(model)


## Imported Dispatcher cruiser.
const DISPATCHER_MODEL_PATH := "res://models/Dispatcher.glb"
const DISPATCHER_MODEL_SCALE := Vector3.ONE * 0.45
const DISPATCHER_MODEL_ROTATION := Vector3.ZERO
const DISPATCHER_MODEL_LIFT := 0.6


func _build_dispatcher_hull() -> void:
	var model := _load_imported_hull(
		DISPATCHER_MODEL_PATH, DISPATCHER_MODEL_SCALE,
		DISPATCHER_MODEL_ROTATION, DISPATCHER_MODEL_LIFT
	)
	if model == null:
		_build_classic_hull()
		return
	_tint_imported_hull(
		model, Color.WHITE, Color.WHITE, effect_overdrive
	)
	# One central exhaust flame.
	engine_anchors = [0.0]
	engine_flame_y = 0.65
	engine_flame_z = 2.4
	wing_anchors = [-0.85, 0.85]
	_add_hull_light(model)


## Imported Striker interceptor.
const STRIKER_MODEL_PATH := "res://models/Striker.glb"
const STRIKER_MODEL_SCALE := Vector3.ONE * 0.5
const STRIKER_MODEL_ROTATION := Vector3.ZERO
const STRIKER_MODEL_LIFT := 0.6


func _build_striker_hull() -> void:
	var model := _load_imported_hull(
		STRIKER_MODEL_PATH, STRIKER_MODEL_SCALE,
		STRIKER_MODEL_ROTATION, STRIKER_MODEL_LIFT
	)
	if model == null:
		_build_classic_hull()
		return
	_tint_imported_hull(
		model, Color.WHITE, Color.WHITE, effect_overdrive
	)
	# One central exhaust flame.
	engine_anchors = [0.0]
	engine_flame_y = 0.725
	engine_flame_z = 2.2
	wing_anchors = [-0.85, 0.85]
	_add_hull_light(model)


## Loads and configures an imported hull model.
## Returns null if the model is unavailable so the caller can
## fall back to the procedural hull.
## The instance is parented to the shared hull group.
func _load_imported_hull(
	path: String, model_scale: Vector3,
	model_rotation: Vector3, model_lift: float
) -> Node3D:
	if not ResourceLoader.exists(path):
		push_warning("[PlayerShip] missing model: " + path)
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var model := scene.instantiate()
	model.name = "ImportedHull"
	model.scale = model_scale
	model.rotation = model_rotation
	model.position.y = model_lift
	hull.add_child(model)
	return model


## Adds a local light that illuminates only the imported hull.
## The light uses a dedicated render layer shared by the hull meshes,
## preventing illumination from spilling onto the road or scenery.
## It is parented to the model so it follows the ship's movement.
func _add_hull_light(root: Node3D) -> void:
	var light := OmniLight3D.new()
	light.name = "HullLight"
	light.omni_range = HULL_LIGHT_RANGE
	light.light_energy = HULL_LIGHT_ENERGY
	light.shadow_enabled = false
	var layer_bit := 1 << (HULL_LIGHT_LAYER - 1)
	light.light_cull_mask = layer_bit
	light.position = HULL_LIGHT_OFFSET
	root.add_child(light)
	# Add every hull mesh to the light's dedicated render layer.
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		(mesh as GeometryInstance3D).layers |= layer_bit


## Applies the selected skin colours and emission effects to an imported hull.
##
## Each StandardMaterial3D is duplicated before modification so the
## original imported resources remain unchanged. The body and roof
## colours tint the original albedo textures rather than replacing them.
##
## Surfaces are assigned to the body or roof colour according to
## their original albedo luminance. Glass and window materials are
## excluded to preserve their appearance.
##
## Each duplicated material also receives additive accent emission.
## The materials are registered in import_materials so update_craft()
## can animate their emission during speed, overdrive and gunfire effects.
func _tint_imported_hull(
	root: Node3D, tint: Color, roof: Color, accent: Color
) -> void:
	# Pass 1: gather the tintable surfaces.
	var targets: Array = []
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		for surface_index in (
			instance.get_surface_override_material_count()
		):
			var material := instance.get_active_material(
				surface_index
			)
			if not (material is StandardMaterial3D):
				continue
			var std := material as StandardMaterial3D
			var name := str(std.resource_name).to_lower()
			# Preserve glass and window materials without skin tinting.
			if name.contains("glass") or name.contains("window"):
				continue
			targets.append(
				{"instance": instance, "index": surface_index, "mat": std}
			)

	# Pass 2: luminance ranking of the ORIGINAL albedo.
	for t in targets:
		var std: StandardMaterial3D = t.mat
		# Texture brightness cannot be determined from albedo_color alone.
		t["lum"] = (
			0.5
			if std.albedo_texture != null
			else std.albedo_color.get_luminance()
		)

	var lums: Array = targets.map(func(t): return t.lum)
	lums.sort()
	var median: float = (
		lums[lums.size() / 2] if lums.size() > 1 else 1.0
	)
	var all_equal: bool = (
		lums.size() < 2 or absf(lums[-1] - lums[0]) < 0.001
	)

	# Pass 3: assign skin colours and create independent material copies.
	var surface_counter := 0
	for t in targets:
		var std: StandardMaterial3D = t.mat
		var secondary: bool
		if all_equal:
			# Alternate colours when luminance cannot distinguish surfaces.
			secondary = surface_counter % 2 == 1
		else:
			secondary = t.lum < median
		surface_counter += 1
		# Modify a duplicate rather than the shared imported material.
		var tinted := std.duplicate()
		tinted.albedo_color = roof if secondary else tint
		tinted.emission_enabled = true
		tinted.emission_operator = (
			BaseMaterial3D.EMISSION_OP_ADD
		)
		tinted.emission = accent
		tinted.emission_energy_multiplier = 0.0
		t.instance.set_surface_override_material(
			t.index, tinted
		)
		# Register the copy for runtime emission updates.
		import_materials.append(tinted)


## Builds the classic procedural dart hull.
func _build_classic_hull() -> void:
	# Hull and wing plating use the dynamic shader; other components
	# retain their static glow materials.
	var body := ShipMaterials.fx_mat(
		Color(skin.body), Color(skin.accent)
	)
	var roof := ShipMaterials.fx_mat(
		Color(skin.roof), Color(skin.accent), 0.75, 0.25
	)
	fx_materials.append(body)
	fx_materials.append(roof)
	var accent := ShipMaterials.neon(Color(skin.accent), 1.8)
	var glass := ShipMaterials.glass()
	var thruster := ShipMaterials.neon(Color("22d3ee"), 2.0)
	var dark := ShipMaterials.dark(Color("586180"))
	var tail := ShipMaterials.neon(Color("ff2b2b"), 1.4)
	# keel + lower hull + needle tip
	Primitives.box(Vector3(0.3, 0.08, 3.4), body, Vector3(0, 0.12, -0.3), hull, 0, 0, 0, true)
	Primitives.box(Vector3(1.05, 0.2, 1.9), body, Vector3(0, 0.28, -0.55), hull, 0, 0, 0, true)
	Primitives.box(Vector3(0.7, 0.18, 1.1), body, Vector3(0, 0.26, 0.55), hull, 0, 0, 0, true)
	Primitives.box(Vector3(0.4, 0.14, 0.7), body, Vector3(0, 0.24, 1.2), hull, 0, 0, 0, true)
	Primitives.box(Vector3(0.14, 0.1, 0.5), body, Vector3(0, 0.2, 1.72), hull, 0, 0, 0, true)
	# upper ridge
	Primitives.box(Vector3(0.55, 0.45, 1.5), roof, Vector3(0, 0.5, -0.75), hull, 0, 0, 0, true)
	Primitives.box(Vector3(0.34, 0.34, 1.5), roof, Vector3(0, 0.44, 0.15), hull, 0, 0, 0, true)
	Primitives.box(Vector3(0.2, 0.22, 1.1), roof, Vector3(0, 0.34, 1.05), hull, 0, 0, 0, true)
	Primitives.box(Vector3(0.26, 0.12, 0.9), glass, Vector3(0, 0.52, 0.2), hull)
	# neon spine
	Primitives.box(Vector3(0.08, 0.05, 1.6), accent, Vector3(0, 0.62, -0.7), hull)
	Primitives.box(Vector3(0.06, 0.04, 1.4), accent, Vector3(0, 0.5, 0.2), hull)
	# tilted delta wings
	var wl := Primitives.box(Vector3(0.85, 0.06, 1.0), roof, Vector3(-0.85, 0.3, -0.85), hull, -0.28, 0.38, 0, true)
	var wr := Primitives.box(Vector3(0.85, 0.06, 1.0), roof, Vector3(0.85, 0.3, -0.85), hull, 0.28, -0.38, 0, true)
	Primitives.box(Vector3(0.07, 0.05, 1.1), accent, Vector3(-1.3, 0.14, -1.0), hull, -0.28, 0.38, 0)
	Primitives.box(Vector3(0.07, 0.05, 1.1), accent, Vector3(1.3, 0.14, -1.0), hull, 0.28, -0.38, 0)
	# Rear engine blocks, thruster glow plates and vertical fin.
	Primitives.box(Vector3(0.4, 0.34, 0.9), dark, Vector3(-0.38, 0.32, -1.35), hull, 0, 0, 0, true)
	Primitives.box(Vector3(0.4, 0.34, 0.9), dark, Vector3(0.38, 0.32, -1.35), hull, 0, 0, 0, true)
	Primitives.box(Vector3(0.3, 0.28, 0.08), thruster, Vector3(-0.38, 0.32, -1.82), hull)
	Primitives.box(Vector3(0.3, 0.28, 0.08), thruster, Vector3(0.38, 0.32, -1.82), hull)
	Primitives.box(Vector3(0.07, 0.8, 1.0), roof, Vector3(0, 0.85, -1.15), hull, 0, 0, 0.18, true)
	Primitives.box(Vector3(0.06, 0.06, 0.8), accent, Vector3(0, 1.18, -1.28), hull)
	Primitives.box(Vector3(0.09, 0.12, 0.06), tail, Vector3(0, 0.9, -1.66), hull)
	# Short rear keel light between the engines.
	var keel := ShipMaterials.neon(Color("22d3ee"), 1.2)
	Primitives.box(Vector3(0.22, 0.05, 1.4), keel, Vector3(0, 0.05, -1.5), hull)


## Builds the LEV Dart, a flat racer with swept delta wings,
## a tapered nose, twin rear engines and a vertical tail fin.
func _build_lev_dart_hull() -> void:
	# Apply the same dynamic hull materials as the classic dart.
	var body := ShipMaterials.fx_mat(
		Color(skin.body), Color(skin.accent)
	)
	var roof := ShipMaterials.fx_mat(
		Color(skin.roof), Color(skin.accent), 0.75, 0.25
	)
	fx_materials.append(body)
	fx_materials.append(roof)
	var accent := ShipMaterials.neon(Color(skin.accent), 1.8)
	var glass := ShipMaterials.glass()
	var thruster := ShipMaterials.neon(Color("22d3ee"), 2.0)
	var dark := ShipMaterials.dark(Color("212529"))
	var tail := ShipMaterials.neon(Color("ff2b2b"), 1.4)
	# Build the fuselage from progressively narrower sections,
	# tapering into a slightly downward-sloping nose.
	Primitives.box(Vector3(0.9, 0.3, 2.6), body, Vector3(0, 0.24, -0.2), hull, 0, 0, 0, true)
	Primitives.box(Vector3(0.5, 0.2, 1.2), body, Vector3(0, 0.26, 0.95), hull, 0, 0, 0.1, true)
	Primitives.box(Vector3(0.26, 0.15, 1.0), body, Vector3(0, 0.18, 1.55), hull, 0, 0, 0.14, true)
	Primitives.box(Vector3(0.1, 0.1, 0.7), body, Vector3(0, 0.11, 2.2), hull, 0, 0, 0.16, true)
	# Dark stripes along the fuselage sides.
	Primitives.box(Vector3(0.94, 0.09, 2.2), dark, Vector3(0, 0.32, -0.3), hull)
	Primitives.box(Vector3(0.54, 0.06, 0.9), dark, Vector3(0, 0.28, 0.85), hull, 0, 0, 0.1)
	# Low cockpit canopy positioned toward the middle of the hull.
	Primitives.box(Vector3(0.34, 0.14, 0.7), glass, Vector3(0, 0.44, -0.3), hull)
	# Swept delta wings with slightly lowered tips.
	Primitives.box(Vector3(0.6, 0.07, 1.2), roof, Vector3(-0.60, 0.18, -0.55), hull, 0.2, 0.42, 0.08, true)
	Primitives.box(Vector3(0.6, 0.07, 1.2), roof, Vector3(0.60, 0.18, -0.55), hull, -0.2, -0.42, 0.08, true)
	# Neon accents along the outer wing edges.
	Primitives.box(Vector3(0.12, 0.05, 1.5), accent, Vector3(-1.0, 0.05, -0.52), hull, 0.2, -0.42, 0.08)
	Primitives.box(Vector3(0.12, 0.05, 1.5), accent, Vector3(1.0, 0.05, -0.52), hull, -0.2, 0.42, 0.08)
	# Neon accent along the top of the fuselage.
	Primitives.box(Vector3(0.08, 0.05, 2.0), accent, Vector3(0, 0.42, 0.2), hull)
	# Twin rear engines with illuminated thruster plates.
	Primitives.box(Vector3(0.42, 0.34, 0.9), dark, Vector3(-0.38, 0.34, -1.3), hull, 0, 0, 0, true)
	Primitives.box(Vector3(0.42, 0.34, 0.9), dark, Vector3(0.38, 0.34, -1.3), hull, 0, 0, 0, true)
	Primitives.box(Vector3(0.3, 0.28, 0.08), thruster, Vector3(-0.38, 0.34, -1.8), hull)
	Primitives.box(Vector3(0.3, 0.28, 0.08), thruster, Vector3(0.38, 0.34, -1.8), hull)
	# Swept rear fin with matching accent strip and navigation light.
	Primitives.box(Vector3(0.06, 0.42, 0.8), roof, Vector3(0, 0.55, -0.85), hull, 0, 0, -0.5, true)
	Primitives.box(Vector3(0.05, 0.28, 0.06), accent, Vector3(0, 0.66, -1.12), hull, 0, 0, -0.5)
	Primitives.box(Vector3(0.09, 0.1, 0.06), tail, Vector3(0, 0.71, -1.22), hull, 0, 0, -0.5)
	# Short rear keel light between the engines.
	var keel := ShipMaterials.neon(Color("22d3ee"), 1.2)
	Primitives.box(Vector3(0.22, 0.05, 1.4), keel, Vector3(0, 0.05, -1.5), hull)


## Builds the Splitstream catamaran.
## Two parallel hulls leave an open channel through the nose and
## cockpit area, joined by a central bridge and rear cross-beam.
func _build_catamaran_hull() -> void:
	# Apply the same dynamic hull materials as the other procedural ships.
	var body := ShipMaterials.fx_mat(
		Color(skin.body), Color(skin.accent)
	)
	var roof := ShipMaterials.fx_mat(
		Color(skin.roof), Color(skin.accent), 0.75, 0.25
	)
	fx_materials.append(body)
	fx_materials.append(roof)
	var accent := ShipMaterials.neon(Color(skin.accent), 1.8)
	var glass := ShipMaterials.glass()
	var thruster := ShipMaterials.neon(Color("22d3ee"), 2.0)
	var dark := ShipMaterials.dark(Color("586180"))
	# Build the two tapered hulls, leaving an open channel between them.
	for x in [-0.55, 0.55]:
		Primitives.box(Vector3(0.42, 0.28, 2.6), body, Vector3(x, 0.22, 0.0), hull, 0, 0, 0, true)
		Primitives.box(Vector3(0.3, 0.2, 1.0), body, Vector3(x, 0.2, 1.5), hull, 0, 0, 0.1, true)
		Primitives.box(Vector3(0.16, 0.12, 0.6), body, Vector3(x, 0.15, 2.1), hull, 0, 0, 0.14, true)
		# Neon accent along the outer edge.
		Primitives.box(Vector3(0.05, 0.05, 2.4), accent, Vector3(x * 1.38, 0.2, 0.1), hull)
		# Rear engine block and illuminated thruster plate.
		Primitives.box(Vector3(0.4, 0.3, 0.9), dark, Vector3(x, 0.3, -1.35), hull, 0, 0, 0, true)
		Primitives.box(Vector3(0.28, 0.24, 0.08), thruster, Vector3(x, 0.3, -1.82), hull)
	# Central cockpit bridge spanning the open channel.
	Primitives.box(Vector3(1.35, 0.3, 1.1), roof, Vector3(0, 0.42, -0.4), hull, 0, 0, 0, true)
	Primitives.box(Vector3(0.4, 0.16, 0.7), glass, Vector3(0, 0.62, -0.2), hull)
	Primitives.box(Vector3(0.07, 0.04, 0.9), accent, Vector3(0, 0.6, -0.75), hull)
	# Cross-beam joining the two hulls and supporting the winglets.
	Primitives.box(Vector3(1.7, 0.12, 0.4), roof, Vector3(0, 0.28, -1.2), hull, 0, 0, 0, true)
	# Rear winglets with neon outer edges.
	Primitives.box(Vector3(0.55, 0.05, 0.5), roof, Vector3(-1.05, 0.3, -1.15), hull, 0, 0, 0, true)
	Primitives.box(Vector3(0.55, 0.05, 0.5), roof, Vector3(1.05, 0.3, -1.15), hull, 0, 0, 0, true)
	Primitives.box(Vector3(0.06, 0.05, 0.5), accent, Vector3(-1.28, 0.3, -1.15), hull)
	Primitives.box(Vector3(0.06, 0.05, 0.5), accent, Vector3(1.28, 0.3, -1.15), hull)
	# Rear keel light across the channel
	var keel := ShipMaterials.neon(Color("22d3ee"), 1.2)
	Primitives.box(Vector3(0.22, 0.05, 1.4), keel, Vector3(0, 0.05, -1.5), hull)
	# Place exhaust flames at the twin hulls and light-lanes at the
	# outer winglet tips.
	engine_anchors = [-0.55, 0.55]
	engine_flame_y = 0.3
	wing_anchors = [-1.28, 1.28]


## Builds the Manta Twinfin.
## A tapered central fuselage carries two stacked winglets on each
## side and a single central rear engine.
func _build_twinfin_hull() -> void:
	# Apply the same dynamic hull materials as the other procedural ships.
	var body := ShipMaterials.fx_mat(
		Color(skin.body), Color(skin.accent)
	)
	var roof := ShipMaterials.fx_mat(
		Color(skin.roof), Color(skin.accent), 0.75, 0.25
	)
	fx_materials.append(body)
	fx_materials.append(roof)
	var accent := ShipMaterials.neon(Color(skin.accent), 1.8)
	var glass := ShipMaterials.glass()
	var thruster := ShipMaterials.neon(Color("22d3ee"), 2.0)
	var dark := ShipMaterials.dark(Color("212529"))
	# Tapered central fuselage.
	Primitives.box(Vector3(0.85, 0.3, 2.4), body, Vector3(0, 0.26, -0.1), hull, 0, 0, 0, true)
	Primitives.box(Vector3(0.5, 0.2, 1.0), body, Vector3(0, 0.28, 1.1), hull, 0, 0, 0.08, true)
	Primitives.box(Vector3(0.2, 0.12, 0.6), body, Vector3(0, 0.22, 1.7), hull, 0, 0, 0.12, true)
	# Cockpit canopy and neon spine.
	Primitives.box(Vector3(0.36, 0.18, 0.8), glass, Vector3(0, 0.48, 0.0), hull)
	Primitives.box(Vector3(0.08, 0.05, 1.5), accent, Vector3(0, 0.45, 0.5), hull)
	# Two stacked winglets on each side, with neon outer edges.
	for x in [-0.68, 0.68]:
		var yaw := 0.35 if x > 0.0 else -0.35
		Primitives.box(Vector3(0.55, 0.05, 0.75), roof, Vector3(x, 0.26, -0.7), hull, 0, yaw, 0.05, true)
		Primitives.box(Vector3(0.5, 0.05, 0.65), roof, Vector3(x, 0.46, -0.9), hull, 0, yaw, 0.05, true)
		Primitives.box(Vector3(0.05, 0.05, 0.6), accent, Vector3(x + yaw * 0.8, 0.46, -1.05), hull, 0, yaw, 0.05)
	# Central rear engine and illuminated thruster plate.
	Primitives.box(Vector3(0.55, 0.5, 1.0), dark, Vector3(0, 0.4, -1.15), hull, 0, 0, 0, true)
	Primitives.box(Vector3(0.4, 0.38, 0.08), thruster, Vector3(0, 0.4, -1.68), hull)
	Primitives.box(Vector3(0.58, 0.05, 0.8), accent, Vector3(0, 0.62, -1.1), hull)
	# Rear keel light beneath the central engine.
	var keel := ShipMaterials.neon(Color("22d3ee"), 1.2)
	Primitives.box(Vector3(0.22, 0.05, 1.4), keel, Vector3(0, 0.05, -1.5), hull)
	# Use one central exhaust flame at the master engine.
	engine_anchors = [0.0]
	engine_flame_y = 0.4
	wing_anchors = [-0.96, 0.96]


## Builds the exhaust flames and blob shadow shared by all hulls.
func _build_engine_effects() -> void:
	# Create one exhaust flame per configured engine anchor.
	# Flames are children of the hull so they follow its hover and
	# banking animation. The 180-degree hull rotation reverses the
	# local horizontal and longitudinal anchor coordinates.
	var flame_mat := flame_material(
		FLAME_OPACITY, effect_flame, effect_overdrive
	)
	# Give single-engine ships a larger exhaust flame.
	var big_flame := engine_anchors.size() == 1
	for x in engine_anchors:
		var fl := Primitives.sphere(0.14, flame_mat, Vector3(-x, engine_flame_y, -engine_flame_z), hull)
		fl.scale = Vector3(0.8, 0.8, 2.0) if big_flame else Vector3(0.5, 0.5, 1.4)
		flames.append(fl)
	# Add a soft blob shadow beneath the ship. It is used when
	# real-time shadows are disabled.
	var blob := Primitives.shadow_blob(self, Vector2(2.6, 3.8), -0.275)
	# Offset the shadow to approximate the direction of the world sun.
	blob.position = Vector3(0.22, -0.275, -0.38)
	# Select real mesh shadows or the blob-shadow fallback.
	# The world lighting remains enabled in either mode.
	Primitives.apply_shadow_mode(self, SaveManager.data.full_shadows)


## Builds effects used only during a race.
## These include the wing light-lanes and pooled smoke puffs.
## Preview ships use the same hull without these effects.
func _build_race_effects() -> void:
	# Skip race-only effects in the garage preview.
	if preview_mode:
		return
	# Create light-lanes extending from the configured wingtip anchors.
	var trail_mat := trail_material()
	# launch from the hull-specific wingtip anchors
	for x in wing_anchors:
		var tr := Primitives.box(Vector3(0.08, 0.06, 1.4), trail_mat,
			Vector3(x, 0.06, 2.6), self)
		tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tr.set_meta("wx", x)
		trails.append(tr)
	# Pooled smoke puffs.
	var smoke := Primitives.mat(Color("9aa0a6"), 0.0, 1.0, Color(0, 0, 0, 0), 0.0, 0.5)
	for i in 14:
		var p := Primitives.sphere(0.14, smoke.duplicate(), Vector3(0, -50, 0), get_parent())
		p.visible = false
		puffs.append({ "mesh": p, "t": -1.0 })

## Updates ship movement, animation and runtime visual effects.
## Set effects_enabled to false for menu and preview updates, which
## preserves the idle animation without spawning race-only effects.
func update_craft(
	delta: float,
	kmh: float,
	speed: float,
	effects_enabled: bool = true
) -> void:
	# Smooth horizontal movement and orient the hull toward its target lane.
	position.x += (target_x - position.x) * minf(1.0, delta * 9.0)
	hull.rotation.y = PI - (target_x - position.x) * 0.12
	# Hover bob.
	var t := Time.get_ticks_msec() / 1000.0
	# Apply a smooth banking roll during lane changes.
	# The hull rotates around its lower pivot, with additional lift
	# to keep the lower wingtip clear of the road.
	var bob := sin(t * 3.1) * 0.06
	bank += ((target_x - position.x) * 0.4 - bank) * minf(1.0, delta * 5.0)
	var roll := sin(t * 2.1) * 0.015 + bank
	var arm := bob - ROLL_PIVOT_Y
	hull.rotation.z = roll
	hull.position = Vector3(
		-arm * sin(roll),
		ROLL_PIVOT_Y + arm * cos(roll) + absf(bank) * BANK_LIFT,
		0.0
	)
	# Update exhaust intensity from the current speed.
	# Actual flame flickering continues independently in _process().
	flame_intensity = minf(1.0, kmh / 90.0)
	var intensity := flame_intensity
	# Update the dynamic hull effects from speed, overdrive and gunfire.
	# Speed is normalized to the normal maximum speed.
	fx_flash = maxf(0.0, fx_flash - delta * 2.5)
	var fx_speed := clampf(kmh / (RaceSession.MAX_SPEED * 3.6), 0.0, 1.0)
	for fx in fx_materials:
		fx.set_shader_parameter("speed", fx_speed)
		fx.set_shader_parameter("overdrive", fx_overdrive)
		fx.set_shader_parameter("flash", fx_flash)
	# Drive imported hull emission from overdrive and gunfire.
	# Unlike the procedural hull shader, imported materials do not
	# use a speed-dependent brightness effect.
	var import_glow := (
		fx_overdrive * IMPORT_OVERDRIVE_GLOW
		+ fx_flash * IMPORT_FLASH_GLOW
	)
	for im in import_materials:
		im.emission_energy_multiplier = import_glow
	# Fade the glass overdrive skin in with overdrive and gunfire.
	if glass_material != null:
		glass_material.set_shader_parameter(
			"intensity", clampf(fx_overdrive + fx_flash * 0.3, 0.0, 1.0)
		)
	# Smooth the light-lane origin so the trails sweep behind the ship
	# during lane changes.
	trail_x += (position.x - trail_x) * minf(1.0, delta * 6.0)
	var sweep := position.x - trail_x
	for tr in trails:
		tr.visible = effects_enabled
		if not effects_enabled:
			continue
		var sz := 0.8 + intensity * 1.8
		tr.scale.z = sz
		# Keep the near end of the streak anchored at the wingtip
		# as its length changes.
		tr.position.z = 1.5 + 0.7 * sz
		# Update the trail's flicker brightness and overdrive colour.
		var tm := tr.material_override as ShaderMaterial
		tm.set_shader_parameter("intensity", 0.8 + intensity * 1.6)
		tm.set_shader_parameter("overdrive", fx_overdrive)
		tr.position.x = (tr.get_meta("wx") as float) - sweep
		tr.rotation.y = -clampf(sweep * 0.28, -0.5, 0.5)
	# Spawn smoke puffs during active race updates.
	if effects_enabled:
		var interval := maxf(0.045, 0.22 - kmh * 0.0018)
		last_spawn += delta
		if last_spawn > interval:
			last_spawn = 0.0
			for p in puffs:
				if p.t < 0.0:
					p.t = 0.0
					p.mesh.visible = true
					p.mesh.position = Vector3(position.x + (0.38 if randf() < 0.5 else -0.38), position.y + 0.32, position.z + 2.3)
					break
	for p in puffs:
		if p.t < 0.0: continue
		p.t += delta
		p.mesh.position.z += (speed * 0.55 + 14.0) * delta
		p.mesh.position.y += delta * 0.55
		p.mesh.scale = Vector3.ONE * (0.25 + p.t * 1.1)
		(p.mesh.material_override as StandardMaterial3D).albedo_color.a = maxf(0.0, 0.45 * (1.0 - p.t / 0.7))
		if p.t > 0.7:
			p.t = -1.0
			p.mesh.visible = false


## Minimum exhaust flicker intensity at zero speed.
## Allows flames to remain animated while the ship is stationary.
const FLAME_IDLE_FLICKER := 0.25

## Animates the exhaust flames continuously, including while paused
## or in the garage preview.
## flame_intensity controls the transition between idle and
## speed-dependent flicker.
func _process(_delta: float) -> void:
	for fl in flames:
		# Randomize the flame size while preserving a minimum idle flicker.
		var flick := 0.5 + randf() * 0.7
		var fi := FLAME_IDLE_FLICKER + flame_intensity * (1.0 - FLAME_IDLE_FLICKER)
		fl.scale = Vector3(
			0.4 + fi * 0.5 * flick,
			0.4 + fi * 0.5 * flick,
			1.0 + fi * 1.6 * flick
		)
		# Keep the flame's inner edge anchored at the engine outlet.
		fl.position.z = -engine_flame_z + 0.14 * (1.0 - fl.scale.z)
		(fl.material_override as ShaderMaterial).set_shader_parameter(
			"intensity", 1.2 + fi * 2.4 * flick
		)
		# Blend the exhaust colour toward purple during overdrive.
		(fl.material_override as ShaderMaterial).set_shader_parameter(
			"overdrive", fx_overdrive
		)


func _exit_tree() -> void:
	# Smoke puffs are parented to the world rather than the ship,
	# so free them explicitly when the ship is removed.
	for puff in puffs:
		var mesh := puff.get("mesh") as Node3D
		if is_instance_valid(mesh):
			mesh.queue_free()
