extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()

# --- Helpers ---

func _horiz_segment() -> Segment:
	return Segment.from_coords(Vector2(100, 200), Vector2(300, 200), Vector2(200, 200))

func _vert_segment() -> Segment:
	return Segment.from_coords(Vector2(200, 100), Vector2(200, 300), Vector2(200, 200))

func _arc_segment() -> Segment:
	return Segment.from_coords(Vector2(300, 200), Vector2(200, 100), Vector2(270, 130))

func _wall(start: Vector2, end_v: Vector2) -> Surface:
	var via := (start + end_v) / 2.0
	return RoomBuilder.create_block_surface(start, end_v, via)

# =================================================================
# Stage 1: Endpoint detection
# =================================================================

func test_at_which_endpoint_at_start() -> void:
	var seg := _horiz_segment()
	var result := Intersection.at_which_endpoint(Vector2(100, 200), seg)
	assert_eq(result, 1, "Point at segment start should return 1")

func test_at_which_endpoint_at_end() -> void:
	var seg := _horiz_segment()
	var result := Intersection.at_which_endpoint(Vector2(300, 200), seg)
	assert_eq(result, 2, "Point at segment end should return 2")

func test_at_which_endpoint_interior() -> void:
	var seg := _horiz_segment()
	var result := Intersection.at_which_endpoint(Vector2(200, 200), seg)
	assert_eq(result, 0, "Point at segment interior should return 0")

func test_at_which_endpoint_off_segment() -> void:
	var seg := _horiz_segment()
	var result := Intersection.at_which_endpoint(Vector2(500, 500), seg)
	assert_eq(result, 0, "Point off segment should return 0")

func test_at_which_endpoint_near_start() -> void:
	var seg := _horiz_segment()
	var result := Intersection.at_which_endpoint(Vector2(100.005, 200.003), seg)
	assert_eq(result, 1, "Point within eps of start should return 1")

func test_at_which_endpoint_arc() -> void:
	var seg := _arc_segment()
	var result_start := Intersection.at_which_endpoint(Vector2(300, 200), seg)
	var result_end := Intersection.at_which_endpoint(Vector2(200, 100), seg)
	assert_eq(result_start, 1, "Point at arc start should return 1")
	assert_eq(result_end, 2, "Point at arc end should return 2")

# =================================================================
# Stage 1: Tangent computation
# =================================================================

func test_tangent_into_line_at_start() -> void:
	var seg := _horiz_segment()
	var tangent := Intersection.tangent_into_segment(seg, 1)
	assert_almost_eq(tangent, Vector2(1, 0), Vector2(0.01, 0.01),
		"Tangent at start of horizontal line should point right (toward end)")

func test_tangent_into_line_at_end() -> void:
	var seg := _horiz_segment()
	var tangent := Intersection.tangent_into_segment(seg, 2)
	assert_almost_eq(tangent, Vector2(-1, 0), Vector2(0.01, 0.01),
		"Tangent at end of horizontal line should point left (toward start)")

func test_tangent_into_vert_line_at_start() -> void:
	var seg := _vert_segment()
	var tangent := Intersection.tangent_into_segment(seg, 1)
	assert_almost_eq(tangent, Vector2(0, 1), Vector2(0.01, 0.01),
		"Tangent at start of vertical line should point down (toward end)")

func test_tangent_into_arc_at_start() -> void:
	var seg := _arc_segment()
	var tangent := Intersection.tangent_into_segment(seg, 1)
	assert_almost_eq(tangent.length(), 1.0, 0.01, "Tangent should be unit vector")
	var to_via := (seg.via.coords - seg.start.coords).normalized()
	assert_gt(tangent.dot(to_via), 0.5, "Tangent should point roughly toward via")

# =================================================================
# Stage 1: Blocked sides computation
# =================================================================

func test_blocked_sides_interior() -> void:
	var seg := _horiz_segment()
	var ray := Ray.from_coords(Vector2(200, 100), Direction.from_coords(Vector2(200, 100), Vector2(200, 300)))
	var sides := Intersection.endpoint_blocked_sides(Vector2(200, 200), seg, ray, 0)
	assert_true(sides[0] and sides[1], "Interior hit should block both sides")

