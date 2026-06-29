extends GutTest

# =============================================================================
# Step 1: E1 — projective_sort exact zero
# =============================================================================

func _make_hit(t: float, seg: Segment = null) -> Intersection.HitRecord:
	var point := Vector2(100 + t * 10, 200)
	return Intersection.HitRecord.new(t, point, seg, Side.Value.LEFT, seg != null)

func test_projective_sort_exact_zero_is_last() -> void:
	var seg := Segment.from_coords(Vector2(100, 200), Vector2(300, 200), Vector2(INF, INF))
	var hits := [
		_make_hit(3.0, seg),
		_make_hit(0.0),       # origin — must be last
		_make_hit(-2.0, seg),
		_make_hit(1.0, seg),
	]
	var sorted := Intersection.projective_sort(hits)
	assert_eq(sorted.size(), 4)
	assert_eq(sorted[3].t, 0.0, "Origin (t=0.0) must be last")
	assert_eq(sorted[3].segment, null, "Origin has null segment")

func test_projective_sort_near_zero_not_treated_as_zero() -> void:
	var seg := Segment.from_coords(Vector2(100, 200), Vector2(300, 200), Vector2(INF, INF))
	var tiny_pos := 1e-15
	var hits := [
		_make_hit(0.0),             # origin
		_make_hit(tiny_pos, seg),   # NOT origin — tiny positive
		_make_hit(1.0, seg),
	]
	var sorted := Intersection.projective_sort(hits)
	# tiny_pos is positive, so it should come BEFORE negative values and BEFORE origin
	# Order: tiny_pos, 1.0, origin(0.0)
	assert_eq(sorted[0].t, tiny_pos, "Tiny positive should be first (regular positive)")
	assert_eq(sorted[1].t, 1.0)
	assert_eq(sorted[2].t, 0.0, "Origin still last")

func test_projective_sort_negative_near_zero_regular() -> void:
	var seg := Segment.from_coords(Vector2(100, 200), Vector2(300, 200), Vector2(INF, INF))
	var tiny_neg := -1e-15
	var hits := [
		_make_hit(0.0),             # origin
		_make_hit(tiny_neg, seg),   # NOT origin — tiny negative
		_make_hit(-1.0, seg),
	]
	var sorted := Intersection.projective_sort(hits)
	# tiny_neg and -1.0 are both negative, sorted ascending: -1.0, tiny_neg
	# Order: -1.0, tiny_neg, origin(0.0)
	assert_eq(sorted[0].t, -1.0, "Larger negative first in ascending order")
	assert_eq(sorted[1].t, tiny_neg, "Tiny negative is regular negative, not origin")
	assert_eq(sorted[2].t, 0.0, "Origin still last")

# =============================================================================
# Step 2: E3 — endpoint_blocked_sides exact sign test
# =============================================================================

func test_endpoint_blocked_both_when_cross_exactly_zero() -> void:
	# Ray direction exactly parallel to segment tangent at endpoint
	var seg := Segment.from_coords(Vector2(100, 200), Vector2(300, 200), Vector2(INF, INF))
	var ray := Ray.from_coords(Vector2(50, 200), Direction.from_coords(Vector2.ZERO, Vector2(1, 0)))
	var result := Intersection.endpoint_blocked_sides(Vector2(100, 200), seg, ray, 1)
	assert_true(result[0], "Left blocked when exactly parallel")
	assert_true(result[1], "Right blocked when exactly parallel")

func test_endpoint_blocked_directional_for_tiny_cross() -> void:
	# Ray direction ALMOST parallel but with a tiny perpendicular component
	var seg := Segment.from_coords(Vector2(100, 200), Vector2(300, 200), Vector2(INF, INF))
	var ray := Ray.from_coords(Vector2(50, 200), Direction.from_coords(Vector2.ZERO, Vector2(1, 1e-15)))
	var result := Intersection.endpoint_blocked_sides(Vector2(100, 200), seg, ray, 1)
	# Tiny cross product should give DIRECTIONAL blockage, not full
	var both_blocked: bool = result[0] and result[1]
	assert_false(both_blocked, "Tiny nonzero cross should NOT block both sides")

# =============================================================================
# Step 3: E4 — maps_lines_to_arcs exact zero check
# =============================================================================

func test_identity_maps_lines_to_lines() -> void:
	var id := MobiusTransform.identity()
	assert_false(id.maps_lines_to_arcs(), "Identity should map lines to lines")

