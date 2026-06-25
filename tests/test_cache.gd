extends GutTest

func before_each() -> void:
	MobiusTransform.reset_id_counter()

func _make_reflection(x: float) -> MobiusTransform:
	var seg := Segment.from_coords(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))
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
	var seg := Segment.from_coords(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var refl := ReflectionEffect.new(seg.get_carrier())
	var config := SideConfig.new(refl, true)
	var mirror := Surface.new(seg, config, config, false, false)
	var w := RoomBuilder.create_block_surface(Vector2(100, 0), Vector2(100, 600), Vector2(100, 300))
	var surfaces: Array = [mirror, w]
	var player := Vector2(600, 300)
	var cursor := Vector2(200, 300)
	var aim := Direction.from_coords(player, cursor)
	var ray := Ray.from_coords(player, aim)

	# PLANNED mode needs a plan entry to apply the mirror's effect
	var plan_entries: Array = [PlanManager.PlanEntry.new(mirror.id, Side.Value.LEFT)]

	# Both traces use the SAME cache — no ID counter reset needed
	var physical := Tracer.trace(player, aim, surfaces, GameState.new(),
		ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, plan_entries, cache, cursor)
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		ray, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan_entries, cache, cursor)

	assert_gt(physical.steps.size(), 1, "Physical trace should have >1 step after reflection")
	assert_gt(planned.steps.size(), 1, "Planned trace should have >1 step after reflection")

	var phys_step1: Tracer.Step = physical.steps[1]
	var plan_step1: Tracer.Step = planned.steps[1]
	assert_ne(phys_step1.frame_id, 0, "Physical trace should have non-identity frame after reflection")
	assert_eq(phys_step1.frame_id, plan_step1.frame_id,
		"Shared cache: same composition = same frame ID")

# --- Stage 72: apply_point bidirectional caching fix ---

func test_apply_point_non_self_inverse_corruption() -> void:
	var seg := Segment.from_coords(Vector2(200, 100), Vector2(200, 500), Vector2(200, 300))
	var result := RigidMotionEffect.create_portal_pair(seg, 0.0, Vector2(300, 0))
	var fwd: MobiusTransform = result.source_effect.get_mobius()
	var p := Vector2(100, 300)
	var expected_q := fwd.apply(p)
	var expected_qq := fwd.apply(expected_q)
	var cache := TransformCache.new()
	var q := cache.apply_point(fwd, p)
	assert_almost_eq(q, expected_q, Vector2(0.01, 0.01),
		"First apply_point must match direct fwd.apply")
	var qq := cache.apply_point(fwd, q)
	assert_almost_eq(qq, expected_qq, Vector2(0.01, 0.01),
		"Second apply_point(fwd, fwd(p)) must return fwd(fwd(p)), not p")

func test_apply_point_cross_direction_caching() -> void:
	var seg := Segment.from_coords(Vector2(200, 100), Vector2(200, 500), Vector2(200, 300))
	var pair := RigidMotionEffect.create_portal_pair(seg, 0.0, Vector2(300, 0))
	var fwd: MobiusTransform = pair.source_effect.get_mobius()
	var inv: MobiusTransform = pair.source_effect.get_inverse_mobius()
	var p := Vector2(100, 300)
	var cache := TransformCache.new()
	var q := cache.apply_point(fwd, p, inv)
	var roundtrip := cache.apply_point(inv, q)
	assert_eq(roundtrip, p,
		"inv(fwd(p)) must return exact p from cache (no FP recomputation)")