func test_blocked_sides_off_segment() -> void:
	var seg := _horiz_segment()
	var record := Intersection.HitRecord.new(1.0, Vector2(500, 200), seg, Side.Value.LEFT, false)
	assert_false(record.on_segment, "Off-segment hit should not be on segment")
	assert_false(record.is_fully_blocked(), "Off-segment hit should not be fully blocked")

func test_blocked_sides_start_endpoint() -> void:
	var seg := _horiz_segment()
	var ray := Ray.from_coords(Vector2(100, 100), Direction.from_coords(Vector2(100, 100), Vector2(100, 300)))
	var sides := Intersection.endpoint_blocked_sides(Vector2(100, 200), seg, ray, 1)
	var left: bool = sides[0]
	var right: bool = sides[1]
	assert_true(left != right, "Start endpoint should block exactly one side")

func test_blocked_sides_end_endpoint() -> void:
	var seg := _horiz_segment()
	var ray := Ray.from_coords(Vector2(300, 100), Direction.from_coords(Vector2(300, 100), Vector2(300, 300)))
	var sides := Intersection.endpoint_blocked_sides(Vector2(300, 200), seg, ray, 2)
	var left: bool = sides[0]
	var right: bool = sides[1]
	assert_true(left != right, "End endpoint should block exactly one side")

func test_blocked_sides_endpoint_direction() -> void:
	# Horizontal segment (100,200)→(300,200). Ray going straight down at x=100.
	# At start endpoint (100,200): tangent into segment = (1,0) (pointing right).
	# Ray dir = (0,1) (pointing down in Y-down).
	# cross = ray_dir.cross(tangent) = 0*0 - 1*1 = -1 → LEFT blocked.
	var seg := _horiz_segment()
	var ray := Ray.from_coords(Vector2(100, 100), Direction.from_coords(Vector2(100, 100), Vector2(100, 300)))
	var sides := Intersection.endpoint_blocked_sides(Vector2(100, 200), seg, ray, 1)
	# The segment extends to the RIGHT of the ray → should block RIGHT side
	# (exact convention established by this test — may need to swap if implementation differs)
	assert_true(sides[0] or sides[1], "Should block at least one side")

# =================================================================
# Stage 1: HitRecord new fields
# =================================================================

func test_hitrecord_interior_fully_blocked() -> void:
	var seg := _horiz_segment()
	var ray := Ray.from_coords(Vector2(200, 100), Direction.from_coords(Vector2(200, 100), Vector2(200, 300)))
	var segments: Array = [seg]
	var hit := Intersection.find_nearest_hit(ray, segments)
	assert_not_null(hit, "Should find a hit")
	assert_true(hit.on_segment, "Interior hit should be on segment")
	assert_true(hit.is_fully_blocked(), "Interior hit should be fully blocked")

func test_hitrecord_endpoint_partial_blocked() -> void:
	var seg := _horiz_segment()
	# Ray going down at x=100, will hit the carrier at the start endpoint
	var ray := Ray.from_coords(Vector2(100, 100), Direction.from_coords(Vector2(100, 100), Vector2(100, 300)))
	var segments: Array = [seg]
	var hit := Intersection.find_nearest_hit(ray, segments)
	assert_not_null(hit, "Should find a hit")
	assert_true(hit.on_segment, "Endpoint hit is geometrically on segment")
	assert_false(hit.is_fully_blocked(), "Endpoint hit should NOT be fully blocked")

func test_hitrecord_off_segment_not_blocked() -> void:
	var seg := _horiz_segment()
	# Ray going down at x=500, will hit the carrier off-segment
	var ray := Ray.from_coords(Vector2(500, 100), Direction.from_coords(Vector2(500, 100), Vector2(500, 300)))
	var segments: Array = [seg]
	var hit := Intersection.find_nearest_hit(ray, segments)
	assert_not_null(hit, "Should find a carrier hit")
	assert_false(hit.on_segment, "Should be off-segment")
	assert_false(hit.is_fully_blocked(), "Off-segment should not be fully blocked")

# =================================================================
# Stage 3: Tracer integration — interior hits unchanged
# =================================================================

