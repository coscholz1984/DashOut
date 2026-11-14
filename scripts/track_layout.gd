
class_name TrackLayout
extends RefCounted
## Derives static road geometry from TrackConfig.
## Provides lane centres, dividers and roadside scenery positions
## shared by the road, player, entities and scenery.

var config: TrackConfig

var road_left: float:
	get:
		return config.road_left
var road_right: float:
	get:
		return config.road_right
var road_width: float:
	get:
		return config.road_right - config.road_left
var road_center: float:
	get:
		return (config.road_left + config.road_right) * 0.5
var lane_count: int:
	get:
		return config.lane_count
var lane_width: float:
	get:
		return road_width / float(config.lane_count)

func _init(road_config: TrackConfig = null) -> void:
	config = road_config if road_config != null else TrackConfig.new()
	config.validate_config()

func get_lane_center(lane_index: int) -> float:
	var i := clampi(lane_index, 0, lane_count - 1)
	return road_left + (float(i) + 0.5) * lane_width

func get_all_lane_indices() -> Array[int]:
	var result: Array[int] = []
	for i in lane_count:
		result.append(i)
	return result

func get_center_lane_index() -> int:
	return (lane_count - 1) / 2

func get_lane_divider_positions() -> Array[float]:
	var result: Array[float] = []
	for i in range(1, lane_count):
		result.append(road_left + float(i) * lane_width)
	return result

func get_left_scenery_start() -> float:
	return road_left - config.shoulder_gap - config.shoulder_width - config.scenery_margin_left

func get_right_scenery_start() -> float:
	return road_right + config.shoulder_gap + config.shoulder_width + config.scenery_margin_right

func get_left_scenery_x(index: int, spread: float = 1.0) -> float:
	return get_left_scenery_start() - fposmod(float(index) * 1.618, config.scenery_zone_width) * spread

func get_right_scenery_x(index: int, spread: float = 1.0) -> float:
	return get_right_scenery_start() + fposmod(float(index) * 1.618, config.scenery_zone_width) * spread
