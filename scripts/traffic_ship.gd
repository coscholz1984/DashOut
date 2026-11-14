
class_name TrafficShip
extends Node3D
## Builds traffic ships using imported models, with a procedural
## shuttle-pod fallback when an imported model is unavailable.
## Handles model orientation, lighting, shadows and exhaust effects.

## Imported traffic models, selected randomly for each spawn.
## Their authored materials and colours are preserved.
const TRAFFIC_MODEL_PATHS := [
	"res://models/traffic_red.glb",
	"res://models/traffic_yellow.glb",
	"res://models/Imperial.glb",
	"res://models/Insurgent.glb",
]

## Per-model scale factors, indexed in parallel with TRAFFIC_MODEL_PATHS.
const TRAFFIC_MODEL_SCALES := [
	Vector3.ONE * 0.40,
	Vector3.ONE * 0.58,
	Vector3.ONE * 0.33,
	Vector3.ONE * 0.375,
]

## Per-model orientation corrections, indexed in parallel with
## TRAFFIC_MODEL_PATHS. Models that are already nose-forward use
## Vector3.ZERO.
const TRAFFIC_MODEL_ROTATIONS := [
	Vector3(0.0, PI / 2.0, 0.0),
	Vector3(0.0, PI / 2.0, 0.0),
	Vector3.ZERO,
	Vector3.ZERO,
]
const TRAFFIC_MODEL_LIFT := 1.0

## Local light settings for imported traffic hulls.
## A dedicated render layer restricts illumination to the ship's
## own meshes, preventing light spill onto the road and other objects.
const TRAFFIC_LIGHT_RANGE := 4.5
const TRAFFIC_LIGHT_ENERGY := 8.6
const TRAFFIC_LIGHT_LAYER := 22
const TRAFFIC_LIGHT_OFFSET := Vector3(-0.7, 3.0, 1.2)

## Per-model exhaust positions in the ship's local coordinate system.
## Each entry corresponds to a model in TRAFFIC_MODEL_PATHS.
const TRAFFIC_FLAME_ANCHORS_X := [
	[-0.55, 0.55],
	[-0.38, 0.38],
	[0.0],
	[-0.3, 0.3],
]
const TRAFFIC_FLAME_Y := [
	0.95,
	1.00,
	1.00,
	1.10,
]
const TRAFFIC_FLAME_Z := [
	1.00,
	0.75,
	2.8,
	2.0,
]

## Per-model exhaust size multiplier, applied to both base scale
## and animated flicker scale.
const TRAFFIC_FLAME_SIZES := [
	1.0,
	1.0,
	1.8,
	1.0,
]

## Fixed flicker intensity for traffic exhausts.
## Unlike the player, traffic ships do not use speed-dependent intensity.
const TRAFFIC_FLAME_INTENSITY := 0.6

var skin: Dictionary
var oncoming := false
var rel := 0.0
## Exhaust flame instances, animated in _process().
var flames: Array[MeshInstance3D] = []
## Exhaust anchor coordinates for the selected model.
var flame_z := 0.0
var flame_y := 0.0
## Exhaust size multiplier for the selected model.
var flame_size := 1.0

func _init(craft_skin: Dictionary, is_oncoming: bool, relative_speed: float) -> void:
	skin = craft_skin
	oncoming = is_oncoming
	rel = relative_speed

func _ready() -> void:
	# Prefer an imported model; use the procedural pod if unavailable.
	if _build_imported_hull() == null:
		_build_procedural_hull()
	if not oncoming:
		rotation.y = PI
	# The shadow offset follows the sun direction. Same-direction ships
	# are rotated by 180°, so their local offset must be inverted to
	# preserve the same world-space shadow direction.
	var blob := Primitives.shadow_blob(self, Vector2(2.4, 4.0), 0.075)
	blob.position = (
		Vector3(0.14, 0.075, -0.24)
		if oncoming
		else Vector3(-0.14, 0.075, 0.24)
	)
	# Select either real drop shadows or the blob-shadow fallback.
	Primitives.apply_shadow_mode(self, SaveManager.data.full_shadows)
	# Give each ship a slightly different static hover height.
	var t := Time.get_ticks_msec() / 1000.0
	position.y = 0.1 + sin(t * 2.0 + rel * 17.0) * 0.08
	# Keep the blob at a consistent world height despite the ship's
	# phase-dependent hover offset. This prevents it from clipping
	# below the road surface.
	blob.position.y = 0.175 - position.y


