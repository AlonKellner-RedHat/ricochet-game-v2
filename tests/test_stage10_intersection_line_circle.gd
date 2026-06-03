extends GutTest

func _make_ray(origin: Vector2, toward: Vector2) -> Ray:
	return Ray.new(origin, Direction.new(origin, toward))

func test_stage10_line_circle_secant() -> void:
	var ray := _make_ray(Vector2(0, 200), Vector2(400, 200))
	var seg := Segment.new(Vector2(200, 100), Vector2(200, 300), Vector2(300, 200))
	var hits := Intersection.intersect_line_with_gcircle(ray, seg)
	assert_eq(hits.size(), 1, "One hit should be on the right semicircle arc")
	assert_almost_eq(hits[0].point.x, 300.0, 0.1, "Hit at (300, 200)")
	assert_almost_eq(hits[0].point.y, 200.0, 0.1, "Hit y at 200")

func test_stage10_line_circle_tangent() -> void:
	# Tangent at the top — ray at y=100, circle center (200,200) r=100
	# Use a full semicircle that includes the tangent point in its interior
	var ray := _make_ray(Vector2(0, 100), Vector2(400, 100))
	var seg := Segment.new(Vector2(300, 200), Vector2(100, 200), Vector2(200, 100))
	var hits := Intersection.intersect_line_with_gcircle(ray, seg)
	assert_eq(hits.size(), 1, "Tangent should produce one hit")
	assert_almost_eq(hits[0].point.x, 200.0, 0.1, "Tangent at (200, 100)")
	assert_almost_eq(hits[0].point.y, 100.0, 0.1, "Tangent y at 100")

func test_stage10_line_circle_miss() -> void:
	var ray := _make_ray(Vector2(0, 0), Vector2(400, 0))
	var seg := Segment.new(Vector2(200, 100), Vector2(200, 300), Vector2(300, 200))
	var hits := Intersection.intersect_line_with_gcircle(ray, seg)
	assert_eq(hits.size(), 0, "Ray missing circle should have no hits")

func test_stage10_arc_containment_major_arc() -> void:
	# Major arc (left semicircle): start=(200,100), end=(200,300), via=(100,200)
	var ray := _make_ray(Vector2(0, 200), Vector2(400, 200))
	var seg := Segment.new(Vector2(200, 100), Vector2(200, 300), Vector2(100, 200))
	var hits := Intersection.intersect_line_with_gcircle(ray, seg)
	assert_gte(hits.size(), 1, "Major arc should have at least one hit")
	var has_left_hit := false
	for hit in hits:
		if absf(hit.point.x - 100.0) < 0.1:
			has_left_hit = true
	assert_true(has_left_hit, "Major arc should include hit at (100, 200)")

func test_stage10_arc_containment_excludes_wrong_arc() -> void:
	# Right semicircle: via=(300,200). Hit at (100,200) is on the opposite arc.
	var ray := _make_ray(Vector2(0, 200), Vector2(400, 200))
	var seg := Segment.new(Vector2(200, 100), Vector2(200, 300), Vector2(300, 200))
	var hits := Intersection.intersect_line_with_gcircle(ray, seg)
	for hit in hits:
		assert_gt(hit.point.x, 150.0, "Right semicircle arc should not include (100, 200)")

func test_stage10_line_circle_negative_t() -> void:
	# Ray from center going right. Left semicircle arc has hit behind (t < 0).
	var ray := _make_ray(Vector2(200, 200), Vector2(400, 200))
	var seg := Segment.new(Vector2(200, 100), Vector2(200, 300), Vector2(100, 200))
	var hits := Intersection.intersect_line_with_gcircle(ray, seg)
	assert_eq(hits.size(), 1, "Should have one hit on left arc")
	assert_lt(hits[0].t, 0.0, "Hit on left arc should be behind the ray")

func test_stage10_S8_line_circle_t_values() -> void:
	# Ray from left, hitting right semicircle at two points
	var ray := _make_ray(Vector2(0, 200), Vector2(400, 200))
	# Use a top semicircle so both hits are on the arc
	var seg := Segment.new(Vector2(100, 200), Vector2(300, 200), Vector2(200, 100))
	var hits := Intersection.intersect_line_with_gcircle(ray, seg)
	assert_eq(hits.size(), 2, "Should have two hits on top semicircle")
	assert_lt(hits[0].t, hits[1].t, "First hit should have smaller t (closer)")
	assert_gt(hits[0].t, 0.0, "First hit should be in front of ray")

func test_stage10_S16_no_nan_inf_circle() -> void:
	var ray := _make_ray(Vector2(0, 200), Vector2(400, 200))
	var seg := Segment.new(Vector2(200, 100), Vector2(200, 300), Vector2(300, 200))
	var hits := Intersection.intersect_line_with_gcircle(ray, seg)
	for hit in hits:
		assert_false(is_nan(hit.point.x), "S16: hit x should not be NaN")
		assert_false(is_nan(hit.point.y), "S16: hit y should not be NaN")
		assert_false(is_nan(hit.t), "S16: t should not be NaN")
		assert_false(is_inf(hit.t), "S16: t should not be Inf")
