
class_name TrackTopology
extends RefCounted
## Distance-based road topology. Lane indices always refer to the original
## configured road, so surviving lanes never move when an outer lane closes.

const FULL_SECTION_MIN := 100.0
const FULL_SECTION_MAX := 160.0
const NARROW_SECTION_MIN := 50.0
const NARROW_SECTION_MAX := 80.0
const TRANSITION_LENGTH := 36.0
const FULL_SECTION_PROBABILITY := 2.0 / 3.0
const PROFILE_SAMPLE_STEP := 6.0

var base_layout: TrackLayout
var _rng := RandomNumberGenerator.new()
var _sections: Array[Dictionary] = []
var _seed := -1


func configure(layout: TrackLayout, seed: int = -1) -> void:
	base_layout = layout
	reset(seed)


func reset(seed: int = -1) -> void:
	_sections.clear()
	_seed = seed
	if seed >= 0:
		_rng.seed = seed
	else:
		_rng.randomize()

	if base_layout == null:
		base_layout = TrackLayout.new(TrackConfig.new())

	var initial_lanes := base_layout.get_all_lane_indices()
	var initial_bounds := _bounds_for_lanes(initial_lanes)
	var initial_length := 120.0
	_sections.append({
		"start": 0.0,
		"end": initial_length,
		"lanes": initial_lanes,
		"left": initial_bounds.x,
		"right": initial_bounds.y
	})
	_generate_until(initial_length + TRANSITION_LENGTH + 220.0)


func ensure_generated_through(distance: float) -> void:
	_generate_until(maxf(0.0, distance))


func get_profile(distance: float) -> Dictionary:
	if base_layout == null:
		base_layout = TrackLayout.new(TrackConfig.new())
	if _sections.is_empty():
		reset(_seed)

	_generate_until(maxf(0.0, distance) + 1.0)

	if distance < 0.0:
		return _profile_from_section(_sections[0], false, 0.0)

	# Sections are sorted by "start" and only ever appended, so a binary
	# search locates the containing section in O(log n) — get_profile runs
	# many times per frame, so the old linear scan was the main cost as
	# the list grew during long runs.
	var index := _find_section_index(distance)
	var current: Dictionary = _sections[index]

	if distance <= float(current.end):
		return _profile_from_section(current, false, 0.0)

	if index + 1 < _sections.size():
		var next_section: Dictionary = _sections[index + 1]
		var transition_start := float(current.end)
		var transition_end: float = next_section.start
		if distance < transition_end:
			var progress := clampf(
				(distance - transition_start) / (transition_end - transition_start),
				0.0,
				1.0
			)
			return _transition_profile(current, next_section, progress)

	return _profile_from_section(current, false, 0.0)

## Largest index whose "start" is <= distance (sections are sorted).
func _find_section_index(distance: float) -> int:
	var lo := 0
	var hi := _sections.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if float(_sections[mid].start) <= distance:
			lo = mid
		else:
			hi = mid - 1
	return lo


func get_available_lane_indices(distance: float) -> Array[int]:
	var profile := get_profile(distance)
	var result: Array[int] = []
	for lane_index in profile.lanes:
		result.append(int(lane_index))
	return result


func get_lane_center(lane_index: int) -> float:
	return base_layout.get_lane_center(lane_index)


func get_lane_center_at(track_distance: float, lane_index: int) -> float:
	return base_layout.get_lane_center(lane_index)

## True only if this physical lane remains open for the complete path.
func is_lane_open_between(lane_index: int, from_distance: float, to_distance: float) -> bool:
	var low := minf(from_distance, to_distance)
	var high := maxf(from_distance, to_distance)
	var sample := low
	while sample <= high:
		if not get_available_lane_indices(sample).has(lane_index):
			return false
		sample += PROFILE_SAMPLE_STEP
	return get_available_lane_indices(high).has(lane_index)


