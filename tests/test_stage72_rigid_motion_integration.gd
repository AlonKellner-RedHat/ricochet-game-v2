extends GutTest

const H := preload("res://tests/test_helpers.gd")
const TOL := Vector2(1.0, 1.0)

func before_each() -> void:
	H.reset_counters()

# --- Helpers ---

func _portal_pair_surfaces(source_seg: Segment, theta: float, d: Vector2) -> Dictionary:
	var result = RigidMotionEffect.create_portal_pair(source_seg, theta, d)
	var src_cfg := SideConfig.new(result.source_effect, true)
	var tgt_cfg := SideConfig.new(result.target_effect, true)
	var source_surf := Surface.new(source_seg, src_cfg, src_cfg, false, false)
	var target_surf := Surface.new(result.target_segment, tgt_cfg, tgt_cfg, false, false)
	return {source = source_surf, target = target_surf}

func _line_seg(x: float) -> Segment:
	return Segment.from_coords(Vector2(x, 100), Vector2(x, 500), Vector2(x, 300))

func _translation_portals() -> Dictionary:
	return _portal_pair_surfaces(_line_seg(200), 0.0, Vector2(300, 0))

func _room_walls() -> Array:
	return [
		H.wall(0),
		H.wall(800),
		RoomBuilder.create_block_surface(Vector2(0, 0), Vector2(800, 0), Vector2(400, 0)),
		RoomBuilder.create_block_surface(Vector2(0, 600), Vector2(800, 600), Vector2(400, 600)),
	]

func _trace(origin: Vector2, cursor: Vector2, surfaces: Array) -> Tracer.TracedPath:
	var aim := Direction.from_coords(origin, cursor)
	return Tracer.trace(origin, aim, surfaces, GameState.new(),
		null, -1.0, Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, [], null, cursor)

func _find_portal_gap(path: Tracer.TracedPath, source_x: float) -> Dictionary:
	for i in range(path.steps.size() - 1):
		var cur: Tracer.Step = path.steps[i]
		var nxt: Tracer.Step = path.steps[i + 1]
		if cur.frame_id == MobiusTransform.IDENTITY_ID and absf(cur.end.x - source_x) < 2.0:
			return {found = true, displacement = nxt.start - cur.end}
	return {found = false, displacement = Vector2.ZERO}

func _find_portal_gap_by_frame(path: Tracer.TracedPath) -> Dictionary:
	for i in range(path.steps.size() - 1):
		var cur: Tracer.Step = path.steps[i]
		var nxt: Tracer.Step = path.steps[i + 1]
		if cur.frame_id != nxt.frame_id:
			return {found = true, displacement = nxt.start - cur.end}
	return {found = false, displacement = Vector2.ZERO}

func _trace_both(surfaces: Array, player: Vector2, cursor: Vector2, plan: Array) -> Dictionary:
	var cache := TransformCache.new()
	var aim := Planner.compute_aim_direction(player, cursor, plan, surfaces, GameState.new(), cache)
	var aim_ray := Ray.from_coords(player, aim)
	var physical := Tracer.trace(player, aim, surfaces, GameState.new(),
		aim_ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, plan, cache, cursor)
	cache = TransformCache.new()
	aim = Planner.compute_aim_direction(player, cursor, plan, surfaces, GameState.new(), cache)
	aim_ray = Ray.from_coords(player, aim)
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		aim_ray, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan, cache, cursor)
	return {"physical": physical, "planned": planned}

# --- Test 1: Display color ---

func test_stage72_portal_surface_cyan() -> void:
	var portals := _translation_portals()
	var state := GameState.new()
	var src_left = portals.source.active_side_config(Side.Value.LEFT, state)
	var tgt_left = portals.target.active_side_config(Side.Value.LEFT, state)
	assert_eq(src_left.effect.get_display_color(), Color.CYAN, "Source portal displays cyan")
	assert_eq(tgt_left.effect.get_display_color(), Color.CYAN, "Target portal displays cyan")

# --- Test 2: Translation portal trace ---

