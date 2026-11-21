
class_name RoadMesh
extends Node3D
## Builds and recycles road chunks.
## Each cross-section samples TrackTopology so road tapers remain
## continuous across chunk boundaries.

const CHUNK_LEN := 24.0
## Number of visible road chunks.
## The total coverage should extend far enough into the fog to hide
## newly recycled chunks at the horizon.
const NUM_CHUNKS := 12
const LONGITUDINAL_SUBDIVISIONS := 24
const ROAD_HEIGHT := 0.15
const SHOULDER_HEIGHT := 0.125

## Height of the raised shoulder strips along the road edges.
## Their inner faces align with the drivable road boundary.
const SHOULDER_CURB_HEIGHT := 0.12

var layout: TrackLayout
var segment_manager: TrackTopology
var body_mat: Material
var line_mat: Material
var grass_mat: Material
var chunks: Array[Node3D] = []
var scroll_z := 0.0


func configure(road_layout: TrackLayout, road_segments: TrackTopology = null) -> void:
	layout = road_layout
	segment_manager = road_segments


func set_layout(road_layout: TrackLayout) -> void:
	layout = road_layout
	_rebuild_chunks()


func set_segment_manager(road_segments: TrackTopology) -> void:
	segment_manager = road_segments
	_rebuild_chunks()


func _ready() -> void:
	if layout == null:
		layout = TrackLayout.new(TrackConfig.new())
	_update_theme()
	if chunks.is_empty():
		for i in NUM_CHUNKS:
			var chunk := Node3D.new()
			chunk.name = "RoadChunk_%02d" % i
			add_child(chunk)
			chunks.append(chunk)
	update_scroll(0.0, true)


func set_road_configuration(
	road_layout: TrackLayout,
	road_segments: TrackTopology
) -> void:
	layout = road_layout
	segment_manager = road_segments
	_rebuild_chunks()


func _update_theme() -> void:
	# Use the same lit shader approach as the ground plane so road
	# and ground surfaces respond consistently to scene lighting.
	var body_shader := _lit_surface_shader()
	body_mat = ShaderMaterial.new()
	(body_mat as ShaderMaterial).shader = body_shader
	# Lift the road colour in dark-sky themes to preserve visibility
	# under the reduced ambient illumination.
	var road_tone := Color(0.12, 0.15, 0.19)
	var sky_lum := Color(
		str(SaveManager.track_skin().get("sky", "87ceeb"))
	).get_luminance()
	var lift := clampf((0.25 - sky_lum) / 0.25, 0.0, 1.0)
	road_tone = road_tone.lerp(Color(0.24, 0.27, 0.33), lift * 0.85)
	(body_mat as ShaderMaterial).set_shader_parameter(
		"surface_color",
		road_tone
	)
	# Apply optional PBR textures; missing files leave the base
	# theme colour unchanged.
	_apply_surface_textures(
		body_mat as ShaderMaterial,
		"road_albedo.png", "road_normal.png", "road_roughness.png"
	)

	line_mat = StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.1, 0.9, 1.0)
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Use the ground-style lit shader for the shoulders so scenery
	# shadows continue across the road boundary.
	var grass_shader := _lit_surface_shader()
	grass_mat = ShaderMaterial.new()
	(grass_mat as ShaderMaterial).shader = grass_shader
	(grass_mat as ShaderMaterial).set_shader_parameter(
		"surface_color",
		Color(0.16, 0.23, 0.19)
	)
	_apply_surface_textures(
		grass_mat as ShaderMaterial,
		"shoulder_albedo.png", "shoulder_normal.png",
		"shoulder_roughness.png"
	)


## Applies optional PBR textures to a lit surface shader.
## Each texture is enabled only when it loads successfully, leaving
## the shader's base colour material as the fallback.
func _apply_surface_textures(
		material: ShaderMaterial,
		albedo_file: String,
		normal_file: String,
		roughness_file: String
) -> void:
	var albedo := TextureManager.tex(albedo_file)
	if albedo != null:
		material.set_shader_parameter("albedo_tex", albedo)
		material.set_shader_parameter("use_albedo", 1.0)

	var normal := TextureManager.tex(normal_file)
	if normal != null:
		material.set_shader_parameter("normal_tex", normal)
		material.set_shader_parameter("use_normal", 1.0)

	var roughness := TextureManager.tex(roughness_file)
	if roughness != null:
		material.set_shader_parameter("roughness_tex", roughness)
		material.set_shader_parameter("use_roughness", 1.0)


## Creates the shared lit shader used by the road and shoulders.
##
## Omitting a custom light() function preserves Godot's default
## lighting and shadow behaviour.
##
## PBR textures use object-space coordinates, so their patterns
## move with recycled chunks rather than remaining fixed in the world.
## Texture features are enabled by _apply_surface_textures() only
## when the corresponding resources are available.
static func _lit_surface_shader() -> Shader:
	var shader := Shader.new()
	shader = load("res://shaders/lit_surface.gdshader")

	return shader


func _rebuild_chunks() -> void:
	for chunk in chunks:
		chunk.set_meta("built_chunk_index", -2147483648)
	update_scroll(0.0, true)


func update_scroll(distance: float, force_rebuild: bool = false) -> void:
	var distance_chunk_index := int(floor(distance / CHUNK_LEN))

	for i in range(chunks.size()):
		var chunk := chunks[i]

		# Assign a stable absolute index to this recycled chunk.
		var chunk_index := distance_chunk_index + i - 1
		var absolute_center := float(chunk_index) * CHUNK_LEN

		# Position the chunk relative to the player.
		chunk.position.z = distance - absolute_center

		if force_rebuild or int(chunk.get_meta("built_chunk_index", -2147483648)) != chunk_index:
			_build_chunk(chunk, absolute_center)
			chunk.set_meta("built_chunk_index", chunk_index)

	scroll_z = fposmod(distance, CHUNK_LEN)


