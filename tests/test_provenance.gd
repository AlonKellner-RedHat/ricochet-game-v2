extends GutTest

func before_each() -> void:
	MobiusTransform.reset_id_counter()

# === Phase 1: TrackedTransform ===

func test_self_inverse_inverse_is_self() -> void:
	var m := MobiusTransform.new(Vector2(1, 0), Vector2(0, 0), Vector2(0, 0), Vector2(1, 0), true)
	var t := TrackedTransform.from_self_inverse(m)
	assert_eq(t.inverse, t, "Self-inverse transform's inverse should be itself")

func test_pair_creates_linked_inverses() -> void:
	var fwd := MobiusTransform.new(Vector2(1, 0), Vector2(2, 0), Vector2(0, 0), Vector2(1, 0), false)
	var bwd := fwd.invert()
	var f := TrackedTransform.from_pair(fwd, bwd)
	assert_ne(f.inverse, f, "Pair forward and inverse should be different objects")
	assert_eq(f.inverse.inverse, f, "Inverse of inverse should be the original")

func test_identity_is_self_inverse() -> void:
	var t := TrackedTransform.identity()
	assert_eq(t.inverse, t, "Identity should be self-inverse")
	assert_eq(t.mobius.id, MobiusTransform.IDENTITY_ID, "Identity mobius should have IDENTITY_ID")

func test_different_self_inverse_are_distinct() -> void:
	var m1 := MobiusTransform.new(Vector2(1, 0), Vector2(0, 0), Vector2(0, 0), Vector2(1, 0), true)
	var m2 := MobiusTransform.new(Vector2(0, 1), Vector2(0, 0), Vector2(0, 0), Vector2(0, 1), true)
	var t1 := TrackedTransform.from_self_inverse(m1)
	var t2 := TrackedTransform.from_self_inverse(m2)
	assert_ne(t1, t2, "Different self-inverse transforms should be distinct objects")

# === Phase 2: Point ===

func _make_reflection_tracked() -> TrackedTransform:
	var carrier := GeneralizedCircle.new(0.0, 1.0, 0.0, -500.0)
	var refl := ReflectionEffect.new(carrier)
	return TrackedTransform.from_self_inverse(refl.get_mobius())

func _make_inversion_tracked() -> TrackedTransform:
	var carrier := GeneralizedCircle.from_circle(Vector2(300, 400), 100.0)
	var inv := CircleInversionEffect.new(carrier)
	return TrackedTransform.from_self_inverse(inv.get_mobius())

# --- Construction ---

func test_point_at_sets_original_and_coords() -> void:
	var p := Point.at(Vector2(42, 99))
	assert_eq(p.original, Vector2(42, 99), "Original should match input")
	assert_eq(p.coords, Vector2(42, 99), "Coords should match input")

func test_point_at_has_empty_transforms() -> void:
	var p := Point.at(Vector2(10, 20))
	assert_eq(p.transforms.size(), 0, "New point should have no transforms")

func test_point_at_frame_is_identity() -> void:
	var p := Point.at(Vector2(10, 20))
	assert_eq(p.frame.id, MobiusTransform.IDENTITY_ID, "New point frame should be identity")

# --- Transformation ---

func test_transformed_returns_new_point() -> void:
	var p := Point.at(Vector2(100, 200))
	var t := _make_reflection_tracked()
	var q := p.transformed(t)
	assert_ne(p, q, "Transformed should return a new Point")

func test_transformed_preserves_original() -> void:
	var p := Point.at(Vector2(100, 200))
	var t := _make_reflection_tracked()
	var q := p.transformed(t)
	assert_eq(q.original, p.original, "Original should be preserved through transforms")

func test_transformed_applies_mobius_to_coords() -> void:
	var p := Point.at(Vector2(100, 200))
	var t := _make_reflection_tracked()
	var q := p.transformed(t)
	var expected := t.mobius.apply(Vector2(100, 200))
	assert_eq(q.coords, expected, "Coords should be mobius.apply(original)")

func test_transformed_appends_to_sequence() -> void:
	var p := Point.at(Vector2(100, 200))
	var t := _make_reflection_tracked()
	var t2 := _make_inversion_tracked()
	var q := p.transformed(t).transformed(t2)
	assert_eq(q.transforms.size(), 2, "Should have 2 transforms in sequence")

# --- Sequence simplification ---

