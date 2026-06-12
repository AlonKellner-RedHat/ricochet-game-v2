extends GutTest

func test_stage8_S1_carrier_via_roundtrip_line() -> void:
	var cache := TransformCache.new()
	var start := Vector2(0, 0)
	var end_pt := Vector2(10, 0)
	var via := Vector2(5, 0)

	var carrier := cache.derive_carrier_cached(start, end_pt, via)
	var recovered := cache.derive_via_cached(start, end_pt, carrier)

	assert_false(is_nan(recovered.x), "S1: Should recover via from cache")
	assert_eq(recovered, via, "S1: Recovered via should match original")

func test_stage8_S1_carrier_via_roundtrip_circle() -> void:
	var cache := TransformCache.new()
	var start := Vector2(200, 100)
	var end_pt := Vector2(200, 300)
	var via := Vector2(300, 200)

	var carrier := cache.derive_carrier_cached(start, end_pt, via)
	var recovered := cache.derive_via_cached(start, end_pt, carrier)

	assert_false(is_nan(recovered.x), "S1: Should recover via from cache")
	assert_eq(recovered, via, "S1: Recovered via should match original")

func test_stage8_cache_hit_on_second_lookup() -> void:
	var cache := TransformCache.new()
	var start := Vector2(0, 0)
	var end_pt := Vector2(10, 0)
	var via := Vector2(5, 0)

	var carrier1 := cache.derive_carrier_cached(start, end_pt, via)
	var carrier2 := cache.derive_carrier_cached(start, end_pt, via)

	assert_eq(carrier1, carrier2, "Second lookup should return same cached object")