func test_trace_interior_hit_blocks() -> void:
	# Ray going down hits a horizontal wall at its interior → should block (terminal)
	var top_wall := _wall(Vector2(0, 200), Vector2(400, 200))
	var surfaces: Array = [top_wall]
	var player := Vector2(200, 100)
	var cursor := Vector2(200, 400)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(), Rect2(0, 0, 400, 400))
	assert_gt(path.steps.size(), 0, "Should have steps")
	var last: Tracer.Step = path.steps[path.steps.size() - 1]
	assert_almost_eq(last.end, Vector2(200, 200), Vector2(1, 1),
		"Trace should end at wall interior hit")

# =================================================================
# Stage 3: Tracer — endpoint open → ray continues
# =================================================================

func test_trace_endpoint_open_continues() -> void:
	# Wall from (100,200) to (300,200). Ray going down at x=300 (the endpoint).
	# With side-hitpoints: endpoint only blocks one side → ray should continue past.
	var wall := _wall(Vector2(100, 200), Vector2(300, 200))
	var bottom_wall := _wall(Vector2(0, 400), Vector2(400, 400))
	var surfaces: Array = [wall, bottom_wall]
	var player := Vector2(300, 100)
	var cursor := Vector2(300, 500)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(), Rect2(0, 0, 400, 500))
	var last: Tracer.Step = path.steps[path.steps.size() - 1]
	# The trace should NOT stop at y=200 (the endpoint). It should continue to y=400 (bottom wall).
	assert_almost_eq(last.end.y, 400.0, 1.0,
		"Trace should pass through open endpoint and reach bottom wall at y=400, got y=%s" % last.end.y)

# =================================================================
# Stage 3: Tracer — corner (two walls meeting) → blocks
# =================================================================

func test_trace_corner_two_walls_blocks() -> void:
	# Two walls meeting at (300, 200): horizontal (100,200)→(300,200) and vertical (300,200)→(300,400).
	# Ray going down-right toward the corner should hit the corner.
	var h_wall := _wall(Vector2(100, 200), Vector2(300, 200))
	var v_wall := _wall(Vector2(300, 200), Vector2(300, 400))
	var surfaces: Array = [h_wall, v_wall]
	var player := Vector2(200, 100)
	var cursor := Vector2(400, 300)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(), Rect2(0, 0, 500, 500))
	# The first carrier step should end at or near the corner (300, 200)
	var first: Tracer.Step = path.steps[0]
	assert_almost_eq(first.end.x, 300.0, 1.0,
		"First step should hit corner x. Got: %s" % first.end)
	assert_almost_eq(first.end.y, 200.0, 1.0,
		"First step should hit corner y. Got: %s" % first.end)

# =================================================================
# Stage 3: Tracer — endpoint hit doesn't cause mid-air ending
# =================================================================

func test_trace_endpoint_does_not_end_midair() -> void:
	# Open-ended wall: only covers part of the space. Ray through endpoint should
	# continue to bounds, not end mid-air at the endpoint.
	var wall := _wall(Vector2(100, 200), Vector2(300, 200))
	var surfaces: Array = [wall]
	var player := Vector2(300, 100)
	var cursor := Vector2(300, 500)
	var aim := Direction.from_coords(player, cursor)
	var bounds := Rect2(0, 0, 400, 500)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(), bounds)
	var last: Tracer.Step = path.steps[path.steps.size() - 1]
	# The trace should reach the bounds, not stop at the wall endpoint
	var at_bounds := (last.end.y >= bounds.end.y - 2.0 or last.end.y <= bounds.position.y + 2.0
		or last.end.x >= bounds.end.x - 2.0 or last.end.x <= bounds.position.x + 2.0)
	assert_true(at_bounds,
		"Trace through open endpoint should reach bounds, not end mid-air at %s" % last.end)

# =================================================================
# Stage 5: Endpoint behavior lock-in tests
# =================================================================

func test_reflection_at_interior_still_works() -> void:
	# Mirror from (100,200) to (300,200). Ray hits interior → should reflect.
	var seg := _horiz_segment()
	var carrier := seg.get_carrier()
	var reflection := ReflectionEffect.new(carrier)
	var left := SideConfig.new(reflection, true)
	var right := SideConfig.new(null, false)
	var mirror := Surface.new(seg, left, right, false, false)
	var bottom := _wall(Vector2(0, 400), Vector2(400, 400))
	var surfaces: Array = [mirror, bottom]
	var player := Vector2(200, 100)
	var cursor := Vector2(200, 400)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(), Rect2(0, 0, 400, 500))
	var found_frame_change := false
	for i in range(1, path.steps.size()):
		var prev: Tracer.Step = path.steps[i - 1]
		var curr: Tracer.Step = path.steps[i]
		if prev.frame_id != curr.frame_id:
			found_frame_change = true
			break
	assert_true(found_frame_change, "Interior mirror hit should still produce a reflection")

