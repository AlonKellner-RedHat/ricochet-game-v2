extends GutTest

func test_stage4_direction_construction() -> void:
	var d := Direction.new(Vector2(0, 0), Vector2(1, 0))
	assert_eq(d.start, Vector2(0, 0), "Start should match")
	assert_eq(d.end, Vector2(1, 0), "End should match")

func test_stage4_direction_immutability() -> void:
	var d := Direction.new(Vector2(0, 0), Vector2(1, 0))
	assert_true(d is RefCounted, "Direction should extend RefCounted")

func test_stage4_direction_zero_length() -> void:
	var d := Direction.new(Vector2(5, 5), Vector2(5, 5))
	assert_true(d.is_zero_length(), "Same start and end should be zero length")

func test_stage4_direction_nonzero() -> void:
	var d := Direction.new(Vector2(0, 0), Vector2(1, 0))
	assert_false(d.is_zero_length(), "Different start and end should not be zero length")

func test_stage4_direction_to_vector() -> void:
	var d := Direction.new(Vector2(3, 4), Vector2(6, 8))
	assert_eq(d.to_vector(), Vector2(3, 4), "to_vector should return end - start")

func test_stage4_direction_normalized_finite() -> void:
	var d := Direction.new(Vector2(0, 0), Vector2(100, 0))
	var n := d.to_normalized()
	assert_almost_eq(n.length(), 1.0, 0.001, "Normalized should have length 1")
	assert_false(is_nan(n.x) or is_nan(n.y), "S16: No NaN in normalized direction")

func test_stage4_direction_zero_normalized() -> void:
	var d := Direction.new(Vector2(5, 5), Vector2(5, 5))
	var n := d.to_normalized()
	assert_eq(n, Vector2.ZERO, "Zero-length direction normalized should be ZERO")

func test_stage4_ray_construction() -> void:
	var d := Direction.new(Vector2(0, 0), Vector2(1, 0))
	var r := Ray.new(Vector2(10, 20), d)
	assert_eq(r.origin, Vector2(10, 20), "Ray origin should match")
	assert_eq(r.direction, d, "Ray direction should match")

func test_stage4_ray_preserves_direction_reference() -> void:
	var d := Direction.new(Vector2(0, 0), Vector2(1, 0))
	var r1 := Ray.new(Vector2(10, 20), d)
	var r2 := Ray.new(Vector2(30, 40), d)
	assert_eq(r1.direction, r2.direction, "Both rays should share the same Direction reference")