func test_self_inverse_cancels_to_empty() -> void:
	var p := Point.at(Vector2(100, 200))
	var t := _make_reflection_tracked()
	var q := p.transformed(t).transformed(t)
	assert_eq(q.transforms.size(), 0, "Self-inverse should cancel: [R, R] -> []")
	assert_eq(q.coords, q.original, "Coords should exactly equal original after cancellation")

func test_pair_inverse_cancels() -> void:
	var fwd_m := MobiusTransform.new(Vector2(1, 0), Vector2(2, 0), Vector2(0, 0), Vector2(1, 0), false)
	var bwd_m := fwd_m.invert()
	var t := TrackedTransform.from_pair(fwd_m, bwd_m)
	var p := Point.at(Vector2(300, 400))
	var q := p.transformed(t).transformed(t.inverse)
	assert_eq(q.transforms.size(), 0, "Pair inverse should cancel: [A, a] -> []")
	assert_eq(q.coords, q.original, "Exact roundtrip")

func test_nested_cancellation() -> void:
	var a := _make_reflection_tracked()
	var b := _make_inversion_tracked()
	var p := Point.at(Vector2(500, 600))
	var q := p.transformed(a).transformed(b).transformed(b).transformed(a)
	assert_eq(q.transforms.size(), 0, "[A, B, B, A] -> [] (nested cancellation)")
	assert_eq(q.coords, q.original, "Exact roundtrip after nested cancellation")

func test_no_false_cancellation() -> void:
	var a := _make_reflection_tracked()
	var b := _make_inversion_tracked()
	var fwd_m := MobiusTransform.new(Vector2(1, 0), Vector2(3, 0), Vector2(0, 0), Vector2(1, 0), false)
	var c := TrackedTransform.from_pair(fwd_m, fwd_m.invert())
	var q := Point.at(Vector2(100, 100)).transformed(a).transformed(b).transformed(c.inverse)
	assert_eq(q.transforms.size(), 3, "[A, B, c] stays [A, B, c] — no false cancellation")

func test_partial_cancellation() -> void:
	var a := _make_reflection_tracked()
	var b := _make_inversion_tracked()
	var fwd_m := MobiusTransform.new(Vector2(1, 0), Vector2(3, 0), Vector2(0, 0), Vector2(1, 0), false)
	var c := TrackedTransform.from_pair(fwd_m, fwd_m.invert())
	var d_m := MobiusTransform.new(Vector2(2, 0), Vector2(1, 0), Vector2(0, 0), Vector2(1, 0), false)
	var d := TrackedTransform.from_pair(d_m, d_m.invert())
	var q := Point.at(Vector2(100, 100)).transformed(a).transformed(b).transformed(c).transformed(c.inverse).transformed(b).transformed(d)
	assert_eq(q.transforms.size(), 2, "[A, B, C, c, b, D] -> [A, D]")
	assert_eq(q.transforms[0], a, "First remaining should be A")
	assert_eq(q.transforms[1], d, "Second remaining should be D")

func test_empty_sequence_exact_original() -> void:
	var t := _make_inversion_tracked()
	var original := Vector2(123.456, 789.012)
	var p := Point.at(original)
	var q := p.transformed(t).transformed(t)
	assert_eq(q.coords.x, original.x, "X must be bit-for-bit exact after cancellation")
	assert_eq(q.coords.y, original.y, "Y must be bit-for-bit exact after cancellation")

# --- Aggregation ---

func test_aggregate_single_equals_mobius() -> void:
	var t := _make_reflection_tracked()
	var p := Point.at(Vector2(100, 200)).transformed(t)
	assert_eq(p.frame.a, t.mobius.a, "Single-transform frame should match the mobius")
	assert_eq(p.frame.b, t.mobius.b, "Single-transform frame b")
	assert_eq(p.frame.c, t.mobius.c, "Single-transform frame c")
	assert_eq(p.frame.d, t.mobius.d, "Single-transform frame d")

func test_aggregate_two_equals_composition() -> void:
	var t1 := _make_reflection_tracked()
	var t2 := _make_inversion_tracked()
	var p := Point.at(Vector2(100, 200)).transformed(t1).transformed(t2)
	var expected := t1.mobius.compose(t2.mobius)
	assert_eq(p.frame.a, expected.a, "Two-transform frame a should match compose")
	assert_eq(p.frame.b, expected.b, "Two-transform frame b")

# --- Equality ---

