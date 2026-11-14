
class_name BuildingModel
extends Object
## Visual definition of the procedural city buildings. Scenery owns
## the layer layout and recycling; this file owns what a building
## looks like. 

static func build(
	seed_a: float,
	width: float,
	depth: float,
	height: float,
	side: float,
	i: int,
	row: int,
	palette: BuildingPalette
) -> Node3D:
	var building := Node3D.new()

	var base_material: Material = (
		palette.building_a if (i + row) % 2 == 0 else palette.building_b
	)
	var light_material: Material = (
		palette.facade_light if (i + row) % 2 == 0
		else palette.facade_light_alt
	)

	# Dark plinth, slightly wider than the building footprint.
	Primitives.box(
		Vector3(width + 0.45, 0.06, depth + 0.45),
		palette.plinth,
		Vector3(0.0, 0.03, 0.0),
		building
	)

	# Main building mass.
	Primitives.box(
		Vector3(width, height, depth),
		base_material,
		Vector3(0.0, height * 0.5, 0.0),
		building,
		0, 0, 0, true
	)

	# A stepped rooftop on some buildings, creates some variation.
	if (i + row * 2) % 3 != 0:
		var crown_width := width * (0.48 + fposmod(seed_a, 3.0) * 0.08)
		var crown_height := 1.2 + fposmod(seed_a * 1.31, 2.2)
		Primitives.box(
			Vector3(crown_width, crown_height, depth * 0.62),
			palette.glass,
			Vector3(0.0, height + crown_height * 0.5, 0.0),
			building
		)

	# Two narrow luminous strips on the facade facing the highway.
	var road_facing_x: float = -side * (width * 0.5 + 0.035)
	for strip_z_pos in [-depth * 0.27, depth * 0.27]:
		Primitives.box(
			Vector3(0.07, height * 0.72, 0.09),
			light_material,
			Vector3(road_facing_x, height * 0.5, strip_z_pos),
			building
		)

	# Thin roof edge, with occasional brighter accent.
	Primitives.box(
		Vector3(width * 1.02, 0.09, depth * 1.02),
		palette.neon2 if (i + row) % 4 == 0 else palette.neon1,
		Vector3(0.0, height + 0.05, 0.0),
		building
	)

	# A few antennae on taller buildings.
	if row == 2 and i % 4 == 0:
		Primitives.box(
			Vector3(0.07, 2.0 + fposmod(seed_a, 2.0), 0.07),
			palette.neon1,
			Vector3(0.0, height + 1.1, 0.0),
			building
		)

	return building
