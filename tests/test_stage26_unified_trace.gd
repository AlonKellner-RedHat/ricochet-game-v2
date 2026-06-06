extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()

func _mirror(x: float) -> Surface:
	var seg := Segment.new(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var config := SideConfig.new(refl, true)
	return Surface.new(seg, config, config, false, false)

func _wall(x: float) -> Surface:
	return RoomBuilder.create_block_surface(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))

func _step(path: Tracer.TracedPath, idx: int) -> Tracer.Step:
	return path.steps[idx]

# --- PHYSICAL mode tests ---

func test_physical_empty_room() -> void:
	var w_left := _wall(100)
	var w_right := _wall(700)
	var w_top := RoomBuilder.create_block_surface(Vector2(100, 50), Vector2(700, 50), Vector2(400, 50))
	var w_bot := RoomBuilder.create_block_surface(Vector2(700, 550), Vector2(100, 550), Vector2(400, 550))
	var surfaces: Array = [w_left, w_right, w_top, w_bot]
	var ray := Ray.new(Vector2(400, 300), Direction.new(Vector2(400, 300), Vector2(700, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	assert_gte(path.steps.size(), 1, "Should have steps")
	for i in path.steps.size():
		var s := _step(path, i)
		assert_false(is_nan(s.start.x) or is_nan(s.end.x), "No NaN in step %d" % i)

func test_physical_mirror_on_path() -> void:
	var m := _mirror(500)
	var w := _wall(100)
	var ray := Ray.new(Vector2(700, 300), Direction.new(Vector2(700, 300), Vector2(300, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, [m, w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	var found_frame_change := false
	var first_fid: int = _step(path, 0).frame_id
	for i in range(1, path.steps.size()):
		if _step(path, i).frame_id != first_fid:
			found_frame_change = true
			break
	assert_true(found_frame_change, "Mirror should cause frame change in PHYSICAL mode")

func test_physical_carrier_off_segment_no_effect() -> void:
	var seg := Segment.new(Vector2(400, 100), Vector2(400, 200), Vector2(400, 150))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var cfg := SideConfig.new(refl, true)
	var mirror := Surface.new(seg, cfg, cfg, false, false)
	var w := _wall(700)
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(800, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, [mirror, w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	var first_fid: int = _step(path, 0).frame_id
	for i in path.steps.size():
		assert_eq(_step(path, i).frame_id, first_fid, "No frame change for off-segment carrier hit at step %d" % i)

# --- PLANNED mode tests ---

func test_planned_mirror_in_plan() -> void:
	var m := _mirror(400)
	var w := _wall(700)
	var plan: Array = [PlanManager.PlanEntry.new(m.id, Side.Value.LEFT)]
	var aim := Planner.compute_aim_direction(Vector2(200, 300), Vector2(600, 300), plan, [m, w], GameState.new())
	var ray := Ray.new(Vector2(200, 300), aim)
	var path := Tracer.trace(ray.origin, aim, [m, w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray, -1.0, Tracer.TraceMode.PLANNED, plan)
	var found_frame_change := false
	var first_fid: int = _step(path, 0).frame_id
	for i in range(1, path.steps.size()):
		if _step(path, i).frame_id != first_fid:
			found_frame_change = true
			break
	assert_true(found_frame_change, "Mirror in plan should cause frame change in PLANNED mode")

func test_planned_mirror_not_in_plan() -> void:
	var m := _mirror(400)
	var w := _wall(700)
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(800, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, [m, w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray, -1.0, Tracer.TraceMode.PLANNED, [])
	var first_fid: int = _step(path, 0).frame_id
	for i in path.steps.size():
		assert_eq(_step(path, i).frame_id, first_fid, "No frame change when mirror not in plan at step %d" % i)

# --- Hitpoint alignment tests ---

func test_hitpoint_alignment_no_effects() -> void:
	var w := _wall(600)
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(800, 300)))
	var physical := Tracer.trace(ray.origin, ray.direction, [w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	var planned := Tracer.trace(ray.origin, ray.direction, [w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray, -1.0, Tracer.TraceMode.PLANNED, [])
	assert_eq(physical.steps.size(), planned.steps.size(), "Same step count")
	for i in physical.steps.size():
		var p := _step(physical, i)
		var r := _step(planned, i)
		assert_eq(p.start, r.start, "Same start at step %d" % i)
		assert_eq(p.end, r.end, "Same end at step %d" % i)
		assert_eq(p.frame_id, r.frame_id, "Same frame at step %d" % i)

func test_hitpoint_alignment_both_apply_effect() -> void:
	var m := _mirror(400)
	var w := _wall(100)
	var plan: Array = [PlanManager.PlanEntry.new(m.id, Side.Value.LEFT)]
	var aim := Planner.compute_aim_direction(Vector2(600, 300), Vector2(200, 300), plan, [m, w], GameState.new())
	var ray := Ray.new(Vector2(600, 300), aim)
	var physical := Tracer.trace(ray.origin, aim, [m, w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	var planned := Tracer.trace(ray.origin, aim, [m, w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray, -1.0, Tracer.TraceMode.PLANNED, plan)
	var min_steps := mini(physical.steps.size(), planned.steps.size())
	assert_gte(min_steps, 2, "Should have at least 2 steps")
	for i in min_steps:
		var p := _step(physical, i)
		var r := _step(planned, i)
		if p.frame_id != r.frame_id:
			break
		assert_eq(p.start, r.start, "Same start at step %d" % i)
		assert_eq(p.end, r.end, "Same end at step %d" % i)

# --- Divergence tests ---

func test_divergence_physical_reflects_planned_doesnt() -> void:
	var m := _mirror(400)
	var w := _wall(700)
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(600, 300)))
	var physical := Tracer.trace(ray.origin, ray.direction, [m, w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	var planned := Tracer.trace(ray.origin, ray.direction, [m, w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray, -1.0, Tracer.TraceMode.PLANNED, [])
	var p0 := _step(physical, 0)
	var r0 := _step(planned, 0)
	assert_eq(p0.frame_id, r0.frame_id, "Step 0 same frame")
	assert_eq(p0.start, r0.start, "Step 0 same start")
	assert_eq(p0.end, r0.end, "Step 0 same end")
	assert_gte(physical.steps.size(), 2, "Physical should have post-mirror steps")
	assert_gte(planned.steps.size(), 2, "Planned should have post-mirror steps")
	assert_ne(_step(physical, 1).frame_id, _step(planned, 1).frame_id, "Step 1 frames diverge")

func test_divergence_planned_applies_physical_doesnt() -> void:
	var seg := Segment.new(Vector2(400, 100), Vector2(400, 200), Vector2(400, 150))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var cfg := SideConfig.new(refl, true)
	var mirror := Surface.new(seg, cfg, cfg, false, false)
	var w := _wall(700)
	var plan: Array = [PlanManager.PlanEntry.new(mirror.id, Side.Value.LEFT)]
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(800, 300)))
	var physical := Tracer.trace(ray.origin, ray.direction, [mirror, w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	var planned := Tracer.trace(ray.origin, ray.direction, [mirror, w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray, -1.0, Tracer.TraceMode.PLANNED, plan)
	assert_eq(_step(physical, 0).frame_id, _step(planned, 0).frame_id, "Step 0 same frame")
	assert_gte(physical.steps.size(), 2, "Physical should have post-carrier steps")
	assert_gte(planned.steps.size(), 2, "Planned should have post-carrier steps")
	assert_ne(_step(physical, 1).frame_id, _step(planned, 1).frame_id, "Step 1 frames diverge")

# --- cursor_index tests ---

func test_cursor_index_set() -> void:
	var w := _wall(600)
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(800, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, [w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray, 200.0)
	assert_gt(path.cursor_index, 0, "cursor_index should be set (>0)")
	assert_lte(path.cursor_index, path.steps.size(), "cursor_index should be <= step count")

func test_cursor_index_match_pre_divergence() -> void:
	var w := _wall(600)
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(800, 300)))
	var physical := Tracer.trace(ray.origin, ray.direction, [w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray, 200.0)
	var planned := Tracer.trace(ray.origin, ray.direction, [w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray, 200.0, Tracer.TraceMode.PLANNED, [])
	assert_eq(physical.cursor_index, planned.cursor_index, "Same cursor_index when no divergence")

func test_virtual_hitpoint_works() -> void:
	var w := _wall(600)
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(800, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, [w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray, 100.0)
	assert_gte(path.steps.size(), 2, "Should have cursor step + post-cursor step")
	assert_eq(path.cursor_index, 1, "Cursor at step 1 (first post-cursor)")
	var cursor_step := _step(path, 0)
	assert_almost_eq(cursor_step.start.distance_to(cursor_step.end), 100.0, 1.0, "Cursor step length ~= target_dist")

# --- Multiple bounce + plan order tests ---

func test_multiple_bounces_physical() -> void:
	var m1 := _mirror(300)
	var m2 := _mirror(600)
	var ray := Ray.new(Vector2(450, 300), Direction.new(Vector2(450, 300), Vector2(200, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, [m1, m2], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	assert_gte(path.steps.size(), 3, "Should bounce between mirrors multiple times")

func test_plan_entries_consumed_in_order() -> void:
	var m1 := _mirror(300)
	var m2 := _mirror(600)
	var plan: Array = [
		PlanManager.PlanEntry.new(m1.id, Side.Value.RIGHT),
		PlanManager.PlanEntry.new(m2.id, Side.Value.LEFT),
	]
	var ray := Ray.new(Vector2(450, 300), Direction.new(Vector2(450, 300), Vector2(200, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, [m1, m2], GameState.new(), Tracer.DEFAULT_BOUNDS, ray, -1.0, Tracer.TraceMode.PLANNED, plan)
	var frame_changes := 0
	for i in range(1, path.steps.size()):
		if _step(path, i).frame_id != _step(path, i - 1).frame_id:
			frame_changes += 1
	assert_gte(frame_changes, 2, "Should have at least 2 frame changes for 2 plan entries")

func test_all_steps_share_ray() -> void:
	var m := _mirror(400)
	var w := _wall(100)
	var ray := Ray.new(Vector2(600, 300), Direction.new(Vector2(600, 300), Vector2(200, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, [m, w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	for i in path.steps.size():
		assert_eq(_step(path, i).ray, ray, "Step %d should share the same Ray reference" % i)