func test_same_origin_after_transform() -> void:
	var p := Point.at(Vector2(100, 200))
	var t := _make_reflection_tracked()
	var q := p.transformed(t)
	assert_true(p.same_origin(q), "Transformed point should have same origin")

func test_different_origin_different_points() -> void:
	var p := Point.at(Vector2(100, 200))
	var q := Point.at(Vector2(100, 201))
	assert_false(p.same_origin(q), "Different originals should not be same origin")

# === Phase 3: Segment with Point ===

func test_segment_from_coords_fields_are_points() -> void:
	var seg := Segment.from_coords(Vector2(0, 0), Vector2(10, 0), Vector2(5, 0))
	assert_true(seg.start is Point, "start should be Point")
	assert_true(seg.end is Point, "end should be Point")
	assert_true(seg.via is Point, "via should be Point")
	assert_eq(seg.start.coords, Vector2(0, 0), "start coords")
	assert_eq(seg.end.coords, Vector2(10, 0), "end coords")

func test_segment_carrier_uses_coords() -> void:
	var seg := Segment.from_coords(Vector2(0, 0), Vector2(10, 0), Vector2(5, 0))
	var carrier := seg.get_carrier()
	assert_true(carrier.is_line(), "Collinear points should produce a line carrier")

func test_segment_transformed_applies_tracked() -> void:
	var seg := Segment.from_coords(Vector2(100, 200), Vector2(300, 200), Vector2(200, 200))
	var carrier := GeneralizedCircle.new(0.0, 1.0, 0.0, -500.0)
	var refl := ReflectionEffect.new(carrier)
	var t := TrackedTransform.from_self_inverse(refl.get_mobius())
	var seg2 := seg.transformed(t)
	assert_ne(seg2.start.coords, seg.start.coords, "Transformed start should differ")
	assert_eq(seg2.start.original, seg.start.original, "Original should be preserved")

func test_segment_transformed_inf_via_preserved() -> void:
	var seg := Segment.from_coords(Vector2(0, 0), Vector2(10, 0), Vector2(INF, INF))
	var carrier := GeneralizedCircle.new(0.0, 1.0, 0.0, -500.0)
	var t := TrackedTransform.from_self_inverse(ReflectionEffect.new(carrier).get_mobius())
	var seg2 := seg.transformed(t)
	assert_true(is_inf(seg2.via.coords.x), "INF via should be preserved")

func test_segment_double_self_inverse_exact_roundtrip() -> void:
	var seg := Segment.from_coords(Vector2(100, 200), Vector2(300, 400), Vector2(200, 300))
	var carrier := GeneralizedCircle.new(0.0, 1.0, 0.0, -500.0)
	var t := TrackedTransform.from_self_inverse(ReflectionEffect.new(carrier).get_mobius())
	var seg2 := seg.transformed(t).transformed(t)
	assert_eq(seg2.start.coords, seg.start.coords, "Double self-inverse start exact")
	assert_eq(seg2.end.coords, seg.end.coords, "Double self-inverse end exact")
	assert_eq(seg2.via.coords, seg.via.coords, "Double self-inverse via exact")

# === Phase 4: Direction and Ray ===

func test_direction_from_coords_fields_are_points() -> void:
	var d := Direction.from_coords(Vector2(10, 20), Vector2(30, 40))
	assert_true(d.start is Point, "start should be Point")
	assert_true(d.end is Point, "end should be Point")
	assert_eq(d.start.coords, Vector2(10, 20))
	assert_eq(d.end.coords, Vector2(30, 40))

func test_direction_to_vector_uses_coords() -> void:
	var d := Direction.from_coords(Vector2(10, 0), Vector2(30, 0))
	assert_eq(d.to_vector(), Vector2(20, 0))

func test_direction_is_zero_length_uses_coords() -> void:
	var d := Direction.from_coords(Vector2(5, 5), Vector2(5, 5))
	assert_true(d.is_zero_length())
	var d2 := Direction.from_coords(Vector2(5, 5), Vector2(6, 5))
	assert_false(d2.is_zero_length())

func test_ray_from_coords_origin_is_point() -> void:
	var d := Direction.from_coords(Vector2(0, 0), Vector2(1, 0))
	var r := Ray.from_coords(Vector2(100, 200), d)
	assert_true(r.origin is Point, "origin should be Point")
	assert_eq(r.origin.coords, Vector2(100, 200))

# === Phase 5: HitRecord ===