func test_stage72_trace_through_translation_portal() -> void:
	var portals := _translation_portals()
	var surfaces := _room_walls()
	surfaces.append(portals.source)
	surfaces.append(portals.target)
	var path := _trace(Vector2(50, 300), Vector2(750, 300), surfaces)
	assert_gt(path.steps.size(), 1, "Should have multiple steps")
	var first: Tracer.Step = path.steps[0]
	assert_almost_eq(first.start, Vector2(50, 300), TOL, "First step starts at player")
	assert_almost_eq(first.end, Vector2(200, 300), TOL, "First step ends at source portal")
	assert_gt(path.steps.size(), 1, "Need post-portal step")
	var second: Tracer.Step = path.steps[1]
	assert_almost_eq(second.start, Vector2(500, 300), TOL,
		"Post-portal step starts at target (x=500)")

# --- Test 2b: Horizontal portal gap ---

func test_stage72_portal_gap_and_displacement() -> void:
	var portals := _translation_portals()
	var surfaces := _room_walls()
	surfaces.append(portals.source)
	surfaces.append(portals.target)
	var path := _trace(Vector2(50, 300), Vector2(750, 300), surfaces)
	var gap := _find_portal_gap(path, 200.0)
	assert_true(gap.found, "Portal transition must be found")
	assert_almost_eq(gap.displacement, Vector2(300, 0), TOL,
		"Gap equals displacement d=(300,0)")

# --- Test 2c: Diagonal ray portal gap ---

func test_stage72_diagonal_portal_gap() -> void:
	var portals := _translation_portals()
	var surfaces := _room_walls()
	surfaces.append(portals.source)
	surfaces.append(portals.target)
	var path := _trace(Vector2(50, 200), Vector2(750, 400), surfaces)
	var gap := _find_portal_gap(path, 200.0)
	assert_true(gap.found, "Portal transition must be found")
	assert_almost_eq(gap.displacement.x, 300.0, 2.0,
		"Gap x-component ≈ 300 (got %.1f)" % gap.displacement.x)

# --- Test 2d: Arc portal gap ---

func test_stage72_portal_gap_arc() -> void:
	var arc_seg := Segment.from_coords(
		Vector2(200, 100), Vector2(200, 300), Vector2(300, 200))
	var portals = _portal_pair_surfaces(arc_seg, 0.0, Vector2(400, 0))
	var surfaces := _room_walls()
	surfaces.append(portals.source)
	surfaces.append(portals.target)
	var path := _trace(Vector2(50, 200), Vector2(750, 200), surfaces)
	var gap := _find_portal_gap_by_frame(path)
	assert_true(gap.found, "Arc portal transition must be found")
	assert_gt(gap.displacement.length(), 100.0,
		"Arc portal gap must be substantial (got %.1f)" % gap.displacement.length())

# --- Test 2e: Vertical displacement portal gap ---

func test_stage72_portal_gap_vertical_d() -> void:
	var portals = _portal_pair_surfaces(_line_seg(200), 0.0, Vector2(0, 600))
	var surfaces := _room_walls()
	surfaces.append(portals.source)
	var path := _trace(Vector2(50, 300), Vector2(750, 300), surfaces)
	var gap := _find_portal_gap_by_frame(path)
	assert_true(gap.found, "Vertical-d portal transition must be found")
	assert_almost_eq(gap.displacement.y, 600.0, 2.0,
		"Gap y-component ≈ 600 (got %.1f)" % gap.displacement.y)

# --- Test 3: Rotation portal trace ---

func test_stage72_trace_through_rotation_portal() -> void:
	var portals = _portal_pair_surfaces(_line_seg(300), PI / 2.0, Vector2.ZERO)
	var surfaces := _room_walls()
	surfaces.append(portals.source)
	var path := _trace(Vector2(50, 300), Vector2(750, 300), surfaces)
	assert_gt(path.steps.size(), 1, "Should have multiple steps")
	var found_portal_frame := false
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame_id != MobiusTransform.IDENTITY_ID:
			found_portal_frame = true
			assert_false(s.frame.conjugating,
				"Rigid motion frame is conformal (conjugating=false)")
			break
	assert_true(found_portal_frame, "Should have a step in non-identity portal frame")