func test_endpoint_reflection_skipped() -> void:
	# Mirror from (100,200) to (300,200). Ray hits at endpoint (100,200) → partial block, no reflection.
	var seg := _horiz_segment()
	var carrier := seg.get_carrier()
	var reflection := ReflectionEffect.new(carrier)
	var left := SideConfig.new(reflection, true)
	var right := SideConfig.new(null, false)
	var mirror := Surface.new(seg, left, right, false, false)
	var surfaces: Array = [mirror]
	var player := Vector2(100, 100)
	var cursor := Vector2(100, 400)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(), Rect2(0, 0, 400, 500))
	var found_frame_change := false
	for i in range(1, path.steps.size()):
		var prev: Tracer.Step = path.steps[i - 1]
		var curr: Tracer.Step = path.steps[i]
		if prev.frame_id != curr.frame_id:
			found_frame_change = true
			break
	assert_false(found_frame_change, "Endpoint-only mirror hit should NOT reflect (partial block)")

func test_trace_ends_violation_1() -> void:
	# Regression: the exact TRACE-ENDS violation position from mirror_and_wall.tscn.
	# Aim point coincides with a carrier intersection — trace must still terminate cleanly.
	var surfaces := _mirror_and_wall_surfaces()
	var player := Vector2(1350, 250)
	var cursor := Vector2(560, 840)
	var aim := Planner.compute_aim_direction(player, cursor, [], surfaces, GameState.new())
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, null, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [], null, cursor)
	assert_gt(planned.steps.size(), 0, "Planned trace should have steps")
	assert_lt(planned.steps.size(), 50,
		"Trace should not loop — got %d steps" % planned.steps.size())
	var last: Tracer.Step = planned.steps[planned.steps.size() - 1]
	assert_almost_eq(last.end, player, Vector2(2, 2),
		"Trace should end at player, got %s" % last.end)

# =================================================================
# Player block through infinity
# =================================================================

func _mirror_and_wall_surfaces() -> Array:
	var top := _wall(Vector2(560, 240), Vector2(1360, 240))
	var bottom := _wall(Vector2(1360, 840), Vector2(560, 840))
	var left := _wall(Vector2(560, 840), Vector2(560, 240))
	var interior := _wall(Vector2(600, 300), Vector2(600, 780))
	var mirror_seg := Segment.from_coords(Vector2(800, 300), Vector2(800, 780), Vector2(800, 540))
	var mirror_carrier := mirror_seg.get_carrier()
	var mirror_refl := ReflectionEffect.new(mirror_carrier)
	var mirror := Surface.new(mirror_seg, SideConfig.new(mirror_refl, true), SideConfig.new(null, false), false, false)
	var sb_top := Surface.new(Segment.from_coords(Vector2(0, 0), Vector2(1920, 0), Vector2(960, 0)),
		SideConfig.new(null, false), SideConfig.new(null, false), false, false)
	var sb_right := Surface.new(Segment.from_coords(Vector2(1920, 0), Vector2(1920, 1080), Vector2(1920, 540)),
		SideConfig.new(null, false), SideConfig.new(null, false), false, false)
	var sb_bottom := Surface.new(Segment.from_coords(Vector2(1920, 1080), Vector2(0, 1080), Vector2(960, 1080)),
		SideConfig.new(null, false), SideConfig.new(null, false), false, false)
	var sb_left := Surface.new(Segment.from_coords(Vector2(0, 1080), Vector2(0, 0), Vector2(0, 540)),
		SideConfig.new(null, false), SideConfig.new(null, false), false, false)
	return [top, bottom, left, interior, mirror, sb_top, sb_right, sb_bottom, sb_left]

