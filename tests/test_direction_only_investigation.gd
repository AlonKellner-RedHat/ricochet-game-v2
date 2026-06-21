extends GutTest

const H := preload("res://tests/test_helpers.gd")

func before_each() -> void:
	H.reset_counters()

# ─────────────────────────────────────────────────────────────────────────────
# PART A — Corner collision investigation (endpoint mismatches)
# ─────────────────────────────────────────────────────────────────────────────

func _build_three_mirrors_surfaces() -> Dictionary:
	var w_top := RoomBuilder.create_block_surface(
		Vector2(560, 240), Vector2(1360, 240), Vector2(960, 240))
	var w_bot := RoomBuilder.create_block_surface(
		Vector2(1360, 840), Vector2(560, 840), Vector2(960, 840))
	var w_left := RoomBuilder.create_block_surface(
		Vector2(560, 840), Vector2(560, 240), Vector2(560, 540))

	var seg4 := Segment.from_coords(
		Vector2(800, 300), Vector2(800, 780), Vector2(800, 540))
	var refl4 := ReflectionEffect.new(seg4.get_carrier())
	var mirror4 := Surface.new(seg4,
		SideConfig.new(refl4, true), SideConfig.new(null, false), false, false)

	var seg5 := Segment.from_coords(
		Vector2(1200, 300), Vector2(1200, 780), Vector2(1200, 540))
	var refl5 := ReflectionEffect.new(seg5.get_carrier())
	var mirror5 := Surface.new(seg5,
		SideConfig.new(refl5, true), SideConfig.new(null, false), false, false)

	var seg6 := Segment.from_coords(
		Vector2(1000, 400), Vector2(1000, 700), Vector2(1000, 550))
	var refl6 := ReflectionEffect.new(seg6.get_carrier())
	var mirror6 := Surface.new(seg6,
		SideConfig.new(null, false), SideConfig.new(refl6, true), false, false)

	var bounds: Array[Surface] = []
	for v4 in [Vector4(0, 0, 1920, 0), Vector4(1920, 0, 1920, 1080),
			Vector4(1920, 1080, 0, 1080), Vector4(0, 1080, 0, 0)]:
		var seg := Segment.from_coords(
			Vector2(v4.x, v4.y), Vector2(v4.z, v4.w),
			Vector2((v4.x + v4.z) / 2.0, (v4.y + v4.w) / 2.0))
		var config := SideConfig.new(null, false)
		bounds.append(Surface.new(seg, config, config, false, false))

	var surfaces: Array = [w_top, w_bot, w_left, mirror4, mirror5, mirror6]
	surfaces.append_array(bounds)
	return {"surfaces": surfaces, "mirror4": mirror4, "mirror5": mirror5,
		"mirror6": mirror6, "w_top": w_top, "w_left": w_left}


func test_A1_aim_point_at_corner() -> void:
	var d := _build_three_mirrors_surfaces()
	var surfaces: Array = d.surfaces
	var mirror4: Surface = d.mirror4
	var mirror5: Surface = d.mirror5

	var cursor := Vector2(1360, 240)
	var plan := [
		PlanManager.PlanEntry.new(mirror4.id, Side.Value.LEFT),
		PlanManager.PlanEntry.new(mirror5.id, Side.Value.LEFT)]

	var aim_point = Planner._compute_image(cursor, plan, surfaces, GameState.new())
	gut.p("A1 aim_point = %s" % str(aim_point))
	assert_not_null(aim_point, "aim_point should not be null")
	assert_almost_eq(aim_point, Vector2(560, 240), Vector2(0.01, 0.01),
		"aim_point should land at top-left corner (560, 240)")

	# Also verify single-mirror double plan
	var plan2 := [
		PlanManager.PlanEntry.new(mirror4.id, Side.Value.LEFT),
		PlanManager.PlanEntry.new(mirror4.id, Side.Value.LEFT)]
	var aim2 = Planner._compute_image(Vector2(560, 240), plan2, surfaces, GameState.new())
	gut.p("A1 double-same aim_point = %s (cursor was %s)" % [str(aim2), str(Vector2(560, 240))])
	assert_not_null(aim2, "double-same aim_point should not be null")
	# Double reflection through same mirror returns to original
	assert_almost_eq(aim2, Vector2(560, 240), Vector2(0.01, 0.01),
		"Double reflection through same mirror should return to original")


