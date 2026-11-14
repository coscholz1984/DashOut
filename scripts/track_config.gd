
class_name TrackConfig
extends Resource
## Authoritative, serializable parameters for the playable road.
## Boundaries are world-space X coordinates; they need not be symmetric.

@export var road_left: float = -4.5
@export var road_right: float = 4.5
@export_range(1, 8, 1) var lane_count: int = 3

@export var shoulder_width: float = 2.0
@export var shoulder_gap: float = 0.0
@export var scenery_margin_left: float = 2.0
@export var scenery_margin_right: float = 2.0

## Lateral width of the city placement zone on EACH side of the road.
@export_range(12.0, 100.0, 1.0) var scenery_zone_width: float = 42.0

## Multiplier for the number of buildings in each city layer.
## 1.0 is the normal density; 1.5 creates 50% more buildings.
@export_range(0.5, 2.5, 0.05) var building_density: float = 1.25

func validate_config() -> void:
	road_left = minf(road_left, road_right - 0.5)
	road_right = maxf(road_right, road_left + 0.5)
	lane_count = clampi(lane_count, 1, 8)
	shoulder_width = maxf(0.0, shoulder_width)
	shoulder_gap = maxf(0.0, shoulder_gap)
	scenery_margin_left = maxf(0.0, scenery_margin_left)
	scenery_margin_right = maxf(0.0, scenery_margin_right)
	scenery_zone_width = clampf(scenery_zone_width, 12.0, 100.0)
	building_density = clampf(building_density, 0.5, 2.5)
