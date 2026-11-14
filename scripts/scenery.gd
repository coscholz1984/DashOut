
class_name Scenery
extends Node3D
## Builds the roadside city and other scenery elements.
## Scenery objects are recycled within a fixed longitudinal window.

const SPAN := 240.0
const BUILDING_ROWS := 3
const BASE_BUILDINGS_PER_ROW := 14

## Height of the shoulder surface, used to position roadside objects.
const SHOULDER_CURB_TOP := 0.27

## Height of the ground plane used by WorldTheme.
const GROUND_Y := -0.15

var layout: TrackLayout


func build(t: Dictionary, road_layout: TrackLayout = null) -> void:
	layout = road_layout if road_layout != null else TrackLayout.new()

	for child in get_children():
		child.queue_free()

	var line_color: Color = Color(t.line)
	var road_color: Color = Color(t.road)
	var sky_color: Color = Color(t.sky)
	var secondary_color: Color = Color(str(t.get("accent", t.grass2)))
	# Match building plinths to the world ground palette.
	var ground_color: Color = Color(t.grass2)

	# Share materials across all buildings in this scenery instance.
	var holo := Primitives.mat(
		line_color, 0.0, 1.0,
		line_color, 1.6, 0.85
	)
	var pod := Primitives.mat(
		road_color.lerp(sky_color, 0.12),
		0.7, 0.3
	)
	var pylon := Primitives.mat(
		road_color.darkened(0.15),
		0.6, 0.4
	)
	var glass := Primitives.mat(
		road_color.lerp(sky_color, 0.18),
		0.9, 0.15
	)
	var neon1 := Primitives.mat(
		line_color, 0.0, 1.0,
		line_color, 1.8
	)
	var neon2 := Primitives.mat(
		secondary_color, 0.0, 1.0,
		secondary_color, 1.8
	)
	var antenna := Primitives.mat(
		Color("8a93a6"), 0.8, 0.3
	)
	var beacon := Primitives.mat(
		Color("ff2d2d"), 0.0, 1.0,
		Color("ff2d2d"), 3.0
	)
	# Use optional PBR facade textures, with colour materials as fallback.
	var building_a := TextureManager.surface_mat(
		road_color.darkened(0.12).lerp(sky_color, 0.08),
		0.78, 0.24,
		"building_a_albedo.png",
		"facade_normal.png",
		"facade_roughness.png",
		Vector3(4.0, 4.0, 4.0),
		"facade_metallic.png",
		"facade_ao.png"
	)
	var building_b := TextureManager.surface_mat(
		road_color.darkened(0.28).lerp(secondary_color, 0.12),
		0.82, 0.2,
		"building_b_albedo.png",
		"facade_normal.png",
		"facade_roughness.png",
		Vector3(4.0, 4.0, 4.0),
		"facade_metallic.png",
		"facade_ao.png"
	)
	var facade_light := Primitives.mat(
		line_color, 0.0, 1.0,
		line_color, 1.25
	)
	var facade_light_alt := Primitives.mat(
		secondary_color, 0.0, 1.0,
		secondary_color, 1.15
	)

	# Provide shared facade materials to all building models.
	var palette := BuildingPalette.new()
	palette.building_a = building_a
	palette.building_b = building_b
	palette.facade_light = facade_light
	palette.facade_light_alt = facade_light_alt
	palette.neon1 = neon1
	palette.neon2 = neon2
	palette.glass = glass
	# Darken the ground colour to distinguish building bases from the ground.
	palette.plinth = Primitives.mat(
		ground_color.darkened(0.45), 0.1, 0.9
	)

	_build_city(palette)

	# Holo-pillars
	for i in 30:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := (
			layout.get_left_scenery_x(i, 0.65)
			if side < 0.0
			else layout.get_right_scenery_x(i, 0.65)
		)
		var z := -fposmod(float(i) * 8.17, SPAN)
		var s := 0.8 + fposmod(float(i) * 13.0, 10.0) / 14.0
		var pillar := Node3D.new()
		pillar.position = Vector3(x, GROUND_Y, z)
		Primitives.box(Vector3(0.18, 2.4 * s, 0.18), pylon,
			Vector3(0.0, 1.2 * s, 0.0), pillar)
		Primitives.box(Vector3(0.12, 0.5 * s, 0.12), holo,
			Vector3(0.0, 2.4 * s, 0.0), pillar)
		for r in 3:
			Primitives.box(
				Vector3((0.9 - r * 0.18) * s, 0.08, (0.9 - r * 0.18) * s),
				pod,
				Vector3(0.0, (1.4 + r * 0.55) * s, 0.0),
				pillar
			)
		add_child(pillar)

	# Ground-level energy conduits.
	var conduit := Primitives.mat(
		Color(t.grass2), 0.0, 1.0,
		Color(t.grass2), 1.4
	)
	for i in 30:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := (
			layout.get_left_scenery_x(i + 31, 0.9)
			if side < 0.0
			else layout.get_right_scenery_x(i + 31, 0.9)
		)
		var z := -fposmod(float(i) * 8.05, SPAN)
		var s := 0.12 + fposmod(float(i) * 17.0, 10.0) / 40.0
		# Center the thin conduit box on the ground plane surface
		# (box height 0.06 → center 0.03 above GROUND_Y).
		Primitives.box(Vector3(0.9, 0.06, 2.4 * s + 0.6), conduit,
			Vector3(x, GROUND_Y + 0.03, z), self)

	# Landmark towers
	for i in 16:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := (
			layout.get_left_scenery_x(i + 61, 1.0)
			if side < 0.0
			else layout.get_right_scenery_x(i + 61, 1.0)
		)
		var z := -fposmod(float(i) * 15.1, SPAN)
		var w := 3.0 + fposmod(float(i) * 11.0, 10.0) / 5.0
		var h := 9.0 + fposmod(float(i) * 7.0, 10.0) / 2.5
		var d := 3.0 + fposmod(float(i) * 13.0, 10.0) / 5.0
		var tower := Node3D.new()
		tower.position = Vector3(x, GROUND_Y, z)
		Primitives.box(Vector3(w * 0.7, h, d * 0.7), glass,
			Vector3(0.0, h / 2.0, 0.0), tower, 0, 0, 0, true)
		for nx in [-w * 0.36, w * 0.36]:
			Primitives.box(Vector3(0.1, h * 0.8, 0.1),
				neon2 if i % 2 == 0 else neon1,
				Vector3(nx, h / 2.0, d * 0.36), tower)
		Primitives.box(Vector3(w * 0.75, 0.15, d * 0.75), neon1,
			Vector3(0.0, h * 0.75, 0.0), tower)
		Primitives.box(Vector3(0.06, 2.4, 0.06), antenna,
			Vector3(0.0, h + 1.2, 0.0), tower)
		Primitives.box(Vector3(0.4, 0.4, 0.4), beacon,
			Vector3(0.0, h + 2.5, 0.0), tower)
		add_child(tower)

	_build_arches(line_color)

	# Store original positions for deterministic recycling and resets.
	for child in get_children():
		child.set_meta("z0", child.position.z)