func _build_chunk(parent: Node3D, absolute_center: float) -> void:
	for child in parent.get_children():
		child.queue_free()

	if segment_manager != null:
		segment_manager.ensure_generated_through(absolute_center + CHUNK_LEN)

	_add_edge_mesh(parent, absolute_center, 0, body_mat, ROAD_HEIGHT)

	# Build continuous shoulder strips that follow the road boundaries
	# through tapers. Their inner edges remain flush with the drivable road.
	if layout.config.shoulder_width > 0.0:
		_add_curb_strip(
			parent,
			absolute_center,
			-1,
			0.0,
			layout.config.shoulder_width,
			SHOULDER_CURB_HEIGHT,
			grass_mat
		)
		_add_curb_strip(
			parent,
			absolute_center,
			1,
			0.0,
			layout.config.shoulder_width,
			SHOULDER_CURB_HEIGHT,
			grass_mat
		)

	# Place dashed lane dividers using the sampled road profile.
	# At a closure, the outer divider becomes the tapered road boundary.
	for dash_index in range(6):
		var dash_z := (float(dash_index) - 2.5) * 4.0
		var track_distance := absolute_center - dash_z
		var profile := _profile_at(track_distance)
		for divider_x in profile.dividers:
			Primitives.box(
				Vector3(0.12, 0.02, 1.5),
				line_mat,
				Vector3(float(divider_x), ROAD_HEIGHT + 0.01, dash_z),
				parent
			)


func _profile_at(track_distance: float) -> Dictionary:
	if segment_manager != null:
		return segment_manager.get_profile(track_distance)
	return {
		"left": layout.road_left,
		"right": layout.road_right,
		"dividers": layout.get_lane_divider_positions()
	}


## Builds a continuous raised strip along one side of the road.
## Cross-sections sample the track profile so the strip follows
## road tapers without gaps between neighbouring chunks.
##
## side selects the left (-1) or right (+1) edge.
## inner_offset moves the inner face outward from the road boundary;
## strip_width and strip_height define the strip's dimensions.
func _add_curb_strip(
	parent: Node3D,
	absolute_center: float,
	side: int,
	inner_offset: float,
	strip_width: float,
	strip_height: float,
	material: Material
) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	# Extend the strip outward from the selected road edge.
	var dir: float = -1.0 if side < 0 else 1.0
	var outward := Vector3(dir, 0.0, 0.0)
	var inward := Vector3(-dir, 0.0, 0.0)
	var base_y := ROAD_HEIGHT - 0.02
	var top_y := ROAD_HEIGHT + strip_height

	for sample_index in range(LONGITUDINAL_SUBDIVISIONS + 1):
		var local_z := -CHUNK_LEN * 0.5 + CHUNK_LEN * float(sample_index) / float(LONGITUDINAL_SUBDIVISIONS)
		var track_distance := absolute_center - local_z
		var profile := _profile_at(track_distance)
		var edge: float = (
			float(profile.left) if side < 0
			else float(profile.right)
		)
		var inner: float = edge + dir * inner_offset
		var outer: float = inner + dir * strip_width

		# Each cross-section contains outer-bottom, inner-bottom,
		# inner-top and outer-top vertices.
		vertices.append(Vector3(outer, base_y, local_z))
		vertices.append(Vector3(inner, base_y, local_z))
		vertices.append(Vector3(inner, top_y, local_z))
		vertices.append(Vector3(outer, top_y, local_z))
		normals.append(outward)
		normals.append(inward)
		normals.append(inward)
		normals.append(outward)

	for sample_index in range(LONGITUDINAL_SUBDIVISIONS):
		var a := sample_index * 4
		var b := a + 4

		# Inner face (toward the road).
		indices.append_array(PackedInt32Array([
			a + 1, a + 2, b + 1,
			b + 1, a + 2, b + 2
		]))
		# Top face.
		indices.append_array(PackedInt32Array([
			a + 2, a + 3, b + 2,
			b + 2, a + 3, b + 3
		]))
		# Outer face (away from the road).
		indices.append_array(PackedInt32Array([
			a + 3, a, b + 3,
			b + 3, a, b
		]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


func _add_edge_mesh(
	parent: Node3D,
	absolute_center: float,
	edge_kind: int,
	material: Material,
	y_position: float
) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var gap := layout.config.shoulder_gap
	var width := layout.config.shoulder_width

	for sample_index in range(LONGITUDINAL_SUBDIVISIONS + 1):
		var local_z := -CHUNK_LEN * 0.5 + CHUNK_LEN * float(sample_index) / float(LONGITUDINAL_SUBDIVISIONS)
		var track_distance := absolute_center - local_z
		var profile := _profile_at(track_distance)
		var left_edge := float(profile.left)
		var right_edge := float(profile.right)
		var x_a := left_edge
		var x_b := right_edge

		match edge_kind:
			-1:
				x_a = left_edge - gap - width
				x_b = left_edge - gap
			1:
				x_a = right_edge + gap
				x_b = right_edge + gap + width

		vertices.append(Vector3(x_a, y_position, local_z))
		vertices.append(Vector3(x_b, y_position, local_z))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)

	for sample_index in range(LONGITUDINAL_SUBDIVISIONS):
		var a := sample_index * 2
		var b := a + 1
		var c := a + 2
		var d := a + 3
		# Winding order gives an upward-facing surface.
		indices.append_array(PackedInt32Array([a, c, b, b, c, d]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