## Loads a randomly selected imported traffic model.
## Returns null when the model cannot be loaded, allowing the
## caller to create the procedural fallback.
func _build_imported_hull() -> Node3D:
	# One random model per spawn; the scale array is parallel to
	# the paths (0 = red, 1 = yellow, 2 = imperial, 3 = insurgent).
	var index := randi() % TRAFFIC_MODEL_PATHS.size()
	var path: String = TRAFFIC_MODEL_PATHS[index]
	if not ResourceLoader.exists(path):
		push_warning("[TrafficShip] missing model: " + path)
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var model := scene.instantiate()
	model.name = "ImportedHull"
	model.scale = TRAFFIC_MODEL_SCALES[index]
	model.rotation = TRAFFIC_MODEL_ROTATIONS[index]
	model.position.y = TRAFFIC_MODEL_LIFT
	add_child(model)
	# Add lighting (only) to imported models. Global light is not sufficient.
	_add_hull_light()
	# Add exhaust effects after the hull light so they are excluded
	# from its dedicated lighting layer.
	_add_engine_flames(index)
	return model


## Adds a local light to the ship, independently of the imported
## model's orientation correction.
##
## The light position is adjusted for the ship's travel direction
## so its world-space position remains consistent.
## A dedicated cull mask restricts illumination to the ship's meshes.
func _add_hull_light() -> void:
	var light := OmniLight3D.new()
	light.name = "HullLight"
	light.omni_range = TRAFFIC_LIGHT_RANGE
	light.light_energy = TRAFFIC_LIGHT_ENERGY
	light.shadow_enabled = false
	var layer_bit := 1 << (TRAFFIC_LIGHT_LAYER - 1)
	light.light_cull_mask = layer_bit
	light.position = (
		TRAFFIC_LIGHT_OFFSET
		if oncoming
		else Vector3(
			-TRAFFIC_LIGHT_OFFSET.x,
			TRAFFIC_LIGHT_OFFSET.y,
			-TRAFFIC_LIGHT_OFFSET.z
		)
	)
	add_child(light)
	# Restrict the light to the imported hull meshes.
	for mesh in find_children("*", "MeshInstance3D", true, false):
		(mesh as GeometryInstance3D).layers |= layer_bit


## Creates exhaust flames at the configured anchors for the selected
## model. Each flame gets its own material instance because its
## flicker animation modifies the shader intensity.
func _add_engine_flames(index: int) -> void:
	flame_y = TRAFFIC_FLAME_Y[index]
	flame_z = TRAFFIC_FLAME_Z[index]
	flame_size = TRAFFIC_FLAME_SIZES[index]
	var flame_mat := PlayerShip.flame_material(PlayerShip.FLAME_OPACITY)
	for x in TRAFFIC_FLAME_ANCHORS_X[index]:
		var fl := Primitives.sphere(
			0.14,
			flame_mat,
			Vector3(x, flame_y, -flame_z),
			self
		)
		fl.scale = Vector3(0.5, 0.5, 1.4) * flame_size
		flames.append(fl)


