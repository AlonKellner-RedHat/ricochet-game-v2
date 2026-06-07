extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()

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

# --- Terminal pass-through in PLANNED mode ---

func test_wall_doesnt_stop_planned() -> void:
	var w := _hwall(400)
	var player := Vector2(600, 500)
	var cursor := Vector2(600, 200)
	var aim := Direction.new(player, cursor)
	var ray := Ray.new(player, aim)
	var path := Tracer.trace(player, aim, [w], GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [])
	assert_gt(path.cursor_index, 0, "Planned trace should reach cursor through wall")

func test_terminal_stops_physical() -> void:
	var w := _hwall(400)
	var player := Vector2(600, 500)
	var cursor := Vector2(600, 200)
	var aim := Direction.new(player, cursor)
	var ray := Ray.new(player, aim)
	var path := Tracer.trace(player, aim, [w], GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray)
	assert_eq(path.cursor_index, -1, "Physical trace should stop at wall before cursor")

# --- Cursor image = direction.end ---

func test_cursor_image_is_direction_end() -> void:
	var w := _wall(600)
	var player := Vector2(200, 300)
	var cursor := Vector2(400, 300)
	var aim := Direction.new(player, cursor)
	var ray := Ray.new(player, aim)
	var path := Tracer.trace(player, aim, [w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	assert_gt(path.cursor_index, 0, "Cursor should be injected")
	var cs := _step(path, path.cursor_index - 1)
	assert_almost_eq(cs.end.x, cursor.x, 1.0, "Cursor step ends at cursor x")
	assert_almost_eq(cs.end.y, cursor.y, 1.0, "Cursor step ends at cursor y")

func test_cursor_with_plan_reachable() -> void:
	# Use full room so the ray can loop back
	var surfaces := _setup_scene()
	var plan: Array = [PlanManager.PlanEntry.new(surfaces[3].id, Side.Value.LEFT)]
	var player := Vector2(960, 500)
	var cursor := Vector2(700, 400)
	var aim := Planner.compute_aim_direction(player, cursor, plan, surfaces, GameState.new())
	var ray := Ray.new(player, aim)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan)
	assert_gt(path.cursor_index, 1, "Planned trace should reach cursor after plan + loop")

func test_cursor_not_reached_after_nonplan_reflection() -> void:
	# No plan, mirror between player and cursor → physical reflects → diverged → cursor NOT reached
	var m := _mirror(400)
	var w := _wall(700)
	var player := Vector2(200, 300)
	var cursor := Vector2(600, 300)
	var aim := Direction.new(player, cursor)
	var ray := Ray.new(player, aim)
	var path := Tracer.trace(player, aim, [m, w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	# Mirror reflects before aim point → non-plan effect → plan_matched=false → cursor NOT reached
	assert_eq(path.cursor_index, -1, "Cursor not reached after non-plan reflection")

# --- Physical preview matches physical trace ---

func test_physical_preview_matches() -> void:
	var surfaces := _setup_scene()
	var player := Vector2(960.0, 827.9623)
	var cursor := Vector2(689.7184, 640.1856)
	var aim := Direction.new(player, cursor)
	var aim_ray := Ray.new(player, aim)

	var physical := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, aim_ray)
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, aim_ray, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [])
	var ci: int = planned.cursor_index
	if ci < 0:
		ci = planned.steps.size()
	var merged := StepTreeMerge.merge(planned.steps, physical.steps, ci)

	var non_red: Array = []
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		if ms.type == StepTypes.Type.ALIGNED or ms.type == StepTypes.Type.ALIGNED_POST_PLANNED or ms.type == StepTypes.Type.DIVERGED_PHYSICAL:
			non_red.append(ms)

	assert_eq(non_red.size(), physical.steps.size(),
		"Non-red count (%d) must match physical count (%d)" % [non_red.size(), physical.steps.size()])

# --- Player block ---

func test_player_block_stops_loop() -> void:
	# No obstacles — ray escapes, loops through infinity, returns to player
	var player := Vector2(500, 300)
	var cursor := Vector2(700, 300)
	var aim := Direction.new(player, cursor)
	var ray := Ray.new(player, aim)
	var path := Tracer.trace(player, aim, [], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	# Should terminate (player block prevents infinite loop)
	assert_gt(path.steps.size(), 0, "Should have steps")
	# Trace should not hit MAX_HITS (256 steps) — player block should stop it
	assert_lt(path.steps.size(), 256, "Player block should stop before MAX_HITS")

func test_player_block_wall_stops_first() -> void:
	var w := _wall(600)
	var player := Vector2(200, 300)
	var cursor := Vector2(400, 300)
	var aim := Direction.new(player, cursor)
	var ray := Ray.new(player, aim)
	var path := Tracer.trace(player, aim, [w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	# Wall should stop the trace, not the player block
	var last := _step(path, path.steps.size() - 1)
	assert_not_null(last.hit, "Last step should hit the wall")

# --- Repro tests ---

func test_repro_bug1_wall_between() -> void:
	var surfaces := _setup_scene()
	var player := Vector2(960.0, 827.9623)
	var cursor := Vector2(968.0083, 153.2839)
	var aim := Planner.compute_aim_direction(player, cursor, [], surfaces, GameState.new())
	var ray := Ray.new(player, aim)
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [])
	assert_gt(planned.cursor_index, 0, "Planned trace must reach cursor past wall")

func test_repro_bug2_mirror_plan() -> void:
	var surfaces := _setup_scene()
	var player := Vector2(1353.337, 827.9246)
	var cursor := Vector2(1092.138, 794.4713)
	var plan: Array = [PlanManager.PlanEntry.new(surfaces[4].id, Side.Value.LEFT)]
	var aim := Planner.compute_aim_direction(player, cursor, plan, surfaces, GameState.new())
	var ray := Ray.new(player, aim)
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan)
	# Cursor reached after plan completes and ray loops back
	assert_gt(planned.cursor_index, 1, "Planned must reach cursor after plan + loop")

func test_repro_bug3_off_segment() -> void:
	var surfaces := _setup_scene()
	var player := Vector2(930.0002, 827.9246)
	var cursor := Vector2(717.7476, 825.5289)
	var plan: Array = [PlanManager.PlanEntry.new(surfaces[3].id, Side.Value.LEFT)]
	var aim := Planner.compute_aim_direction(player, cursor, plan, surfaces, GameState.new())
	var ray := Ray.new(player, aim)
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, ray, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan)
	assert_gt(planned.cursor_index, 1, "Planned must reach cursor after plan + loop")

# --- Side flip after odd reflections ---

func _setup_three_mirrors() -> Array:
	var w_top := RoomBuilder.create_block_surface(Vector2(560, 240), Vector2(1360, 240), Vector2(960, 240))
	var w_bot := RoomBuilder.create_block_surface(Vector2(1360, 840), Vector2(560, 840), Vector2(960, 840))
	var w_left := RoomBuilder.create_block_surface(Vector2(560, 840), Vector2(560, 240), Vector2(560, 540))
	var m1_seg := Segment.new(Vector2(800, 300), Vector2(800, 780), Vector2(800, 540))
	var m1 := Surface.new(m1_seg, SideConfig.new(ReflectionEffect.new(m1_seg.get_carrier()), true), SideConfig.new(null, false), false, false)
	var m2_seg := Segment.new(Vector2(1200, 300), Vector2(1200, 780), Vector2(1200, 540))
	var m2 := Surface.new(m2_seg, SideConfig.new(ReflectionEffect.new(m2_seg.get_carrier()), true), SideConfig.new(null, false), false, false)
	var m3_seg := Segment.new(Vector2(1000, 400), Vector2(1000, 700), Vector2(1000, 550))
	var m3 := Surface.new(m3_seg, SideConfig.new(null, false), SideConfig.new(ReflectionEffect.new(m3_seg.get_carrier()), true), false, false)
	return [w_top, w_bot, w_left, m1, m2, m3]

func test_side_correct_after_odd_reflections() -> void:
	var surfaces := _setup_three_mirrors()
	var player := Vector2(960.0, 827.9623)
	var cursor := Vector2(857.8936, 783.4509)
	var aim := Direction.new(player, cursor)
	var ray := Ray.new(player, aim)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	# Step 2 hits mirror at x=1000 (R=reflect). After 1 reflection, frame conjugating.
	# Side must be flipped → R=reflect applied → frame changes.
	var step1: Tracer.Step = path.steps[1] if path.steps.size() > 1 else null
	var step2: Tracer.Step = path.steps[2] if path.steps.size() > 2 else null
	assert_not_null(step2, "Should have step 2")
	if step1 and step2:
		assert_ne(step1.frame_id, step2.frame_id,
			"Step 2 should reflect — side must be flipped after odd reflection")

# --- Wrong carrier reflection bug ---

func test_repro_wrong_carrier_reflection() -> void:
	# WRONG case: cursor at y=736.364. After reflecting off x=800, the hit at
	# x=1000 uses the ORIGINAL carrier Möbius (x=1000) instead of the NORMALIZED
	# carrier (x=600). This produces a backtracking ray instead of proper reflection.
	var surfaces := _setup_three_mirrors()
	var player := Vector2(960.0, 827.9623)
	var cursor := Vector2(820.855, 736.3637)
	var aim := Direction.new(player, cursor)
	var ray := Ray.new(player, aim)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	# Should bounce between mirrors ≥5 steps (not backtrack to x=560 at step 3)
	assert_gte(path.steps.size(), 5,
		"Should bounce between mirrors, not backtrack (got %d steps)" % path.steps.size())

func test_repro_correct_carrier_reflection() -> void:
	# CORRECT case: cursor at y=737.366. Very close angle. Should also bounce ≥5 steps.
	var surfaces := _setup_three_mirrors()
	var player := Vector2(960.0, 827.9623)
	var cursor := Vector2(820.855, 737.3656)
	var aim := Direction.new(player, cursor)
	var ray := Ray.new(player, aim)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	assert_gte(path.steps.size(), 5,
		"Regression: correct case should still bounce ≥5 steps (got %d steps)" % path.steps.size())

func test_reflection_direction_after_frame_change() -> void:
	# After reflecting off x=800 (going left→right), hitting x=1000 should
	# reflect back to the left (x reverses). The y-slope should be preserved.
	var surfaces := _setup_three_mirrors()
	var player := Vector2(960.0, 827.9623)
	var cursor := Vector2(820.855, 736.3637)
	var aim := Direction.new(player, cursor)
	var ray := Ray.new(player, aim)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	if path.steps.size() >= 4:
		# Step 2: (800, ~723) → (1000, ~591) — going RIGHT
		# Step 3: should go LEFT (reflected at x=1000)
		var s2 := _step(path, 2)
		var s3 := _step(path, 3)
		var dir2_x := s2.end.x - s2.start.x  # positive (going right)
		var dir3_x := s3.end.x - s3.start.x  # should be negative (going left)
		assert_gt(dir2_x, 0.0, "Step 2 should go right (toward x=1000)")
		assert_lt(dir3_x, 0.0, "Step 3 should go left (reflected back from x=1000)")

# --- Player block fires mid-air after reflections ---

func test_no_midair_end_after_reflections() -> void:
	# Trace bounces between mirrors, then loops through infinity.
	# Should NOT end mid-air at the player's image — should reach a surface or bounds.
	var surfaces := _setup_three_mirrors()
	var player := Vector2(942.1896, 449.0703)
	var cursor := Vector2(877.9145, 441.8182)
	var aim := Direction.new(player, cursor)
	var ray := Ray.new(player, aim)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	# Last step should end at a surface hit or bounds edge, not mid-air
	var last := _step(path, path.steps.size() - 1)
	# Check: last step end should be near a surface or bounds edge
	var bounds := Tracer.DEFAULT_BOUNDS
	var near_surface := false
	for surf in surfaces:
		var s: Surface = surf
		var dist_start := _point_to_segment_dist(last.end, s.segment.start, s.segment.end)
		if dist_start < 2.0:
			near_surface = true
			break
	var near_bounds := (last.end.x <= bounds.position.x + 2.0 or
		last.end.x >= bounds.end.x - 2.0 or
		last.end.y <= bounds.position.y + 2.0 or
		last.end.y >= bounds.end.y - 2.0)
	var near_player := last.end.distance_to(player) < 2.0
	assert_true(near_surface or near_bounds or near_player,
		"Trace should end at surface, bounds, or player — not mid-air at %s" % last.end)

func _point_to_segment_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ap := p - a
	var t := clampf(ap.dot(ab) / ab.length_squared(), 0.0, 1.0)
	var closest := a + t * ab
	return p.distance_to(closest)

func test_player_block_in_identity_frame() -> void:
	# No reflections, trace loops. Player block should prevent infinite loop.
	var player := Vector2(500, 300)
	var cursor := Vector2(700, 300)
	var aim := Direction.new(player, cursor)
	var ray := Ray.new(player, aim)
	var path := Tracer.trace(player, aim, [], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	assert_lt(path.steps.size(), 256, "Should terminate before MAX_HITS")

func test_player_waypoint_after_reflection() -> void:
	# After reflection, player image is a waypoint, trace continues past it.
	var surfaces := _setup_three_mirrors()
	var player := Vector2(942.1896, 449.0703)
	var cursor := Vector2(877.9145, 441.8182)
	var aim := Direction.new(player, cursor)
	var ray := Ray.new(player, aim)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	# The trace should continue past the player image (after reflections)
	# and reach an actual surface hit
	var has_hit_after_escape := false
	for i in path.steps.size():
		var s := _step(path, i)
		if s.hit != null and s.hit.on_segment and i > 5:
			has_hit_after_escape = true
	assert_true(has_hit_after_escape,
		"After reflections + escape, trace should hit a real surface")
