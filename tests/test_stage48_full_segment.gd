extends GutTest

const H := preload("res://tests/test_helpers.gd")

func before_each() -> void:
	H.reset_counters()

func _full_circle_mirror(center: Vector2, r: float) -> Surface:
	var carrier := GeneralizedCircle.from_circle(center, r)
	var seg := Segment.full_from_carrier(carrier)
	var refl := ReflectionEffect.new(carrier)
	var config := SideConfig.new(refl, true)
	return Surface.new(seg, config, config, false, false)

# --- Step 1: full property + factory ---

func test_default_segment_not_full() -> void:
	var seg := Segment.from_coords(Vector2(0, 0), Vector2(100, 0), Vector2(50, 0))
	assert_false(seg.full, "Default segment should not be full")

func test_full_from_carrier_circle() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var carrier := GeneralizedCircle.from_circle(center, r)
	var seg := Segment.full_from_carrier(carrier)
	assert_true(seg.full, "Factory segment should be full")
	assert_false(seg.is_line(), "Circle carrier should not be a line")
	var derived_center := seg.get_carrier().center()
	var derived_radius := seg.get_carrier().radius()
	assert_almost_eq(derived_center, center, Vector2(0.1, 0.1),
		"Carrier center should match. Got %s" % derived_center)
	assert_almost_eq(derived_radius, r, 0.1,
		"Carrier radius should match. Got %s" % derived_radius)

func test_full_from_carrier_line() -> void:
	var carrier := GeneralizedCircle.from_line(1.0, 0.0, -500.0)
	var seg := Segment.full_from_carrier(carrier)
	assert_true(seg.full, "Factory segment should be full")
	assert_true(seg.is_line(), "Line carrier should be a line")

# --- Step 2: is_on_segment early return ---

func test_is_on_segment_full_circle_all_angles() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var carrier := GeneralizedCircle.from_circle(center, r)
	var seg := Segment.full_from_carrier(carrier)
	for angle_deg in [0, 45, 90, 135, 180, 225, 270, 315]:
		var angle := deg_to_rad(angle_deg)
		var point := center + Vector2(cos(angle), sin(angle)) * r
		assert_true(Intersection.is_on_segment(point, seg),
			"Full circle: point at %d degrees should be on segment" % angle_deg)

func test_is_on_segment_full_line() -> void:
	var carrier := GeneralizedCircle.from_line(0.0, 1.0, -300.0)
	var seg := Segment.full_from_carrier(carrier)
	for x in [-1000.0, 0.0, 300.0, 99999.0]:
		assert_true(Intersection.is_on_segment(Vector2(x, 300), seg),
			"Full line: point at x=%s should be on segment" % x)

func test_is_on_segment_non_full_unchanged() -> void:
	var seg := Segment.from_coords(Vector2(0, 0), Vector2(100, 0), Vector2(50, 0))
	assert_true(Intersection.is_on_segment(Vector2(50, 0), seg),
		"Midpoint should be on non-full segment")

# --- Step 3: _detect_endpoints_on_ray empty for full ---

func test_detect_endpoints_empty_for_full_circle() -> void:
	var center := Vector2(960, 540)
	var carrier := GeneralizedCircle.from_circle(center, 200.0)
	var seg := Segment.full_from_carrier(carrier)
	var ray := Ray.from_coords(Vector2(500, 540), Direction.from_coords(Vector2(500, 540), Vector2(1500, 540)))
	var result := Intersection._detect_endpoints_on_ray(ray, seg)
	assert_eq(result.size(), 0,
		"Full segment should have no endpoint detections. Got %s" % result)

# --- Step 4: at_which_endpoint returns 0 for full ---

func test_at_which_endpoint_zero_for_full() -> void:
	var center := Vector2(960, 540)
	var carrier := GeneralizedCircle.from_circle(center, 200.0)
	var seg := Segment.full_from_carrier(carrier)
	assert_eq(Intersection.at_which_endpoint(seg.start.coords, seg), 0,
		"Full segment: start coords should not be detected as endpoint")
	assert_eq(Intersection.at_which_endpoint(seg.end.coords, seg), 0,
		"Full segment: end coords should not be detected as endpoint")

# --- Step 5: transformed propagates full ---

func test_transformed_propagates_full() -> void:
	var center := Vector2(960, 540)
	var carrier := GeneralizedCircle.from_circle(center, 200.0)
	var seg := Segment.full_from_carrier(carrier)
	var refl := ReflectionEffect.new(carrier)
	var tracked := refl.get_tracked_transform()
	var transformed := seg.transformed(tracked.inverse)
	assert_true(transformed.full,
		"Transformed full segment should remain full")

func test_transformed_non_full_stays_non_full() -> void:
	var seg := Segment.from_coords(
		Vector2(960 + 200, 540), Vector2(960 - 200, 540), Vector2(960, 740))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var tracked := refl.get_tracked_transform()
	var transformed := seg.transformed(tracked.inverse)
	assert_false(transformed.full,
		"Transformed non-full segment should remain non-full")

# --- Step 6: Integration — full circle reflects at the gap ---

func _count_frame_transitions(path: Tracer.TracedPath) -> Array:
	var transitions: Array = []
	var prev_conj := false
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame.conjugating != prev_conj:
			transitions.append(s.frame.conjugating)
			prev_conj = s.frame.conjugating
	return transitions

func test_full_circle_reflects_at_old_gap() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var gap_point := Vector2(center.x, center.y - r)
	var player := gap_point + Vector2(0, -100)
	var aim := Direction.from_coords(player, gap_point)
	var path := Tracer.trace(player, aim, [surf], GameState.new())
	var transitions := _count_frame_transitions(path)
	assert_gte(transitions.size(), 2,
		"Ray at old gap location should reflect. Got transitions=%s" % [transitions])

func test_full_circle_reflects_horizontal() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var player := Vector2(center.x - r - 100, center.y)
	var aim := Direction.from_coords(player, center)
	var path := Tracer.trace(player, aim, [surf], GameState.new())
	var transitions := _count_frame_transitions(path)
	assert_gte(transitions.size(), 2,
		"Horizontal ray through center should reflect. Got transitions=%s" % [transitions])

func test_full_circle_no_slip_through_sweep() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var slip_count := 0
	for angle_deg in range(0, 360, 5):
		var angle := deg_to_rad(angle_deg)
		var target := center + Vector2(cos(angle), sin(angle)) * r
		var player := target + (target - center).normalized() * 100
		var aim := Direction.from_coords(player, target)
		H.reset_counters()
		var path := Tracer.trace(player, aim, [surf], GameState.new())
		var transitions := _count_frame_transitions(path)
		if transitions.size() < 2:
			slip_count += 1
	assert_eq(slip_count, 0,
		"No rays should slip through full circle. %d angles failed." % slip_count)