func test_A2_projective_sort_tiebreaking() -> void:
	var d := _build_three_mirrors_surfaces()
	var w_top: Surface = d.w_top
	var w_left: Surface = d.w_left

	var player := Vector2(570, 250)
	var aim_point := Vector2(560, 240)
	var dir := Direction.from_coords(player, aim_point)
	var ray := Ray.from_coords(player, dir)

	var all_hits := Intersection.find_all_hits(ray, [w_top.segment, w_left.segment])
	gut.p("A2 carrier hits count: %d" % all_hits.size())
	for i in all_hits.size():
		var h: Intersection.HitRecord = all_hits[i]
		gut.p("  hit[%d]: t=%.4f point=%s seg_null=%s on_seg=%s at_ep=%d bl=%s br=%s" % [
			i, h.t, h.point.coords, str(h.segment == null), str(h.on_segment),
			h.at_endpoint, str(h.blocked_left), str(h.blocked_right)])

	var cursor_t := Intersection.project_point_on_ray(ray, aim_point)
	gut.p("A2 cursor_t = %.4f" % cursor_t)
	var cursor_hp := Intersection.HitRecord.new(
		cursor_t, aim_point, null, Side.Value.LEFT, false)
	var origin_hp := Intersection.HitRecord.new(
		0.0, player, null, Side.Value.LEFT, false)

	var combined: Array = all_hits.duplicate()
	combined.append(cursor_hp)
	combined.append(origin_hp)
	var sorted := Intersection.projective_sort(combined)

	gut.p("A2 sorted order:")
	var cursor_idx := -1
	var wall_indices: Array = []
	for i in sorted.size():
		var h: Intersection.HitRecord = sorted[i]
		var label := "surface"
		if h == cursor_hp:
			label = "CURSOR"
			cursor_idx = i
		elif h == origin_hp:
			label = "ORIGIN"
		gut.p("  [%d] %s t=%.4f point=%s seg_null=%s bl=%s br=%s" % [
			i, label, h.t, h.point.coords, str(h.segment == null),
			str(h.blocked_left), str(h.blocked_right)])
		if h.segment != null and absf(h.t - cursor_t) < 0.001:
			wall_indices.append(i)

	assert_gt(cursor_idx, -1, "cursor should be found in sorted list")
	for wi in wall_indices:
		assert_gt(wi, cursor_idx,
			"Wall hit at same t should sort AFTER cursor (cursor_idx=%d, wall_idx=%d)" % [cursor_idx, wi])


func test_A3_endpoint_blocked_sides_at_corner() -> void:
	var w_top := RoomBuilder.create_block_surface(
		Vector2(560, 240), Vector2(1360, 240), Vector2(960, 240))
	var w_left := RoomBuilder.create_block_surface(
		Vector2(560, 840), Vector2(560, 240), Vector2(560, 540))

	var player := Vector2(570, 250)
	var corner := Vector2(560, 240)
	var dir := Direction.from_coords(player, corner)
	var ray := Ray.from_coords(player, dir)

	# Top wall: (560,240) is endpoint 1 (start)
	var top_blocked := Intersection.endpoint_blocked_sides(corner, w_top.segment, ray, 1)
	gut.p("A3 top wall blocked sides at endpoint 1: %s" % str(top_blocked))

	# Left wall: (560,240) is endpoint 2 (end)
	var left_blocked := Intersection.endpoint_blocked_sides(corner, w_left.segment, ray, 2)
	gut.p("A3 left wall blocked sides at endpoint 2: %s" % str(left_blocked))

	var combined_left: bool = top_blocked[0] or left_blocked[0]
	var combined_right: bool = top_blocked[1] or left_blocked[1]
	gut.p("A3 combined: left=%s right=%s fully_blocked=%s" % [
		str(combined_left), str(combined_right), str(combined_left and combined_right)])

	assert_false(top_blocked[0] and top_blocked[1],
		"Top wall alone should NOT be fully blocked at its endpoint")
	assert_false(left_blocked[0] and left_blocked[1],
		"Left wall alone should NOT be fully blocked at its endpoint")
	assert_true(combined_left and combined_right,
		"Combined blockage should be fully blocked")