func _build_city(palette: BuildingPalette) -> void:
	var density: float = layout.config.building_density
	var building_count: int = clampi(
		roundi(float(BASE_BUILDINGS_PER_ROW) * density),
		8,
		36
	)

	# Place buildings in three depth bands beyond the scenery margins.
	var row_offsets := [6.0, 19.0, 34.0]
	var row_jitter := [2.0, 3.5, 5.0]
	var height_min := [8.0, 13.0, 20.0]
	var height_range := [12.0, 20.0, 28.0]

	for row in BUILDING_ROWS:
		var spacing: float = SPAN / float(building_count)

		for side in [-1.0, 1.0]:
			var scenery_start: float = (
				layout.get_left_scenery_start()
				if side < 0.0
				else layout.get_right_scenery_start()
			)

			for i in building_count:
				# Use deterministic variation so layouts remain stable across rebuilds.
				var seed_a := float(i * 37 + row * 19 + (0 if side < 0.0 else 11))
				var jitter := fposmod(seed_a * 2.417, 2.0) - 1.0
				var lateral_offset: float = row_offsets[row] + jitter * row_jitter[row]
				var x: float = scenery_start + side * lateral_offset

				var z_offset := spacing * 0.5 if side > 0.0 else 0.0
				z_offset += float(row) * spacing / 3.0
				var z: float = -fposmod(float(i) * spacing + z_offset, SPAN)

				var width: float = 3.8 + fposmod(seed_a * 1.73, 3.2)
				var depth: float = 5.0 + fposmod(seed_a * 2.91, 4.0)
				var height: float = height_min[row] + fposmod(seed_a * 3.71, height_range[row])

				var building := BuildingModel.build(
					seed_a,
					width,
					depth,
					height,
					side,
					i,
					row,
					palette
				)
				building.position = Vector3(x, GROUND_Y, z)
				add_child(building)


