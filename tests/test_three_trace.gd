extends GutTest

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

func _build_merged(player: Vector2, cursor: Vector2, surfaces: Array, plan_entries: Array = []) -> Array:
	var aim := Planner.compute_aim_direction(player, cursor, plan_entries, surfaces, GameState.new())
	var aim_ray := Ray.new(player, aim)
	var target_dist := player.distance_to(cursor)
	MobiusTransform.reset_id_counter()
	var physical := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, aim_ray, target_dist)
	MobiusTransform.reset_id_counter()
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, aim_ray, target_dist,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan_entries)
	var ci: int = planned.cursor_index
	if ci < 0:
		ci = planned.steps.size()
	return StepTreeMerge.merge(planned.steps, physical.steps, ci)

# --- Empty plan, mirror AFTER cursor → all green ---

func test_empty_plan_mirror_after_cursor() -> void:
	var m := _mirror(400)
	var w := _wall(100)
	var merged := _build_merged(Vector2(600, 300), Vector2(500, 300), [m, w])
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		assert_true(
			ms.type == StepTypes.Type.ALIGNED or ms.type == StepTypes.Type.ALIGNED_POST_PLANNED,
			"Step %d should be green (type=%d)" % [i, ms.type])

# --- Empty plan, mirror BEFORE cursor → divergence ---

func test_empty_plan_mirror_before_cursor() -> void:
	var m := _mirror(400)
	var w := _wall(700)
	var merged := _build_merged(Vector2(200, 300), Vector2(600, 300), [m, w])
	var has_diverged := false
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		if ms.type == StepTypes.Type.DIVERGED_PLANNED or ms.type == StepTypes.Type.DIVERGED_PHYSICAL:
			has_diverged = true
	assert_true(has_diverged, "Mirror before cursor should cause divergence")

# --- Plan matches physics → all green ---

func test_plan_matches_physics() -> void:
	var m := _mirror(400)
	var w := _wall(100)
	var plan: Array = [PlanManager.PlanEntry.new(m.id, Side.Value.LEFT)]
	var merged := _build_merged(Vector2(600, 300), Vector2(200, 300), [m, w], plan)
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		assert_true(
			ms.type == StepTypes.Type.ALIGNED or ms.type == StepTypes.Type.ALIGNED_POST_PLANNED,
			"Step %d should be green when plan matches (type=%d)" % [i, ms.type])

# --- Plan misses physics → divergence ---

func test_plan_misses_physics() -> void:
	var m := _mirror(400)
	var w := _wall(700)
	# Mirror between player and cursor, no plan → physical reflects, planned doesn't
	var merged := _build_merged(Vector2(200, 300), Vector2(600, 300), [m, w])
	var has_div_physical := false
	var has_div_planned := false
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		if ms.type == StepTypes.Type.DIVERGED_PHYSICAL:
			has_div_physical = true
		if ms.type == StepTypes.Type.DIVERGED_PLANNED:
			has_div_planned = true
	assert_true(has_div_physical, "Should have DIVERGED_PHYSICAL")
	assert_true(has_div_planned, "Should have DIVERGED_PLANNED")

# --- Wall blocks both → aligned ---

func test_wall_blocks_both() -> void:
	var w := _wall(400)
	var merged := _build_merged(Vector2(300, 300), Vector2(500, 300), [w])
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		assert_true(
			ms.type == StepTypes.Type.ALIGNED or ms.type == StepTypes.Type.ALIGNED_POST_PLANNED,
			"Step %d should be aligned when wall blocks both (type=%d)" % [i, ms.type])

# --- Physical reflects, never reaches cursor ---

func test_physical_diverges_before_cursor() -> void:
	# Mirror between player and cursor. Physical reflects away. Planned passes through.
	# Physical may never reach cursor.
	var m := _mirror(400)
	var w_right := _wall(700)
	var w_left := _wall(100)
	var merged := _build_merged(Vector2(300, 300), Vector2(600, 300), [m, w_right, w_left])
	# Should have ALIGNED up to mirror, then DIVERGED
	var first: StepTreeMerge.MergedStep = merged[0]
	assert_true(
		first.type == StepTypes.Type.ALIGNED or first.type == StepTypes.Type.ALIGNED_POST_PLANNED,
		"First step should be green")
	var has_div := false
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		if ms.type == StepTypes.Type.DIVERGED_PHYSICAL or ms.type == StepTypes.Type.DIVERGED_PLANNED:
			has_div = true
	assert_true(has_div, "Should have divergence")

# --- User bug repro ---

func test_user_bug_two_mirrors_empty_plan() -> void:
	var w_top := RoomBuilder.create_block_surface(Vector2(560, 240), Vector2(1360, 240), Vector2(960, 240))
	var w_bot := RoomBuilder.create_block_surface(Vector2(1360, 840), Vector2(560, 840), Vector2(960, 840))
	var w_left := RoomBuilder.create_block_surface(Vector2(560, 840), Vector2(560, 240), Vector2(560, 540))

	var m1_seg := Segment.new(Vector2(800, 300), Vector2(800, 780), Vector2(800, 540))
	var m1_refl := ReflectionEffect.new(m1_seg.get_carrier())
	var m1_left := SideConfig.new(m1_refl, true)
	var m1_right := SideConfig.new(null, false)
	var mirror1 := Surface.new(m1_seg, m1_left, m1_right, false, false)

	var m2_seg := Segment.new(Vector2(1200, 300), Vector2(1200, 780), Vector2(1200, 540))
	var m2_refl := ReflectionEffect.new(m2_seg.get_carrier())
	var m2_left := SideConfig.new(m2_refl, true)
	var m2_right := SideConfig.new(null, false)
	var mirror2 := Surface.new(m2_seg, m2_left, m2_right, false, false)

	var surfaces: Array = [w_top, w_bot, w_left, mirror1, mirror2]
	var merged := _build_merged(Vector2(1040.0, 827.9904), Vector2(914.9531, 708.3118), surfaces)

	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		assert_true(
			ms.type == StepTypes.Type.ALIGNED or ms.type == StepTypes.Type.ALIGNED_POST_PLANNED,
			"Step %d should be aligned (type=%d) — empty plan, no obstacle before cursor" % [i, ms.type])

# --- Green from player ---

func test_first_step_green() -> void:
	var m := _mirror(400)
	var w := _wall(700)
	var merged := _build_merged(Vector2(200, 300), Vector2(600, 300), [m, w])
	assert_gt(merged.size(), 0, "Should have steps")
	var first: StepTreeMerge.MergedStep = merged[0]
	assert_true(
		first.type == StepTypes.Type.ALIGNED or first.type == StepTypes.Type.ALIGNED_POST_PLANNED,
		"First step should be green (type=%d)" % first.type)