func test_A4_trace_divergence_at_corner() -> void:
	var d := _build_three_mirrors_surfaces()
	var surfaces: Array = d.surfaces
	var mirror4: Surface = d.mirror4
	var mirror5: Surface = d.mirror5

	var player := Vector2(570, 250)
	var cursor := Vector2(1360, 240)
	var plan := [
		PlanManager.PlanEntry.new(mirror4.id, Side.Value.LEFT),
		PlanManager.PlanEntry.new(mirror5.id, Side.Value.LEFT)]

	var cache := TransformCache.new()
	var aim_dir := Planner.compute_aim_direction(
		player, cursor, plan, surfaces, GameState.new(), cache)
	var aim_point = Planner._compute_image(
		cursor, plan, surfaces, GameState.new())
	gut.p("A4 aim_dir zero_length=%s aim_point=%s" % [
		str(aim_dir.is_zero_length()), str(aim_point)])

	var trace_wp := Tracer.trace(player, aim_dir, surfaces, GameState.new(),
		null, -1.0, Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL,
		plan, null, cursor)
	var trace_np := Tracer.trace(player, aim_dir, surfaces, GameState.new(),
		null, -1.0, Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL,
		[], null, aim_point)

	gut.p("A4 with_plan: %d steps, cursor_index=%d" % [
		trace_wp.steps.size(), trace_wp.cursor_index])
	for i in mini(trace_wp.steps.size(), 10):
		var s: Tracer.Step = trace_wp.steps[i]
		gut.p("  wp[%d]: start=%s end=%s fid=%d zero=%s" % [
			i, s.start, s.end, s.frame_id, str(s.start == s.end)])

	gut.p("A4 no_plan: %d steps, cursor_index=%d" % [
		trace_np.steps.size(), trace_np.cursor_index])
	for i in mini(trace_np.steps.size(), 10):
		var s: Tracer.Step = trace_np.steps[i]
		gut.p("  np[%d]: start=%s end=%s fid=%d zero=%s" % [
			i, s.start, s.end, s.frame_id, str(s.start == s.end)])

	var geo_wp := InvariantChecker._extract_trace_geometry(trace_wp)
	var geo_np := InvariantChecker._extract_trace_geometry(trace_np)

	gut.p("A4 geometry: with_plan=%d segments, no_plan=%d segments" % [
		geo_wp.size(), geo_np.size()])
	for i in mini(geo_wp.size(), 5):
		gut.p("  wp_geo[%d]: start=%s end=%s" % [i, geo_wp[i].start, geo_wp[i].end])
	for i in mini(geo_np.size(), 5):
		gut.p("  np_geo[%d]: start=%s end=%s" % [i, geo_np[i].start, geo_np[i].end])

	if geo_wp.size() > 0 and geo_np.size() > 0:
		var end_match: float = geo_wp[0].end.distance_to(geo_np[0].end)
		gut.p("A4 segment 0 end distance: %.2f" % end_match)
		if end_match > 1.0:
			gut.p("A4 CONFIRMED: segment 0 ends diverge — with_plan ends at %s, no_plan ends at %s" % [
				geo_wp[0].end, geo_np[0].end])


# ─────────────────────────────────────────────────────────────────────────────
# PART B — Cursor reachability investigation (segment count mismatches)
# ─────────────────────────────────────────────────────────────────────────────

func test_B1_plan_matched_with_empty_plan() -> void:
	# Simulate the plan_matched logic from tracer.gd _apply_effect (lines 248-255)
	var plan_index := 0
	var plan_matched := true
	var cursor_injected := false
	var plan_entries: Array = []

	var cursor_reachable_before := not cursor_injected \
		and plan_index >= plan_entries.size() and plan_matched
	gut.p("B1 before reflection: plan_index=%d plan_matched=%s cursor_reachable=%s" % [
		plan_index, str(plan_matched), str(cursor_reachable_before)])
	assert_true(cursor_reachable_before,
		"cursor_reachable should be TRUE before any reflection with empty plan")

	# Simulate what _apply_effect does when a TRANSFORMATIVE effect is applied
	# with empty plan_entries (tracer.gd lines 248-255):
	if plan_index < plan_entries.size():
		gut.p("B1 plan_index < plan_entries.size() — would check surface match")
	else:
		plan_matched = false
		gut.p("B1 plan_index >= plan_entries.size() — set plan_matched = false")

	var cursor_reachable_after := not cursor_injected \
		and plan_index >= plan_entries.size() and plan_matched
	gut.p("B1 after reflection: plan_index=%d plan_matched=%s cursor_reachable=%s" % [
		plan_index, str(plan_matched), str(cursor_reachable_after)])
	assert_false(cursor_reachable_after,
		"cursor_reachable should be FALSE after reflection with empty plan")


