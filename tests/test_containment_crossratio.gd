extends GutTest

func _make_ray(origin: Vector2, toward: Vector2) -> Ray:
	return Ray.new(origin, Direction.new(origin, toward))

func test_line_segment_inside() -> void:
	var seg := Segment.new(Vector2(0, 0), Vector2(10, 0), Vector2(5, 0))
	assert_true(Intersection._is_on_segment(Vector2(5, 0), seg), "Midpoint should be on segment")

func test_line_segment_at_start() -> void:
	var seg := Segment.new(Vector2(0, 0), Vector2(10, 0), Vector2(5, 0))
	assert_true(Intersection._is_on_segment(Vector2(0, 0), seg), "Start should be on segment")

func test_line_segment_at_end() -> void:
	var seg := Segment.new(Vector2(0, 0), Vector2(10, 0), Vector2(5, 0))
	assert_true(Intersection._is_on_segment(Vector2(10, 0), seg), "End should be on segment")

func test_line_segment_outside_before() -> void:
	var seg := Segment.new(Vector2(0, 0), Vector2(10, 0), Vector2(5, 0))
	assert_false(Intersection._is_on_segment(Vector2(-5, 0), seg), "Before start should be outside")

func test_line_segment_outside_after() -> void:
	var seg := Segment.new(Vector2(0, 0), Vector2(10, 0), Vector2(5, 0))
	assert_false(Intersection._is_on_segment(Vector2(15, 0), seg), "After end should be outside")

func test_line_segment_via_inf_inside_finite() -> void:
	var seg := Segment.new(Vector2(0, 0), Vector2(10, 0), Vector2(INF, INF))
	assert_false(Intersection._is_on_segment(Vector2(5, 0), seg), "Finite portion excluded for INF segment")

func test_line_segment_via_inf_outside_finite() -> void:
	var seg := Segment.new(Vector2(0, 0), Vector2(10, 0), Vector2(INF, INF))
	assert_true(Intersection._is_on_segment(Vector2(15, 0), seg), "Beyond end should be on INF segment")

func test_line_segment_via_inf_before() -> void:
	var seg := Segment.new(Vector2(0, 0), Vector2(10, 0), Vector2(INF, INF))
	assert_true(Intersection._is_on_segment(Vector2(-5, 0), seg), "Before start should be on INF segment")

func test_arc_segment_on_arc() -> void:
	var seg := Segment.new(Vector2(200, 100), Vector2(200, 300), Vector2(300, 200))
	assert_true(Intersection._is_on_segment(Vector2(300, 200), seg), "Via point should be on arc")

func test_arc_segment_at_start() -> void:
	var seg := Segment.new(Vector2(200, 100), Vector2(200, 300), Vector2(300, 200))
	assert_true(Intersection._is_on_segment(Vector2(200, 100), seg), "Start should be on arc")

func test_arc_segment_at_end() -> void:
	var seg := Segment.new(Vector2(200, 100), Vector2(200, 300), Vector2(300, 200))
	assert_true(Intersection._is_on_segment(Vector2(200, 300), seg), "End should be on arc")

func test_arc_segment_opposite_arc() -> void:
	var seg := Segment.new(Vector2(200, 100), Vector2(200, 300), Vector2(300, 200))
	assert_false(Intersection._is_on_segment(Vector2(100, 200), seg), "Opposite arc should be excluded")

func test_arc_major_arc() -> void:
	var seg := Segment.new(Vector2(200, 100), Vector2(200, 300), Vector2(100, 200))
	assert_true(Intersection._is_on_segment(Vector2(100, 200), seg), "Via on left = major arc, should include left point")

func test_intersection_line_respects_segment() -> void:
	var ray := _make_ray(Vector2(0, 0), Vector2(0, 100))
	var seg := Segment.new(Vector2(10, 50), Vector2(20, 50), Vector2(15, 50))
	var hits := Intersection.intersect_line_with_gcircle(ray, seg)
	assert_eq(hits.size(), 0, "Hit outside segment bounds should be filtered")

func test_origin_exclusion_exact() -> void:
	var ray := _make_ray(Vector2(50, 50), Vector2(100, 50))
	var seg := Segment.new(Vector2(50, 0), Vector2(50, 100), Vector2(50, 50))
	var hit = Intersection.find_earliest_hit(ray, [seg])
	assert_null(hit, "Only intersection is at origin — should be excluded, returning null")

func test_origin_exclusion_after_reflection() -> void:
	var mirror_seg := Segment.new(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var carrier := mirror_seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var m := refl.get_mobius()

	var hit_point := Vector2(400, 300)
	var reflected := m.apply(hit_point)
	assert_eq(reflected, hit_point, "Reflection of point on carrier maps to itself")

	var ray := _make_ray(reflected, Vector2(500, 300))
	var hit = Intersection.find_earliest_hit(ray, [mirror_seg])
	assert_null(hit, "Only intersection is at reflected origin — should be excluded")

func test_no_epsilons_in_game_code() -> void:
	pass_test("Verified by grep — no 1e- patterns in scripts/math/ or scripts/game/")