# --- Test 4: Conformal composition with reflection ---

func test_stage72_frame_conformal_after_portal() -> void:
	var portals = _portal_pair_surfaces(_line_seg(200), 0.0, Vector2(0, 100))
	var mirror := H.mirror(400)
	var surfaces := _room_walls()
	surfaces.append(portals.source)
	surfaces.append(mirror)
	var path := _trace(Vector2(50, 300), Vector2(750, 300), surfaces)
	var found_conformal := false
	var found_anticonformal := false
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame_id == MobiusTransform.IDENTITY_ID:
			continue
		if not s.frame.conjugating:
			found_conformal = true
		else:
			found_anticonformal = true
	assert_true(found_conformal, "Portal frame alone is conformal")
	assert_true(found_anticonformal, "Portal + reflection yields anti-conformal frame")

# --- Test 5: Portal chain (two source portals, no cancellation) ---

func test_stage72_portal_chain() -> void:
	var pair1 = _portal_pair_surfaces(_line_seg(200), 0.0, Vector2(0, 100))
	var pair2 = _portal_pair_surfaces(_line_seg(400), 0.0, Vector2(0, 100))
	var surfaces := _room_walls()
	surfaces.append(pair1.source)
	surfaces.append(pair2.source)
	var path := _trace(Vector2(50, 300), Vector2(750, 300), surfaces)
	assert_gt(path.steps.size(), 2, "Should have 3+ steps through two portals")
	var non_identity_count := 0
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame_id != MobiusTransform.IDENTITY_ID:
			non_identity_count += 1
	assert_gt(non_identity_count, 1,
		"Multiple steps in non-identity frames after chained portals")

# --- Test 6: Portal pair — ray continues past target ---

func test_stage72_portal_pair_continues_past_target() -> void:
	var portals := _translation_portals()
	var surfaces := _room_walls()
	surfaces.append(portals.source)
	surfaces.append(portals.target)
	var path := _trace(Vector2(50, 300), Vector2(750, 300), surfaces)
	assert_gt(path.steps.size(), 1, "Should have multiple steps")
	var portal_step_found := false
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame_id != MobiusTransform.IDENTITY_ID:
			portal_step_found = true
			assert_false(s.frame.conjugating,
				"Portal frame is conformal (conjugating=false)")
	assert_true(portal_step_found,
		"Ray enters portal frame after source portal")

# --- Test 7: Planner portal alignment ---

func test_stage72_planner_portal_aligned() -> void:
	var portals := _translation_portals()
	var surfaces := _room_walls()
	surfaces.append(portals.source)
	surfaces.append(portals.target)
	var plan := [
		PlanManager.PlanEntry.new(portals.source.id, Side.Value.RIGHT),
		PlanManager.PlanEntry.new(portals.target.id, Side.Value.RIGHT),
	]
	var player := Vector2(50, 300)
	var cursor := Vector2(700, 300)
	var result := _trace_both(surfaces, player, cursor, plan)
	var physical: Tracer.TracedPath = result.physical
	var planned: Tracer.TracedPath = result.planned
	assert_gt(physical.steps.size(), 0, "Physical trace has steps")
	assert_gt(planned.steps.size(), 0, "Planned trace has steps")
	var ci := planned.cursor_index if planned.cursor_index >= 0 else planned.steps.size()
	var merged := StepTreeMerge.merge(planned.steps, physical.steps, ci)
	var aligned_count := 0
	for step in merged:
		var s: Tracer.Step = step
		if s.type == StepTypes.Type.ALIGNED or s.type == StepTypes.Type.ALIGNED_POST_PLANNED:
			aligned_count += 1
	assert_gt(aligned_count, 0, "Should have aligned steps in planned+physical merge")

# --- Test 8: Planner image chain ---