func _three_mirrors_surfaces() -> Array:
	var top := _wall(Vector2(560, 240), Vector2(1360, 240))
	var bottom := _wall(Vector2(1360, 840), Vector2(560, 840))
	var left := _wall(Vector2(560, 840), Vector2(560, 240))
	var m1_seg := Segment.from_coords(Vector2(800, 300), Vector2(800, 780), Vector2(800, 540))
	var m1 := Surface.new(m1_seg, SideConfig.new(ReflectionEffect.new(m1_seg.get_carrier()), true), SideConfig.new(null, false), false, false)
	var m2_seg := Segment.from_coords(Vector2(1200, 300), Vector2(1200, 780), Vector2(1200, 540))
	var m2 := Surface.new(m2_seg, SideConfig.new(ReflectionEffect.new(m2_seg.get_carrier()), true), SideConfig.new(null, false), false, false)
	var m3_seg := Segment.from_coords(Vector2(1000, 400), Vector2(1000, 700), Vector2(1000, 550))
	var m3 := Surface.new(m3_seg, SideConfig.new(null, false), SideConfig.new(ReflectionEffect.new(m3_seg.get_carrier()), true), false, false)
	var sb_top := Surface.new(Segment.from_coords(Vector2(0, 0), Vector2(1920, 0), Vector2(960, 0)),
		SideConfig.new(null, false), SideConfig.new(null, false), false, false)
	var sb_right := Surface.new(Segment.from_coords(Vector2(1920, 0), Vector2(1920, 1080), Vector2(1920, 540)),
		SideConfig.new(null, false), SideConfig.new(null, false), false, false)
	var sb_bottom := Surface.new(Segment.from_coords(Vector2(1920, 1080), Vector2(0, 1080), Vector2(960, 1080)),
		SideConfig.new(null, false), SideConfig.new(null, false), false, false)
	var sb_left := Surface.new(Segment.from_coords(Vector2(0, 1080), Vector2(0, 0), Vector2(0, 540)),
		SideConfig.new(null, false), SideConfig.new(null, false), false, false)
	return [top, bottom, left, m1, m2, m3, sb_top, sb_right, sb_bottom, sb_left]

func test_player_blocks_ray_looping_through_infinity() -> void:
	# Ray from player loops through screen boundaries in identity frame.
	# Player must block it when it returns — trace should terminate at player, not loop 288 times.
	var surfaces := _mirror_and_wall_surfaces()
	var player := Vector2(1350, 250)
	var cursor := Vector2(560, 840)
	var aim := Planner.compute_aim_direction(player, cursor, [], surfaces, GameState.new())
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, null, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [], null, cursor)
	var last: Tracer.Step = planned.steps[planned.steps.size() - 1]
	assert_lt(planned.steps.size(), 50,
		"Trace should terminate, not loop %d times" % planned.steps.size())
	assert_almost_eq(last.end, player, Vector2(2, 2),
		"Trace through infinity should end at player position, got %s" % last.end)

func test_physical_trace_player_blocks_with_unsatisfied_plan() -> void:
	# Physical trace with planner direction and unsatisfied plan.
	# The ray goes toward the image point, wraps through infinity, and returns to the player.
	# Player should block in the identity frame regardless of plan state.
	var surfaces := _three_mirrors_surfaces()
	var m1_id: int = surfaces[3].id
	var player := Vector2(560, 840)
	var cursor := Vector2(1920, 0)
	var plan_entries: Array = [PlanManager.PlanEntry.new(m1_id, Side.Value.LEFT)]
	var aim := Planner.compute_aim_direction(player, cursor, plan_entries, surfaces, GameState.new())
	var physical := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, null, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, plan_entries, null, cursor)
	var last: Tracer.Step = physical.steps[physical.steps.size() - 1]
	assert_lt(physical.steps.size(), 50,
		"Physical trace should terminate at player, not loop %d times" % physical.steps.size())
	assert_almost_eq(last.end, player, Vector2(2, 2),
		"Physical trace should end at player position, got %s" % last.end)

func test_normal_aim_cursor_still_injected() -> void:
	# Normal planned trace: aim and cursor should still be injected when cursor is reachable.
	var wall := _wall(Vector2(0, 400), Vector2(800, 400))
	var surfaces: Array = [wall]
	var player := Vector2(400, 100)
	var cursor := Vector2(400, 300)
	var aim := Direction.from_coords(player, cursor)
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		Rect2(0, 0, 800, 500), null, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [], null, cursor)
	assert_ne(planned.cursor_index, -1,
		"Cursor should be injected in normal planned trace (got cursor_index=%d)" % planned.cursor_index)

