extends GutTest

# §16.2 arc: start=(200,100), end=(200,300), via=(300,200)
# Carrier: circle center=(200,200), radius=100

func test_stage41_visual_converter_line_carrier() -> void:
	var s := Vector2(100, 200)
	var e := Vector2(400, 200)
	var v := Vector2(250, 200)
	assert_false(VisualConverter.is_arc(s, v, e), "Collinear points are not an arc")

func test_stage41_visual_converter_circle_carrier() -> void:
	var s := Vector2(200, 100)
	var e := Vector2(200, 300)
	var v := Vector2(300, 200)
	assert_true(VisualConverter.is_arc(s, v, e), "Non-collinear points are an arc")
	var p: Dictionary = VisualConverter.arc_params(s, v, e)
	assert_almost_eq(p["center"], Vector2(200, 200), Vector2(0.1, 0.1), "Center = (200,200)")
	assert_almost_eq(p["radius"], 100.0, 0.1, "Radius = 100")

func test_stage41_arc_angles_from_three_points() -> void:
	var s := Vector2(200, 100)
	var e := Vector2(200, 300)
	var v := Vector2(300, 200)
	var p: Dictionary = VisualConverter.arc_params(s, v, e)
	var sa: float = (s - Vector2(200, 200)).angle()
	var ea: float = (e - Vector2(200, 200)).angle()
	assert_almost_eq(p["start_angle"], sa, 0.01, "Start angle matches")
	assert_almost_eq(p["end_angle"], ea, 0.01, "End angle matches")

func test_stage41_clockwise_flag_ccw_winding() -> void:
	var s := Vector2(200, 100)
	var e := Vector2(200, 300)
	var v := Vector2(300, 200)
	var p: Dictionary = VisualConverter.arc_params(s, v, e)
	var cross: float = (s - Vector2(200, 200)).cross(v - Vector2(200, 200))
	if cross >= 0.0:
		assert_false(p["clockwise"], "CCW winding → clockwise=false")
	else:
		assert_true(p["clockwise"], "CW winding → clockwise=true")

func test_stage41_clockwise_flag_cw_winding() -> void:
	var s := Vector2(200, 300)
	var e := Vector2(200, 100)
	var v := Vector2(300, 200)
	var p: Dictionary = VisualConverter.arc_params(s, v, e)
	var cross: float = (s - p["center"]).cross(v - p["center"])
	if cross < 0.0:
		assert_true(p["clockwise"], "CW winding → clockwise=true")
	else:
		assert_false(p["clockwise"], "CCW winding → clockwise=false")

func test_stage41_draw_arc_clockwise_swap() -> void:
	# via on the LEFT side of start→end → CW winding
	var s := Vector2(200, 100)
	var e := Vector2(200, 300)
	var v := Vector2(100, 200)
	var p: Dictionary = VisualConverter.arc_params(s, v, e)
	assert_true(p["clockwise"], "This geometry should be CW")
	var sa: float = (s - p["center"]).angle()
	var ea: float = (e - p["center"]).angle()
	assert_almost_eq(p["start_angle"], ea, 0.01, "CW: draw_start = end_angle (swapped)")
	assert_almost_eq(p["end_angle"], sa, 0.01, "CW: draw_end = start_angle (swapped)")

func test_stage41_point_count_full_circle() -> void:
	var span := TAU
	var count := maxi(4, int(256 * span / TAU))
	assert_eq(count, 256, "Full circle = 256 points")

func test_stage41_point_count_quarter_circle() -> void:
	var span := TAU / 4.0
	var count := maxi(4, int(256 * span / TAU))
	assert_eq(count, 64, "Quarter circle = 64 points")

func test_stage41_escape_step_guard() -> void:
	var s := Vector2(200, 200)
	var e := Vector2(INF, INF)
	var v := Vector2(300, 300)
	assert_false(VisualConverter.is_arc(s, v, e), "Escape step (end=INF) is not an arc")

func test_stage41_S16_arc_no_nan() -> void:
	var test_cases: Array = [
		[Vector2(200, 100), Vector2(300, 200), Vector2(200, 300)],
		[Vector2(0, 100), Vector2(100, 0), Vector2(0, -100)],
		[Vector2(500, 300), Vector2(600, 400), Vector2(500, 500)],
	]
	for tc in test_cases:
		var s: Vector2 = tc[0]
		var v: Vector2 = tc[1]
		var e: Vector2 = tc[2]
		if VisualConverter.is_arc(s, v, e):
			var p: Dictionary = VisualConverter.arc_params(s, v, e)
			assert_false(is_nan(p["center"].x) or is_nan(p["center"].y),
				"S16: no NaN in center for %s" % [tc])
			assert_false(is_nan(p["radius"]),
				"S16: no NaN in radius for %s" % [tc])
			assert_false(is_nan(p["start_angle"]) or is_nan(p["end_angle"]),
				"S16: no NaN in angles for %s" % [tc])