func test_B2_cursor_index_divergence() -> void:
	# Use simple geometry: room + mirror, cursor NOT at a corner
	var w_top := RoomBuilder.create_block_surface(
		Vector2(0, 0), Vector2(1000, 0), Vector2(500, 0))
	var w_right := RoomBuilder.create_block_surface(
		Vector2(1000, 0), Vector2(1000, 600), Vector2(1000, 300))
	var w_bot := RoomBuilder.create_block_surface(
		Vector2(1000, 600), Vector2(0, 600), Vector2(500, 600))
	var w_left := RoomBuilder.create_block_surface(
		Vector2(0, 600), Vector2(0, 0), Vector2(0, 300))
	var mirror := H.mirror(400)

	var surfaces: Array = [w_top, w_right, w_bot, w_left, mirror]
	var bounds: Array = []
	for v4 in [Vector4(0, 0, 1920, 0), Vector4(1920, 0, 1920, 1080),
			Vector4(1920, 1080, 0, 1080), Vector4(0, 1080, 0, 0)]:
		var seg := Segment.from_coords(
			Vector2(v4.x, v4.y), Vector2(v4.z, v4.w),
			Vector2((v4.x + v4.z) / 2.0, (v4.y + v4.w) / 2.0))
		var config := SideConfig.new(null, false)
		bounds.append(Surface.new(seg, config, config, false, false))
	surfaces.append_array(bounds)

	var player := Vector2(200, 300)
	var cursor := Vector2(700, 200)
	var plan := [PlanManager.PlanEntry.new(mirror.id, Side.Value.LEFT)]

	var aim_point = Planner._compute_image(cursor, plan, surfaces, GameState.new())
	gut.p("B2 aim_point = %s" % str(aim_point))
	assert_not_null(aim_point)

	# Verify aim_point is NOT at any corner
	var corners := [Vector2(0, 0), Vector2(1000, 0), Vector2(0, 600), Vector2(1000, 600)]
	for c in corners:
		assert_gt(aim_point.distance_to(c), 10.0,
			"aim_point should not be at corner %s" % str(c))

	var cache := TransformCache.new()
	var aim_dir := Planner.compute_aim_direction(
		player, cursor, plan, surfaces, GameState.new(), cache)

	var trace_wp := Tracer.trace(player, aim_dir, surfaces, GameState.new(),
		null, -1.0, Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL,
		plan, null, cursor)
	var trace_np := Tracer.trace(player, aim_dir, surfaces, GameState.new(),
		null, -1.0, Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL,
		[], null, aim_point)

	gut.p("B2 with_plan: steps=%d cursor_index=%d" % [
		trace_wp.steps.size(), trace_wp.cursor_index])
	gut.p("B2 no_plan: steps=%d cursor_index=%d" % [
		trace_np.steps.size(), trace_np.cursor_index])

	var geo_wp := InvariantChecker._extract_trace_geometry(trace_wp)
	var geo_np := InvariantChecker._extract_trace_geometry(trace_np)
	gut.p("B2 geometry: with_plan=%d segments, no_plan=%d segments" % [
		geo_wp.size(), geo_np.size()])

	if trace_wp.cursor_index >= 0:
		gut.p("B2 CONFIRMED: with_plan has cursor_index=%d (cursor was injected)" % trace_wp.cursor_index)
	if trace_np.cursor_index == -1:
		gut.p("B2 CONFIRMED: no_plan has cursor_index=-1 (cursor was never injected)")


