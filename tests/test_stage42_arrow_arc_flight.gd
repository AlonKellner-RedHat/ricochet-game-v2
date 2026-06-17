extends GutTest

const H := preload("res://tests/test_helpers.gd")
const Arrow := preload("res://scripts/game/arrow_animator.gd")

func before_each() -> void:
	H.reset_counters()

func _make_arc_step(start: Vector2, end_v: Vector2, via: Vector2) -> Tracer.Step:
	var frame := MobiusTransform.identity()
	var ray := Ray.from_coords(start, Direction.from_coords(start, end_v))
	return Tracer.Step.new(start, end_v, frame.id, null, ray, frame, via, true)

func _make_line_step(start: Vector2, end_v: Vector2) -> Tracer.Step:
	var frame := MobiusTransform.identity()
	var ray := Ray.from_coords(start, Direction.from_coords(start, end_v))
	var via := (start + end_v) / 2.0
	return Tracer.Step.new(start, end_v, frame.id, null, ray, frame, via, false)

# --- CCW semicircle: start=(2,0), end=(-2,0), via=(0,2) ---
# Center=(0,0), radius=2, span=PI, arc_length=2*PI

func test_arc_position_at_midpoint() -> void:
	var step := _make_arc_step(Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2))
	var arc_len := 2.0 * PI
	var r := Arrow.advance([step], 0, 0.0, step.start, arc_len * 0.5,
		VisualConverter.DEFAULT_BOUNDS)
	assert_almost_eq(r.position, Vector2(0, 2), Vector2(0.01, 0.01),
		"Midpoint of CCW semicircle should be at top (0, 2)")

func test_arc_position_at_quarter() -> void:
	var step := _make_arc_step(Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2))
	var arc_len := 2.0 * PI
	var r := Arrow.advance([step], 0, 0.0, step.start, arc_len * 0.25,
		VisualConverter.DEFAULT_BOUNDS)
	var expected := Vector2(sqrt(2.0), sqrt(2.0))
	assert_almost_eq(r.position, expected, Vector2(0.01, 0.01),
		"Quarter of CCW semicircle should be at 45 degrees")

func test_arc_constant_visual_speed() -> void:
	var step := _make_arc_step(Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2))
	var chord_dist := step.start.distance_to(step.end)
	assert_almost_eq(chord_dist, 4.0, 0.01, "Chord distance should be 4")
	var arc_len := 2.0 * PI
	assert_gt(arc_len, chord_dist, "Arc length must exceed chord distance")
	var r := Arrow.advance([step], 0, 0.0, step.start, arc_len * 0.5,
		VisualConverter.DEFAULT_BOUNDS)
	assert_almost_eq(r.position, Vector2(0, 2), Vector2(0.01, 0.01),
		"Half arc_length should reach midpoint, not chord midpoint")

func test_arc_tangent_direction_at_midpoint() -> void:
	var step := _make_arc_step(Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2))
	var arc_len := 2.0 * PI
	var r := Arrow.advance([step], 0, 0.0, step.start, arc_len * 0.5,
		VisualConverter.DEFAULT_BOUNDS)
	assert_almost_eq(r.direction, Vector2(-1, 0), Vector2(0.01, 0.01),
		"Tangent at top of CCW semicircle should point left (-1, 0)")

func test_arc_tangent_direction_at_start() -> void:
	var step := _make_arc_step(Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2))
	var r := Arrow.advance([step], 0, 0.0, step.start, 0.001,
		VisualConverter.DEFAULT_BOUNDS)
	assert_almost_eq(r.direction, Vector2(0, 1), Vector2(0.02, 0.02),
		"Tangent at start of CCW semicircle should point up (0, 1)")

func test_clockwise_arc() -> void:
	var step := _make_arc_step(Vector2(0, 2), Vector2(0, -2), Vector2(2, 0))
	var arc_len := 2.0 * PI
	var r := Arrow.advance([step], 0, 0.0, step.start, arc_len * 0.5,
		VisualConverter.DEFAULT_BOUNDS)
	assert_almost_eq(r.position, Vector2(2, 0), Vector2(0.01, 0.01),
		"Midpoint of CW semicircle should be at (2, 0)")
	assert_almost_eq(r.direction, Vector2(0, -1), Vector2(0.01, 0.01),
		"CW tangent at (2,0) should point down (0, -1)")

func test_line_step_unchanged() -> void:
	var step := _make_line_step(Vector2(0, 0), Vector2(100, 0))
	var r := Arrow.advance([step], 0, 0.0, step.start, 50.0,
		VisualConverter.DEFAULT_BOUNDS)
	assert_almost_eq(r.position, Vector2(50, 0), Vector2(0.01, 0.01),
		"Line step should use linear interpolation")
	assert_almost_eq(r.direction, Vector2(1, 0), Vector2(0.01, 0.01),
		"Line step direction should be chord direction")

func test_arc_reaches_end() -> void:
	var step := _make_arc_step(Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2))
	var arc_len := 2.0 * PI
	var r := Arrow.advance([step], 0, 0.0, step.start, arc_len + 1.0,
		VisualConverter.DEFAULT_BOUNDS)
	assert_almost_eq(r.position, Vector2(-2, 0), Vector2(0.01, 0.01),
		"Advancing past arc length should land at step end")
	assert_true(r.finished, "Should be finished after single step")

func test_multi_step_line_then_arc() -> void:
	var line := _make_line_step(Vector2(0, 0), Vector2(2, 0))
	var arc := _make_arc_step(Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2))
	var arc_len := 2.0 * PI
	var r := Arrow.advance([line, arc], 0, 0.0, line.start,
		2.0 + arc_len * 0.5, VisualConverter.DEFAULT_BOUNDS)
	assert_eq(r.step_index, 1, "Should be on the arc step")
	assert_almost_eq(r.position, Vector2(0, 2), Vector2(0.01, 0.01),
		"After line + half arc, should be at arc midpoint")
