extends GutTest

func test_on_segment_hit_matches_find_earliest() -> void:
	var seg := Segment.new(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(600, 300)))
	var segments: Array = [seg]

	var standard := Intersection.find_earliest_hit(ray, segments)
	var carrier := Intersection.find_earliest_carrier_hit(ray, segments)

	assert_not_null(standard, "Standard should find on-segment hit")
	assert_not_null(carrier, "Carrier should also find it")
	assert_eq(carrier.point, standard.point, "Same hit point")
	assert_almost_eq(carrier.t, standard.t, 0.001, "Same t value")
	assert_true(carrier.on_segment, "Should be on_segment")

func test_off_segment_carrier_found() -> void:
	# Segment from (400, 100) to (400, 200) — short vertical segment
	# Ray at y=300 going right — carrier line x=400 crosses ray, but NOT on segment
	var seg := Segment.new(Vector2(400, 100), Vector2(400, 200), Vector2(400, 150))
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(600, 300)))
	var segments: Array = [seg]

	var standard := Intersection.find_earliest_hit(ray, segments)
	var carrier := Intersection.find_earliest_carrier_hit(ray, segments)

	assert_null(standard, "Standard should NOT find hit (off-segment)")
	assert_not_null(carrier, "Carrier should find carrier intersection")
	assert_false(carrier.on_segment, "Should be off-segment")
	assert_almost_eq(carrier.point.x, 400.0, 0.01, "Hit at carrier line x=400")

func test_on_segment_closer_than_off_segment() -> void:
	# Wall (on-segment) at x=300, mirror carrier (off-segment) at x=500
	var wall := Segment.new(Vector2(300, 0), Vector2(300, 600), Vector2(300, 300))
	var mirror := Segment.new(Vector2(500, 100), Vector2(500, 200), Vector2(500, 150))
	var ray := Ray.new(Vector2(100, 300), Direction.new(Vector2(100, 300), Vector2(600, 300)))
	var segments: Array = [wall, mirror]

	var carrier := Intersection.find_earliest_carrier_hit(ray, segments)

	assert_not_null(carrier, "Should find hit")
	assert_almost_eq(carrier.point.x, 300.0, 0.01, "Wall at x=300 is closer")
	assert_true(carrier.on_segment, "Wall hit is on-segment")

func test_off_segment_closer_than_on_segment() -> void:
	# Mirror carrier (off-segment) at x=300, wall (on-segment) at x=500
	var mirror := Segment.new(Vector2(300, 100), Vector2(300, 200), Vector2(300, 150))
	var wall := Segment.new(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var ray := Ray.new(Vector2(100, 300), Direction.new(Vector2(100, 300), Vector2(600, 300)))
	var segments: Array = [mirror, wall]

	var carrier := Intersection.find_earliest_carrier_hit(ray, segments)

	assert_not_null(carrier, "Should find hit")
	assert_almost_eq(carrier.point.x, 300.0, 0.01, "Mirror carrier at x=300 is closer")
	assert_false(carrier.on_segment, "Mirror hit is off-segment")

func test_excluded_segments_respected() -> void:
	var seg_a := Segment.new(Vector2(300, 0), Vector2(300, 600), Vector2(300, 300))
	var seg_b := Segment.new(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var ray := Ray.new(Vector2(100, 300), Direction.new(Vector2(100, 300), Vector2(600, 300)))

	var carrier := Intersection.find_earliest_carrier_hit(ray, [seg_a, seg_b], [seg_a])

	assert_not_null(carrier, "Should find hit on non-excluded segment")
	assert_almost_eq(carrier.point.x, 500.0, 0.01, "Hit on seg_b")

func test_origin_exclusion() -> void:
	# Segment passes through ray origin
	var seg := Segment.new(Vector2(200, 0), Vector2(200, 600), Vector2(200, 300))
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(600, 300)))

	var carrier := Intersection.find_earliest_carrier_hit(ray, [seg])

	assert_null(carrier, "Hit at origin should be excluded")

func test_no_intersection_parallel() -> void:
	# Horizontal segment, horizontal ray at different y — parallel, no intersection
	var seg := Segment.new(Vector2(100, 100), Vector2(500, 100), Vector2(300, 100))
	var ray := Ray.new(Vector2(100, 300), Direction.new(Vector2(100, 300), Vector2(500, 300)))

	var carrier := Intersection.find_earliest_carrier_hit(ray, [seg])

	assert_null(carrier, "Parallel carrier should have no intersection")

func test_side_determination_off_segment() -> void:
	# Off-segment carrier hit should still compute a valid side
	var seg := Segment.new(Vector2(400, 100), Vector2(400, 200), Vector2(400, 150))
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(600, 300)))

	var carrier := Intersection.find_earliest_carrier_hit(ray, [seg])

	assert_not_null(carrier, "Should find carrier hit")
	assert_true(
		carrier.side == Side.Value.LEFT or carrier.side == Side.Value.RIGHT,
		"Side should be LEFT or RIGHT")

func test_carrier_superset_invariant() -> void:
	# Every on-segment hit from find_earliest_hit is also found by carrier at same t
	var segs: Array = [
		Segment.new(Vector2(300, 0), Vector2(300, 600), Vector2(300, 300)),
		Segment.new(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300)),
	]
	var ray := Ray.new(Vector2(100, 300), Direction.new(Vector2(100, 300), Vector2(600, 300)))

	var standard := Intersection.find_earliest_hit(ray, segs)
	var carrier := Intersection.find_earliest_carrier_hit(ray, segs)

	assert_not_null(standard, "Standard should find hit")
	assert_not_null(carrier, "Carrier should find hit")
	# Carrier result should be at the same or earlier t
	assert_true(carrier.t <= standard.t + 0.001,
		"Carrier hit t=%f should be <= standard t=%f" % [carrier.t, standard.t])