func is_position_on_road(distance: float, x_position: float, edge_margin: float = 0.15) -> bool:
	var profile := get_profile(distance)
	return (
		x_position >= float(profile.left) + edge_margin
		and x_position <= float(profile.right) - edge_margin
	)


func _generate_until(target_distance: float) -> void:
	if base_layout == null:
		return
	if _sections.is_empty():
		reset(_seed)
	while float(_sections.back().end) < target_distance:
		_append_next_section()


func _append_next_section() -> void:
	var previous: Dictionary = _sections.back()
	var full_lane_count := base_layout.lane_count
	var next_lanes: Array[int] = base_layout.get_all_lane_indices()

	if full_lane_count > 1 and _rng.randf() >= FULL_SECTION_PROBABILITY:
		# Narrow by removing one outer lane. For the standard three-lane road,
		# this yields either [0, 1] or [1, 2], retaining the original X centres.
		var remove_left := _rng.randf() < 0.5
		if remove_left:
			next_lanes.remove_at(0)
		else:
			next_lanes.remove_at(next_lanes.size() - 1)

	var bounds := _bounds_for_lanes(next_lanes)
	var is_full := next_lanes.size() == full_lane_count
	var section_length := (
		_rng.randf_range(FULL_SECTION_MIN, FULL_SECTION_MAX)
		if is_full
		else _rng.randf_range(NARROW_SECTION_MIN, NARROW_SECTION_MAX)
	)
	var next_start: float = float(previous.end) + TRANSITION_LENGTH
	_sections.append({
		"start": next_start,
		"end": next_start + section_length,
		"lanes": next_lanes,
		"left": bounds.x,
		"right": bounds.y
	})


func _bounds_for_lanes(lanes: Array[int]) -> Vector2:
	if lanes.is_empty():
		return Vector2(base_layout.road_left, base_layout.road_right)
	var half_lane := base_layout.lane_width * 0.5
	var left := base_layout.get_lane_center(lanes[0]) - half_lane
	var right := base_layout.get_lane_center(lanes.back()) + half_lane
	return Vector2(left, right)


func _profile_from_section(section: Dictionary, transitioning: bool, progress: float) -> Dictionary:
	return {
		"left": float(section.left),
		"right": float(section.right),
		"lanes": section.lanes.duplicate(),
		"dividers": _dividers_between(float(section.left), float(section.right)),
		"transitioning": transitioning,
		"transition_progress": progress
	}


func _transition_profile(from_section: Dictionary, to_section: Dictionary, progress: float) -> Dictionary:
	var left := lerpf(float(from_section.left), float(to_section.left), progress)
	var right := lerpf(float(from_section.right), float(to_section.right), progress)
	# A lane becomes selectable when its centre reaches the taper boundary.
	# For symmetric one-lane closures this occurs at the midpoint of the taper.
	var active_section: Dictionary = from_section if progress < 0.5 else to_section
	return {
		"left": left,
		"right": right,
		"lanes": active_section.lanes.duplicate(),
		# Keep the old/new divider positions visible through the taper; a divider
		# that reaches the road edge naturally becomes the edge marking.
		"dividers": _transition_dividers(from_section, to_section, left, right),
		"transitioning": true,
		"transition_progress": progress
	}


func _dividers_between(left: float, right: float) -> Array[float]:
	var result: Array[float] = []
	for divider_x in base_layout.get_lane_divider_positions():
		if divider_x > left + 0.1 and divider_x < right - 0.1:
			result.append(divider_x)
	return result


func _transition_dividers(from_section: Dictionary, to_section: Dictionary, left: float, right: float) -> Array[float]:
	var result: Array[float] = []
	var candidates: Array[float] = []
	for x in _dividers_between(float(from_section.left), float(from_section.right)):
		if not candidates.has(x):
			candidates.append(x)
	for x in _dividers_between(float(to_section.left), float(to_section.right)):
		if not candidates.has(x):
			candidates.append(x)
	for x in candidates:
		if x > left + 0.1 and x < right - 0.1:
			result.append(x)
	return result
