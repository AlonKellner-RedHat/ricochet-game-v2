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
		var seg := Segment.from_coords(Vector2(def.x, def.y), Vector2(def.z, def.w),
			Vector2((def.x + def.z) / 2.0, (def.y + def.w) / 2.0))
		var carrier := seg.get_carrier()
		var refl := ReflectionEffect.new(carrier)
		surfs.append(Surface.new(seg, SideConfig.new(refl, true), SideConfig.new(null, false), false, false))
	# mirror_right_lines
	for def in [Vector4(960, 200, 960, 500)]:
		var seg := Segment.from_coords(Vector2(def.x, def.y), Vector2(def.z, def.w),
			Vector2((def.x + def.z) / 2.0, (def.y + def.w) / 2.0))
		var carrier := seg.get_carrier()
		var refl := ReflectionEffect.new(carrier)
		surfs.append(Surface.new(seg, SideConfig.new(null, false), SideConfig.new(refl, true), false, false))
	# inversion_left_arcs: (1100, 400, 1100, 700, 1230, 550)
	var inv_seg := Segment.from_coords(Vector2(1100, 400), Vector2(1100, 700), Vector2(1230, 550))
	var inv_carrier := inv_seg.get_carrier()
	var inv_effect := CircleInversionEffect.new(inv_carrier)
	surfs.append(Surface.new(inv_seg, SideConfig.new(inv_effect, true), SideConfig.new(null, false), false, false))
	# Screen boundary pass-throughs
	for def in [Vector4(0, 0, 1920, 0), Vector4(1920, 0, 1920, 1080),
				Vector4(1920, 1080, 0, 1080), Vector4(0, 1080, 0, 0)]:
		var seg := Segment.from_coords(Vector2(def.x, def.y), Vector2(def.z, def.w),
			Vector2((def.x + def.z) / 2.0, (def.y + def.w) / 2.0))
		surfs.append(Surface.new(seg, SideConfig.new(null, false), SideConfig.new(null, false), false, false))
	return surfs

# === STEP 1: Reproduce the infinite loop ===

func test_step1_reproduce_infinite_loop() -> void:
	var surfs := _build_scene_surfaces()
	var player := Vector2(1309.974, 816.636)
	var cursor := Vector2(1244.296, 594.100)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfs, GameState.new())
	gut.p("Step count: %d" % path.steps.size())
	assert_lt(path.steps.size(), 50, "Trace should not produce hundreds of steps (got %d)" % path.steps.size())

# === STEP 2: Instrument the trace — per-step diagnostics ===

func test_step2_trace_diagnostics() -> void:
	var surfs := _build_scene_surfaces()
	var player := Vector2(1309.974, 816.636)
	var cursor := Vector2(1244.296, 594.100)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfs, GameState.new())
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
	var seg := Segment.from_coords(Vector2(1100, 400), Vector2(1100, 700), Vector2(1230, 550))
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
	var seg := Segment.from_coords(Vector2(1100, 400), Vector2(1100, 700), Vector2(1230, 550))
	var carrier := seg.get_carrier()
	var inv := CircleInversionEffect.new(carrier)
	var mobius := inv.get_mobius()
	var cache := TransformCache.new()
	var center := carrier.center()
	var radius := carrier.radius()
	var test_angles := [0.0, 0.7, 1.4, 2.1, 2.8, 3.5, 4.2, 5.0]
	for angle in test_angles:
		var p := center + Vector2(cos(angle), sin(angle)) * radius
		var q := cache.apply_point(mobius, p, mobius)
		var roundtrip := cache.apply_point(mobius, q)
		assert_eq(roundtrip, p,
			"Self-inverse round-trip must be EXACT for angle %.1f (p=%s rt=%s)" % [angle, p, roundtrip])

func test_cache_non_carrier_point_roundtrip() -> void:
	var seg := Segment.from_coords(Vector2(1100, 400), Vector2(1100, 700), Vector2(1230, 550))
	var carrier := seg.get_carrier()
	var inv := CircleInversionEffect.new(carrier)
	var mobius := inv.get_mobius()
	var cache := TransformCache.new()
	var p := Vector2(500, 300)
	var q := cache.apply_point(mobius, p, mobius)
	var roundtrip := cache.apply_point(mobius, q)
	assert_eq(roundtrip, p,
		"Self-inverse round-trip must be EXACT for off-carrier points too")

# === STEP 4: Segment exclusion after re-normalization ===

func test_step4_segment_exclusion_after_renorm() -> void:
	# Minimal scene: just the inversion surface + walls
	var inv_seg := Segment.from_coords(Vector2(1100, 400), Vector2(1100, 700), Vector2(1230, 550))
	var inv_carrier := inv_seg.get_carrier()
	var inv_effect := CircleInversionEffect.new(inv_carrier)
	var inv_surf := Surface.new(inv_seg, SideConfig.new(inv_effect, true), SideConfig.new(null, false), false, false)
	var walls := RoomBuilder.create_room_surfaces(Rect2(160, 90, 1600, 900))
	var surfs: Array = walls + [inv_surf]

	# Use a ray that approaches the arc from OUTSIDE (to trigger the effect)
	var player := Vector2(1400, 550)
	var cursor := Vector2(900, 550)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfs, GameState.new())

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