## Animates the imported hull's exhaust flames using random flicker.
## Flame growth is compensated so the inner edge remains anchored
## at the exhaust outlet.
func _process(_delta: float) -> void:
	if flames.is_empty():
		return
	var intensity := TRAFFIC_FLAME_INTENSITY
	for fl in flames:
		var flick := 0.5 + randf() * 0.7
		fl.scale = Vector3(
			0.4 + intensity * 0.5 * flick,
			0.4 + intensity * 0.5 * flick,
			1.0 + intensity * 1.6 * flick
		) * flame_size
		# Keep the inner edge anchored at the exhaust outlet.
		fl.position.z = -flame_z + 0.14 * flame_size * (1.0 - fl.scale.z)
		# Update emission intensity to match the current flicker.
		(
			fl.material_override as ShaderMaterial
		).set_shader_parameter(
			"intensity", 1.2 + intensity * 2.4 * flick
		)


## Builds the original procedural shuttle-pod fallback.
## Uses the supplied skin colours instead of imported model materials.
func _build_procedural_hull() -> void:
	var body := ShipMaterials.hull(Color(skin.body))
	var roof := ShipMaterials.roof(Color(skin.roof))
	var accent := ShipMaterials.neon(Color(skin.accent), 0.6)
	var glass := ShipMaterials.glass()
	var thruster := ShipMaterials.neon(Color("22d3ee"), 2.0)
	var head := ShipMaterials.neon(Color("fff59a"), 0.9)
	var tail := ShipMaterials.neon(Color("ff2b2b"), 1.4)
	var dark := ShipMaterials.dark(Color("586180"))
	Primitives.box(Vector3(1.05, 0.62, 1.1), body, Vector3(0, 0.4, 0.95), self, 0, 0, 0, true)
	Primitives.box(Vector3(1.3, 0.72, 0.9), body, Vector3(0, 0.42, 0.55), self, 0, 0, 0, true)
	Primitives.box(Vector3(1.35, 0.78, 2.0), body, Vector3(0, 0.44, -0.35), self, 0, 0, 0, true)
	Primitives.box(Vector3(1.0, 0.6, 0.8), body, Vector3(0, 0.42, -1.25), self, 0, 0, 0, true)
	Primitives.box(Vector3(0.6, 0.42, 0.5), body, Vector3(0, 0.4, -1.7), self, 0, 0, 0, true)
	Primitives.box(Vector3(0.8, 0.3, 0.35), glass, Vector3(0, 0.62, 1.15), self)
	Primitives.box(Vector3(1.15, 0.12, 2.6), dark, Vector3(0, 0.06, -0.1), self)
	Primitives.box(Vector3(0.3, 0.05, 2.2), thruster, Vector3(-0.4, 0.02, -0.1), self)
	Primitives.box(Vector3(0.3, 0.05, 2.2), thruster, Vector3(0.4, 0.02, -0.1), self)
	Primitives.box(Vector3(0.06, 0.14, 1.9), accent, Vector3(-0.69, 0.5, -0.2), self)
	Primitives.box(Vector3(0.06, 0.14, 1.9), accent, Vector3(0.69, 0.5, -0.2), self)
	Primitives.box(Vector3(0.5, 0.08, 0.5), roof, Vector3(-0.85, 0.5, -1.3), self, 0, 0, 0, true)
	Primitives.box(Vector3(0.5, 0.08, 0.5), roof, Vector3(0.85, 0.5, -1.3), self, 0, 0, 0, true)
	Primitives.box(Vector3(0.8, 0.3, 0.12), dark, Vector3(0, 0.42, -1.95), self)
	Primitives.box(Vector3(0.55, 0.2, 0.05), thruster, Vector3(0, 0.42, -2.0), self)
	Primitives.box(Vector3(0.22, 0.12, 0.06), tail, Vector3(-0.42, 0.55, -1.92), self)
	Primitives.box(Vector3(0.22, 0.12, 0.06), tail, Vector3(0.42, 0.55, -1.92), self)
	Primitives.box(Vector3(0.4, 0.14, 0.08), head, Vector3(-0.35, 0.5, 1.48), self)
	Primitives.box(Vector3(0.4, 0.14, 0.08), head, Vector3(0.35, 0.5, 1.48), self)
