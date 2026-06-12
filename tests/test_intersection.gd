extends GutTest

# --- Stage A: Intersection tests ---

func test_on_segment_hit() -> void:
	# Vertical wall at x=400, y=[0,600]. Ray from left going right.
	var seg := Segment.from_coords(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var ray := Ray.from_coords(Vector2(200, 300), Direction.from_coords(Vector2(200, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg])
	assert_not_null(hit, "Should find on-segment hit")
	assert_almost_eq(hit.point.coords.x, 400.0, 0.01, "Hit at x=400")
	assert_true(hit.on_segment, "Should be on_segment")
	assert_gt(hit.t, 0.0, "Forward hit")

func test_off_segment_carrier_hit() -> void:
	# Short segment at x=400, y=[100,200]. Ray at y=300 — carrier crosses but segment doesn't.
	var seg := Segment.from_coords(Vector2(400, 100), Vector2(400, 200), Vector2(400, 150))
	var ray := Ray.from_coords(Vector2(200, 300), Direction.from_coords(Vector2(200, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg])
	assert_not_null(hit, "Should find carrier hit even off-segment")
	assert_almost_eq(hit.point.coords.x, 400.0, 0.01, "Hit at carrier x=400")
	assert_false(hit.on_segment, "Should be off-segment")

func test_nearest_wins() -> void:
	# Two segments: A at x=300, B at x=500. A is closer.
	var seg_a := Segment.from_coords(Vector2(300, 0), Vector2(300, 600), Vector2(300, 300))
	var seg_b := Segment.from_coords(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var ray := Ray.from_coords(Vector2(100, 300), Direction.from_coords(Vector2(100, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg_a, seg_b])
	assert_not_null(hit, "Should find hit")
	assert_almost_eq(hit.point.coords.x, 300.0, 0.01, "Nearest segment at x=300 wins")

func test_off_segment_nearer_than_on_segment() -> void:
	# Off-segment carrier at x=300, on-segment wall at x=500.
	var carrier_seg := Segment.from_coords(Vector2(300, 100), Vector2(300, 200), Vector2(300, 150))
	var wall_seg := Segment.from_coords(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var ray := Ray.from_coords(Vector2(100, 300), Direction.from_coords(Vector2(100, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [carrier_seg, wall_seg])
	assert_not_null(hit, "Should find hit")
	assert_almost_eq(hit.point.coords.x, 300.0, 0.01, "Off-segment carrier at x=300 is nearer")
	assert_false(hit.on_segment, "Nearer hit is off-segment")

func test_skip_segment() -> void:
	var seg_a := Segment.from_coords(Vector2(300, 0), Vector2(300, 600), Vector2(300, 300))
	var seg_b := Segment.from_coords(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var ray := Ray.from_coords(Vector2(100, 300), Direction.from_coords(Vector2(100, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg_a, seg_b], Vector2(NAN, NAN), seg_a)
	assert_not_null(hit, "Should find non-skipped hit")
	assert_almost_eq(hit.point.coords.x, 500.0, 0.01, "Skipped A, hit B at x=500")

func test_origin_hit_returned_as_beyond() -> void:
	var seg := Segment.from_coords(Vector2(200, 0), Vector2(200, 600), Vector2(200, 300))
	var ray := Ray.from_coords(Vector2(200, 300), Direction.from_coords(Vector2(200, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg])
	assert_not_null(hit, "Hit at ray origin should be returned (t=0 in beyond set)")
	assert_almost_eq(hit.t, 0.0, 1e-6, "Hit at origin has t=0")

func test_parallel_no_hit() -> void:
	# Horizontal segment, horizontal ray at different y — parallel, no intersection.
	var seg := Segment.from_coords(Vector2(100, 100), Vector2(500, 100), Vector2(300, 100))
	var ray := Ray.from_coords(Vector2(100, 300), Direction.from_coords(Vector2(100, 300), Vector2(500, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg])
	assert_null(hit, "Parallel carrier has no intersection")

func test_side_determination() -> void:
	# Vertical segment at x=400. Ray from left → approaching from LEFT side.
	var seg := Segment.from_coords(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var ray := Ray.from_coords(Vector2(200, 300), Direction.from_coords(Vector2(200, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg])
	assert_not_null(hit, "Should find hit")
	assert_true(hit.side == Side.Value.LEFT or hit.side == Side.Value.RIGHT, "Side should be valid")

func test_no_segments_returns_null() -> void:
	var ray := Ray.from_coords(Vector2(200, 300), Direction.from_coords(Vector2(200, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [])
	assert_null(hit, "No segments → null")

func test_beyond_hit_used_as_fallback() -> void:
	# Segment behind the ray (t < 0). Should be returned as beyond fallback.
	var seg := Segment.from_coords(Vector2(100, 0), Vector2(100, 600), Vector2(100, 300))
	var ray := Ray.from_coords(Vector2(200, 300), Direction.from_coords(Vector2(200, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg])
	assert_not_null(hit, "Beyond hit should be returned as fallback")
	assert_lt(hit.t, 0.0, "Beyond hit has t < 0")

func test_forward_preferred_over_beyond() -> void:
	# One segment ahead (t > 0), one behind (t < 0). Forward wins.
	var seg_behind := Segment.from_coords(Vector2(100, 0), Vector2(100, 600), Vector2(100, 300))
	var seg_ahead := Segment.from_coords(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var ray := Ray.from_coords(Vector2(300, 300), Direction.from_coords(Vector2(300, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg_behind, seg_ahead])
	assert_not_null(hit, "Should find hit")
	assert_gt(hit.t, 0.0, "Forward hit preferred")
	assert_almost_eq(hit.point.coords.x, 500.0, 0.01, "Forward segment at x=500")

func test_is_on_segment_finite_line() -> void:
	var seg := Segment.from_coords(Vector2(0, 0), Vector2(10, 0), Vector2(5, 0))
	assert_true(Intersection.is_on_segment(Vector2(5, 0), seg), "Midpoint on segment")
	assert_true(Intersection.is_on_segment(Vector2(0, 0), seg), "Start on segment")
	assert_true(Intersection.is_on_segment(Vector2(10, 0), seg), "End on segment")
	assert_false(Intersection.is_on_segment(Vector2(-5, 0), seg), "Before start off segment")
	assert_false(Intersection.is_on_segment(Vector2(15, 0), seg), "After end off segment")

func test_is_on_segment_inf() -> void:
	# INF via = line extending to infinity in both directions beyond the segment
	var seg := Segment.from_coords(Vector2(0, 0), Vector2(10, 0), Vector2(INF, INF))
	assert_true(Intersection.is_on_segment(Vector2(15, 0), seg), "Beyond end on INF segment")
	assert_true(Intersection.is_on_segment(Vector2(-5, 0), seg), "Before start on INF segment")
	assert_false(Intersection.is_on_segment(Vector2(5, 0), seg), "Finite portion excluded for INF via")

# --- Side determination (analytical, no epsilon) ---

func test_side_opposite_from_each_direction() -> void:
	var seg := Segment.from_coords(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var ray_from_left := Ray.from_coords(Vector2(200, 300), Direction.from_coords(Vector2(200, 300), Vector2(600, 300)))
	var ray_from_right := Ray.from_coords(Vector2(600, 300), Direction.from_coords(Vector2(600, 300), Vector2(200, 300)))
	var hit_left := Intersection.find_nearest_hit(ray_from_left, [seg])
	var hit_right := Intersection.find_nearest_hit(ray_from_right, [seg])
	assert_not_null(hit_left, "Should hit from left")
	assert_not_null(hit_right, "Should hit from right")
	assert_ne(hit_left.side, hit_right.side, "Opposite directions must give opposite sides")

func test_side_near_tangent() -> void:
	# Ray nearly parallel to segment — side should still be deterministic
	var seg := Segment.from_coords(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var ray := Ray.from_coords(Vector2(399, 0), Direction.from_coords(Vector2(399, 0), Vector2(401, 600)))
	var hit := Intersection.find_nearest_hit(ray, [seg])
	assert_not_null(hit, "Should hit even near-tangent")
	assert_true(hit.side == Side.Value.LEFT or hit.side == Side.Value.RIGHT, "Side should be deterministic")

func test_side_consistent_with_determine_side() -> void:
	# Analytical side should match determine_side with a large offset
	var seg := Segment.from_coords(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var ray := Ray.from_coords(Vector2(200, 300), Direction.from_coords(Vector2(200, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg])
	var dir := ray.direction.to_vector().normalized()
	var far_approach := hit.point.coords - dir * 100.0
	var expected := seg.determine_side(far_approach)
	assert_eq(hit.side, expected, "Analytical side should match determine_side with large offset")

# --- project_point_on_ray ---

func test_project_direction_end_initial() -> void:
	var player := Vector2(200, 300)
	var cursor := Vector2(500, 400)
	var dir := Direction.from_coords(player, cursor)
	var ray := Ray.from_coords(player, dir)
	var t := Intersection.project_point_on_ray(ray, dir.end.coords)
	assert_almost_eq(t, 1.0, 0.0001, "direction.end at t=1.0 on initial ray")

func test_project_origin() -> void:
	var player := Vector2(200, 300)
	var dir := Direction.from_coords(player, Vector2(500, 400))
	var ray := Ray.from_coords(player, dir)
	var t := Intersection.project_point_on_ray(ray, player)
	assert_almost_eq(t, 0.0, 0.0001, "origin at t=0.0")

func test_project_direction_end_after_advance() -> void:
	var player := Vector2(200, 300)
	var cursor := Vector2(500, 400)
	var dir := Direction.from_coords(player, cursor)
	# Advance ray to a point along the direction
	var advanced := player + 0.3 * dir.to_vector()
	var ray := Ray.from_coords(advanced, dir)
	var t := Intersection.project_point_on_ray(ray, dir.end.coords)
	assert_almost_eq(t, 0.7, 0.0001, "direction.end at t=0.7 after advancing 30%")
	assert_gt(t, 0.0, "direction.end should be ahead after partial advance")

# --- find_all_hits ---

func test_find_all_hits_single_segment() -> void:
	var seg := Segment.from_coords(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var ray := Ray.from_coords(Vector2(200, 300), Direction.from_coords(Vector2(200, 300), Vector2(600, 300)))
	var hits := Intersection.find_all_hits(ray, [seg])
	assert_eq(hits.size(), 1, "Line carrier gives 1 intersection")
	assert_gt(hits[0].t, 0.0, "Forward hit")

func test_find_all_hits_two_segments() -> void:
	var seg_a := Segment.from_coords(Vector2(300, 0), Vector2(300, 600), Vector2(300, 300))
	var seg_b := Segment.from_coords(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var ray := Ray.from_coords(Vector2(100, 300), Direction.from_coords(Vector2(100, 300), Vector2(600, 300)))
	var hits := Intersection.find_all_hits(ray, [seg_a, seg_b])
	assert_eq(hits.size(), 2, "Two segments give 2 hits")

func test_find_all_hits_skip_segment() -> void:
	var seg_a := Segment.from_coords(Vector2(300, 0), Vector2(300, 600), Vector2(300, 300))
	var seg_b := Segment.from_coords(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var ray := Ray.from_coords(Vector2(100, 300), Direction.from_coords(Vector2(100, 300), Vector2(600, 300)))
	var hits := Intersection.find_all_hits(ray, [seg_a, seg_b], seg_a)
	assert_eq(hits.size(), 1, "Skipped segment excluded")
	assert_almost_eq(hits[0].point.coords.x, 500.0, 0.01, "Only seg_b hit")

func test_find_all_hits_parallel() -> void:
	var seg := Segment.from_coords(Vector2(100, 100), Vector2(500, 100), Vector2(300, 100))
	var ray := Ray.from_coords(Vector2(100, 300), Direction.from_coords(Vector2(100, 300), Vector2(500, 300)))
	var hits := Intersection.find_all_hits(ray, [seg])
	assert_eq(hits.size(), 0, "Parallel carrier gives 0 hits")

func test_find_all_hits_origin_included() -> void:
	var seg := Segment.from_coords(Vector2(200, 0), Vector2(200, 600), Vector2(200, 300))
	var ray := Ray.from_coords(Vector2(200, 300), Direction.from_coords(Vector2(200, 300), Vector2(600, 300)))
	var hits := Intersection.find_all_hits(ray, [seg])
	assert_eq(hits.size(), 1, "Origin hit included")
	assert_almost_eq(hits[0].t, 0.0, 1e-6, "Hit at origin has t=0")

# --- projective_sort ---

func _make_hit(t: float, seg: Segment = null) -> Intersection.HitRecord:
	return Intersection.HitRecord.new(t, Vector2.ZERO, seg, Side.Value.LEFT, false)

func test_projective_sort_mixed() -> void:
	var hits := [_make_hit(3.0), _make_hit(-2.0), _make_hit(1.0), _make_hit(-5.0)]
	var sorted := Intersection.projective_sort(hits)
	assert_eq(sorted[0].t, 1.0, "Positive ascending first")
	assert_eq(sorted[1].t, 3.0, "Positive ascending")
	assert_eq(sorted[2].t, -5.0, "Negative ascending")
	assert_eq(sorted[3].t, -2.0, "Negative ascending")

func test_projective_sort_zero_last() -> void:
	var hits := [_make_hit(3.0), _make_hit(0.0), _make_hit(-2.0)]
	var sorted := Intersection.projective_sort(hits)
	assert_eq(sorted[0].t, 3.0, "Positive first")
	assert_eq(sorted[1].t, -2.0, "Negative second")
	assert_eq(sorted[2].t, 0.0, "Zero last")

func test_projective_sort_only_zero() -> void:
	var hits := [_make_hit(0.0)]
	var sorted := Intersection.projective_sort(hits)
	assert_eq(sorted.size(), 1)
	assert_eq(sorted[0].t, 0.0)

func test_projective_sort_empty() -> void:
	var sorted := Intersection.projective_sort([])
	assert_eq(sorted.size(), 0)

# --- build_stage_hitpoints ---

func test_build_stage_hitpoints_basic() -> void:
	var seg := Segment.from_coords(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var ray := Ray.from_coords(Vector2(200, 300), Direction.from_coords(Vector2(200, 300), Vector2(600, 300)))
	var hits := Intersection.build_stage_hitpoints(ray, [seg])
	assert_gt(hits.size(), 1, "Should have carrier hit + origin")
	var last: Intersection.HitRecord = hits[hits.size() - 1]
	assert_null(last.segment, "Origin hitpoint has null segment")
	assert_almost_eq(last.t, 0.0, 1e-6, "Origin at t=0")

func test_build_stage_hitpoints_origin_always_last() -> void:
	var seg_a := Segment.from_coords(Vector2(300, 0), Vector2(300, 600), Vector2(300, 300))
	var seg_b := Segment.from_coords(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var ray := Ray.from_coords(Vector2(100, 300), Direction.from_coords(Vector2(100, 300), Vector2(600, 300)))
	var hits := Intersection.build_stage_hitpoints(ray, [seg_a, seg_b])
	var last: Intersection.HitRecord = hits[hits.size() - 1]
	assert_null(last.segment, "Origin is last")
	assert_almost_eq(last.t, 0.0, 1e-6)

func test_build_stage_hitpoints_skip_segment() -> void:
	var seg_a := Segment.from_coords(Vector2(300, 0), Vector2(300, 600), Vector2(300, 300))
	var seg_b := Segment.from_coords(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var ray := Ray.from_coords(Vector2(100, 300), Direction.from_coords(Vector2(100, 300), Vector2(600, 300)))
	var hits := Intersection.build_stage_hitpoints(ray, [seg_a, seg_b], seg_a)
	assert_eq(hits.size(), 2, "1 carrier hit + 1 origin")
	assert_almost_eq(hits[0].point.coords.x, 500.0, 0.01, "Only seg_b")
	assert_null(hits[1].segment, "Origin last")

func test_build_stage_hitpoints_projective_order() -> void:
	var seg_behind := Segment.from_coords(Vector2(50, 0), Vector2(50, 600), Vector2(50, 300))
	var seg_ahead := Segment.from_coords(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var ray := Ray.from_coords(Vector2(200, 300), Direction.from_coords(Vector2(200, 300), Vector2(600, 300)))
	var hits := Intersection.build_stage_hitpoints(ray, [seg_behind, seg_ahead])
	assert_eq(hits.size(), 3, "2 carrier hits + origin")
	assert_gt(hits[0].t, 0.0, "Forward hit first")
	assert_lt(hits[1].t, 0.0, "Behind hit second")
	assert_almost_eq(hits[2].t, 0.0, 1e-6, "Origin last")