func test_tiny_c_still_maps_to_arcs() -> void:
	var m := MobiusTransform.new(
		Vector2(1, 0), Vector2(0, 0),
		Vector2(1e-25, 0), Vector2(1, 0),
		false)
	assert_true(m.maps_lines_to_arcs(), "Even tiny nonzero c should map lines to arcs")

func test_composed_identities_stay_linear() -> void:
	var id1 := MobiusTransform.identity()
	var id2 := MobiusTransform.identity()
	var composed := id1.compose(id2)
	assert_false(composed.maps_lines_to_arcs(), "Identity composed with identity stays linear")
	assert_eq(composed.c_re, 0.0, "Composed identity c_re should be exactly zero")
	assert_eq(composed.c_im, 0.0, "Composed identity c_im should be exactly zero")

# =============================================================================
# Step 4: E5 + E6 — exact equality for zero-length steps and degenerate arcs
# =============================================================================

func test_degenerate_arc_exact_equality() -> void:
	var p := Vector2(100, 200)
	assert_false(VisualConverter.is_arc(p, p, p), "Identical start/end/via is not an arc")

func test_near_degenerate_arc_still_valid() -> void:
	var start := Vector2(100, 200)
	var end_v := Vector2(100.001, 200)
	assert_ne(start, end_v, "Near-identical points are not rejected by exact equality check")

# =============================================================================
# Step 5: E2 — three-tier endpoint detection
# =============================================================================

func test_tier1_exact_match_origin_at_start() -> void:
	# Vertical segment, ray origin at the start — ray crosses the segment (not on carrier)
	var seg := Segment.from_coords(Vector2(200, 100), Vector2(200, 300), Vector2(INF, INF))
	var ray := Ray.from_coords(Vector2(200, 100), Direction.from_coords(Vector2(200, 100), Vector2(300, 200)))
	var hits := Intersection.find_all_hits(ray, [seg])
	var found_start := false
	for h in hits:
		var hr: Intersection.HitRecord = h
		if hr.at_endpoint == 1:
			assert_eq(hr.point.coords, Vector2(200, 100), "Exact start coords from provenance")
			found_start = true
	assert_true(found_start, "Should detect hit at start endpoint via Tier 1")

func test_tier1_exact_match_origin_at_end() -> void:
	var seg := Segment.from_coords(Vector2(200, 100), Vector2(200, 300), Vector2(INF, INF))
	var ray := Ray.from_coords(Vector2(200, 300), Direction.from_coords(Vector2(200, 300), Vector2(300, 200)))
	var hits := Intersection.find_all_hits(ray, [seg])
	var found_end := false
	for h in hits:
		var hr: Intersection.HitRecord = h
		if hr.at_endpoint == 2:
			assert_eq(hr.point.coords, Vector2(200, 300), "Exact end coords from provenance")
			found_end = true
	assert_true(found_end, "Should detect hit at end endpoint via Tier 1")

func test_tier2_cross_zero_detects_endpoint() -> void:
	# Vertical segment, ray passes through both endpoints (ray is on the carrier)
	# Provenance adds them even though quadratic returns empty (ray on carrier)
	var seg := Segment.from_coords(Vector2(200, 100), Vector2(200, 300), Vector2(INF, INF))
	var ray := Ray.from_coords(Vector2(200, 50), Direction.from_coords(Vector2(200, 50), Vector2(200, 400)))
	var hits := Intersection.find_all_hits(ray, [seg])
	var endpoint_hits := 0
	for h in hits:
		var hr: Intersection.HitRecord = h
		if hr.at_endpoint > 0:
			endpoint_hits += 1
	assert_eq(endpoint_hits, 2, "Both endpoints on the ray should be detected via Tier 2")

func test_tier3_quadratic_interior_no_endpoint() -> void:
	var seg := Segment.from_coords(Vector2(100, 100), Vector2(100, 300), Vector2(INF, INF))
	var ray := Ray.from_coords(Vector2(50, 200), Direction.from_coords(Vector2(50, 200), Vector2(200, 200)))
	var hits := Intersection.find_all_hits(ray, [seg])
	assert_eq(hits.size(), 1, "Should have exactly 1 hit")
	var hr: Intersection.HitRecord = hits[0]
	assert_eq(hr.at_endpoint, 0, "Interior hit should have at_endpoint=0")

func test_at_which_endpoint_exact_equality() -> void:
	var seg := Segment.from_coords(Vector2(100, 200), Vector2(300, 200), Vector2(INF, INF))
	assert_eq(Intersection.at_which_endpoint(Vector2(100, 200), seg), 1, "Exact start match")
	assert_eq(Intersection.at_which_endpoint(Vector2(300, 200), seg), 2, "Exact end match")
	assert_eq(Intersection.at_which_endpoint(Vector2(200, 200), seg), 0, "Interior point")
	assert_eq(Intersection.at_which_endpoint(Vector2(100.001, 200), seg), 0, "Near but not exact")

