extends GutTest
## Tests for the three-trace model: planned + post-planned + physical.

func before_each() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()

func _mirror(x: float, y_start: float = 0.0, y_end: float = 600.0) -> Surface:
	var mid_y := (y_start + y_end) / 2.0
	var seg := Segment.new(Vector2(x, y_start), Vector2(x, y_end), Vector2(x, mid_y))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var config := SideConfig.new(refl, true)
	return Surface.new(seg, config, config, false, false)

func _wall(x: float) -> Surface:
	return RoomBuilder.create_block_surface(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))

func _step(path: Tracer.TracedPath, idx: int) -> Tracer.Step:
	return path.steps[idx]

func _build_three_trace(player: Vector2, cursor: Vector2, surfaces: Array, plan_entries: Array = []) -> Dictionary:
	var aim := Planner.compute_aim_direction(player, cursor, plan_entries, surfaces, GameState.new())
	var aim_ray := Ray.new(player, aim)
	var target_dist := player.distance_to(cursor)
	var bounds := Tracer.DEFAULT_BOUNDS

	var physical := Tracer.trace(player, aim, surfaces, GameState.new(), bounds, aim_ray, target_dist, Tracer.TraceMode.PHYSICAL)

	var planned_full := Tracer.trace(player, aim, surfaces, GameState.new(), bounds, aim_ray, target_dist, Tracer.TraceMode.PLANNED, plan_entries)

	var ci: int = planned_full.cursor_index
	var cursor_reached: bool = ci >= 0
	if not cursor_reached:
		ci = planned_full.steps.size()
	var combined: Array = planned_full.steps.slice(0, ci)

	if cursor_reached and ci > 0 and ci <= planned_full.steps.size():
		var last: Tracer.Step = combined[ci - 1]
		var post := Tracer.trace(last.end, aim, surfaces, GameState.new(), bounds, aim_ray, -1.0, Tracer.TraceMode.PHYSICAL, [], last.frame)
		for i in post.steps.size():
			combined.append(post.steps[i])

	var merged := StepTreeMerge.merge(combined, physical.steps, ci)
	return {"physical": physical, "combined": combined, "merged": merged, "cursor_index": ci}

# --- T1: Empty plan, mirror AFTER cursor → fully aligned ---

func test_empty_plan_mirror_after_cursor_aligned() -> void:
	var m := _mirror(400)
	var w := _wall(100)
	# Player at 600, cursor at 500 — cursor is between player and mirror
	var result := _build_three_trace(Vector2(600, 300), Vector2(500, 300), [m, w])
	var merged: Array = result.merged
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		assert_true(
			ms.type == StepTypes.Type.ALIGNED or ms.type == StepTypes.Type.ALIGNED_POST_PLANNED,
			"Step %d should be aligned (type=%d)" % [i, ms.type])

# --- T2: Empty plan, mirror BEFORE cursor → divergence at mirror ---

func test_empty_plan_mirror_before_cursor_diverges() -> void:
	var m := _mirror(400)
	var w := _wall(700)
	# Player at 200, cursor at 600 — mirror at 400 is between them
	var result := _build_three_trace(Vector2(200, 300), Vector2(600, 300), [m, w])
	var merged: Array = result.merged
	var has_diverged := false
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		if ms.type == StepTypes.Type.DIVERGED_PLANNED or ms.type == StepTypes.Type.DIVERGED_PHYSICAL:
			has_diverged = true
	assert_true(has_diverged, "Should have divergence when mirror is between player and cursor")

# --- T3: Plan with mirror, post-planned continues in planned frame → aligned post-cursor ---

func test_plan_with_mirror_post_planned_aligned() -> void:
	var m := _mirror(400)
	var w := _wall(100)
	var plan: Array = [PlanManager.PlanEntry.new(m.id, Side.Value.LEFT)]
	# Player at 600, cursor at 500 — mirror at 400, cursor between player and mirror
	# Plan says reflect off mirror → both planned and physical reflect → aligned
	var result := _build_three_trace(Vector2(600, 300), Vector2(500, 300), [m, w], plan)
	var merged: Array = result.merged
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		assert_true(
			ms.type == StepTypes.Type.ALIGNED or ms.type == StepTypes.Type.ALIGNED_POST_PLANNED,
			"Step %d should be aligned when plan matches physics (type=%d)" % [i, ms.type])