func test_hit_record_point_is_point_type() -> void:
	var seg := Segment.from_coords(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var ray := Ray.from_coords(Vector2(200, 300), Direction.from_coords(Vector2(200, 300), Vector2(600, 300)))
	var hit := Intersection.find_nearest_hit(ray, [seg])
	assert_not_null(hit, "Should find a hit")
	assert_true(hit.point is Point, "HitRecord.point should be Point")
	assert_almost_eq(hit.point.coords.x, 400.0, 1.0, "Hit x should be near 400")

# === Phase 6: Effects return TrackedTransform ===

func test_reflection_tracked_is_self_inverse() -> void:
	var carrier := GeneralizedCircle.new(0.0, 1.0, 0.0, -500.0)
	var refl := ReflectionEffect.new(carrier)
	var t := refl.get_tracked_transform()
	assert_eq(t.inverse, t, "Reflection tracked should be self-inverse")
	assert_eq(t.mobius, refl.get_mobius(), "Tracked mobius should match effect mobius")

func test_circle_inversion_tracked_is_self_inverse() -> void:
	var carrier := GeneralizedCircle.from_circle(Vector2(200, 200), 100.0)
	var inv := CircleInversionEffect.new(carrier)
	var t := inv.get_tracked_transform()
	assert_eq(t.inverse, t, "Inversion tracked should be self-inverse")
	assert_eq(t.mobius, inv.get_mobius(), "Tracked mobius should match effect mobius")

func test_different_effects_produce_different_tracked() -> void:
	var c1 := GeneralizedCircle.new(0.0, 1.0, 0.0, -500.0)
	var c2 := GeneralizedCircle.new(0.0, 0.0, 1.0, -300.0)
	var t1 := ReflectionEffect.new(c1).get_tracked_transform()
	var t2 := ReflectionEffect.new(c2).get_tracked_transform()
	assert_ne(t1, t2, "Different effects should produce different tracked transforms")

func test_normalized_effect_produces_different_tracked() -> void:
	var carrier := GeneralizedCircle.from_circle(Vector2(200, 200), 100.0)
	var inv := CircleInversionEffect.new(carrier)
	var carrier2 := GeneralizedCircle.from_circle(Vector2(300, 300), 50.0)
	var norm := inv.normalized(carrier2) as CircleInversionEffect
	var t1 := inv.get_tracked_transform()
	var t2 := norm.get_tracked_transform()
	assert_ne(t1, t2, "Normalized effect should produce different tracked transform")

# === Phase 7: Tracer with provenance ===

func _make_mirror_surface(x: float, y_start: float = 0.0, y_end: float = 600.0) -> Surface:
	var mid := (y_start + y_end) / 2.0
	var seg := Segment.from_coords(Vector2(x, y_start), Vector2(x, y_end), Vector2(x, mid))
	var refl := ReflectionEffect.new(seg.get_carrier())
	return Surface.new(seg, SideConfig.new(refl, true), SideConfig.new(refl, true), false, false)

func test_tracer_reflection_terminates_and_aim_correct() -> void:
	var m := _make_mirror_surface(400)
	var player := Vector2(600, 300)
	var cursor := Vector2(500, 300)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, [m], GameState.new())
	assert_true(path.steps.size() > 0, "Should have steps after reflection")
	assert_true(path.steps.size() < 20, "Should terminate quickly with single mirror")

func _build_three_mirrors_surfaces() -> Array:
	var surfaces: Array = []
	# Block lines (walls)
	surfaces.append(RoomBuilder.create_block_surface(
		Vector2(560, 240), Vector2(1360, 240), Vector2(960, 240)))
	surfaces.append(RoomBuilder.create_block_surface(
		Vector2(1360, 840), Vector2(560, 840), Vector2(960, 840)))
	surfaces.append(RoomBuilder.create_block_surface(
		Vector2(560, 840), Vector2(560, 240), Vector2(560, 540)))
	# Mirror at x=800 (left-side reflects)
	var seg1 := Segment.from_coords(Vector2(800, 300), Vector2(800, 780), Vector2(800, 540))
	var refl1 := ReflectionEffect.new(seg1.get_carrier())
	var m1 := Surface.new(seg1, SideConfig.new(refl1, true), SideConfig.new(null, false), false, false)
	surfaces.append(m1)
	# Mirror at x=1200 (left-side reflects)
	var seg2 := Segment.from_coords(Vector2(1200, 300), Vector2(1200, 780), Vector2(1200, 540))
	var refl2 := ReflectionEffect.new(seg2.get_carrier())
	var m2 := Surface.new(seg2, SideConfig.new(refl2, true), SideConfig.new(null, false), false, false)
	surfaces.append(m2)
	# Mirror at x=1000 (right-side reflects)
	var seg3 := Segment.from_coords(Vector2(1000, 400), Vector2(1000, 700), Vector2(1000, 550))
	var refl3 := ReflectionEffect.new(seg3.get_carrier())
	var m3 := Surface.new(seg3, SideConfig.new(null, false), SideConfig.new(refl3, true), false, false)
	surfaces.append(m3)
	return surfaces

