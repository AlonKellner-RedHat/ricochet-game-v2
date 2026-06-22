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

static func _has_nan(step: Tracer.Step) -> bool:
	return is_nan(step.start.x) or is_nan(step.start.y) \
		or is_nan(step.end.x) or is_nan(step.end.y) \
		or is_nan(step.via.x) or is_nan(step.via.y)

# --- Unit tests: prepare_for_display with synthetic infinite steps ---

func _make_dummy_hit() -> Intersection.HitRecord:
	var seg := Segment.from_coords(Vector2(0, 0), Vector2(100, 0), Vector2(50, 0))
	return Intersection.HitRecord.new(1.0, Vector2(50, 0), seg, Side.Value.LEFT, true)

func test_no_nan_after_prepare_for_display_end_inf_via_inf() -> void:
	var player := Vector2(0, 0)
	var cursor := Vector2(480, 270)
	var aim := Direction.from_coords(player, cursor)
	var ray := Ray.from_coords(player, aim)
	var hit := _make_dummy_hit()
	var step := Tracer.Step.new(
		Vector2(-275643520.0, -68910640.0),
		Vector2(INF, INF),
		0, hit, ray, null,
		Vector2(INF, INF), false)
	var path := Tracer.TracedPath.new()
	path.steps.append(step)

	var display := VisualConverter.prepare_for_display(path, VisualConverter.DEFAULT_BOUNDS)
	for i in display.steps.size():
		var s: Tracer.Step = display.steps[i]
		assert_false(_has_nan(s),
			"Display step %d has NaN: start=%s end=%s via=%s" % [i, s.start, s.end, s.via])

func test_no_nan_after_prepare_for_display_start_inf_via_inf() -> void:
	var player := Vector2(0, 0)
	var cursor := Vector2(480, 270)
	var aim := Direction.from_coords(player, cursor)
	var ray := Ray.from_coords(player, aim)
	var hit := _make_dummy_hit()
	var step := Tracer.Step.new(
		Vector2(INF, INF),
		Vector2(585744384.0, 122.6381),
		0, hit, ray, null,
		Vector2(INF, INF), false)
	var path := Tracer.TracedPath.new()
	path.steps.append(step)

	var display := VisualConverter.prepare_for_display(path, VisualConverter.DEFAULT_BOUNDS)
	for i in display.steps.size():
		var s: Tracer.Step = display.steps[i]
		assert_false(_has_nan(s),
			"Display step %d has NaN: start=%s end=%s via=%s" % [i, s.start, s.end, s.via])

# --- Integration tests: full circle_no_walls traces ---

func test_circle_no_walls_trace_no_nan_case1() -> void:
	var surfaces := _circle_no_walls_surfaces()
	var player := Vector2(0, 0)
	var cursor := Vector2(480, 270)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfaces, GameState.new())
	var display := VisualConverter.prepare_for_display(path, VisualConverter.DEFAULT_BOUNDS)

	for i in display.steps.size():
		var s: Tracer.Step = display.steps[i]
		assert_false(_has_nan(s),
			"Display step %d has NaN: start=%s end=%s via=%s" % [i, s.start, s.end, s.via])

func test_circle_no_walls_trace_no_nan_case2() -> void:
	var surfaces := _circle_no_walls_surfaces()
	var player := Vector2(0, 0)
	var cursor := Vector2(960, 540)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfaces, GameState.new())
	var display := VisualConverter.prepare_for_display(path, VisualConverter.DEFAULT_BOUNDS)

	for i in display.steps.size():
		var s: Tracer.Step = display.steps[i]
		assert_false(_has_nan(s),
			"Display step %d has NaN: start=%s end=%s via=%s" % [i, s.start, s.end, s.via])