func test_B3_segment_count_divergence() -> void:
	# Reproduce the simplest segment count violation from violations.json:
	# player=(570, 540), cursor=(765, 540), plan=[surface4 LEFT]
	# scene: three_mirrors.tscn
	var d := _build_three_mirrors_surfaces()
	var surfaces: Array = d.surfaces
	var mirror4: Surface = d.mirror4

	var player := Vector2(570, 540)
	var cursor := Vector2(765, 540)
	var plan := [PlanManager.PlanEntry.new(mirror4.id, Side.Value.LEFT)]

	var cache := TransformCache.new()
	var aim_point = Planner._compute_image(cursor, plan, surfaces, GameState.new())
	var aim_dir := Planner.compute_aim_direction(
		player, cursor, plan, surfaces, GameState.new(), cache)
	gut.p("B3 aim_point=%s aim_dir_zero=%s" % [str(aim_point), str(aim_dir.is_zero_length())])

	var trace_wp := Tracer.trace(player, aim_dir, surfaces, GameState.new(),
		null, -1.0, Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL,
		plan, null, cursor)
	var trace_np := Tracer.trace(player, aim_dir, surfaces, GameState.new(),
		null, -1.0, Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL,
		[], null, aim_point)

	var geo_wp := InvariantChecker._extract_trace_geometry(trace_wp)
	var geo_np := InvariantChecker._extract_trace_geometry(trace_np)

	gut.p("B3 with_plan: steps=%d segments=%d cursor_index=%d" % [
		trace_wp.steps.size(), geo_wp.size(), trace_wp.cursor_index])
	gut.p("B3 no_plan: steps=%d segments=%d cursor_index=%d" % [
		trace_np.steps.size(), geo_np.size(), trace_np.cursor_index])

	# Dump last 15 steps of each trace to see where they diverge
	gut.p("B3 with_plan last steps:")
	var wp_start := maxi(0, trace_wp.steps.size() - 15)
	for i in range(wp_start, trace_wp.steps.size()):
		var s: Tracer.Step = trace_wp.steps[i]
		gut.p("  wp[%d]: start=%s end=%s fid=%d" % [i, s.start, s.end, s.frame_id])

	gut.p("B3 no_plan last steps:")
	var np_start := maxi(0, trace_np.steps.size() - 15)
	for i in range(np_start, trace_np.steps.size()):
		var s: Tracer.Step = trace_np.steps[i]
		gut.p("  np[%d]: start=%s end=%s fid=%d" % [i, s.start, s.end, s.frame_id])

	# Dump last few geometry segments to see where they diverge
	gut.p("B3 with_plan last 5 geo segments:")
	for i in range(maxi(0, geo_wp.size() - 5), geo_wp.size()):
		gut.p("  wp_geo[%d]: start=%s end=%s" % [i, geo_wp[i].start, geo_wp[i].end])
	gut.p("B3 no_plan last 5 geo segments:")
	for i in range(maxi(0, geo_np.size() - 5), geo_np.size()):
		gut.p("  np_geo[%d]: start=%s end=%s" % [i, geo_np[i].start, geo_np[i].end])

	# Report
	if geo_wp.size() != geo_np.size():
		gut.p("B3 CONFIRMED: segment count mismatch with_plan=%d no_plan=%d (diff=%d)" % [
			geo_wp.size(), geo_np.size(), geo_wp.size() - geo_np.size()])
	else:
		gut.p("B3 segment counts match — no divergence in this geometry")


# ─────────────────────────────────────────────────────────────────────────────
# ASSERTING TESTS — must FAIL before fixes, PASS after
# ─────────────────────────────────────────────────────────────────────────────

