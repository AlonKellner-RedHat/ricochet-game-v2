extends GutTest

const H := preload("res://tests/test_helpers.gd")

func before_each() -> void:
	H.reset_counters()

func _circle_no_walls_surfaces() -> Array:
	var center := Vector2(960, 540)
	var r := 200.0
	var carrier := GeneralizedCircle.from_circle(center, r)
	var seg := Segment.full_from_carrier(carrier)
	var reflection := ReflectionEffect.new(carrier)
	var config := SideConfig.new(reflection, true)
	var surf := Surface.new(seg, config, config, false, false)
	var surfaces: Array = [surf]
	var screen_defs := [
		[Vector2(0, 0), Vector2(1920, 0)],
		[Vector2(1920, 0), Vector2(1920, 1080)],
		[Vector2(1920, 1080), Vector2(0, 1080)],
		[Vector2(0, 1080), Vector2(0, 0)],
	]
	for bd in screen_defs:
		var s: Vector2 = bd[0]
		var e: Vector2 = bd[1]
		var bseg := Segment.from_coords(s, e, (s + e) / 2.0)
		var bconf := SideConfig.new(null, false)
		surfaces.append(Surface.new(bseg, bconf, bconf, false, false))
	return surfaces

# --- Unit tests for _is_infinity_gap helper ---

func test_infinity_gap_detected_as_infinity() -> void:
	assert_true(
		InvariantChecker._is_infinity_gap(
			Vector2(-275643616.0, -68910664.0),
			Vector2(585744512.0, 122.6381)),
		"Both endpoints from violation data should be detected as infinity gap")

func test_normal_gap_not_detected_as_infinity() -> void:
	assert_false(
		InvariantChecker._is_infinity_gap(
			Vector2(100.0, 200.0),
			Vector2(300.0, 400.0)),
		"On-screen points should not be detected as infinity gap")

func test_one_huge_one_normal_is_infinity() -> void:
	assert_true(
		InvariantChecker._is_infinity_gap(
			Vector2(-275643616.0, -68910664.0),
			Vector2(500.0, 300.0)),
		"One huge + one normal should be detected as infinity gap")
	assert_true(
		InvariantChecker._is_infinity_gap(
			Vector2(500.0, 300.0),
			Vector2(585744512.0, 122.6381)),
		"One normal + one huge should be detected as infinity gap")

func test_asymmetric_violation_pattern() -> void:
	assert_true(
		InvariantChecker._is_infinity_gap(
			Vector2(996.0467, -1171484800.0),
			Vector2(1026.471, 1154.711)),
		"prev.end with huge y + on-screen curr.start should be detected as infinity gap")

# --- Integration tests: full trace pipeline ---

func _count_nogaps_violations(path: Tracer.TracedPath) -> int:
	var count := 0
	for i in range(1, path.steps.size()):
		var prev: Tracer.Step = path.steps[i - 1]
		var curr: Tracer.Step = path.steps[i]
		if prev.hit == null or curr.hit == null:
			continue
		var gap := prev.end.distance_to(curr.start)
		var tol := 0.05 + 0.001 * i
		if gap > tol:
			if InvariantChecker._is_infinity_gap(prev.end, curr.start):
				continue
			count += 1
	return count

func _count_continuity_violations(path: Tracer.TracedPath) -> int:
	var count := 0
	for i in range(1, path.steps.size()):
		var prev: Tracer.Step = path.steps[i - 1]
		var curr: Tracer.Step = path.steps[i]
		var prev_is_escape: bool = (prev.hit == null) or (prev.hit != null and prev.hit.t < 0.0)
		var curr_is_return: bool = (curr.hit != null and curr.hit.t < 0.0)
		if prev_is_escape or curr_is_return:
			continue
		var gap := prev.end.distance_to(curr.start)
		var tol := 0.05 + 0.001 * i
		if gap > tol:
			if InvariantChecker._is_infinity_gap(prev.end, curr.start):
				continue
			count += 1
	return count

