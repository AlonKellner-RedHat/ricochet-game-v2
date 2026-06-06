extends GutTest

func test_divergence_room_mirror_between() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()

	var mirror_seg := Segment.new(Vector2(960, 240), Vector2(960, 840), Vector2(960, 540))
	var carrier := mirror_seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var config := SideConfig.new(refl, true)
	var mirror := Surface.new(mirror_seg, config, config, false, false)

	var w_right := RoomBuilder.create_block_surface(Vector2(1360, 240), Vector2(1360, 840), Vector2(1360, 540))
	var w_left := RoomBuilder.create_block_surface(Vector2(560, 240), Vector2(560, 840), Vector2(560, 540))
	var w_top := RoomBuilder.create_block_surface(Vector2(560, 240), Vector2(1360, 240), Vector2(960, 240))
	var w_bot := RoomBuilder.create_block_surface(Vector2(1360, 840), Vector2(560, 840), Vector2(960, 840))

	var surfaces: Array[Surface] = [mirror, w_right, w_left, w_top, w_bot]

	var player := Vector2(570, 250)
	var cursor := Vector2(1155, 250)
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

	gut.p("=== Physical: %d steps ===" % physical.steps.size())
	for i in physical.steps.size():
		var s: Tracer.Step = physical.steps[i]
		gut.p("  [%d] %s → %s  frame=%d" % [i, s.start, s.end, s.frame_id])

	gut.p("=== Combined (planned+post): %d steps, cursor_index=%d ===" % [combined.size(), ci])
	for i in combined.size():
		var s: Tracer.Step = combined[i]
		gut.p("  [%d] %s → %s  frame=%d" % [i, s.start, s.end, s.frame_id])

	var merged := StepTreeMerge.merge(combined, physical.steps, ci)
	gut.p("=== Merged: %d steps ===" % merged.size())
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		gut.p("  [%d] type=%d (%s) %s → %s" % [
			i, ms.type,
			["ALIGNED","POST_PLANNED","DIV_PHYS","DIV_PLAN","DIV_POST"][ms.type],
			ms.start, ms.end])

	pass_test("Diagnostic only")
