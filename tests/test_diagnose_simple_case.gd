extends GutTest

func test_simple_no_plan_no_obstacle() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()

	var w_top := RoomBuilder.create_block_surface(Vector2(560, 240), Vector2(1360, 240), Vector2(960, 240))
	var surfaces: Array[Surface] = [w_top]

	var player := Vector2(960.0, 827.9623)
	var cursor := Vector2(963.0031, 462.8572)
	var target_dist: float = player.distance_to(cursor)
	var aim_dir := Direction.new(player, cursor)
	var aim_ray := Ray.new(player, aim_dir)
	var bounds := Tracer.DEFAULT_BOUNDS

	# Three-trace model
	var physical := Tracer.trace(player, aim_dir, surfaces, GameState.new(), bounds, aim_ray, target_dist, Tracer.TraceMode.PHYSICAL)
	var planned_full := Tracer.trace(player, aim_dir, surfaces, GameState.new(), bounds, aim_ray, target_dist, Tracer.TraceMode.PLANNED, [])

	var ci: int = planned_full.cursor_index
	var cursor_reached: bool = ci >= 0
	if not cursor_reached:
		ci = planned_full.steps.size()
	var combined: Array = planned_full.steps.slice(0, ci)
	if cursor_reached and ci > 0 and ci <= planned_full.steps.size():
		var last: Tracer.Step = combined[ci - 1]
		var post := Tracer.trace(last.end, aim_dir, surfaces, GameState.new(), bounds, aim_ray, -1.0, Tracer.TraceMode.PHYSICAL, [], last.frame)
		for i in post.steps.size():
			combined.append(post.steps[i])

	gut.p("=== Physical: %d steps, cursor_index=%d ===" % [physical.steps.size(), physical.cursor_index])
	gut.p("=== Combined: %d steps, cursor_index=%d ===" % [combined.size(), ci])

	var merged := StepTreeMerge.merge(combined, physical.steps, ci)

	var has_post_planned := false
	var has_div_physical := false
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		if ms.type == StepTypes.Type.ALIGNED_POST_PLANNED:
			has_post_planned = true
		if ms.type == StepTypes.Type.DIVERGED_PHYSICAL:
			has_div_physical = true

	assert_true(has_post_planned, "Should have ALIGNED_POST_PLANNED for post-cursor")
	assert_false(has_div_physical, "Should NOT have DIVERGED_PHYSICAL in simple case")