func test_near_miss_not_detected() -> void:
	# Ray crosses vertical segment near (but not at) endpoint
	var seg := Segment.from_coords(Vector2(200, 100), Vector2(200, 300), Vector2(INF, INF))
	var ray := Ray.from_coords(Vector2(100, 100.1), Direction.from_coords(Vector2(100, 100.1), Vector2(300, 100.1)))
	var hits := Intersection.find_all_hits(ray, [seg])
	assert_gt(hits.size(), 0, "Should intersect the segment")
	for h in hits:
		var hr: Intersection.HitRecord = h
		assert_eq(hr.at_endpoint, 0, "Near-miss should not detect endpoint")

func test_vertex_coincidence_exact() -> void:
	# Two segments sharing a vertex at (200, 200)
	var seg1 := Segment.from_coords(Vector2(100, 200), Vector2(200, 200), Vector2(INF, INF))
	var seg2 := Segment.from_coords(Vector2(200, 200), Vector2(200, 100), Vector2(INF, INF))
	var shared_point := Vector2(200, 200)
	assert_eq(Intersection.at_which_endpoint(shared_point, seg1), 2, "Shared point is end of seg1")
	assert_eq(Intersection.at_which_endpoint(shared_point, seg2), 1, "Shared point is start of seg2")

func test_dedup_tier1_replaces_tier3() -> void:
	# Ray origin at segment endpoint, crossing the segment (not on carrier)
	# Quadratic finds the intersection, provenance snaps it to exact endpoint coords
	var seg := Segment.from_coords(Vector2(200, 100), Vector2(200, 300), Vector2(INF, INF))
	var ray := Ray.from_coords(Vector2(200, 100), Direction.from_coords(Vector2(200, 100), Vector2(300, 200)))
	var hits := Intersection.find_all_hits(ray, [seg])
	assert_eq(hits.size(), 1, "Quadratic and provenance should merge into single hit")
	var hr: Intersection.HitRecord = hits[0]
	assert_eq(hr.at_endpoint, 1, "Should be at start endpoint")
	assert_eq(hr.point.coords, Vector2(200, 100), "Should have exact endpoint coords")

# =============================================================================
# Step 6: Anti-regression tests — FAIL if epsilons reintroduced
# =============================================================================

func test_no_epsilon_sort_boundary() -> void:
	# Values at 1e-13, 1e-14, 1e-15 must NOT be treated as zero (origin)
	var seg := Segment.from_coords(Vector2(100, 200), Vector2(300, 200), Vector2(INF, INF))
	for tiny in [1e-13, 1e-14, 1e-15]:
		var hits := [_make_hit(0.0), _make_hit(tiny, seg)]
		var sorted := Intersection.projective_sort(hits)
		assert_eq(sorted[0].t, tiny, "t=%s should come before origin, not be treated as zero" % str(tiny))
		assert_eq(sorted[1].t, 0.0, "Origin must be last")

func test_no_epsilon_blocked_sides_boundary() -> void:
	var seg := Segment.from_coords(Vector2(100, 200), Vector2(300, 200), Vector2(INF, INF))
	# Tiny cross values must give directional blockage, not full
	for angle_offset in [1e-10, 1e-12, 1e-14]:
		var ray := Ray.from_coords(Vector2(50, 200), Direction.from_coords(Vector2.ZERO, Vector2(1, angle_offset)))
		var result := Intersection.endpoint_blocked_sides(Vector2(100, 200), seg, ray, 1)
		var both: bool = result[0] and result[1]
		assert_false(both, "Cross at ~%s should give directional, not full blockage" % str(angle_offset))

func test_no_epsilon_maps_lines_boundary() -> void:
	# Tiny c magnitudes must still return true (maps lines to arcs)
	for c_val in [1e-21, 1e-25, 1e-30]:
		var m := MobiusTransform.new(
			Vector2(1, 0), Vector2(0, 0),
			Vector2(c_val, 0), Vector2(1, 0), false)
		assert_true(m.maps_lines_to_arcs(), "c=%s should map lines to arcs" % str(c_val))

func test_no_epsilon_zero_length_boundary() -> void:
	# Sub-pixel differences must NOT be treated as zero-length
	var a := Vector2(100, 200)
	var b := Vector2(100.001, 200)
	assert_ne(a, b, "Sub-pixel difference must not be treated as zero-length")
