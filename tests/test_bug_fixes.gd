extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()

func _wall(x: float) -> Surface:
	return RoomBuilder.create_block_surface(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))

func _hwall(y: float) -> Surface:
	return RoomBuilder.create_block_surface(Vector2(0, y), Vector2(1200, y), Vector2(600, y))

func _mirror(x: float, y_start: float = 0.0, y_end: float = 600.0) -> Surface:
	var mid := (y_start + y_end) / 2.0
	var seg := Segment.new(Vector2(x, y_start), Vector2(x, y_end), Vector2(x, mid))
	var refl := ReflectionEffect.new(seg.get_carrier())
	var config := SideConfig.new(refl, true)
	return Surface.new(seg, config, config, false, false)

func _step(path: Tracer.TracedPath, idx: int) -> Tracer.Step:
	return path.steps[idx]

func _setup_scene() -> Array:
	var w_top := RoomBuilder.create_block_surface(Vector2(560, 240), Vector2(1360, 240), Vector2(960, 240))
	var w_bot := RoomBuilder.create_block_surface(Vector2(1360, 840), Vector2(560, 840), Vector2(960, 840))
	var w_left := RoomBuilder.create_block_surface(Vector2(560, 840), Vector2(560, 240), Vector2(560, 540))
	var m1_seg := Segment.new(Vector2(800, 300), Vector2(800, 780), Vector2(800, 540))
	var m1_refl := ReflectionEffect.new(m1_seg.get_carrier())
	var m1 := Surface.new(m1_seg, SideConfig.new(m1_refl, true), SideConfig.new(null, false), false, false)
	var m2_seg := Segment.new(Vector2(1200, 300), Vector2(1200, 780), Vector2(1200, 540))
	var m2_refl := ReflectionEffect.new(m2_seg.get_carrier())
	var m2 := Surface.new(m2_seg, SideConfig.new(m2_refl, true), SideConfig.new(null, false), false, false)
	return [w_top, w_bot, w_left, m1, m2]

# --- Fix 1: PLANNED mode ignores terminal walls ---

func test_wall_doesnt_stop_planned() -> void:
	var w := _hwall(400)
	var ray := Ray.new(Vector2(600, 500), Direction.new(Vector2(600, 500), Vector2(600, 200)))
	var path := Tracer.trace(ray.origin, ray.direction, [w], GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray, 200.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [], Vector2(600, 200))
	assert_gt(path.cursor_index, 0, "Planned trace should reach cursor through wall")

func test_terminal_stops_physical() -> void:
	var w := _hwall(400)
	var ray := Ray.new(Vector2(600, 500), Direction.new(Vector2(600, 500), Vector2(600, 200)))
	var path := Tracer.trace(ray.origin, ray.direction, [w], GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray, 200.0)
	assert_eq(path.cursor_index, -1, "Physical trace should stop at wall before cursor")

# --- Fix 2: Cursor at actual position ---

func test_cursor_at_actual_position_after_reflection() -> void:
	var m := _mirror(400)
	var w := _wall(100)
	var plan: Array = [PlanManager.PlanEntry.new(m.id, Side.Value.LEFT)]
	var player := Vector2(600, 300)
	var cursor := Vector2(300, 250)
	var aim := Planner.compute_aim_direction(player, cursor, plan, [m, w], GameState.new())
	var ray := Ray.new(player, aim)
	var target_dist := player.distance_to(cursor)
	MobiusTransform.reset_id_counter()
	var path := Tracer.trace(player, aim, [m, w], GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray, target_dist,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan, cursor)
	assert_gt(path.cursor_index, 0, "Should reach cursor")
	var cs := _step(path, path.cursor_index - 1)
	assert_almost_eq(cs.end.x, cursor.x, 2.0, "Cursor step should end at actual cursor x")
	assert_almost_eq(cs.end.y, cursor.y, 2.0, "Cursor step should end at actual cursor y")

func test_cursor_at_actual_position_off_segment() -> void:
	# Mirror segment y=[100,200], ray at y=300 — off-segment carrier hit
	var seg := Segment.new(Vector2(400, 100), Vector2(400, 200), Vector2(400, 150))
	var refl := ReflectionEffect.new(seg.get_carrier())
	var m := Surface.new(seg, SideConfig.new(refl, true), SideConfig.new(refl, true), false, false)
	var w := _wall(100)
	var plan: Array = [PlanManager.PlanEntry.new(m.id, Side.Value.LEFT)]
	var player := Vector2(600, 300)
	var cursor := Vector2(300, 300)
	var aim := Planner.compute_aim_direction(player, cursor, plan, [m, w], GameState.new())
	var ray := Ray.new(player, aim)
	var target_dist := player.distance_to(cursor)
	MobiusTransform.reset_id_counter()
	var path := Tracer.trace(player, aim, [m, w], GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray, target_dist,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan, cursor)
	assert_gt(path.cursor_index, 0, "Should reach cursor")
	var cs := _step(path, path.cursor_index - 1)
	assert_almost_eq(cs.end.x, cursor.x, 2.0, "Cursor end x = actual cursor")
	assert_almost_eq(cs.end.y, cursor.y, 2.0, "Cursor end y = actual cursor")

# --- Merged: solid path reaches cursor ---

