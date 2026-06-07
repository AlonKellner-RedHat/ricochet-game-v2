extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()

func _wall(x: float) -> Surface:
	return RoomBuilder.create_block_surface(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))

func _mirror(x: float) -> Surface:
	var seg := Segment.new(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var config := SideConfig.new(refl, true)
	return Surface.new(seg, config, config, false, false)

func _step(path: Tracer.TracedPath, idx: int) -> Tracer.Step:
	return path.steps[idx]

# --- PLANNED mode with empty plan ---

func test_planned_empty_plan_no_effects() -> void:
	var m := _mirror(400)
	var w := _wall(700)
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(800, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, [m, w], GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray, 100.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [])
	# Pre-cursor: PLANNED mode, empty plan → no effects
	# Carrier hit at mirror → pass-through (not in plan)
	var first_fid: int = _step(path, 0).frame_id
	# Check pre-cursor steps have same frame (no effects)
	for i in range(0, mini(path.cursor_index, path.steps.size())):
		assert_eq(_step(path, i).frame_id, first_fid,
			"Pre-cursor step %d should have no effect (empty plan)" % i)

func test_planned_empty_plan_physical_after_cursor() -> void:
	# After cursor, mode switches to PHYSICAL → should reflect off mirror
	var m := _mirror(400)
	var w := _wall(100)
	var ray := Ray.new(Vector2(600, 300), Direction.new(Vector2(600, 300), Vector2(200, 300)))
	# Cursor at dist=100 (at x=500), mirror at x=400 (post-cursor)
	var path := Tracer.trace(ray.origin, ray.direction, [m, w], GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray, 100.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [])
	# Post-cursor should apply physical effects → mirror reflection
	var found_frame_change := false
	var cursor_fid: int = _step(path, 0).frame_id
	for i in range(path.cursor_index, path.steps.size()):
		if _step(path, i).frame_id != cursor_fid:
			found_frame_change = true
			break
	assert_true(found_frame_change, "Post-cursor PHYSICAL mode should reflect off mirror")

# --- PLANNED mode with plan entries ---

func test_planned_mirror_in_plan() -> void:
	var m := _mirror(400)
	var w := _wall(100)
	var plan: Array = [PlanManager.PlanEntry.new(m.id, Side.Value.LEFT)]
	var aim := Planner.compute_aim_direction(Vector2(600, 300), Vector2(200, 300), plan, [m, w], GameState.new())
	var ray := Ray.new(Vector2(600, 300), aim)
	var path := Tracer.trace(ray.origin, aim, [m, w], GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan)
	var found_frame_change := false
	var first_fid: int = _step(path, 0).frame_id
	for i in range(1, path.steps.size()):
		if _step(path, i).frame_id != first_fid:
			found_frame_change = true
			break
	assert_true(found_frame_change, "Mirror in plan should cause frame change")

func test_planned_mirror_not_in_plan_passthrough() -> void:
	var m := _mirror(400)
	var w := _wall(700)
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(800, 300)))
	# Mirror present but not in plan → carrier hit is pass-through pre-cursor
	var path := Tracer.trace(ray.origin, ray.direction, [m, w], GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [])
	# No cursor → all steps in initial mode (PLANNED). Mirror not in plan → no effects.
	var first_fid: int = _step(path, 0).frame_id
	for i in path.steps.size():
		assert_eq(_step(path, i).frame_id, first_fid,
			"Mirror not in plan should be pass-through at step %d" % i)

# --- Both modes produce same hitpoints pre-divergence ---

func test_hitpoint_alignment_no_effects() -> void:
	var w := _wall(600)
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(800, 300)))
	var physical := Tracer.trace(ray.origin, ray.direction, [w], GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray, 100.0)
	var planned := Tracer.trace(ray.origin, ray.direction, [w], GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray, 100.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [])
	assert_eq(physical.steps.size(), planned.steps.size(), "Same step count")
	for i in physical.steps.size():
		assert_eq(_step(physical, i).start, _step(planned, i).start, "Same start at %d" % i)
		assert_eq(_step(physical, i).end, _step(planned, i).end, "Same end at %d" % i)

# --- Plan entries consumed in order ---

func test_plan_entries_order() -> void:
	var m1 := _mirror(300)
	var m2 := _mirror(600)
	var plan: Array = [
		PlanManager.PlanEntry.new(m1.id, Side.Value.RIGHT),
		PlanManager.PlanEntry.new(m2.id, Side.Value.LEFT),
	]
	var ray := Ray.new(Vector2(450, 300), Direction.new(Vector2(450, 300), Vector2(200, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, [m1, m2], GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan)
	var frame_changes := 0
	for i in range(1, path.steps.size()):
		if _step(path, i).frame_id != _step(path, i - 1).frame_id:
			frame_changes += 1
	assert_gte(frame_changes, 2, "Two plan entries → at least 2 frame changes")

# --- Terminal stops both modes ---

func test_terminal_stops_planned() -> void:
	var w := _wall(400)
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(600, 300)))
	var physical := Tracer.trace(ray.origin, ray.direction, [w], GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray)
	var planned := Tracer.trace(ray.origin, ray.direction, [w], GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [])
	assert_eq(physical.steps.size(), planned.steps.size(), "Both stop at terminal wall")