# --- T5: Wall blocks before cursor → no post-planned, fully aligned ---

func test_wall_blocks_before_cursor() -> void:
	var w := _wall(400)
	# Player at 300, cursor at 500 — wall at 400 blocks both
	var result := _build_three_trace(Vector2(300, 300), Vector2(500, 300), [w])
	var merged: Array = result.merged
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		assert_true(
			ms.type == StepTypes.Type.ALIGNED or ms.type == StepTypes.Type.ALIGNED_POST_PLANNED,
			"Step %d should be aligned when wall blocks both (type=%d)" % [i, ms.type])

# --- T6: initial_frame starts trace correctly ---

func test_initial_frame_normalizes_origin() -> void:
	var w := _wall(600)
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(800, 300)))
	# Trace with identity frame
	var path_id := Tracer.trace(Vector2(200, 300), ray.direction, [w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	# Trace with identity as explicit initial_frame — should produce same result
	var identity := MobiusTransform.identity()
	var path_if := Tracer.trace(Vector2(200, 300), ray.direction, [w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray, -1.0, Tracer.TraceMode.PHYSICAL, [], identity)
	assert_eq(path_id.steps.size(), path_if.steps.size(), "Same step count with explicit identity frame")
	for i in path_id.steps.size():
		var a := _step(path_id, i)
		var b := _step(path_if, i)
		assert_eq(a.start, b.start, "Same start at step %d" % i)
		assert_eq(a.end, b.end, "Same end at step %d" % i)

# --- T7: Reproduce exact user bug ---

func test_repro_user_bug_two_mirrors_empty_plan() -> void:
	# Exact setup from user's F12 debug state
	var w_top := RoomBuilder.create_block_surface(Vector2(560, 240), Vector2(1360, 240), Vector2(960, 240))
	var w_bot := RoomBuilder.create_block_surface(Vector2(1360, 840), Vector2(560, 840), Vector2(960, 840))
	var w_left := RoomBuilder.create_block_surface(Vector2(560, 840), Vector2(560, 240), Vector2(560, 540))

	var m1_seg := Segment.new(Vector2(800, 300), Vector2(800, 780), Vector2(800, 540))
	var m1_carrier := m1_seg.get_carrier()
	var m1_refl := ReflectionEffect.new(m1_carrier)
	var m1_left := SideConfig.new(m1_refl, true)
	var m1_right := SideConfig.new(null, false)
	var mirror1 := Surface.new(m1_seg, m1_left, m1_right, false, false)

	var m2_seg := Segment.new(Vector2(1200, 300), Vector2(1200, 780), Vector2(1200, 540))
	var m2_carrier := m2_seg.get_carrier()
	var m2_refl := ReflectionEffect.new(m2_carrier)
	var m2_left := SideConfig.new(m2_refl, true)
	var m2_right := SideConfig.new(null, false)
	var mirror2 := Surface.new(m2_seg, m2_left, m2_right, false, false)

	var surfaces: Array = [w_top, w_bot, w_left, mirror1, mirror2]
	var player := Vector2(1040.0, 827.9904)
	var cursor := Vector2(914.9531, 708.3118)

	var result := _build_three_trace(player, cursor, surfaces)
	var merged: Array = result.merged

	gut.p("=== Merged: %d steps ===" % merged.size())
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		gut.p("  [%d] type=%d (%s) %s → %s" % [
			i, ms.type,
			["ALIGNED","POST_PLANNED","DIV_PHYS","DIV_PLAN","DIV_POST"][ms.type],
			ms.start, ms.end])

	# With empty plan and no surfaces between player and cursor:
	# All steps should be ALIGNED or ALIGNED_POST_PLANNED
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		assert_true(
			ms.type == StepTypes.Type.ALIGNED or ms.type == StepTypes.Type.ALIGNED_POST_PLANNED,
			"Step %d should be aligned (type=%d), not diverged" % [i, ms.type])
