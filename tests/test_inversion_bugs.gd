extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()

func _build_scene_surfaces() -> Array:
	var surfs: Array = []
	# Room walls: Rect2(160, 90, 1600, 900)
	surfs.append_array(RoomBuilder.create_room_surfaces(Rect2(160, 90, 1600, 900)))
	# mirror_lines (left-side reflect)
	for def in [Vector4(500, 200, 500, 700), Vector4(1400, 300, 1400, 800), Vector4(700, 800, 1200, 800)]:
		var seg := Segment.new(Vector2(def.x, def.y), Vector2(def.z, def.w),
			Vector2((def.x + def.z) / 2.0, (def.y + def.w) / 2.0))
		var carrier := seg.get_carrier()
		var refl := ReflectionEffect.new(carrier)
		surfs.append(Surface.new(seg, SideConfig.new(refl, true), SideConfig.new(null, false), false, false))
	# mirror_right_lines
	for def in [Vector4(960, 200, 960, 500)]:
		var seg := Segment.new(Vector2(def.x, def.y), Vector2(def.z, def.w),
			Vector2((def.x + def.z) / 2.0, (def.y + def.w) / 2.0))
		var carrier := seg.get_carrier()
		var refl := ReflectionEffect.new(carrier)
		surfs.append(Surface.new(seg, SideConfig.new(null, false), SideConfig.new(refl, true), false, false))
	# inversion_left_arcs: (1100, 400, 1100, 700, 1230, 550)
	var inv_seg := Segment.new(Vector2(1100, 400), Vector2(1100, 700), Vector2(1230, 550))
	var inv_carrier := inv_seg.get_carrier()
	var inv_effect := CircleInversionEffect.new(inv_carrier)
	surfs.append(Surface.new(inv_seg, SideConfig.new(inv_effect, true), SideConfig.new(null, false), false, false))
	# Screen boundary pass-throughs
	for def in [Vector4(0, 0, 1920, 0), Vector4(1920, 0, 1920, 1080),
				Vector4(1920, 1080, 0, 1080), Vector4(0, 1080, 0, 0)]:
		var seg := Segment.new(Vector2(def.x, def.y), Vector2(def.z, def.w),
			Vector2((def.x + def.z) / 2.0, (def.y + def.w) / 2.0))
		surfs.append(Surface.new(seg, SideConfig.new(null, false), SideConfig.new(null, false), false, false))
	return surfs

# === STEP 1: Reproduce the infinite loop ===

func test_step1_reproduce_infinite_loop() -> void:
	var surfs := _build_scene_surfaces()
	var player := Vector2(1309.974, 816.636)
	var cursor := Vector2(1244.296, 594.100)
	var aim := Direction.new(player, cursor)
	var path := Tracer.trace(player, aim, surfs, GameState.new(), Rect2(0, 0, 1920, 1080))
	gut.p("Step count: %d" % path.steps.size())
	assert_lt(path.steps.size(), 50, "Trace should not produce hundreds of steps (got %d)" % path.steps.size())

# === STEP 2: Instrument the trace — per-step diagnostics ===

func test_step2_trace_diagnostics() -> void:
	var surfs := _build_scene_surfaces()
	var player := Vector2(1309.974, 816.636)
	var cursor := Vector2(1244.296, 594.100)
	var aim := Direction.new(player, cursor)
	var path := Tracer.trace(player, aim, surfs, GameState.new(), Rect2(0, 0, 1920, 1080))
	gut.p("Total steps: %d" % path.steps.size())
	var limit: int = mini(path.steps.size(), 20)
	for i in limit:
		var s: Tracer.Step = path.steps[i]
		var hit_info := "no_hit"
		if s.hit != null:
			hit_info = "t=%.4f on_seg=%s seg_line=%s" % [s.hit.t, s.hit.on_segment, s.hit.segment.is_line()]
		var step_len := s.start.distance_to(s.end)
		gut.p("  [%d] fid=%d start=%s end=%s len=%.4f is_arc=%s %s" % [
			i, s.frame_id, s.start, s.end, step_len, s.is_arc_step, hit_info])
	# Check for zero-length steps
	var zero_count := 0
	for s in path.steps:
		var step: Tracer.Step = s
		if step.start.distance_to(step.end) < 0.01:
			zero_count += 1
	gut.p("Zero-length steps: %d" % zero_count)
	assert_eq(zero_count, 0, "Should have no zero-length steps")

# === STEP 3: Floating-point precision of self-inversion ===

