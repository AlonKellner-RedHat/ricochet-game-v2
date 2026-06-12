extends GutTest

func test_stage7_collinear_produces_line() -> void:
	var seg := Segment.from_coords(Vector2(0, 0), Vector2(10, 0), Vector2(5, 0))
	assert_true(seg.is_line(), "Collinear points should produce a line carrier")

func test_stage7_noncollinear_produces_circle() -> void:
	var seg := Segment.from_coords(Vector2(200, 100), Vector2(200, 300), Vector2(300, 200))
	var carrier := seg.get_carrier()
	assert_false(seg.is_line(), "Non-collinear points should produce a circle carrier")
	assert_almost_eq(carrier.center().x, 200.0, 0.01, "Center x should be 200")
	assert_almost_eq(carrier.center().y, 200.0, 0.01, "Center y should be 200")
	assert_almost_eq(carrier.radius(), 100.0, 0.01, "Radius should be 100")

func test_stage7_via_inf_produces_line() -> void:
	var seg := Segment.from_coords(Vector2(0, 0), Vector2(10, 0), Vector2(INF, INF))
	assert_true(seg.is_line(), "via=INF should produce a line carrier")

func test_stage7_side_determination_line() -> void:
	var seg := Segment.from_coords(Vector2(100, 400), Vector2(100, 200), Vector2(100, 300))
	assert_eq(seg.determine_side(Vector2(50, 300)), Side.Value.LEFT, "Point left of vertical line should be LEFT")
	assert_eq(seg.determine_side(Vector2(150, 300)), Side.Value.RIGHT, "Point right of vertical line should be RIGHT")

func test_stage7_side_determination_circle() -> void:
	var seg := Segment.from_coords(Vector2(200, 100), Vector2(200, 300), Vector2(300, 200))
	var outside_side := seg.determine_side(Vector2(400, 200))
	var inside_side := seg.determine_side(Vector2(200, 200))
	assert_ne(outside_side, inside_side, "Outside and inside should be different sides")

func test_stage7_S11_three_points_on_carrier() -> void:
	var line_seg := Segment.from_coords(Vector2(0, 0), Vector2(10, 0), Vector2(5, 0))
	var line_carrier := line_seg.get_carrier()
	assert_almost_eq(line_carrier.evaluate(line_seg.start.coords), 0.0, 1e-6, "S11: start should be on line carrier")
	assert_almost_eq(line_carrier.evaluate(line_seg.end.coords), 0.0, 1e-6, "S11: end should be on line carrier")
	assert_almost_eq(line_carrier.evaluate(line_seg.via.coords), 0.0, 1e-6, "S11: via should be on line carrier")

	var arc_seg := Segment.from_coords(Vector2(200, 100), Vector2(200, 300), Vector2(300, 200))
	var arc_carrier := arc_seg.get_carrier()
	assert_almost_eq(arc_carrier.evaluate(arc_seg.start.coords), 0.0, 0.01, "S11: start should be on circle carrier")
	assert_almost_eq(arc_carrier.evaluate(arc_seg.end.coords), 0.0, 0.01, "S11: end should be on circle carrier")
	assert_almost_eq(arc_carrier.evaluate(arc_seg.via.coords), 0.0, 0.01, "S11: via should be on circle carrier")

func test_stage7_S12_side_consistent() -> void:
	var seg := Segment.from_coords(Vector2(100, 400), Vector2(100, 200), Vector2(100, 300))
	var side_a := seg.determine_side(Vector2(50, 100))
	var side_b := seg.determine_side(Vector2(50, 300))
	var side_c := seg.determine_side(Vector2(50, 500))
	assert_eq(side_a, side_b, "S12: Same-side points should have same side")
	assert_eq(side_b, side_c, "S12: Same-side points should have same side")
	var side_d := seg.determine_side(Vector2(150, 100))
	var side_e := seg.determine_side(Vector2(150, 300))
	assert_eq(side_d, side_e, "S12: Same-side points should have same side")
	assert_ne(side_a, side_d, "S12: Opposite-side points should have different sides")

func test_stage7_winding_ccw() -> void:
	var seg := Segment.from_coords(Vector2(0, 0), Vector2(0, 10), Vector2(5, 5))
	var winding := (seg.via.coords - seg.start.coords).cross(seg.end.coords - seg.start.coords)
	assert_gt(winding, 0.0, "Should be CCW winding (positive signed area)")
	var carrier := seg.get_carrier()
	var test_point := Vector2(10, 5)
	var f_val := carrier.evaluate(test_point)
	if f_val > 0.0:
		assert_eq(seg.determine_side(test_point), Side.Value.LEFT, "CCW: f(P) > 0 should be LEFT")

func test_stage7_winding_cw() -> void:
	var seg := Segment.from_coords(Vector2(0, 10), Vector2(0, 0), Vector2(5, 5))
	var winding := (seg.via.coords - seg.start.coords).cross(seg.end.coords - seg.start.coords)
	assert_lt(winding, 0.0, "Should be CW winding (negative signed area)")
	var carrier := seg.get_carrier()
	var test_point := Vector2(10, 5)
	var f_val := carrier.evaluate(test_point)
	if f_val > 0.0:
		assert_eq(seg.determine_side(test_point), Side.Value.RIGHT, "CW: f(P) > 0 should be RIGHT")