func test_circle_no_walls_no_nogaps_violations() -> void:
	var surfaces := _circle_no_walls_surfaces()
	var cases := [
		[Vector2(0, 0), Vector2(480, 270)],
		[Vector2(0, 0), Vector2(960, 540)],
		[Vector2(0, 0), Vector2(1440, 810)],
		[Vector2(0, 0), Vector2(1920, 1080)],
		[Vector2(0, 0), Vector2(160, 90)],
		[Vector2(960, 0), Vector2(960, 270)],
		[Vector2(960, 0), Vector2(960, 540)],
	]
	for case_data in cases:
		var player: Vector2 = case_data[0]
		var cursor: Vector2 = case_data[1]
		var aim := Direction.from_coords(player, cursor)
		var raw := Tracer.trace(player, aim, surfaces, GameState.new())
		var display := VisualConverter.prepare_for_display(raw, VisualConverter.DEFAULT_BOUNDS)
		var violations := _count_nogaps_violations(display)
		assert_eq(violations, 0,
			"NOGAPS violations for %s->%s should be 0 (infinity gaps skipped)" % [player, cursor])

func test_circle_no_walls_no_continuity_violations() -> void:
	var surfaces := _circle_no_walls_surfaces()
	var cases := [
		[Vector2(0, 0), Vector2(480, 270)],
		[Vector2(0, 0), Vector2(960, 540)],
		[Vector2(0, 0), Vector2(1440, 810)],
		[Vector2(0, 0), Vector2(1920, 1080)],
		[Vector2(0, 0), Vector2(160, 90)],
		[Vector2(960, 0), Vector2(960, 270)],
		[Vector2(960, 0), Vector2(960, 540)],
	]
	for case_data in cases:
		var player: Vector2 = case_data[0]
		var cursor: Vector2 = case_data[1]
		var aim := Direction.from_coords(player, cursor)
		var raw := Tracer.trace(player, aim, surfaces, GameState.new())
		var display := VisualConverter.prepare_for_display(raw, VisualConverter.DEFAULT_BOUNDS)
		var violations := _count_continuity_violations(display)
		assert_eq(violations, 0,
			"PHYSICAL-CONTINUITY violations for %s->%s should be 0 (infinity gaps skipped)" % [player, cursor])

# --- Negative test: normal gaps still reported ---

func test_normal_gap_still_reported() -> void:
	var seg := Segment.from_coords(Vector2(0, 0), Vector2(100, 0), Vector2(50, 0))
	var hit := Intersection.HitRecord.new(1.0, Vector2(50, 0), seg, Side.Value.LEFT, true)
	var path := Tracer.TracedPath.new()
	path.steps.append(Tracer.Step.new(Vector2(0, 0), Vector2(100, 0), 0, hit))
	path.steps.append(Tracer.Step.new(Vector2(200, 0), Vector2(300, 0), 0, hit))
	var violations := _count_nogaps_violations(path)
	assert_eq(violations, 1, "Normal 100px gap should still be reported")

# --- POST-INVERSION-ARC: ray through circle center ---

func _count_post_inversion_arc_violations(path: Tracer.TracedPath) -> int:
	var count := 0
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		if step.frame == null or step.hit == null:
			continue
		if not step.frame.maps_lines_to_arcs():
			continue
		if step.is_arc_step:
			continue
		if step.ray != null and InvariantChecker._is_ray_through_pole(step.ray, step.frame):
			continue
		count += 1
	return count

func test_ray_through_pole_detected() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var carrier := GeneralizedCircle.from_circle(center, r)
	var reflection := ReflectionEffect.new(carrier)
	var frame: MobiusTransform = reflection.get_mobius()
	var player := Vector2(0, 0)
	var aim := Direction.from_coords(player, center)
	var ray := Ray.from_coords(player, aim)
	assert_true(
		InvariantChecker._is_ray_through_pole(ray, frame),
		"Ray from (0,0) toward circle center (960,540) should pass through pole")

func test_ray_not_through_pole() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var carrier := GeneralizedCircle.from_circle(center, r)
	var reflection := ReflectionEffect.new(carrier)
	var frame: MobiusTransform = reflection.get_mobius()
	var player := Vector2(0, 0)
	var aim := Direction.from_coords(player, Vector2(100, 900))
	var ray := Ray.from_coords(player, aim)
	assert_false(
		InvariantChecker._is_ray_through_pole(ray, frame),
		"Ray from (0,0) toward (100,900) should NOT pass through pole")