func test_stage72_planner_image_chain() -> void:
	var portals := _translation_portals()
	var plan := [PlanManager.PlanEntry.new(portals.source.id, Side.Value.RIGHT)]
	var cursor := Vector2(600, 300)
	var image = Planner._compute_image(cursor, plan, [portals.source, portals.target], GameState.new())
	assert_not_null(image, "Image should not be null")
	assert_almost_eq(image, Vector2(300, 300), TOL,
		"Image = get_inverse_mobius().apply(cursor) = (600-300, 300) = (300, 300)")

# --- Test 9: Planner bounce point ---

func test_stage72_planner_bounce_point() -> void:
	var portals := _translation_portals()
	var plan := [PlanManager.PlanEntry.new(portals.source.id, Side.Value.RIGHT)]
	var player := Vector2(50, 300)
	var cursor := Vector2(600, 300)
	var surfaces := [portals.source, portals.target]
	var planned_path := Planner.plan_transformative_subchain(
		player, cursor, plan, surfaces, GameState.new())
	assert_eq(planned_path.steps.size(), 2,
		"Should have 2 steps (player->bounce, bounce->cursor), got %d" % planned_path.steps.size())
	var first_step: Tracer.Step = planned_path.steps[0]
	assert_almost_eq(first_step.end, Vector2(200, 300), TOL,
		"Bounce point on source portal carrier at x=200")

# --- Test 10: S5 aligned provenance ---

func test_stage72_S5_aligned_provenance() -> void:
	var portals := _translation_portals()
	var surfaces := _room_walls()
	surfaces.append(portals.source)
	surfaces.append(portals.target)
	var plan := [
		PlanManager.PlanEntry.new(portals.source.id, Side.Value.RIGHT),
		PlanManager.PlanEntry.new(portals.target.id, Side.Value.RIGHT),
	]
	var player := Vector2(50, 300)
	var cursor := Vector2(700, 300)
	var result := _trace_both(surfaces, player, cursor, plan)
	var planned: Tracer.TracedPath = result.planned
	assert_gt(planned.steps.size(), 1, "Planned trace has multiple steps")
	var first: Tracer.Step = planned.steps[0]
	assert_eq(first.frame_id, MobiusTransform.IDENTITY_ID,
		"First planned step is in identity frame (before portal)")
	var found_portal_frame := false
	for step in planned.steps:
		var s: Tracer.Step = step
		if s.frame_id != MobiusTransform.IDENTITY_ID:
			found_portal_frame = true
			break
	assert_true(found_portal_frame,
		"Planned trace has steps in portal frame (non-identity frame_id)")

# --- Test 11: S16 no NaN/Inf ---

func test_stage72_S16_no_nan_in_trace() -> void:
	var portals := _translation_portals()
	var surfaces := _room_walls()
	surfaces.append(portals.source)
	surfaces.append(portals.target)
	var origins := [
		Vector2(50, 200), Vector2(50, 300), Vector2(50, 400),
		Vector2(100, 150), Vector2(100, 450),
	]
	for origin in origins:
		var path := _trace(origin, Vector2(750, 300), surfaces)
		for step in path.steps:
			var s: Tracer.Step = step
			assert_false(is_nan(s.start.x) or is_nan(s.start.y),
				"No NaN in start from origin %s: %s" % [origin, s.start])
			assert_false(is_nan(s.end.x) or is_nan(s.end.y),
				"No NaN in end from origin %s: %s" % [origin, s.end])
			assert_false(is_inf(s.start.x) or is_inf(s.start.y),
				"No Inf in start from origin %s: %s" % [origin, s.start])

# --- Test 12: Arc portal trace ---