# === BUG 2: Post-inversion aim point ignores surfaces ===

func test_bug2_reproduce_aim_ignores_surfaces() -> void:
	var surfs := _build_scene_surfaces()
	var player := Vector2(1301.632, 932.631)
	var cursor := Vector2(1112.158, 507.941)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfs, GameState.new())
	gut.p("Steps: %d" % path.steps.size())
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		var hit_info := "no_hit"
		if s.hit != null:
			hit_info = "t=%.4f on_seg=%s seg_line=%s" % [s.hit.t, s.hit.on_segment, s.hit.segment.is_line()]
		gut.p("  [%d] fid=%d start=%s end=%s is_arc=%s %s" % [
			i, s.frame_id, s.start, s.end, s.is_arc_step, hit_info])
	# After inversion, the trace should still interact with walls (block surfaces)
	# The user reports steps 2-4 are all escape/no_hit, passing through walls
	var escape_count := 0
	for s in path.steps:
		var step: Tracer.Step = s
		if step.hit == null:
			escape_count += 1
	gut.p("Escape (no_hit) steps: %d out of %d" % [escape_count, path.steps.size()])
	# There should be at most 2 escape steps (forward + return from infinity)
	# The user sees 3 escape steps passing through blocking surfaces
	assert_lt(escape_count, 3, "Should not have multiple escape steps passing through walls")

func test_bug2_aim_point_frame_analysis() -> void:
	var surfs := _build_scene_surfaces()
	var player := Vector2(1301.632, 932.631)
	var cursor := Vector2(1112.158, 507.941)
	var aim := Direction.from_coords(player, cursor)
	gut.p("aim_point (direction.end) = %s" % aim.end.coords)
	gut.p("Player = %s, Cursor = %s" % [player, cursor])

	# Trace and capture per-step details about aim injection
	var path := Tracer.trace(player, aim, surfs, GameState.new())

	# Check: does step 1 hit the inversion surface?
	var found_inversion_hit := false
	var inversion_step := -1
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if s.hit != null and s.hit.on_segment and not s.hit.segment.is_line():
			found_inversion_hit = true
			inversion_step = i
			gut.p("Inversion hit at step %d, point=%s, frame_id after=%s" % [
				i, s.end,
				path.steps[i + 1].frame_id if i + 1 < path.steps.size() else "N/A"])
			break
	assert_true(found_inversion_hit, "Should hit the inversion surface")

	# Check: what is the first post-inversion step?
	if inversion_step >= 0 and inversion_step + 1 < path.steps.size():
		var post := path.steps[inversion_step + 1] as Tracer.Step
		gut.p("Post-inversion step: start=%s end=%s fid=%d hit=%s is_arc=%s" % [
			post.start, post.end, post.frame_id,
			"hit" if post.hit != null else "NO HIT",
			post.is_arc_step])
		# The post-inversion step ends at the aim image — check if that's where it ends
		var inv_seg := Segment.from_coords(Vector2(1100, 400), Vector2(1100, 700), Vector2(1230, 550))
		var inv_carrier := inv_seg.get_carrier()
		var inv_eff := CircleInversionEffect.new(inv_carrier)
		var aim_image := inv_eff.get_mobius().apply(cursor)
		gut.p("aim_point = %s" % aim.end.coords)
		gut.p("aim_image (M(cursor)) = %s" % aim_image)
		gut.p("Post-inversion step end = %s" % post.end)
		gut.p("Distance to aim_image: %.4f" % post.end.distance_to(aim_image))

	assert_true(true, "Diagnostic — check output")

# === BUG 3: Three user-reported cases ===

func _trace_and_diagnose(player: Vector2, cursor: Vector2, label: String) -> Tracer.TracedPath:
	var surfs := _build_scene_surfaces()
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfs, GameState.new())
	gut.p("--- %s ---" % label)
	gut.p("Player=%s Cursor=%s Steps=%d" % [player, cursor, path.steps.size()])
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		var hit_info := "no_hit"
		if s.hit != null:
			hit_info = "t=%.4f on_seg=%s line=%s side=%d" % [
				s.hit.t, s.hit.on_segment, s.hit.segment.is_line(), s.hit.side]
		gut.p("  [%d] fid=%d arc=%s %s->%s %s" % [
			i, s.frame_id, s.is_arc_step, s.start, s.end, hit_info])
	# Check: is the first post-inversion step an aim virtual hit?
	var inv_carrier := Segment.from_coords(
		Vector2(1100, 400), Vector2(1100, 700), Vector2(1230, 550)).get_carrier()
	var inv_mobius := CircleInversionEffect.new(inv_carrier).get_mobius()
	var aim_image := inv_mobius.apply(cursor)
	gut.p("M(cursor) = %s" % aim_image)
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if s.hit == null and s.frame_id != 0:
			var dist := s.end.distance_to(aim_image)
			gut.p("  Step %d (no_hit, fid=%d) ends at dist %.4f from M(cursor)" % [i, s.frame_id, dist])
			if dist < 1.0:
				gut.p("  >>> This is the AIM virtual hit at M(cursor)!")
	return path