func test_A5_corner_blocks_with_zero_length() -> void:
	var d := _build_three_mirrors_surfaces()
	var surfaces: Array = d.surfaces
	var mirror4: Surface = d.mirror4
	var mirror5: Surface = d.mirror5

	var player := Vector2(570, 250)
	var cursor := Vector2(1360, 240)
	var plan := [
		PlanManager.PlanEntry.new(mirror4.id, Side.Value.LEFT),
		PlanManager.PlanEntry.new(mirror5.id, Side.Value.LEFT)]

	var cache := TransformCache.new()
	var aim_dir := Planner.compute_aim_direction(
		player, cursor, plan, surfaces, GameState.new(), cache)
	var aim_point = Planner._compute_image(
		cursor, plan, surfaces, GameState.new())

	var trace_wp := Tracer.trace(player, aim_dir, surfaces, GameState.new(),
		null, -1.0, Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL,
		plan, null, cursor)
	var trace_np := Tracer.trace(player, aim_dir, surfaces, GameState.new(),
		null, -1.0, Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL,
		[], null, aim_point)

	var geo_wp := InvariantChecker._extract_trace_geometry(trace_wp)
	var geo_np := InvariantChecker._extract_trace_geometry(trace_np)

	assert_eq(geo_wp.size(), geo_np.size(),
		"Corner: segment count must match (wp=%d np=%d)" % [geo_wp.size(), geo_np.size()])
	if geo_wp.size() > 0 and geo_np.size() > 0:
		var end_dist: float = geo_wp[0].end.distance_to(geo_np[0].end)
		assert_lt(end_dist, 1.0,
			"Corner: segment 0 end must match (dist=%.2f)" % end_dist)


func test_B4_collinear_stage_merge() -> void:
	var path := Tracer.TracedPath.new()
	# 3 collinear rightward steps with different frame_ids
	path.steps.append(Tracer.Step.new(
		Vector2(0, 100), Vector2(100, 100), 1))
	path.steps.append(Tracer.Step.new(
		Vector2(100, 100), Vector2(200, 100), 2))
	path.steps.append(Tracer.Step.new(
		Vector2(200, 100), Vector2(300, 100), 3))
	# 1 leftward step
	path.steps.append(Tracer.Step.new(
		Vector2(300, 100), Vector2(200, 100), 4))
	# 1 rightward step (not collinear with leftward)
	path.steps.append(Tracer.Step.new(
		Vector2(200, 100), Vector2(300, 100), 5))

	var geo := InvariantChecker._extract_trace_geometry(path)
	assert_eq(geo.size(), 3,
		"Collinear merge: 3 rightward + 1 leftward + 1 rightward = 3 stages (got %d)" % geo.size())
	if geo.size() >= 1:
		assert_eq(geo[0].start, Vector2(0, 100), "Stage 0 starts at (0, 100)")
		assert_eq(geo[0].end, Vector2(300, 100), "Stage 0 ends at (300, 100)")


func test_B5_max_hits_truncation_accepted() -> void:
	var d := _build_three_mirrors_surfaces()
	var surfaces: Array = d.surfaces
	var mirror4: Surface = d.mirror4

	var player := Vector2(570, 540)
	var cursor := Vector2(765, 540)
	var plan := [PlanManager.PlanEntry.new(mirror4.id, Side.Value.LEFT)]

	var cache := TransformCache.new()
	var aim_point = Planner._compute_image(cursor, plan, surfaces, GameState.new())
	var aim_dir := Planner.compute_aim_direction(
		player, cursor, plan, surfaces, GameState.new(), cache)

	var trace_wp := Tracer.trace(player, aim_dir, surfaces, GameState.new(),
		null, -1.0, Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL,
		plan, null, cursor)
	var trace_np := Tracer.trace(player, aim_dir, surfaces, GameState.new(),
		null, -1.0, Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL,
		[], null, aim_point)

	assert_eq(trace_wp.steps.size(), Tracer.MAX_HITS,
		"with_plan should hit MAX_HITS")
	assert_eq(trace_np.steps.size(), Tracer.MAX_HITS,
		"no_plan should hit MAX_HITS")

	var geo_wp := InvariantChecker._extract_trace_geometry(trace_wp)
	var geo_np := InvariantChecker._extract_trace_geometry(trace_np)

	# After collinear merge + lenient comparison, common segments should match
	var compare_count := mini(geo_wp.size(), geo_np.size())
	assert_gt(compare_count, 0, "Both traces should have geometry")
	var tol := 1.0
	var mismatches := 0
	for i in compare_count:
		var start_dist: float = geo_wp[i].start.distance_to(geo_np[i].start)
		var end_dist: float = geo_wp[i].end.distance_to(geo_np[i].end)
		if start_dist > tol or end_dist > tol:
			mismatches += 1
	assert_eq(mismatches, 0,
		"MAX_HITS truncation: common segments must match (mismatches=%d of %d)" % [
			mismatches, compare_count])
