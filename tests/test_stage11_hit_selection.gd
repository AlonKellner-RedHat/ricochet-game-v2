extends GutTest

func _make_ray(origin: Vector2, toward: Vector2) -> Ray:
	return Ray.new(origin, Direction.new(origin, toward))

func _v_seg(x: float, y_start: float, y_end: float) -> Segment:
	return Segment.new(Vector2(x, y_start), Vector2(x, y_end), Vector2(x, (y_start + y_end) / 2.0))

func _h_seg(y: float, x_start: float, x_end: float) -> Segment:
	return Segment.new(Vector2(x_start, y), Vector2(x_end, y), Vector2((x_start + x_end) / 2.0, y))

func test_stage11_earliest_hit_single_surface() -> void:
	var ray := _make_ray(Vector2(0, 50), Vector2(100, 50))
	var seg := _v_seg(80, 0, 100)
	var hit = Intersection.find_earliest_hit(ray, [seg])
	assert_not_null(hit, "Should find a hit")
	assert_almost_eq(hit.point.x, 80.0, 0.1, "Hit at x=80")
	assert_eq(hit.segment, seg, "Hit should reference the correct segment")

func test_stage11_earliest_hit_two_surfaces_forward() -> void:
	var ray := _make_ray(Vector2(0, 50), Vector2(200, 50))
	var seg_close := _v_seg(50, 0, 100)
	var seg_far := _v_seg(150, 0, 100)
	var hit = Intersection.find_earliest_hit(ray, [seg_far, seg_close])
	assert_not_null(hit, "Should find a hit")
	assert_almost_eq(hit.point.x, 50.0, 0.1, "Closer surface should win")

func test_stage11_earliest_hit_only_behind() -> void:
	var ray := _make_ray(Vector2(100, 50), Vector2(200, 50))
	var seg_a := _v_seg(30, 0, 100)
	var seg_b := _v_seg(60, 0, 100)
	var hit = Intersection.find_earliest_hit(ray, [seg_a, seg_b])
	assert_not_null(hit, "Should find a behind-infinity hit")
	assert_lt(hit.t, 0.0, "Hit should have negative t")
	assert_almost_eq(hit.point.x, 30.0, 0.1, "Most negative t (furthest behind) wins")

func test_stage11_earliest_hit_mixed() -> void:
	var ray := _make_ray(Vector2(50, 50), Vector2(200, 50))
	var seg_forward := _v_seg(100, 0, 100)
	var seg_behind := _v_seg(20, 0, 100)
	var hit = Intersection.find_earliest_hit(ray, [seg_behind, seg_forward])
	assert_not_null(hit, "Should find a hit")
	assert_gt(hit.t, 0.0, "Forward hit should take priority")
	assert_almost_eq(hit.point.x, 100.0, 0.1, "Forward surface wins")

func test_stage11_origin_exclusion() -> void:
	var ray := _make_ray(Vector2(80, 50), Vector2(200, 50))
	var seg_at_origin := _v_seg(80, 0, 100)
	var seg_ahead := _v_seg(150, 0, 100)
	var hit = Intersection.find_earliest_hit(ray, [seg_at_origin, seg_ahead])
	assert_not_null(hit, "Should find hit past origin surface")
	assert_almost_eq(hit.point.x, 150.0, 0.1, "Origin surface should be excluded")

func test_stage11_excluded_surfaces() -> void:
	var ray := _make_ray(Vector2(0, 50), Vector2(200, 50))
	var seg_excluded := _v_seg(50, 0, 100)
	var seg_included := _v_seg(100, 0, 100)
	var hit = Intersection.find_earliest_hit(ray, [seg_excluded, seg_included], [seg_excluded])
	assert_not_null(hit, "Should find non-excluded hit")
	assert_almost_eq(hit.point.x, 100.0, 0.1, "Excluded surface should be skipped")

func test_stage11_no_hit_returns_null() -> void:
	var ray := _make_ray(Vector2(0, 50), Vector2(100, 50))
	var hit = Intersection.find_earliest_hit(ray, [])
	assert_null(hit, "Empty scene should return null")

func test_stage11_no_hit_parallel() -> void:
	var ray := _make_ray(Vector2(0, 50), Vector2(100, 50))
	var seg := _h_seg(50, 0, 100)
	var hit = Intersection.find_earliest_hit(ray, [seg])
	assert_null(hit, "Parallel/coincident surface should return null")

func test_stage11_side_determination_at_hit() -> void:
	var ray := _make_ray(Vector2(0, 50), Vector2(200, 50))
	var seg := Segment.new(Vector2(100, 100), Vector2(100, 0), Vector2(100, 50))
	var hit = Intersection.find_earliest_hit(ray, [seg])
	assert_not_null(hit, "Should find hit")
	assert_eq(hit.side, Side.Value.LEFT, "Approaching from left should record LEFT side")

func test_stage11_S9_double_exclusion() -> void:
	var ray := _make_ray(Vector2(50, 50), Vector2(200, 50))
	var seg_at_origin := _v_seg(50, 0, 100)
	var seg_excluded := _v_seg(80, 0, 100)
	var seg_remaining := _v_seg(120, 0, 100)
	var hit = Intersection.find_earliest_hit(ray, [seg_at_origin, seg_excluded, seg_remaining], [seg_excluded])
	assert_not_null(hit, "Should find remaining surface")
	assert_almost_eq(hit.point.x, 120.0, 0.1, "Both exclusion mechanisms should work together")

func test_stage11_beyond_infinity_winning() -> void:
	var ray := _make_ray(Vector2(200, 50), Vector2(300, 50))
	var seg_a := _v_seg(50, 0, 100)
	var seg_b := _v_seg(100, 0, 100)
	var hit = Intersection.find_earliest_hit(ray, [seg_a, seg_b])
	assert_not_null(hit, "Should select beyond-infinity winner")
	assert_lt(hit.t, 0.0, "Should have negative t")
	assert_almost_eq(hit.point.x, 50.0, 0.1, "Most negative t wins among beyond hits")