func test_step3_self_inversion_precision() -> void:
	# The scene's inversion circle: start=(1100,400) end=(1100,700) via=(1230,550)
	var seg := Segment.new(Vector2(1100, 400), Vector2(1100, 700), Vector2(1230, 550))
	var carrier := seg.get_carrier()
	var center := carrier.center()
	var radius := carrier.radius()
	gut.p("Inversion circle: center=%s radius=%.4f" % [center, radius])

	var inv := CircleInversionEffect.new(carrier)
	var mobius := inv.get_mobius()

	# Test several points ON the circle
	var test_angles := [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0]
	for angle in test_angles:
		var p := center + Vector2(cos(angle), sin(angle)) * radius
		var p_inv := mobius.apply(p)
		var dist := p.distance_to(p_inv)
		var exact_eq := (p == p_inv)
		gut.p("  angle=%.1f P=%s P'=%s dist=%.10f exact_eq=%s" % [angle, p, p_inv, dist, exact_eq])

	# Test the specific point from the bug report: (1075.258, 527.893)
	var bug_point := Vector2(1075.258, 527.8928)
	var bug_dist := bug_point.distance_to(center)
	gut.p("Bug point dist from center: %.4f (radius=%.4f, on_circle=%s)" % [
		bug_dist, radius, absf(bug_dist - radius) < 1.0])
	var bug_inv := mobius.apply(bug_point)
	var bug_roundtrip_dist := bug_point.distance_to(bug_inv)
	gut.p("Bug point: P=%s P'=%s dist=%.10f exact_eq=%s" % [
		bug_point, bug_inv, bug_roundtrip_dist, bug_point == bug_inv])

	assert_true(true, "Diagnostic test — check output above")

# === Cache round-trip tests ===

func test_cache_self_inverse_roundtrip_exact() -> void:
	var seg := Segment.new(Vector2(1100, 400), Vector2(1100, 700), Vector2(1230, 550))
	var carrier := seg.get_carrier()
	var inv := CircleInversionEffect.new(carrier)
	var mobius := inv.get_mobius()
	var cache := TransformCache.new()
	var center := carrier.center()
	var radius := carrier.radius()
	var test_angles := [0.0, 0.7, 1.4, 2.1, 2.8, 3.5, 4.2, 5.0]
	for angle in test_angles:
		var p := center + Vector2(cos(angle), sin(angle)) * radius
		var q := cache.apply_point_cached(mobius, p)
		var roundtrip := cache.apply_point_cached(mobius, q)
		assert_eq(roundtrip, p,
			"Self-inverse round-trip must be EXACT for angle %.1f (p=%s rt=%s)" % [angle, p, roundtrip])

func test_cache_non_carrier_point_roundtrip() -> void:
	var seg := Segment.new(Vector2(1100, 400), Vector2(1100, 700), Vector2(1230, 550))
	var carrier := seg.get_carrier()
	var inv := CircleInversionEffect.new(carrier)
	var mobius := inv.get_mobius()
	var cache := TransformCache.new()
	var p := Vector2(500, 300)
	var q := cache.apply_point_cached(mobius, p)
	var roundtrip := cache.apply_point_cached(mobius, q)
	assert_eq(roundtrip, p,
		"Self-inverse round-trip must be EXACT for off-carrier points too")

# === STEP 4: Segment exclusion after re-normalization ===

func test_step4_segment_exclusion_after_renorm() -> void:
	# Minimal scene: just the inversion surface + walls
	var inv_seg := Segment.new(Vector2(1100, 400), Vector2(1100, 700), Vector2(1230, 550))
	var inv_carrier := inv_seg.get_carrier()
	var inv_effect := CircleInversionEffect.new(inv_carrier)
	var inv_surf := Surface.new(inv_seg, SideConfig.new(inv_effect, true), SideConfig.new(null, false), false, false)
	var walls := RoomBuilder.create_room_surfaces(Rect2(160, 90, 1600, 900))
	var surfs: Array = walls + [inv_surf]

	# Use a ray that approaches the arc from OUTSIDE (to trigger the effect)
	var player := Vector2(1400, 550)
	var cursor := Vector2(900, 550)
	var aim := Direction.new(player, cursor)
	var path := Tracer.trace(player, aim, surfs, GameState.new(), Rect2(0, 0, 1920, 1080))

	gut.p("Step count: %d" % path.steps.size())
	var limit2: int = mini(path.steps.size(), 15)
	for i in limit2:
		var s: Tracer.Step = path.steps[i]
		var hit_info := "no_hit"
		if s.hit != null:
			hit_info = "t=%.4f on_seg=%s" % [s.hit.t, s.hit.on_segment]
		gut.p("  [%d] fid=%d %s->%s %s" % [i, s.frame_id, s.start, s.end, hit_info])

	# Check: does the trace loop?
	if path.steps.size() > 20:
		var s10: Tracer.Step = path.steps[10]
		var s13: Tracer.Step = path.steps[13]
		var repeating := s10.start.distance_to(s13.start) < 1.0
		gut.p("Steps 10 and 13 same start: %s (dist=%.4f)" % [repeating, s10.start.distance_to(s13.start)])

	assert_lt(path.steps.size(), 50, "Should not loop (got %d steps)" % path.steps.size())