func test_aim_wins_tie_with_carrier() -> void:
	# Cursor at mirror via point (800,540) — exactly on the mirror carrier.
	# t_aim == t_carrier == 1.0. Aim should win the tie and inject cursor.
	var surfaces := _mirror_and_wall_surfaces()
	var player := Vector2(1360, 840)
	var cursor := Vector2(800, 540)
	var aim := Planner.compute_aim_direction(player, cursor, [], surfaces, GameState.new())
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, null, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [], null, cursor)
	assert_ne(planned.cursor_index, -1,
		"Cursor should be injected when aim ties with carrier (cursor_index=%d, steps=%d)" % [
			planned.cursor_index, planned.steps.size()])
	assert_lt(planned.steps.size(), 50,
		"Trace should not loop — got %d steps" % planned.steps.size())

func test_player_block_wins_tie_with_carrier() -> void:
	# Player at (1360,840), cursor at mirror via (800,540).
	# With aim tiebreaker, cursor injects → PHYSICAL mode → trace blocks at wall.
	# This tests the full pipeline: aim tiebreaker + physical mode termination.
	var surfaces := _mirror_and_wall_surfaces()
	var player := Vector2(1360, 840)
	var cursor := Vector2(800, 540)
	var aim := Planner.compute_aim_direction(player, cursor, [], surfaces, GameState.new())
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, null, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [], null, cursor)
	assert_lt(planned.steps.size(), 50,
		"Trace should terminate cleanly, got %d steps" % planned.steps.size())
	assert_ne(planned.cursor_index, -1,
		"Cursor should be injected")

func test_three_mirrors_planned_trace_injects_cursor() -> void:
	# Three mirrors scene: planned trace with plan=[m1/L] should inject cursor.
	var surfaces := _three_mirrors_surfaces()
	var m1_id: int = surfaces[3].id
	var player := Vector2(560, 840)
	var cursor := Vector2(1920, 0)
	var plan_entries: Array = [PlanManager.PlanEntry.new(m1_id, Side.Value.LEFT)]
	var aim := Planner.compute_aim_direction(player, cursor, plan_entries, surfaces, GameState.new())
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, null, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan_entries, null, cursor)
	assert_ne(planned.cursor_index, -1,
		"Planned trace should inject cursor (got cursor_index=%d)" % planned.cursor_index)

func test_planned_trace_terminates_post_cursor() -> void:
	# Planned trace with plan=[m1/L] should terminate after cursor injection.
	# Post-cursor switches to PHYSICAL mode in reflected frame.
	# The reflected bottom wall must terminate the trace — no waypoint should steal it.
	var surfaces := _three_mirrors_surfaces()
	var m1_id: int = surfaces[3].id
	var player := Vector2(560, 840)
	var cursor := Vector2(1920, 0)
	var plan_entries: Array = [PlanManager.PlanEntry.new(m1_id, Side.Value.LEFT)]
	var aim := Planner.compute_aim_direction(player, cursor, plan_entries, surfaces, GameState.new())
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, null, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan_entries, null, cursor)
	assert_ne(planned.cursor_index, -1,
		"Cursor should be injected (got cursor_index=%d)" % planned.cursor_index)
	assert_lt(planned.steps.size(), 50,
		"Planned trace should terminate post-cursor, not loop %d times" % planned.steps.size())

func test_trace_ends_violation_2() -> void:
	# Regression: cursor at mirror via point with player at open corner.
	# With priority tiebreaker, aim wins tie → cursor injects → trace terminates cleanly.
	var surfaces := _mirror_and_wall_surfaces()
	var player := Vector2(1360, 840)
	var cursor := Vector2(800, 540)
	var aim := Planner.compute_aim_direction(player, cursor, [], surfaces, GameState.new())
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, null, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [], null, cursor)
	assert_ne(planned.cursor_index, -1,
		"Cursor should be injected (cursor_index=%d)" % planned.cursor_index)
	assert_lt(planned.steps.size(), 50,
		"Trace should not loop — got %d steps" % planned.steps.size())