func _build_arches(line_color: Color) -> void:

	# Derive the arch width from the configured road boundaries.
	var half_width: float = maxf(
		absf(layout.road_left - layout.road_center),
		absf(layout.road_right - layout.road_center)
	) + 0.7
	var segment_width: float = half_width * 2.0 / 4.0

	for i in 8:
		var arch := Node3D.new()
		# Centre the arch on the road and place its supports on the
		# elevated shoulder surface.
		arch.position = Vector3(
			layout.road_center,
			SHOULDER_CURB_TOP,
			-i * 30.0
		)

		var arch_pylon := Primitives.mat(
			Color("3c4358"), 0.6, 0.4,
			Color(0, 0, 0, 0), 0.0, 1.0
		)
		var arch_neon := Primitives.mat(
			line_color, 0.0, 1.0,
			line_color, 2.2, 1.0
		)
		var arch_holo := Primitives.mat(
			line_color, 0.0, 1.0,
			line_color, 1.6, 0.85
		)
		arch.set_meta("fade", [
			[arch_pylon, 1.0],
			[arch_neon, 1.0],
			[arch_holo, 0.85]
		])

		for side in [-1.0, 1.0]:
			var x: float = side * half_width
			Primitives.box(
				Vector3(0.35, 5.2, 0.35),
				arch_pylon,
				Vector3(x, 2.6, 0.0),
				arch,
				0, 0, 0, true
			)
			Primitives.box(
				Vector3(0.4, 0.2, 0.4),
				arch_neon,
				Vector3(x, 0.12, 0.0),
				arch
			)

		for k in 4:
			Primitives.box(
				Vector3(segment_width * 1.08, 0.3, 0.3),
				arch_pylon,
				Vector3(
					(float(k) - 1.5) * segment_width,
					5.4 - absf(float(k) - 1.5) * 0.45,
					0.0
				),
				arch
			)

		Primitives.box(
			Vector3(0.5, 0.15, 0.5),
			arch_holo,
			Vector3(0.0, 5.15, 0.0),
			arch
		)
		add_child(arch)


func restore_layout() -> void:
	# Restore arch transparency; positions are recalculated by update_scroll().
	for child in get_children():
		if child.has_meta("fade"):
			for pair in child.get_meta("fade"):
				(pair[0] as StandardMaterial3D).albedo_color.a = pair[1]

## Repositions scenery relative to its original position and wraps it
## into the active recycling window.
func update_scroll(dist: float) -> void:
	for child in get_children():
		var u: float = float(child.get_meta("z0")) + dist
		var tz: float = u - SPAN * (floorf((u - 15.0) / SPAN) + 1.0)
		child.position.z = tz

		if child.has_meta("fade"):
			var fade: float = clampf((-12.0 - tz) / 40.0, 0.0, 1.0)
			for pair in child.get_meta("fade"):
				(pair[0] as StandardMaterial3D).albedo_color.a = pair[1] * fade
