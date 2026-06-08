extends GutTest

func before_each() -> void:
	MobiusTransform.reset_id_counter()

func _make_reflection(x: float) -> MobiusTransform:
	var seg := Segment.new(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))
	var refl := ReflectionEffect.new(seg.get_carrier())
	return refl.get_mobius()

# --- Stage 1: compose_cached + invert_cached ---

func test_compose_cached_same_result() -> void:
	var cache := TransformCache.new()
	var identity := MobiusTransform.identity()
	var refl := _make_reflection(400)
	var r1 := cache.compose_cached(identity, refl)
	var r2 := cache.compose_cached(identity, refl)
	assert_eq(r1, r2, "Same inputs should return same object")
	assert_eq(r1.id, r2.id, "Same ID from cache")

func test_compose_cached_different_inputs() -> void:
	var cache := TransformCache.new()
	var identity := MobiusTransform.identity()
	var refl_a := _make_reflection(400)
	var refl_b := _make_reflection(600)
	var r1 := cache.compose_cached(identity, refl_a)
	var r2 := cache.compose_cached(identity, refl_b)
	assert_ne(r1.id, r2.id, "Different inputs should produce different IDs")

func test_invert_cached_same_result() -> void:
	var cache := TransformCache.new()
	var refl := _make_reflection(400)
	var inv1 := cache.invert_cached(refl)
	var inv2 := cache.invert_cached(refl)
	assert_eq(inv1, inv2, "Same input should return same inverse object")

func test_invert_cached_bidirectional() -> void:
	var cache := TransformCache.new()
	var refl := _make_reflection(400)
	var inv := cache.invert_cached(refl)
	var roundtrip := cache.invert_cached(inv)
	assert_eq(roundtrip, refl, "invert(invert(M)) should return original M")

func test_clear_empties_caches() -> void:
	var cache := TransformCache.new()
	var identity := MobiusTransform.identity()
	var refl := _make_reflection(400)
	var r1 := cache.compose_cached(identity, refl)
	var inv1 := cache.invert_cached(refl)
	cache.clear()
	var r2 := cache.compose_cached(identity, refl)
	var inv2 := cache.invert_cached(refl)
	assert_ne(r1.id, r2.id, "After clear, new composition gets new ID")
	assert_ne(inv1.id, inv2.id, "After clear, new inversion gets new ID")

# --- Stage 2: Shared cache between traces ---

# --- Stage 3: Normalized surface caching ---

func test_norm_cache_returns_null_initially() -> void:
	var cache := TransformCache.new()
	assert_null(cache.get_normalized(0), "No cached value initially")

func test_norm_cache_stores_and_retrieves() -> void:
	var cache := TransformCache.new()
	var surfaces: Array = [1, 2, 3]
	var mapping: Dictionary = {"a": "b"}
	cache.set_normalized(42, surfaces, mapping)
	var result = cache.get_normalized(42)
	assert_not_null(result, "Should retrieve cached value")
	assert_eq(result.surfaces, surfaces, "Same surfaces")

func test_norm_cache_different_frame_ids() -> void:
	var cache := TransformCache.new()
	cache.set_normalized(1, [1], {})
	cache.set_normalized(2, [2], {})
	assert_eq(cache.get_normalized(1).surfaces, [1], "Frame 1 cached")
	assert_eq(cache.get_normalized(2).surfaces, [2], "Frame 2 cached")

# --- Stage 2: Shared cache between traces ---

func test_shared_cache_same_frame_ids() -> void:
	var cache := TransformCache.new()
	var seg := Segment.new(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var refl := ReflectionEffect.new(seg.get_carrier())
	var config := SideConfig.new(refl, true)
	var mirror := Surface.new(seg, config, config, false, false)
	var w := RoomBuilder.create_block_surface(Vector2(100, 0), Vector2(100, 600), Vector2(100, 300))
	var surfaces: Array = [mirror, w]
	var player := Vector2(600, 300)
	var cursor := Vector2(200, 300)
	var aim := Direction.new(player, cursor)
	var ray := Ray.new(player, aim)

	# PLANNED mode needs a plan entry to apply the mirror's effect
	var plan_entries: Array = [PlanManager.PlanEntry.new(mirror.id, Side.Value.LEFT)]

	# Both traces use the SAME cache — no ID counter reset needed
	var physical := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, plan_entries, cache)
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan_entries, cache)

	assert_gt(physical.steps.size(), 1, "Physical trace should have >1 step after reflection")
	assert_gt(planned.steps.size(), 1, "Planned trace should have >1 step after reflection")

	var phys_step1: Tracer.Step = physical.steps[1]
	var plan_step1: Tracer.Step = planned.steps[1]
	assert_ne(phys_step1.frame_id, 0, "Physical trace should have non-identity frame after reflection")
	assert_eq(phys_step1.frame_id, plan_step1.frame_id,
		"Shared cache: same composition = same frame ID")
