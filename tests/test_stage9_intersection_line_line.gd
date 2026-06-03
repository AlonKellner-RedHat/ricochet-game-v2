extends GutTest

func _make_ray(origin: Vector2, toward: Vector2) -> Ray:
	return Ray.new(origin, Direction.new(origin, toward))

func test_stage9_line_line_perpendicular() -> void:
	var ray := _make_ray(Vector2(0, 0), Vector2(0, 100))
	var seg := Segment.new(Vector2(-50, 50), Vector2(50, 50), Vector2(0, 50))
	var hits := Intersection.intersect_line_with_gcircle(ray, seg)
	assert_eq(hits.size(), 1, "Should find one intersection")
	assert_gt(hits[0].t, 0.0, "Hit should be in front of ray")
	assert_almost_eq(hits[0].point.x, 0.0, 0.01, "Hit x should be 0")
	assert_almost_eq(hits[0].point.y, 50.0, 0.01, "Hit y should be 50")

func test_stage9_line_line_oblique() -> void:
	var ray := _make_ray(Vector2(0, 0), Vector2(100, 100))
	var seg := Segment.new(Vector2(50, 0), Vector2(50, 100), Vector2(50, 50))
	var hits := Intersection.intersect_line_with_gcircle(ray, seg)
	assert_eq(hits.size(), 1, "Should find one intersection")
	assert_almost_eq(hits[0].point.x, 50.0, 0.01, "Hit x should be 50")
	assert_almost_eq(hits[0].point.y, 50.0, 0.01, "Hit y should be 50")

func test_stage9_line_line_parallel() -> void:
	var ray := _make_ray(Vector2(0, 0), Vector2(0, 100))
	var seg := Segment.new(Vector2(50, 0), Vector2(50, 100), Vector2(50, 50))
	var hits := Intersection.intersect_line_with_gcircle(ray, seg)
	assert_eq(hits.size(), 0, "Parallel lines should have no intersection")

func test_stage9_line_line_coincident() -> void:
	var ray := _make_ray(Vector2(0, 0), Vector2(100, 0))
	var seg := Segment.new(Vector2(50, 0), Vector2(150, 0), Vector2(100, 0))
	var hits := Intersection.intersect_line_with_gcircle(ray, seg)
	assert_eq(hits.size(), 0, "Coincident lines should have no intersection")

func test_stage9_line_line_outside_segment() -> void:
	var ray := _make_ray(Vector2(0, 0), Vector2(0, 100))
	var seg := Segment.new(Vector2(10, 50), Vector2(20, 50), Vector2(15, 50))
	var hits := Intersection.intersect_line_with_gcircle(ray, seg)
	assert_eq(hits.size(), 0, "Hit outside segment bounds should be filtered")

func test_stage9_line_line_at_segment_endpoint() -> void:
	var ray := _make_ray(Vector2(0, 0), Vector2(0, 100))
	var seg := Segment.new(Vector2(0, 50), Vector2(50, 50), Vector2(25, 50))
	var hits := Intersection.intersect_line_with_gcircle(ray, seg)
	assert_eq(hits.size(), 1, "Hit at segment endpoint should be included")
	assert_almost_eq(hits[0].point.x, 0.0, 0.01, "Hit at start endpoint")

func test_stage9_line_line_negative_t() -> void:
	var ray := _make_ray(Vector2(0, 100), Vector2(0, 200))
	var seg := Segment.new(Vector2(-50, 50), Vector2(50, 50), Vector2(0, 50))
	var hits := Intersection.intersect_line_with_gcircle(ray, seg)
	assert_eq(hits.size(), 1, "Behind-ray hit should still be returned")
	assert_lt(hits[0].t, 0.0, "Hit behind ray should have negative t")

func test_stage9_line_line_via_inf() -> void:
	var ray := _make_ray(Vector2(0, 0), Vector2(0, 100))
	var seg := Segment.new(Vector2(-50, 50), Vector2(50, 50), Vector2(INF, INF))
	var hits := Intersection.intersect_line_with_gcircle(ray, seg)
	assert_eq(hits.size(), 0, "Hit in finite portion of INF segment should be excluded")

func test_stage9_S8_forward_first() -> void:
	var ray := _make_ray(Vector2(0, 50), Vector2(100, 50))
	var seg_front := Segment.new(Vector2(80, 0), Vector2(80, 100), Vector2(80, 50))
	var seg_back := Segment.new(Vector2(-30, 0), Vector2(-30, 100), Vector2(-30, 50))
	var hits_front := Intersection.intersect_line_with_gcircle(ray, seg_front)
	var hits_back := Intersection.intersect_line_with_gcircle(ray, seg_back)
	assert_eq(hits_front.size(), 1, "Front surface should produce a hit")
	assert_eq(hits_back.size(), 1, "Back surface should produce a hit")
	assert_gt(hits_front[0].t, 0.0, "Front hit should have positive t")
	assert_lt(hits_back[0].t, 0.0, "Back hit should have negative t")

func test_stage9_S16_no_nan_inf() -> void:
	var ray := _make_ray(Vector2(0, 0), Vector2(0, 100))
	var seg := Segment.new(Vector2(-50, 50), Vector2(50, 50), Vector2(0, 50))
	var hits := Intersection.intersect_line_with_gcircle(ray, seg)
	for hit in hits:
		assert_false(is_nan(hit.point.x), "S16: hit x should not be NaN")
		assert_false(is_nan(hit.point.y), "S16: hit y should not be NaN")
		assert_false(is_inf(hit.point.x), "S16: hit x should not be Inf")
		assert_false(is_inf(hit.point.y), "S16: hit y should not be Inf")
		assert_false(is_nan(hit.t), "S16: t should not be NaN")