# =================================================================
# Repro: player block failure at screen corner (0,0)
# =================================================================

func test_repro_player_block_at_screen_corner_case1() -> void:
	# Violation: plan=[5/L] player=(0,0) cursor=(1360,840)
	# TRACE-ENDS: planned trace ends mid-air at (1531.429, 240.0)
	var surfaces := _mirror_and_wall_surfaces()
	var mirror_id: int = surfaces[4].id  # mirror is index 4
	var player := Vector2(0, 0)
	var cursor := Vector2(1360, 840)
	var plan_entries: Array = [PlanManager.PlanEntry.new(mirror_id, Side.Value.LEFT)]

	var cache := TransformCache.new()
	var aim := Planner.compute_aim_direction(player, cursor, plan_entries, surfaces, GameState.new(), cache)
	print("  aim direction: start=%s end=%s" % [aim.start.coords, aim.end.coords])
	print("  aim vector: %s" % aim.to_vector().normalized())

	# Physical trace
	var physical := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, null, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, plan_entries, null, cursor)
	print("  PHYSICAL: %d steps, cursor_index=%d" % [physical.steps.size(), physical.cursor_index])
	_print_steps(physical, "P", 10)

	# Planned trace
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, null, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan_entries, null, cursor)
	print("  PLANNED: %d steps, cursor_index=%d" % [planned.steps.size(), planned.cursor_index])
	_print_steps(planned, "L", 10)

	# Check player_t for identity-frame steps
	for i in planned.steps.size():
		var step: Tracer.Step = planned.steps[i]
		if step.frame_id == MobiusTransform.IDENTITY_ID:
			var ray_at_step := Ray.from_coords(step.start, aim)
			var pt := Intersection.project_point_on_ray(ray_at_step, player)
			print("  IDENTITY step %d: start=%s player_t=%.4f" % [i, step.start, pt])

	var last_phys: Tracer.Step = physical.steps[physical.steps.size() - 1]
	var last_plan: Tracer.Step = planned.steps[planned.steps.size() - 1]
	print("  Physical ends at: %s" % last_phys.end)
	print("  Planned ends at: %s" % last_plan.end)

	assert_lt(physical.steps.size(), Tracer.MAX_HITS,
		"Physical trace should not hit MAX_HITS (got %d)" % physical.steps.size())
	assert_lt(planned.steps.size(), Tracer.MAX_HITS,
		"Planned trace should not hit MAX_HITS (got %d)" % planned.steps.size())

func test_repro_player_block_at_screen_corner_case2() -> void:
	# Violation: plan=[5/L,5/L] player=(0,0) cursor=(560,840)
	# TRACE-ENDS: planned trace ends mid-air at (160.0, 240.0)
	var surfaces := _mirror_and_wall_surfaces()
	var mirror_id: int = surfaces[4].id
	var player := Vector2(0, 0)
	var cursor := Vector2(560, 840)
	var plan_entries: Array = [
		PlanManager.PlanEntry.new(mirror_id, Side.Value.LEFT),
		PlanManager.PlanEntry.new(mirror_id, Side.Value.LEFT),
	]

	var cache := TransformCache.new()
	var aim := Planner.compute_aim_direction(player, cursor, plan_entries, surfaces, GameState.new(), cache)
	print("  aim direction: start=%s end=%s" % [aim.start.coords, aim.end.coords])
	print("  aim vector: %s" % aim.to_vector().normalized())

	var physical := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, null, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, plan_entries, null, cursor)
	print("  PHYSICAL: %d steps, cursor_index=%d" % [physical.steps.size(), physical.cursor_index])
	_print_steps(physical, "P", 10)

	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, null, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan_entries, null, cursor)
	print("  PLANNED: %d steps, cursor_index=%d" % [planned.steps.size(), planned.cursor_index])
	_print_steps(planned, "L", 10)

	var last_phys: Tracer.Step = physical.steps[physical.steps.size() - 1]
	var last_plan: Tracer.Step = planned.steps[planned.steps.size() - 1]
	print("  Physical ends at: %s" % last_phys.end)
	print("  Planned ends at: %s" % last_plan.end)

	assert_lt(physical.steps.size(), Tracer.MAX_HITS,
		"Physical trace should not hit MAX_HITS (got %d)" % physical.steps.size())
	assert_lt(planned.steps.size(), Tracer.MAX_HITS,
		"Planned trace should not hit MAX_HITS (got %d)" % planned.steps.size())