func test_bug3_case1_line_ignores_surfaces() -> void:
	var path := _trace_and_diagnose(
		Vector2(1370.004, 540.0), Vector2(1301.356, 503.933),
		"Case 1: line ignores surfaces after inversion")
	# After inversion, post-aim steps should still hit walls
	var post_inversion_escapes := 0
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if s.frame_id != 0 and s.hit == null:
			post_inversion_escapes += 1
	assert_lt(post_inversion_escapes, 3,
		"Post-inversion should not have 3+ escape steps (got %d)" % post_inversion_escapes)

func test_bug3_case2_cursor_inside_circle() -> void:
	var path := _trace_and_diagnose(
		Vector2(1346.67, 540.0), Vector2(1144.192, 495.918),
		"Case 2: cursor inside circle carrier")
	var post_inversion_escapes := 0
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if s.frame_id != 0 and s.hit == null:
			post_inversion_escapes += 1
	assert_lt(post_inversion_escapes, 3,
		"Post-inversion should not have 3+ escape steps (got %d)" % post_inversion_escapes)

func test_bug3_case3_arc_direction_flip() -> void:
	var path_a := _trace_and_diagnose(
		Vector2(1072.635, 965.964), Vector2(1154.202, 378.701),
		"Case 3a: cursor (1154, 379)")
	var path_b := _trace_and_diagnose(
		Vector2(1072.635, 965.964), Vector2(1156.204, 379.703),
		"Case 3b: cursor (1156, 380)")
	# Both should have an arc step after the inversion hit
	# Check if the arc directions match (both should be same winding)
	var arc_a_via := Vector2.ZERO
	var arc_b_via := Vector2.ZERO
	for s in path_a.steps:
		var step: Tracer.Step = s
		if step.is_arc_step and step.frame_id != 0:
			arc_a_via = step.via
			gut.p("Case 3a arc: start=%s via=%s end=%s" % [step.start, step.via, step.end])
			var cross_a := (step.via - step.start).cross(step.end - step.start)
			gut.p("  cross product: %.4f (%s)" % [cross_a, "CCW" if cross_a > 0 else "CW"])
			break
	for s in path_b.steps:
		var step: Tracer.Step = s
		if step.is_arc_step and step.frame_id != 0:
			arc_b_via = step.via
			gut.p("Case 3b arc: start=%s via=%s end=%s" % [step.start, step.via, step.end])
			var cross_b := (step.via - step.start).cross(step.end - step.start)
			gut.p("  cross product: %.4f (%s)" % [cross_b, "CCW" if cross_b > 0 else "CW"])
			break
	assert_true(true, "Diagnostic — check arc directions above")

# === Step 4: Why does player_waypoint fire after reflections? ===

func test_step4_plan_matched_after_reflection() -> void:
	# Simple reflection scene (no inversion) — empty plan
	var walls := RoomBuilder.create_room_surfaces(Rect2(160, 90, 1600, 900))
	var mirror_seg := Segment.from_coords(Vector2(960, 200), Vector2(960, 800), Vector2(960, 500))
	var carrier := mirror_seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var mirror := Surface.new(mirror_seg, SideConfig.new(refl, true), SideConfig.new(null, false), false, false)
	var surfs: Array = walls + [mirror]
	var player := Vector2(800, 500)
	var cursor := Vector2(700, 500)
	var aim := Direction.from_coords(player, cursor)
	# Empty plan — what happens to plan_matched after reflection?
	var path := Tracer.trace(player, aim, surfs, GameState.new())
	gut.p("Reflection test — Steps: %d" % path.steps.size())
	gut.p("cursor_index: %d" % path.cursor_index)
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		var hit_info := "no_hit"
		if s.hit != null:
			hit_info = "on_seg=%s" % s.hit.on_segment
		gut.p("  [%d] fid=%d %s->%s %s" % [i, s.frame_id, s.start, s.end, hit_info])
	# Does the trace pass through the player position?
	var found_player_waypoint := false
	for s in path.steps:
		var step: Tracer.Step = s
		if step.end.distance_to(player) < 5.0 or step.start.distance_to(player) < 5.0:
			found_player_waypoint = true
			gut.p("Player position touched at step: %s->%s" % [step.start, step.end])
	gut.p("Player waypoint fired: %s" % found_player_waypoint)
	assert_true(true, "Diagnostic — check output")