func test_stage72_arc_portal_trace() -> void:
	var arc_seg := Segment.from_coords(
		Vector2(200, 100), Vector2(200, 300), Vector2(300, 200))
	var portals = _portal_pair_surfaces(arc_seg, 0.0, Vector2(400, 0))
	var source_carrier = portals.source.segment.get_carrier()
	var target_carrier = portals.target.segment.get_carrier()
	assert_false(source_carrier.is_line(), "Source carrier is a circle")
	assert_false(target_carrier.is_line(), "Target carrier is a circle")
	assert_almost_eq(target_carrier.radius(), source_carrier.radius(), 0.1,
		"Same radius after translation")
	var surfaces := _room_walls()
	surfaces.append(portals.source)
	surfaces.append(portals.target)
	var path := _trace(Vector2(50, 200), Vector2(750, 200), surfaces)
	assert_gt(path.steps.size(), 0, "Should produce steps through arc portal")
	for step in path.steps:
		var s: Tracer.Step = step
		assert_false(is_nan(s.start.x) or is_nan(s.start.y),
			"No NaN in arc portal trace: %s" % s.start)

# --- Portal origin_on_surface regression tests ---

func _big_room_walls() -> Array:
	return [
		RoomBuilder.create_block_surface(Vector2(100, 100), Vector2(100, 900), Vector2(100, 500)),
		RoomBuilder.create_block_surface(Vector2(1800, 100), Vector2(1800, 900), Vector2(1800, 500)),
		RoomBuilder.create_block_surface(Vector2(100, 100), Vector2(1800, 100), Vector2(950, 100)),
		RoomBuilder.create_block_surface(Vector2(100, 900), Vector2(1800, 900), Vector2(950, 900)),
	]

func _big_line_seg(x: float) -> Segment:
	return Segment.from_coords(Vector2(x, 200), Vector2(x, 800), Vector2(x, 500))

func test_stage72_portal_single_trace_enters_frame() -> void:
	var portals := _portal_pair_surfaces(_big_line_seg(1500), 0.0, Vector2(-1100, 0))
	var surfaces := _big_room_walls()
	surfaces.append(portals.source)
	surfaces.append(portals.target)
	var path := _trace(Vector2(950, 500), Vector2(1700, 500), surfaces)
	var found_portal_frame := false
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame_id != MobiusTransform.IDENTITY_ID:
			found_portal_frame = true
			break
	assert_true(found_portal_frame,
		"Trace through portal must produce steps in non-identity frame")

func test_stage72_portal_stability_across_cursors() -> void:
	var portals := _portal_pair_surfaces(_big_line_seg(1500), 0.0, Vector2(-1100, 0))
	var surfaces := _big_room_walls()
	surfaces.append(portals.source)
	surfaces.append(portals.target)
	var player := Vector2(950, 500)
	for dy in range(-10, 11):
		var cursor := Vector2(1700, 500 + dy)
		var path := _trace(player, cursor, surfaces)
		var entered := false
		for step in path.steps:
			var s: Tracer.Step = step
			if s.frame_id != MobiusTransform.IDENTITY_ID:
				entered = true
				break
		assert_true(entered,
			"Cursor dy=%d must enter portal frame" % dy)

func test_stage72_portal_post_cursor_contiguity() -> void:
	var portals := _portal_pair_surfaces(_big_line_seg(1500), 0.0, Vector2(-1100, 0))
	var surfaces := _big_room_walls()
	surfaces.append(portals.source)
	surfaces.append(portals.target)
	var plan := [
		PlanManager.PlanEntry.new(portals.source.id, Side.Value.RIGHT),
		PlanManager.PlanEntry.new(portals.target.id, Side.Value.RIGHT),
	]
	var player := Vector2(950, 500)
	var cursor := Vector2(1700, 500)
	var result := _trace_both(surfaces, player, cursor, plan)
	var planned: Tracer.TracedPath = result.planned
	var ci := planned.cursor_index if planned.cursor_index >= 0 else planned.steps.size()
	assert_gt(planned.steps.size(), ci, "Should have post-cursor steps")
	for i in range(ci, planned.steps.size() - 1):
		var cur: Tracer.Step = planned.steps[i]
		var nxt: Tracer.Step = planned.steps[i + 1]
		if nxt.after_portal:
			continue
		assert_almost_eq(cur.end, nxt.start, TOL,
			"Post-cursor steps %d-%d must be contiguous: end=%s start=%s" % [i, i+1, cur.end, nxt.start])