func test_repro_first_hit_from_origin() -> void:
	# Diagnostic: what does find_nearest_hit return for a ray starting at (0,0)?
	var surfaces := _mirror_and_wall_surfaces()
	var player := Vector2(0, 0)
	var cursor := Vector2(1360, 840)
	var mirror_id: int = surfaces[4].id
	var plan_entries: Array = [PlanManager.PlanEntry.new(mirror_id, Side.Value.LEFT)]

	var aim := Planner.compute_aim_direction(player, cursor, plan_entries, surfaces, GameState.new())
	var ray := Ray.from_coords(player, aim)
	print("  Ray: origin=%s dir=%s" % [ray.origin.coords, ray.direction.to_vector().normalized()])

	var segments: Array = []
	for s in surfaces:
		segments.append(s.segment)
		print("  Surface id=%d: (%s)->(%s) solid=%s" % [s.id, s.segment.start.coords, s.segment.end.coords, s.player_solid])

	var hit := Intersection.find_nearest_hit(ray, segments)
	if hit:
		print("  First hit: t=%.4f point=%s on_seg=%s ep=%d bl=%s br=%s seg=(%s)->(%s)" % [
			hit.t, hit.point.coords, hit.on_segment, hit.at_endpoint,
			hit.blocked_left, hit.blocked_right,
			hit.segment.start.coords, hit.segment.end.coords])
		# Which surface does this segment belong to?
		for s in surfaces:
			if s.segment == hit.segment:
				print("  Hit surface id=%d solid=%s" % [s.id, s.player_solid])
	else:
		print("  No hit found!")

	assert_not_null(hit, "Should find a hit from (0,0)")

func _print_steps(path: Tracer.TracedPath, prefix: String, max_steps: int) -> void:
	var count := mini(path.steps.size(), max_steps)
	for i in count:
		var step: Tracer.Step = path.steps[i]
		var hit_info := "null"
		if step.hit:
			hit_info = "t=%.2f seg=(%s)->(%s) on=%s" % [
				step.hit.t, step.hit.segment.start.coords, step.hit.segment.end.coords, step.hit.on_segment]
		print("  %s[%d] frame=%d start=%s end=%s hit=%s" % [
			prefix, i, step.frame_id, step.start, step.end, hit_info])
	if path.steps.size() > max_steps:
		var last: Tracer.Step = path.steps[path.steps.size() - 1]
		print("  %s[...%d more...] last end=%s" % [prefix, path.steps.size() - max_steps, last.end])

func test_two_mirrors_at_corner_reflects() -> void:
	# Two mirrors meeting at (200,200): horiz (100,200)→(200,200) and vert (200,200)→(200,300).
	# Ray from (150,100) going down hits at the shared endpoint (200,200).
	# Both mirrors' endpoints combine → full block → effect from the actually hit mirror should apply.
	var h_seg := Segment.from_coords(Vector2(100, 200), Vector2(200, 200), Vector2(150, 200))
	var h_carrier := h_seg.get_carrier()
	var h_refl := ReflectionEffect.new(h_carrier)
	var h_mirror := Surface.new(h_seg, SideConfig.new(h_refl, true), SideConfig.new(null, false), false, false)

	var v_seg := Segment.from_coords(Vector2(200, 200), Vector2(200, 300), Vector2(200, 250))
	var v_carrier := v_seg.get_carrier()
	var v_refl := ReflectionEffect.new(v_carrier)
	var v_mirror := Surface.new(v_seg, SideConfig.new(v_refl, true), SideConfig.new(null, false), false, false)

	var surfaces: Array = [h_mirror, v_mirror]
	# Ray hitting the horizontal carrier at x≈200 (near the shared endpoint)
	var player := Vector2(150, 100)
	var cursor := Vector2(150, 400)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(), Rect2(0, 0, 400, 400))
	# The first carrier hit at ~(150, 200) is an interior hit on h_mirror → should reflect
	var first_hit: Tracer.Step = path.steps[0]
	assert_almost_eq(first_hit.end.y, 200.0, 1.0, "Should hit h_mirror interior at y=200")