func test_circle_no_walls_no_post_inversion_arc_violations() -> void:
	var surfaces := _circle_no_walls_surfaces()
	var cases := [
		[Vector2(0, 0), Vector2(480, 270)],
		[Vector2(0, 0), Vector2(960, 540)],
	]
	for case_data in cases:
		var player: Vector2 = case_data[0]
		var cursor: Vector2 = case_data[1]
		var aim := Direction.from_coords(player, cursor)
		var raw := Tracer.trace(player, aim, surfaces, GameState.new())
		var display := VisualConverter.prepare_for_display(raw, VisualConverter.DEFAULT_BOUNDS)
		var violations := _count_post_inversion_arc_violations(display)
		assert_eq(violations, 0,
			"POST-INVERSION-ARC violations for %s->%s should be 0 (ray through center)" % [player, cursor])

# --- ORIGIN-NOT-REHIT: zero-length clipped steps ---

static func _has_zero_length_hit(path: Tracer.TracedPath) -> bool:
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if s.start == s.end and s.hit != null and s.hit.t > 0.0:
			return true
	return false

func test_no_zero_length_after_prepare_start_inf_end_on_bounds() -> void:
	var player := Vector2(1920, 0)
	var cursor := Vector2(1440, 270)
	var aim := Direction.from_coords(player, cursor)
	var ray := Ray.from_coords(player, aim)
	var seg := Segment.from_coords(Vector2(0, 0), Vector2(100, 0), Vector2(50, 0))
	var hit := Intersection.HitRecord.new(0.43, Vector2(50, 0), seg, Side.Value.LEFT, true)
	var step := Tracer.Step.new(
		Vector2(INF, INF),
		Vector2(0.002144, 1080.0),
		0, hit, ray, null,
		Vector2(INF, INF), false)
	var path := Tracer.TracedPath.new()
	path.steps.append(step)
	var display := VisualConverter.prepare_for_display(path, VisualConverter.DEFAULT_BOUNDS)
	assert_false(_has_zero_length_hit(display),
		"start_inf step with end on bounds should not produce zero-length hit step")

func test_no_zero_length_after_prepare_end_inf_start_on_bounds() -> void:
	var player := Vector2(1920, 0)
	var cursor := Vector2(1440, 270)
	var aim := Direction.from_coords(player, cursor)
	var ray := Ray.from_coords(player, aim)
	var seg := Segment.from_coords(Vector2(0, 0), Vector2(100, 0), Vector2(50, 0))
	var hit := Intersection.HitRecord.new(0.43, Vector2(50, 0), seg, Side.Value.LEFT, true)
	var step := Tracer.Step.new(
		Vector2(0.0, 0.0),
		Vector2(INF, INF),
		0, hit, ray, null,
		Vector2(INF, INF), false)
	var path := Tracer.TracedPath.new()
	path.steps.append(step)
	var display := VisualConverter.prepare_for_display(path, VisualConverter.DEFAULT_BOUNDS)
	assert_false(_has_zero_length_hit(display),
		"end_inf step with start on bounds should not produce zero-length hit step")

func test_circle_no_walls_no_origin_not_rehit_violations() -> void:
	var surfaces := _circle_no_walls_surfaces()
	var cases := [
		[Vector2(1920, 0), Vector2(1440, 270)],
		[Vector2(1920, 0), Vector2(960, 540)],
		[Vector2(1920, 0), Vector2(0, 1080)],
	]
	for case_data in cases:
		var player: Vector2 = case_data[0]
		var cursor: Vector2 = case_data[1]
		var aim := Direction.from_coords(player, cursor)
		var raw := Tracer.trace(player, aim, surfaces, GameState.new())
		var display := VisualConverter.prepare_for_display(raw, VisualConverter.DEFAULT_BOUNDS)
		assert_false(_has_zero_length_hit(display),
			"ORIGIN-NOT-REHIT: %s->%s should have no zero-length hit steps" % [player, cursor])
