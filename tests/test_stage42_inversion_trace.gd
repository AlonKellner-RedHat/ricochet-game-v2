extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()

func _inversion_surface() -> Surface:
	var seg := Segment.from_coords(Vector2(200, 100), Vector2(200, 300), Vector2(300, 200))
	var carrier := seg.get_carrier()
	var inv := CircleInversionEffect.new(carrier)
	var left := SideConfig.new(inv, true)
	var right := SideConfig.new(null, false)
	return Surface.new(seg, left, right, false, false)

func _wall(x: float) -> Surface:
	return RoomBuilder.create_block_surface(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))

# --- Step 1: Purple rendering ---

func test_stage42_purple_rendering() -> void:
	var surf := _inversion_surface()
	var state := GameState.new()
	var left_config := surf.active_side_config(Side.Value.LEFT, state)
	assert_true(left_config.effect is CircleInversionEffect, "Left side is CircleInversionEffect")
	var node := Node2D.new()
	node.set_script(load("res://scripts/game/surface_node.gd"))
	add_child_autofree(node)
	node.setup(surf)
	var color: Color = node._effect_color(left_config)
	assert_eq(color, Color.PURPLE, "Inversion surfaces render purple")

# --- Step 3: Surface creation ---

func test_stage42_inversion_surface_creation() -> void:
	var surf := _inversion_surface()
	var carrier := surf.segment.get_carrier()
	assert_false(carrier.is_line(), "Carrier is a circle, not a line")
	assert_almost_eq(carrier.center(), Vector2(200, 200), Vector2(0.1, 0.1), "Center = (200,200)")
	assert_almost_eq(carrier.radius(), 100.0, 0.1, "Radius = 100")

# --- Step 4: Physical trace through inversion ---

func _trace_outside_in(plan_entries: Array = []) -> Tracer.TracedPath:
	# Player approaches the arc from outside (right side), hitting the LEFT (outer) side.
	# Ray at y=250 (not y=200) to avoid passing through the inversion center,
	# which would keep the post-inversion path as a straight line instead of an arc.
	var inv_surf := _inversion_surface()
	var w_left := _wall(0)
	var w_right := _wall(600)
	var w_top := RoomBuilder.create_block_surface(Vector2(0, 0), Vector2(600, 0), Vector2(300, 0))
	var w_bot := RoomBuilder.create_block_surface(Vector2(0, 400), Vector2(600, 400), Vector2(300, 400))
	var surfaces: Array = [inv_surf, w_left, w_right, w_top, w_bot]
	var player := Vector2(450, 250)
	var cursor := Vector2(50, 250)
	var aim := Planner.compute_aim_direction(player, cursor, plan_entries, surfaces, GameState.new())
	return Tracer.trace(player, aim, surfaces, GameState.new(), Rect2(0, 0, 600, 400),
		null, -1.0, Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, plan_entries, null, cursor)

func test_stage42_trace_through_inversion() -> void:
	var path := _trace_outside_in()
	assert_gt(path.steps.size(), 1, "Trace should have multiple steps")
	var found_hit := false
	for step in path.steps:
		var s: Tracer.Step = step
		if s.hit != null and s.hit.on_segment:
			found_hit = true
			break
	assert_true(found_hit, "Should hit the inversion surface on-segment")

func test_stage42_frame_after_inversion() -> void:
	# Player approaches from outside the circle (right side), hitting the arc's outer (LEFT) side
	var inv_surf := _inversion_surface()
	var w := _wall(0)
	var surfaces: Array = [inv_surf, w]
	var player := Vector2(450, 200)
	var cursor := Vector2(50, 200)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(), Rect2(0, 0, 600, 400))
	var found_non_identity := false
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame_id != MobiusTransform.IDENTITY_ID:
			found_non_identity = true
			assert_true(s.frame.conjugating, "Post-inversion frame is anti-conformal")
			break
	assert_true(found_non_identity, "Should have a step with non-identity frame after inversion")

func test_stage42_origin_advance_self_inverse() -> void:
	var carrier := GeneralizedCircle.from_circle(Vector2(200, 200), 100.0)
	var inv := CircleInversionEffect.new(carrier)
	var hit_point := Vector2(300, 200)
	var advanced := inv.get_inverse_mobius().apply(hit_point)
	assert_almost_eq(advanced, Vector2(300, 200), Vector2(0.01, 0.01),
		"Point on circle maps to itself under self-inverse")

func test_stage42_inversion_direction_unchanged() -> void:
	var inv_surf := _inversion_surface()
	var w := _wall(600)
	var surfaces: Array = [inv_surf, w]
	var player := Vector2(50, 200)
	var cursor := Vector2(400, 200)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(), Rect2(0, 0, 600, 400))
	for step in path.steps:
		var s: Tracer.Step = step
		assert_eq(s.ray.direction, aim, "Direction reference stays the same (transformative)")

func test_stage42_S16_2_full_reproduction() -> void:
	var path := _trace_outside_in()
	assert_gt(path.steps.size(), 0, "Should produce steps")
	var first: Tracer.Step = path.steps[0]
	assert_almost_eq(first.start, Vector2(450, 250), Vector2(1, 1), "First step starts at player")

func test_stage42_S16_no_nan_in_trace() -> void:
	var path := _trace_outside_in()
	for step in path.steps:
		var s: Tracer.Step = step
		assert_false(is_nan(s.start.x) or is_nan(s.start.y), "No NaN in start: %s" % s.start)
		assert_false(is_nan(s.end.x) or is_nan(s.end.y), "No NaN in end: %s" % s.end)
		assert_false(is_inf(s.start.x) or is_inf(s.start.y), "No Inf in start: %s" % s.start)

func test_stage42_visual_path_contains_arc() -> void:
	var plan := [PlanManager.PlanEntry.new(1, Side.Value.LEFT)]
	var path := _trace_outside_in(plan)
	var found_arc := false
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		gut.p("  step[%d] fid=%d is_arc=%s c=%s" % [i, s.frame_id, s.is_arc_step, s.frame.c])
		if s.is_arc_step:
			found_arc = true
	assert_true(found_arc, "Post-inversion step should be marked as arc")

func test_stage42_transform_all_line_becomes_circle() -> void:
	var carrier := GeneralizedCircle.from_circle(Vector2(200, 200), 100.0)
	var inv := CircleInversionEffect.new(carrier)
	var line_seg := Segment.from_coords(Vector2(50, 100), Vector2(50, 300), Vector2(50, 200))
	assert_true(line_seg.is_line(), "Original segment is a line")
	var m_inv := inv.get_mobius().invert()
	var s := m_inv.apply(line_seg.start.coords)
	var e := m_inv.apply(line_seg.end.coords)
	var v := m_inv.apply(line_seg.via.coords)
	var transformed := Segment.from_coords(s, e, v)
	assert_false(transformed.is_line(), "Line becomes circle under inversion")
