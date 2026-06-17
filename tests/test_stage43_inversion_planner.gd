extends GutTest

const H := preload("res://tests/test_helpers.gd")

func before_each() -> void:
	H.reset_counters()

func _inversion_surface() -> Surface:
	var seg := Segment.from_coords(Vector2(200, 100), Vector2(200, 300), Vector2(300, 200))
	var carrier := seg.get_carrier()
	var inv := CircleInversionEffect.new(carrier)
	var left := SideConfig.new(inv, true)
	var right := SideConfig.new(null, false)
	return Surface.new(seg, left, right, false, false)

func _s16_2_surfaces() -> Array:
	var inv_surf := _inversion_surface()
	var w_left := H.wall(0)
	var w_right := H.wall(600)
	var w_top := RoomBuilder.create_block_surface(Vector2(0, 0), Vector2(600, 0), Vector2(300, 0))
	var w_bot := RoomBuilder.create_block_surface(Vector2(0, 400), Vector2(600, 400), Vector2(300, 400))
	return [inv_surf, w_left, w_right, w_top, w_bot]

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

# --- Test 1: Image chain computation ---

func test_stage43_inversion_image_chain() -> void:
	var inv_surf := _inversion_surface()
	var plan := [PlanManager.PlanEntry.new(inv_surf.id, Side.Value.LEFT)]
	var cursor := Vector2(400, 200)
	var image = Planner._compute_image(cursor, plan, [inv_surf], GameState.new())
	assert_not_null(image, "Image should not be null")
	assert_almost_eq(image, Vector2(250, 200), Vector2(0.1, 0.1),
		"Image of (400,200) through inversion center=(200,200) r=100 should be (250,200)")

# --- Test 2: Bounce point on carrier ---

func test_stage43_bounce_point_on_carrier() -> void:
	var inv_surf := _inversion_surface()
	var plan := [PlanManager.PlanEntry.new(inv_surf.id, Side.Value.LEFT)]
	var player := Vector2(50, 200)
	var cursor := Vector2(400, 200)
	var planned_path := Planner.plan_transformative_subchain(player, cursor, plan, [inv_surf], GameState.new())
	assert_gt(planned_path.steps.size(), 0, "Should have steps")
	var first_step: Tracer.Step = planned_path.steps[0]
	assert_almost_eq(first_step.end, Vector2(300, 200), Vector2(1, 1),
		"Bounce should be at (300,200) on the arc, not (100,200) off the arc")

# --- Test 3: Full S16.2 plan-physical merge produces valid result ---

func test_stage43_S16_2_plan_physical_aligned() -> void:
	var surfaces := _s16_2_surfaces()
	var inv_surf: Surface = surfaces[0]
	var plan := [PlanManager.PlanEntry.new(inv_surf.id, Side.Value.LEFT)]
	var player := Vector2(50, 200)
	var cursor := Vector2(400, 200)
	var result := _trace_both(surfaces, player, cursor, plan)
	var physical: Tracer.TracedPath = result.physical
	var planned: Tracer.TracedPath = result.planned
	assert_gt(physical.steps.size(), 0, "Physical trace should have steps")
	assert_gt(planned.steps.size(), 0, "Planned trace should have steps")
	var ci := planned.cursor_index if planned.cursor_index >= 0 else planned.steps.size()
	var merged := StepTreeMerge.merge(planned.steps, physical.steps, ci)
	assert_gt(merged.size(), 0, "Merged steps should not be empty")
	var first: Tracer.Step = merged[0]
	assert_eq(first.type, StepTypes.Type.ALIGNED,
		"First step should be ALIGNED (both traces agree on path to arc surface)")

# --- Test 4: Planned step count ---

func test_stage43_planned_step_count() -> void:
	var inv_surf := _inversion_surface()
	var plan := [PlanManager.PlanEntry.new(inv_surf.id, Side.Value.LEFT)]
	var player := Vector2(50, 200)
	var cursor := Vector2(400, 200)
	var planned_path := Planner.plan_transformative_subchain(player, cursor, plan, [inv_surf], GameState.new())
	assert_eq(planned_path.steps.size(), 2,
		"Should have exactly 2 steps (origin-to-bounce, bounce-to-cursor), got %d" % planned_path.steps.size())

# --- Test 5: Planned visual path has arc ---

func test_stage43_planned_visual_path_has_arc() -> void:
	var surfaces := _s16_2_surfaces()
	var inv_surf: Surface = surfaces[0]
	var plan := [PlanManager.PlanEntry.new(inv_surf.id, Side.Value.LEFT)]
	var player := Vector2(50, 200)
	var cursor := Vector2(400, 200)
	var cache := TransformCache.new()
	var aim := Planner.compute_aim_direction(player, cursor, plan, surfaces, GameState.new(), cache)
	var aim_ray := Ray.from_coords(player, aim)
	var planned := Tracer.trace(player, aim, surfaces, GameState.new(),
		aim_ray, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan, cache, cursor)
	var found_arc := false
	for step in planned.steps:
		var s: Tracer.Step = step
		if s.is_arc_step:
			found_arc = true
	assert_true(found_arc, "Planned path should have an arc step after inversion")

# --- Test 6: Inversion unreachable (cursor at center) ---