func test_aim_does_not_jump_back_after_unplanned_reflections() -> void:
	Surface.reset_id_counter()
	var surfaces := _build_three_mirrors_surfaces()
	var player := Vector2(960, 827.9623)
	var cursor := Vector2(737.7685, 715.3248)
	var plan: Array = []
	var cache := TransformCache.new()
	var aim := Planner.compute_aim_direction(player, cursor, plan, surfaces, GameState.new(), cache)
	var aim_ray := Ray.from_coords(player, aim)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, aim_ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, plan, cache)
	assert_true(path.steps.size() >= 2, "Should have multiple steps")
	var aim_dir := aim.to_vector().normalized()
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		if step.start == step.end:
			continue
		if step.frame.maps_lines_to_arcs():
			continue
		var frame_inv := step.frame.invert()
		var bt_start := frame_inv.apply(step.start)
		var bt_end := frame_inv.apply(step.end)
		var cross_s := (bt_start - player).cross(aim_dir)
		var cross_e := (bt_end - player).cross(aim_dir)
		assert_almost_eq(cross_s, 0.0, 1.0,
			"Step %d start back-transform should be on aim ray (cross=%f)" % [i, cross_s])
		assert_almost_eq(cross_e, 0.0, 1.0,
			"Step %d end back-transform should be on aim ray (cross=%f)" % [i, cross_e])

func test_no_zero_length_carrier_at_bounds_corner() -> void:
	Surface.reset_id_counter()
	var surfaces := _build_three_mirrors_surfaces()
	var m1: Surface = surfaces[3]
	var plan := [PlanManager.PlanEntry.new(m1.id, Side.Value.LEFT)]
	var player := Vector2(1350, 250)
	var cursor := Vector2(1920, 1080)
	var cache := TransformCache.new()
	var aim := Planner.compute_aim_direction(player, cursor, plan, surfaces, GameState.new(), cache)
	var aim_ray := Ray.from_coords(player, aim)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, aim_ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, plan, cache)
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		assert_false(step.start == step.end and step.hit != null and step.hit.t > 0.0,
			"No zero-length carrier step at %s" % step.start)

func test_planned_trace_aligns_with_physical_when_plan_matches() -> void:
	Surface.reset_id_counter()
	var surfaces := _build_three_mirrors_surfaces()
	var player := Vector2(960, 827.9623)
	var cursor := Vector2(861.8978, 703.3025)
	var plan := [PlanManager.PlanEntry.new(4, Side.Value.LEFT)]
	var cache := TransformCache.new()
	var aim := Planner.compute_aim_direction(player, cursor, plan, surfaces, GameState.new(), cache)
	var aim_ray := Ray.from_coords(player, aim)
	var physical := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, aim_ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, plan, cache, cursor)
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, aim_ray, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan, cache, cursor)

	assert_gt(planned.cursor_index, 0, "Planned trace should reach cursor")
	assert_true(planned.cursor_index <= 3, "Planned trace should reach cursor in few steps, got %d" % planned.cursor_index)
	assert_gt(physical.cursor_index, 0, "Physical trace should reach cursor when plan matches")

	var min_ci := mini(physical.cursor_index, planned.cursor_index)
	for i in min_ci:
		var ps: Tracer.Step = physical.steps[i]
		var ls: Tracer.Step = planned.steps[i]
		assert_almost_eq(ps.start, ls.start, Vector2(1, 1),
			"Step %d start should align: phys=%s plan=%s" % [i, ps.start, ls.start])
		assert_almost_eq(ps.end, ls.end, Vector2(1, 1),
			"Step %d end should align: phys=%s plan=%s" % [i, ps.end, ls.end])
