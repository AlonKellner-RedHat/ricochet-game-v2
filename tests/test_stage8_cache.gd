extends GutTest

func before_each() -> void:
	Point.reset_id_counter()

func test_stage8_point_id_unique() -> void:
	var ids: Dictionary = {}
	for i in 100:
		var p := Point.new(Vector2(i, i))
		assert_false(ids.has(p.id), "S17: Point ID %d should be unique" % p.id)
		ids[p.id] = true

func test_stage8_point_id_monotonic() -> void:
	var prev_id := 0
	for i in 10:
		var p := Point.new(Vector2(i, i))
		assert_gt(p.id, prev_id, "Point IDs should be monotonically incrementing")
		prev_id = p.id

func test_stage8_S1_carrier_via_roundtrip_line() -> void:
	var cache := TransformCache.new()
	var start := Point.new(Vector2(0, 0), Point.Provenance.SEGMENT_START)
	var end_pt := Point.new(Vector2(10, 0), Point.Provenance.SEGMENT_END)
	var via := Point.new(Vector2(5, 0), Point.Provenance.SEGMENT_VIA)

	var carrier := cache.derive_carrier_cached(start, end_pt, via, true)
	var recovered := cache.derive_via_cached(start, end_pt, carrier)

	assert_not_null(recovered, "S1: Should recover via from cache")
	assert_eq(recovered.id, via.id, "S1: Recovered via should have same ID (exact round-trip)")
	assert_eq(recovered.position, via.position, "S1: Recovered via should have same position")

func test_stage8_S1_carrier_via_roundtrip_circle() -> void:
	var cache := TransformCache.new()
	var start := Point.new(Vector2(200, 100), Point.Provenance.SEGMENT_START)
	var end_pt := Point.new(Vector2(200, 300), Point.Provenance.SEGMENT_END)
	var via := Point.new(Vector2(300, 200), Point.Provenance.SEGMENT_VIA)

	var carrier := cache.derive_carrier_cached(start, end_pt, via)
	var recovered := cache.derive_via_cached(start, end_pt, carrier)

	assert_not_null(recovered, "S1: Should recover via from cache")
	assert_eq(recovered.id, via.id, "S1: Recovered via should have same ID (exact round-trip)")
	assert_eq(recovered.position, via.position, "S1: Recovered via should have same position")

func test_stage8_cache_hit_on_second_lookup() -> void:
	var cache := TransformCache.new()
	var start := Point.new(Vector2(0, 0))
	var end_pt := Point.new(Vector2(10, 0))
	var via := Point.new(Vector2(5, 0))

	var carrier1 := cache.derive_carrier_cached(start, end_pt, via, true)
	var carrier2 := cache.derive_carrier_cached(start, end_pt, via, true)

	assert_eq(carrier1, carrier2, "Second lookup should return same cached object")

func test_stage8_S17_provenance_unique() -> void:
	var points: Array[Point] = []
	points.append(Point.new(Vector2(0, 0), Point.Provenance.ORIGIN))
	points.append(Point.new(Vector2(1, 1), Point.Provenance.BOUNCE))
	points.append(Point.new(Vector2(2, 2), Point.Provenance.IMAGE))
	points.append(Point.new(Vector2(3, 3), Point.Provenance.CORNER))
	points.append(Point.new(Vector2(4, 4), Point.Provenance.CURSOR))

	var ids: Dictionary = {}
	for p in points:
		assert_false(ids.has(p.id), "S17: ID %d should be unique across provenance types" % p.id)
		ids[p.id] = true

func test_stage8_point_provenance_stored() -> void:
	var p := Point.new(Vector2(42, 99), Point.Provenance.BOUNCE)
	assert_eq(p.provenance, Point.Provenance.BOUNCE, "Provenance should be stored")
	assert_eq(p.position, Vector2(42, 99), "Position should be stored")