func test_stage43_inversion_unreachable() -> void:
	var inv_surf := _inversion_surface()
	var plan := [PlanManager.PlanEntry.new(inv_surf.id, Side.Value.LEFT)]
	var player := Vector2(50, 200)
	var cursor := Vector2(200, 200)
	var aim := Planner.compute_aim_direction(player, cursor, plan, [inv_surf], GameState.new())
	assert_false(aim.is_zero_length(), "Should produce a valid direction even when image is degenerate")
	var dir_vec := aim.to_vector().normalized()
	var expected_dir := (cursor - player).normalized()
	assert_almost_eq(dir_vec, expected_dir, Vector2(0.01, 0.01),
		"Should fall back to direct aim toward cursor")

# --- Test 7: Double inversion plan ---

func test_stage43_double_inversion_plan() -> void:
	var inv_surf := _inversion_surface()
	var plan := [
		PlanManager.PlanEntry.new(inv_surf.id, Side.Value.LEFT),
		PlanManager.PlanEntry.new(inv_surf.id, Side.Value.LEFT),
	]
	var cursor := Vector2(400, 200)
	var image = Planner._compute_image(cursor, plan, [inv_surf], GameState.new())
	assert_not_null(image, "Double inversion image should not be null")
	assert_almost_eq(image, cursor, Vector2(0.5, 0.5),
		"Double inversion = identity: image should equal cursor")

# --- Test 8: Planned trace applies inversion (frame_id changes) ---

func test_stage43_S5_aligned_provenance() -> void:
	var surfaces := _s16_2_surfaces()
	var inv_surf: Surface = surfaces[0]
	var plan := [PlanManager.PlanEntry.new(inv_surf.id, Side.Value.LEFT)]
	var player := Vector2(50, 200)
	var cursor := Vector2(400, 200)
	var result := _trace_both(surfaces, player, cursor, plan)
	var planned: Tracer.TracedPath = result.planned
	assert_gt(planned.steps.size(), 1, "Planned trace should have multiple steps")
	var first_step: Tracer.Step = planned.steps[0]
	assert_eq(first_step.frame_id, MobiusTransform.IDENTITY_ID,
		"First planned step should be in identity frame (before inversion)")
	var found_inverted := false
	for step in planned.steps:
		var s: Tracer.Step = step
		if s.frame_id != MobiusTransform.IDENTITY_ID:
			found_inverted = true
	assert_true(found_inverted, "Planned trace should have steps in inverted frame")

# --- Test 9: Merged alignment has correct step types ---

func test_stage43_S6_aligned_match() -> void:
	var surfaces := _s16_2_surfaces()
	var inv_surf: Surface = surfaces[0]
	var plan := [PlanManager.PlanEntry.new(inv_surf.id, Side.Value.LEFT)]
	var player := Vector2(50, 200)
	var cursor := Vector2(400, 200)
	var result := _trace_both(surfaces, player, cursor, plan)
	var physical: Tracer.TracedPath = result.physical
	var planned: Tracer.TracedPath = result.planned
	var ci := planned.cursor_index if planned.cursor_index >= 0 else planned.steps.size()
	var merged := StepTreeMerge.merge(planned.steps, physical.steps, ci)
	var aligned_count := 0
	for step in merged:
		var s: Tracer.Step = step
		if s.type == StepTypes.Type.ALIGNED or s.type == StepTypes.Type.ALIGNED_POST_PLANNED:
			aligned_count += 1
	assert_gt(aligned_count, 0, "Should have at least one aligned step in merge")

# --- Test 10: Full circle in planner ---

func test_stage43_full_circle_in_planner() -> void:
	var seg := Segment.from_coords(Vector2(300.0, 200.001), Vector2(300.0, 199.999), Vector2(100, 200))
	var carrier := seg.get_carrier()
	var inv := CircleInversionEffect.new(carrier)
	var left := SideConfig.new(inv, true)
	var right := SideConfig.new(null, false)
	var surf := Surface.new(seg, left, right, false, false)
	var plan := [PlanManager.PlanEntry.new(surf.id, Side.Value.LEFT)]
	var cursor := Vector2(400, 200)
	var image = Planner._compute_image(cursor, plan, [surf], GameState.new())
	assert_not_null(image, "Full circle image should compute")
	assert_false(is_nan(image.x) or is_nan(image.y), "No NaN in image")
	assert_false(is_inf(image.x) or is_inf(image.y), "No Inf in image")

# --- Test 11: Two forward hits on circle carrier ---

func test_stage43_aim_line_two_forward_hits() -> void:
	var inv_surf := _inversion_surface()
	var player := Vector2(50, 200)
	var cursor := Vector2(400, 200)
	var plan := [PlanManager.PlanEntry.new(inv_surf.id, Side.Value.LEFT)]
	var image = Planner._compute_image(cursor, plan, [inv_surf], GameState.new())
	var aim_dir := Direction.from_coords(player, image)
	var aim_ray := Ray.from_coords(player, aim_dir)
	var carrier := inv_surf.segment.get_carrier()
	var hits := Intersection.intersect_line_with_carrier(aim_ray, carrier)
	assert_eq(hits.size(), 2, "Should have 2 carrier hits on circle")
	var h0: Dictionary = hits[0]
	var h1: Dictionary = hits[1]
	assert_true(h0.t > 0 and h1.t > 0, "Both hits should be forward (t > 0)")
	var planned_path := Planner.plan_transformative_subchain(player, cursor, plan, [inv_surf], GameState.new())
	assert_gt(planned_path.steps.size(), 0, "Should have steps")
	var bounce: Vector2 = planned_path.steps[0].end
	assert_almost_eq(bounce, Vector2(300, 200), Vector2(1, 1),
		"Should pick (300,200) which is on the arc, not (100,200) which is off the arc")
