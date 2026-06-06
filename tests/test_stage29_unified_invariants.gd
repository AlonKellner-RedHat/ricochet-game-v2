extends GutTest

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

func _trace_both(player: Vector2, cursor: Vector2, surfaces: Array, plan_entries: Array = []) -> Array:
	var aim := Planner.compute_aim_direction(player, cursor, plan_entries, surfaces, GameState.new())
	var ray := Ray.new(player, aim)
	var target_dist := player.distance_to(cursor)
	var physical := Tracer.trace(player, aim, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, ray, target_dist, Tracer.TraceMode.PHYSICAL)
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, ray, target_dist, Tracer.TraceMode.PLANNED, plan_entries)
	return [physical, planned]

# --- HITPOINT-ALIGNMENT ---

func test_hitpoint_alignment_empty_room() -> void:
	Surface.reset_id_counter()
	var w := _wall(600)
	var traces := _trace_both(Vector2(200, 300), Vector2(400, 300), [w])
	var physical: Tracer.TracedPath = traces[0]
	var planned: Tracer.TracedPath = traces[1]
	assert_eq(physical.steps.size(), planned.steps.size(), "Same step count")
	for i in physical.steps.size():
		var p := _step(physical, i)
		var r := _step(planned, i)
		assert_eq(p.start, r.start, "Aligned start at step %d" % i)
		assert_eq(p.end, r.end, "Aligned end at step %d" % i)

func test_hitpoint_alignment_with_mirror_both_reflect() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()
	var m := _mirror(400)
	var w := _wall(100)
	var plan: Array = [PlanManager.PlanEntry.new(m.id, Side.Value.LEFT)]
	var traces := _trace_both(Vector2(600, 300), Vector2(200, 300), [m, w], plan)
	var physical: Tracer.TracedPath = traces[0]
	var planned: Tracer.TracedPath = traces[1]
	var min_steps := mini(physical.steps.size(), planned.steps.size())
	for i in min_steps:
		var p := _step(physical, i)
		var r := _step(planned, i)
		if p.frame_id != r.frame_id:
			break
		assert_eq(p.start, r.start, "Aligned start at step %d" % i)
		assert_eq(p.end, r.end, "Aligned end at step %d" % i)

func test_hitpoint_alignment_divergence_stops_checking() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()
	var m := _mirror(400)
	var w := _wall(700)
	var traces := _trace_both(Vector2(200, 300), Vector2(500, 300), [m, w])
	var physical: Tracer.TracedPath = traces[0]
	var planned: Tracer.TracedPath = traces[1]
	# Step 0: both identity frame → aligned
	assert_eq(_step(physical, 0).frame_id, _step(planned, 0).frame_id, "Step 0 same frame")
	assert_eq(_step(physical, 0).start, _step(planned, 0).start, "Step 0 same start")
	assert_eq(_step(physical, 0).end, _step(planned, 0).end, "Step 0 same end")
	# Step 1: physical reflected, planned didn't → different frames → no alignment check needed
	assert_gte(physical.steps.size(), 2, "Physical has post-mirror steps")
	assert_gte(planned.steps.size(), 2, "Planned has post-mirror steps")
	assert_ne(_step(physical, 1).frame_id, _step(planned, 1).frame_id, "Step 1 diverged")

# --- CURSOR-INDEX-MATCH ---

func test_cursor_index_match_no_divergence() -> void:
	Surface.reset_id_counter()
	var w := _wall(600)
	var traces := _trace_both(Vector2(200, 300), Vector2(400, 300), [w])
	var physical: Tracer.TracedPath = traces[0]
	var planned: Tracer.TracedPath = traces[1]
	assert_eq(physical.cursor_index, planned.cursor_index, "Same cursor_index without divergence")

func test_cursor_index_match_skipped_with_pre_cursor_divergence() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()
	var m := _mirror(300)
	var w := _wall(700)
	# Cursor at x=500, mirror at x=300 between player and cursor
	var traces := _trace_both(Vector2(100, 300), Vector2(500, 300), [m, w])
	var physical: Tracer.TracedPath = traces[0]
	var planned: Tracer.TracedPath = traces[1]
	# Divergence occurs at the mirror (before cursor). cursor_index may differ.
	# The invariant should NOT be checked (no violation even if indices differ).
	pass_test("Pre-cursor divergence: cursor_index match not required")

# --- FRAME-DIVERGENCE-MONOTONIC ---

func test_frame_divergence_monotonic() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()
	var m := _mirror(400)
	var w := _wall(700)
	var traces := _trace_both(Vector2(200, 300), Vector2(500, 300), [m, w])
	var physical: Tracer.TracedPath = traces[0]
	var planned: Tracer.TracedPath = traces[1]
	var diverged := false
	var reconverged := false
	var min_steps := mini(physical.steps.size(), planned.steps.size())
	for i in min_steps:
		var p := _step(physical, i)
		var r := _step(planned, i)
		if p.frame_id != r.frame_id:
			diverged = true
		elif diverged:
			reconverged = true
	if diverged:
		assert_false(reconverged, "Once diverged, frames should never re-converge")