func test_solid_path_reaches_cursor_wall_case() -> void:
	var surfaces := _setup_scene()
	var player := Vector2(960.0, 827.9623)
	var cursor := Vector2(968.0083, 153.2839)
	var aim := Planner.compute_aim_direction(player, cursor, [], surfaces, GameState.new())
	var aim_ray := Ray.new(player, aim)
	var td := player.distance_to(cursor)
	MobiusTransform.reset_id_counter()
	var physical := Tracer.trace(player, aim, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, aim_ray, td,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, [], cursor)
	MobiusTransform.reset_id_counter()
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, aim_ray, td,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [], cursor)
	var ci: int = planned.cursor_index
	if ci < 0:
		ci = planned.steps.size()
	var merged := StepTreeMerge.merge(planned.steps, physical.steps, ci)
	var has_solid_near_cursor := false
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		if StepTypes.is_solid(ms.type) and ms.end.distance_to(cursor) < 2.0:
			has_solid_near_cursor = true
	assert_true(has_solid_near_cursor, "Solid path should reach cursor through wall")

func test_solid_path_reaches_cursor_mirror_case() -> void:
	var surfaces := _setup_scene()
	var player := Vector2(1353.337, 827.9246)
	var cursor := Vector2(1092.138, 794.4713)
	var plan: Array = [PlanManager.PlanEntry.new(surfaces[4].id, Side.Value.LEFT)]
	var aim := Planner.compute_aim_direction(player, cursor, plan, surfaces, GameState.new())
	var aim_ray := Ray.new(player, aim)
	var td := player.distance_to(cursor)
	MobiusTransform.reset_id_counter()
	var physical := Tracer.trace(player, aim, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, aim_ray, td,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, [], cursor)
	MobiusTransform.reset_id_counter()
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, aim_ray, td,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan, cursor)
	var ci: int = planned.cursor_index
	if ci < 0:
		ci = planned.steps.size()
	var merged := StepTreeMerge.merge(planned.steps, physical.steps, ci)
	var has_solid_near_cursor := false
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		if StepTypes.is_solid(ms.type) and ms.end.distance_to(cursor) < 2.0:
			has_solid_near_cursor = true
	assert_true(has_solid_near_cursor, "Solid path should reach cursor with plan")

# --- Full repros ---

func test_repro_bug1() -> void:
	var surfaces := _setup_scene()
	var player := Vector2(960.0, 827.9623)
	var cursor := Vector2(968.0083, 153.2839)
	var aim := Planner.compute_aim_direction(player, cursor, [], surfaces, GameState.new())
	var aim_ray := Ray.new(player, aim)
	var td := player.distance_to(cursor)
	MobiusTransform.reset_id_counter()
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, aim_ray, td,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [], cursor)
	assert_gt(planned.cursor_index, 0, "Bug1: Planned trace must reach cursor past wall")

func test_repro_bug2() -> void:
	var surfaces := _setup_scene()
	var player := Vector2(1353.337, 827.9246)
	var cursor := Vector2(1092.138, 794.4713)
	var plan: Array = [PlanManager.PlanEntry.new(surfaces[4].id, Side.Value.LEFT)]
	var aim := Planner.compute_aim_direction(player, cursor, plan, surfaces, GameState.new())
	var aim_ray := Ray.new(player, aim)
	var td := player.distance_to(cursor)
	MobiusTransform.reset_id_counter()
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, aim_ray, td,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan, cursor)
	assert_gt(planned.cursor_index, 0, "Bug2: Planned must reach cursor")
	var cs := _step(planned, planned.cursor_index - 1)
	assert_almost_eq(cs.end.x, cursor.x, 2.0, "Bug2: Cursor at actual x")
	assert_almost_eq(cs.end.y, cursor.y, 2.0, "Bug2: Cursor at actual y")

func test_repro_bug3() -> void:
	var surfaces := _setup_scene()
	var player := Vector2(930.0002, 827.9246)
	var cursor := Vector2(717.7476, 825.5289)
	var plan: Array = [PlanManager.PlanEntry.new(surfaces[3].id, Side.Value.LEFT)]
	var aim := Planner.compute_aim_direction(player, cursor, plan, surfaces, GameState.new())
	var aim_ray := Ray.new(player, aim)
	var td := player.distance_to(cursor)
	MobiusTransform.reset_id_counter()
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, aim_ray, td,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan, cursor)
	assert_gt(planned.cursor_index, 0, "Bug3: Planned must reach cursor")
	var cs := _step(planned, planned.cursor_index - 1)
	assert_almost_eq(cs.end.x, cursor.x, 2.0, "Bug3: Cursor at actual x")
	assert_almost_eq(cs.end.y, cursor.y, 2.0, "Bug3: Cursor at actual y")

# --- Fix: No gap after reflection + cursor ---

func test_no_gap_after_reflection_cursor() -> void:
	# Mirror between player and cursor. Physical reflects, then cursor injected.
	# The step AFTER cursor must start at the cursor position, not the reflected image.
	var surfaces := _setup_scene()
	var player := Vector2(960.0, 827.9623)
	var cursor := Vector2(706.7361, 508.9425)
	var aim := Direction.new(player, cursor)
	var aim_ray := Ray.new(player, aim)
	var td := player.distance_to(cursor)
	MobiusTransform.reset_id_counter()
	var physical := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, aim_ray, td,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, [], cursor)
	assert_gt(physical.cursor_index, 0, "Should reach cursor")
	assert_lt(physical.cursor_index, physical.steps.size(), "Should have post-cursor step")
	var post_step := _step(physical, physical.cursor_index)
	var cursor_step := _step(physical, physical.cursor_index - 1)
	assert_almost_eq(post_step.start.x, cursor.x, 2.0,
		"Post-cursor step must start at cursor x, not reflected image")
	assert_almost_eq(post_step.start.y, cursor.y, 2.0,
		"Post-cursor step must start at cursor y, not reflected image")
	assert_almost_eq(cursor_step.end.x, post_step.start.x, 0.01,
		"No gap: cursor step end == next step start (x)")
	assert_almost_eq(cursor_step.end.y, post_step.start.y, 0.01,
		"No gap: cursor step end == next step start (y)")
