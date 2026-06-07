extends GutTest

# --- Stage A: Intersection tests ---

func test_on_segment_hit() -> void:
	# Vertical wall at x=400, y=[0,600]. Ray from left going right.
	var seg := Segment.new(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg])
	assert_not_null(hit, "Should find on-segment hit")
	assert_almost_eq(hit.point.x, 400.0, 0.01, "Hit at x=400")
	assert_true(hit.on_segment, "Should be on_segment")
	assert_gt(hit.t, 0.0, "Forward hit")

func test_off_segment_carrier_hit() -> void:
	# Short segment at x=400, y=[100,200]. Ray at y=300 — carrier crosses but segment doesn't.
	var seg := Segment.new(Vector2(400, 100), Vector2(400, 200), Vector2(400, 150))
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg])
	assert_not_null(hit, "Should find carrier hit even off-segment")
	assert_almost_eq(hit.point.x, 400.0, 0.01, "Hit at carrier x=400")
	assert_false(hit.on_segment, "Should be off-segment")

func test_nearest_wins() -> void:
	# Two segments: A at x=300, B at x=500. A is closer.
	var seg_a := Segment.new(Vector2(300, 0), Vector2(300, 600), Vector2(300, 300))
	var seg_b := Segment.new(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var ray := Ray.new(Vector2(100, 300), Direction.new(Vector2(100, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg_a, seg_b])
	assert_not_null(hit, "Should find hit")
	assert_almost_eq(hit.point.x, 300.0, 0.01, "Nearest segment at x=300 wins")

func test_off_segment_nearer_than_on_segment() -> void:
	# Off-segment carrier at x=300, on-segment wall at x=500.
	var carrier_seg := Segment.new(Vector2(300, 100), Vector2(300, 200), Vector2(300, 150))
	var wall_seg := Segment.new(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var ray := Ray.new(Vector2(100, 300), Direction.new(Vector2(100, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [carrier_seg, wall_seg])
	assert_not_null(hit, "Should find hit")
	assert_almost_eq(hit.point.x, 300.0, 0.01, "Off-segment carrier at x=300 is nearer")
	assert_false(hit.on_segment, "Nearer hit is off-segment")

func test_excluded_segments() -> void:
	var seg_a := Segment.new(Vector2(300, 0), Vector2(300, 600), Vector2(300, 300))
	var seg_b := Segment.new(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var ray := Ray.new(Vector2(100, 300), Direction.new(Vector2(100, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg_a, seg_b], [seg_a])
	assert_not_null(hit, "Should find non-excluded hit")
	assert_almost_eq(hit.point.x, 500.0, 0.01, "Excluded A, hit B at x=500")

func test_origin_skip() -> void:
	# Segment passes through ray origin — hit at origin should be skipped.
	var seg := Segment.new(Vector2(200, 0), Vector2(200, 600), Vector2(200, 300))
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg])
	assert_null(hit, "Hit at ray origin should be skipped")

func test_parallel_no_hit() -> void:
	# Horizontal segment, horizontal ray at different y — parallel, no intersection.
	var seg := Segment.new(Vector2(100, 100), Vector2(500, 100), Vector2(300, 100))
	var ray := Ray.new(Vector2(100, 300), Direction.new(Vector2(100, 300), Vector2(500, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg])
	assert_null(hit, "Parallel carrier has no intersection")

func test_side_determination() -> void:
	# Vertical segment at x=400. Ray from left → approaching from LEFT side.
	var seg := Segment.new(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg])
	assert_not_null(hit, "Should find hit")
	assert_true(hit.side == Side.Value.LEFT or hit.side == Side.Value.RIGHT, "Side should be valid")

func test_no_segments_returns_null() -> void:
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [])
	assert_null(hit, "No segments → null")

func test_beyond_hit_used_as_fallback() -> void:
	# Segment behind the ray (t < 0). Should be returned as beyond fallback.
	var seg := Segment.new(Vector2(100, 0), Vector2(100, 600), Vector2(100, 300))
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg])
	assert_not_null(hit, "Beyond hit should be returned as fallback")
	assert_lt(hit.t, 0.0, "Beyond hit has t < 0")

func test_forward_preferred_over_beyond() -> void:
	# One segment ahead (t > 0), one behind (t < 0). Forward wins.
	var seg_behind := Segment.new(Vector2(100, 0), Vector2(100, 600), Vector2(100, 300))
	var seg_ahead := Segment.new(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var ray := Ray.new(Vector2(300, 300), Direction.new(Vector2(300, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg_behind, seg_ahead])
	assert_not_null(hit, "Should find hit")
	assert_gt(hit.t, 0.0, "Forward hit preferred")
	assert_almost_eq(hit.point.x, 500.0, 0.01, "Forward segment at x=500")

func test_is_on_segment_finite_line() -> void:
	var seg := Segment.new(Vector2(0, 0), Vector2(10, 0), Vector2(5, 0))
	assert_true(Intersection.is_on_segment(Vector2(5, 0), seg), "Midpoint on segment")
	assert_true(Intersection.is_on_segment(Vector2(0, 0), seg), "Start on segment")
	assert_true(Intersection.is_on_segment(Vector2(10, 0), seg), "End on segment")
	assert_false(Intersection.is_on_segment(Vector2(-5, 0), seg), "Before start off segment")
	assert_false(Intersection.is_on_segment(Vector2(15, 0), seg), "After end off segment")

func test_is_on_segment_inf() -> void:
	# INF via = line extending to infinity in both directions beyond the segment
	var seg := Segment.new(Vector2(0, 0), Vector2(10, 0), Vector2(INF, INF))
	assert_true(Intersection.is_on_segment(Vector2(15, 0), seg), "Beyond end on INF segment")
	assert_true(Intersection.is_on_segment(Vector2(-5, 0), seg), "Before start on INF segment")
	assert_false(Intersection.is_on_segment(Vector2(5, 0), seg), "Finite portion excluded for INF via")

# --- Side determination (analytical, no epsilon) ---

func test_side_opposite_from_each_direction() -> void:
	var seg := Segment.new(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var ray_from_left := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(600, 300)))
	var ray_from_right := Ray.new(Vector2(600, 300), Direction.new(Vector2(600, 300), Vector2(200, 300)))
	var hit_left := Intersection.find_nearest_hit(ray_from_left, [seg])
	var hit_right := Intersection.find_nearest_hit(ray_from_right, [seg])
	assert_not_null(hit_left, "Should hit from left")
	assert_not_null(hit_right, "Should hit from right")
	assert_ne(hit_left.side, hit_right.side, "Opposite directions must give opposite sides")

func test_side_near_tangent() -> void:
	# Ray nearly parallel to segment — side should still be deterministic
	var seg := Segment.new(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var ray := Ray.new(Vector2(399, 0), Direction.new(Vector2(399, 0), Vector2(401, 600)))
	var hit := Intersection.find_nearest_hit(ray, [seg])
	assert_not_null(hit, "Should hit even near-tangent")
	assert_true(hit.side == Side.Value.LEFT or hit.side == Side.Value.RIGHT, "Side should be deterministic")

func test_side_consistent_with_determine_side() -> void:
	# Analytical side should match determine_side with a large offset
	var seg := Segment.new(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg])
	var dir := ray.direction.to_vector().normalized()
	var far_approach := hit.point - dir * 100.0
	var expected := seg.determine_side(far_approach)
	assert_eq(hit.side, expected, "Analytical side should match determine_side with large offset")
