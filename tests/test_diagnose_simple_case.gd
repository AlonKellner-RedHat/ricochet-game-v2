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
	var identity_frame := MobiusTransform.identity()

	# Physical trace with target
	var physical := Tracer.trace(player, aim_dir, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, aim_ray, target_dist)
	gut.p("=== Physical trace: %d steps ===" % physical.steps.size())
	for i in physical.steps.size():
		var s: Tracer.Step = physical.steps[i]
		gut.p("  [%d] %s → %s  ray=%d frame=%d hit=%s" % [
			i, s.start, s.end, s.ray.get_instance_id(), s.frame_id,
			"yes" if s.hit != null else "no"])

	# Planned steps (no plan = synthetic player→cursor)
	var planned_steps: Array = [Tracer.Step.new(player, cursor, MobiusTransform.IDENTITY_ID, null, aim_ray, identity_frame)]
	gut.p("=== Pre-cursor planned: %d steps ===" % planned_steps.size())
	for i in planned_steps.size():
		var s: Tracer.Step = planned_steps[i]
		gut.p("  [%d] %s → %s  ray=%d frame=%d" % [
			i, s.start, s.end, s.ray.get_instance_id(), s.frame_id])

	var cursor_index: int = planned_steps.size()

	# Post-cursor trace — use aim_ray as provenance (same ray identity as physical trace)
	var last_planned: Tracer.Step = planned_steps[planned_steps.size() - 1]
	var post_start: Vector2 = last_planned.end
	gut.p("=== Post-cursor: start=%s, aim_ray=%d ===" % [post_start, aim_ray.get_instance_id()])

	var post_trace := Tracer.trace(post_start, last_planned.ray.direction, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, aim_ray)
	gut.p("=== Post-cursor trace: %d steps ===" % post_trace.steps.size())
	for i in post_trace.steps.size():
		var s: Tracer.Step = post_trace.steps[i]
		gut.p("  [%d] %s → %s  ray=%d frame=%d" % [
			i, s.start, s.end, s.ray.get_instance_id(), s.frame_id])

	for i in post_trace.steps.size():
		planned_steps.append(post_trace.steps[i])

	gut.p("=== Full planned: %d steps (cursor_index=%d) ===" % [planned_steps.size(), cursor_index])
	for i in planned_steps.size():
		var s: Tracer.Step = planned_steps[i]
		gut.p("  [%d] %s → %s  ray=%d frame=%d" % [
			i, s.start, s.end, s.ray.get_instance_id(), s.frame_id])

	# Now compare step by step
	gut.p("=== Step-by-step comparison ===")
	var max_idx: int = maxi(planned_steps.size(), physical.steps.size())
	for idx in max_idx:
		var p: Tracer.Step = planned_steps[idx] if idx < planned_steps.size() else null
		var r: Tracer.Step = physical.steps[idx] if idx < physical.steps.size() else null
		if p != null and r != null:
			gut.p("  [%d] same_ray=%s same_frame=%s same_start=%s same_end=%s" % [
				idx,
				p.ray == r.ray,
				p.frame_id == r.frame_id,
				p.start == r.start,
				p.end == r.end])
			if p.ray != r.ray:
				gut.p("       ray_p=%d ray_r=%d" % [p.ray.get_instance_id(), r.ray.get_instance_id()])
			if p.start != r.start:
				gut.p("       start_p=%s start_r=%s dist=%f" % [p.start, r.start, p.start.distance_to(r.start)])
			if p.end != r.end:
				gut.p("       end_p=%s end_r=%s dist=%f" % [p.end, r.end, p.end.distance_to(r.end)])

	# Merge
	var merged := StepTreeMerge.merge(planned_steps, physical.steps, cursor_index)
	gut.p("=== Merged: %d steps ===" % merged.size())
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		gut.p("  [%d] type=%d (%s) %s → %s" % [
			i, ms.type,
			["ALIGNED","POST_PLANNED","DIV_PHYS","DIV_PLAN","DIV_POST"][ms.type],
			ms.start, ms.end])

	# Assert expected behavior
	var has_post_planned := false
	var has_div_physical := false
	for i in merged.size():
		if merged[i].type == StepTypes.Type.ALIGNED_POST_PLANNED:
			has_post_planned = true
		if merged[i].type == StepTypes.Type.DIVERGED_PHYSICAL:
			has_div_physical = true

	assert_true(has_post_planned, "Should have ALIGNED_POST_PLANNED for post-cursor")
	assert_false(has_div_physical, "Should NOT have DIVERGED_PHYSICAL in simple case")
