extends GutTest

const H := preload("res://tests/test_helpers.gd")
const TOL := Vector2(1.0, 1.0)

func before_each() -> void:
	H.reset_counters()

# --- Helpers ---

func _vertical_seg(x: float) -> Segment:
	return Segment.from_coords(Vector2(x, 100), Vector2(x, 500), Vector2(x, 300))

func _horizontal_seg(y: float) -> Segment:
	return Segment.from_coords(Vector2(100, y), Vector2(500, y), Vector2(300, y))

func _projective_surface(seg: Segment, project_back: bool = false) -> Surface:
	var effect := LineNormalProjection.new(project_back)
	var config := SideConfig.new(effect, true)
	return Surface.new(seg, config, config, false, false)

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

# --- Test 1: apply_forward on vertical line ---

func test_stage73_apply_forward_vertical_line() -> void:
	var seg := _vertical_seg(250.0)
	var effect := LineNormalProjection.new()
	var hit_point := Vector2(250, 200)
	var result := effect.apply_forward(hit_point, seg, Side.Value.LEFT)
	assert_not_null(result, "apply_forward should return a Ray")
	assert_almost_eq(result.origin.coords, hit_point, TOL,
		"Origin should be at hit point")
	var dir_vec := result.direction.to_normalized()
	assert_almost_eq(absf(dir_vec.x), 1.0, 0.01,
		"Direction should be horizontal (|x| = 1)")
	assert_almost_eq(dir_vec.y, 0.0, 0.01,
		"Direction should be horizontal (y = 0)")

# --- Test 2: direction is perpendicular to surface ---

func test_stage73_apply_forward_direction_is_perpendicular() -> void:
	var effect := LineNormalProjection.new()
	# Vertical line -> horizontal output
	var v_seg := _vertical_seg(250.0)
	var v_result := effect.apply_forward(Vector2(250, 200), v_seg, Side.Value.LEFT)
	var v_dir := v_result.direction.to_normalized()
	var v_line_dir := Vector2(0, 1)
	assert_almost_eq(absf(v_dir.dot(v_line_dir)), 0.0, 0.01,
		"Vertical line: output should be perpendicular to line direction")
	# Horizontal line -> vertical output
	var h_seg := _horizontal_seg(300.0)
	var h_result := effect.apply_forward(Vector2(200, 300), h_seg, Side.Value.LEFT)
	var h_dir := h_result.direction.to_normalized()
	var h_line_dir := Vector2(1, 0)
	assert_almost_eq(absf(h_dir.dot(h_line_dir)), 0.0, 0.01,
		"Horizontal line: output should be perpendicular to line direction")

# --- Test 3: back_propagate within segment ---

func test_stage73_back_propagate_within_segment() -> void:
	var seg := _vertical_seg(250.0)
	var effect := LineNormalProjection.new()
	var result = effect.back_propagate(Vector2(400, 300), seg)
	assert_not_null(result, "Should return projected point within segment")
	assert_almost_eq(result, Vector2(250, 300), TOL,
		"Projection of (400,300) onto x=250 should be (250,300)")

# --- Test 4: back_propagate outside segment ---

func test_stage73_back_propagate_outside_segment() -> void:
	var seg := _vertical_seg(250.0)
	var effect := LineNormalProjection.new()
	var result = effect.back_propagate(Vector2(400, 600), seg)
	assert_null(result, "Should return null when projection falls outside segment")

# --- Test 5: S10 - frame resets to identity after projective hit ---

func test_stage73_S10_frame_resets_to_identity() -> void:
	var surfaces := _room_walls()
	# Portal pair to change frame from identity before hitting projective
	var source_seg := Segment.from_coords(
		Vector2(200, 100), Vector2(200, 500), Vector2(200, 300))
	var portal_data := RigidMotionEffect.create_portal_pair(source_seg, 0.0, Vector2(100, 0))
	var src_cfg := SideConfig.new(portal_data.source_effect, true)
	var tgt_cfg := SideConfig.new(portal_data.target_effect, true)
	var source_surf := Surface.new(source_seg, src_cfg, src_cfg, false, false)
	var target_surf := Surface.new(portal_data.target_segment, tgt_cfg, tgt_cfg, false, false)
	surfaces.append(source_surf)
	surfaces.append(target_surf)
	# Projective surface after portal exit
	var proj_seg := _vertical_seg(500.0)
	var proj_surf := _projective_surface(proj_seg)
	surfaces.append(proj_surf)
	# Horizontal trace through portal then projective
	var path := _trace(Vector2(50, 300), Vector2(750, 300), surfaces)
	# Find the step hitting the projective surface
	var found_post_projective := false
	for i in range(path.steps.size()):
		var step: Tracer.Step = path.steps[i]
		if step.surface_id == proj_surf.id:
			if i + 1 < path.steps.size():
				var post_step: Tracer.Step = path.steps[i + 1]
				assert_eq(post_step.frame_id, MobiusTransform.IDENTITY_ID,
					"Frame should reset to identity after projective hit")
				found_post_projective = true
			break
	assert_true(found_post_projective, "Should have a step after the projective surface")

# --- Test 6: new direction created ---

func test_stage73_new_direction_created() -> void:
	var seg := _vertical_seg(250.0)
	var effect := LineNormalProjection.new()
	var incoming_dir := Direction.from_coords(Vector2(100, 100), Vector2(250, 200))
	var result := effect.apply_forward(Vector2(250, 200), seg, Side.Value.LEFT)
	assert_ne(result.direction, incoming_dir,
		"Outgoing Direction should be a new object, not the incoming")
	var out_dir := result.direction.to_normalized()
	assert_almost_eq(absf(out_dir.dot(Vector2(0, 1))), 0.0, 0.01,
		"Outgoing direction should be perpendicular to vertical line")

# --- Test 7: trace through projective surface ---

func test_stage73_trace_through_projective_surface() -> void:
	var surfaces := _room_walls()
	var proj_seg := _vertical_seg(400.0)
	var proj_surf := _projective_surface(proj_seg)
	surfaces.append(proj_surf)
	# Diagonal approach: player at (100, 200) aiming at (700, 400)
	var path := _trace(Vector2(100, 200), Vector2(700, 400), surfaces)
	assert_gt(path.steps.size(), 1, "Should have multiple steps")
	# Find the projective surface hit and check the post-projection step
	var post_proj_idx := -1
	for i in range(path.steps.size()):
		var step: Tracer.Step = path.steps[i]
		if step.surface_id == proj_surf.id:
			post_proj_idx = i + 1
			break
	assert_gt(post_proj_idx, 0, "Should find the projective surface hit")
	assert_lt(post_proj_idx, path.steps.size(), "Should have a step after projective")
	if post_proj_idx > 0 and post_proj_idx < path.steps.size():
		var post_step: Tracer.Step = path.steps[post_proj_idx]
		var step_dir := (post_step.end - post_step.start).normalized()
		assert_almost_eq(absf(step_dir.y), 0.0, 0.05,
			"Post-projection step should be horizontal (perpendicular to vertical line)")
		assert_eq(post_step.frame_id, MobiusTransform.IDENTITY_ID,
			"Frame should be identity after projective hit")

# --- Test 8: orange rendering ---

func test_stage73_orange_rendering() -> void:
	var effect := LineNormalProjection.new()
	assert_eq(effect.get_display_color(), Color(1.0, 0.8, 0.2),
		"Projective surface should render in orange")
	assert_eq(effect.get_display_name(), "line_normal",
		"Display name should be 'line_normal'")

# --- Test 9: S16 - no NaN/Inf ---

func test_stage73_S16_no_nan_inf() -> void:
	var seg := _vertical_seg(250.0)
	var effect := LineNormalProjection.new()
	var ray := effect.apply_forward(Vector2(250, 200), seg, Side.Value.LEFT)
	assert_false(is_nan(ray.origin.coords.x), "origin.x should not be NaN")
	assert_false(is_nan(ray.origin.coords.y), "origin.y should not be NaN")
	assert_false(is_inf(ray.origin.coords.x), "origin.x should not be Inf")
	assert_false(is_inf(ray.origin.coords.y), "origin.y should not be Inf")
	var dir := ray.direction.to_normalized()
	assert_false(is_nan(dir.x), "direction.x should not be NaN")
	assert_false(is_nan(dir.y), "direction.y should not be NaN")
	var proj = effect.back_propagate(Vector2(400, 300), seg)
	if proj != null:
		assert_false(is_nan(proj.x), "back_propagate x should not be NaN")
		assert_false(is_nan(proj.y), "back_propagate y should not be NaN")

# --- Test 10: project_back exits on same side ---

func test_stage73_project_back_exits_same_side() -> void:
	var seg := _vertical_seg(250.0)
	var through := LineNormalProjection.new(false)
	var back := LineNormalProjection.new(true)
	var hit := Vector2(250, 200)
	var through_dir := through.apply_forward(hit, seg, Side.Value.LEFT).direction.to_normalized()
	var back_dir := back.apply_forward(hit, seg, Side.Value.LEFT).direction.to_normalized()
	assert_almost_eq(through_dir.x + back_dir.x, 0.0, 0.01,
		"Through and back should have opposite x directions")
	assert_almost_eq(through_dir.y, 0.0, 0.01, "Through should be horizontal")
	assert_almost_eq(back_dir.y, 0.0, 0.01, "Back should be horizontal")

# --- Test 11: project_back is still perpendicular ---

func test_stage73_project_back_perpendicular() -> void:
	var back := LineNormalProjection.new(true)
	# Vertical line -> horizontal output
	var v_seg := _vertical_seg(250.0)
	var v_dir := back.apply_forward(Vector2(250, 200), v_seg, Side.Value.LEFT).direction.to_normalized()
	assert_almost_eq(absf(v_dir.dot(Vector2(0, 1))), 0.0, 0.01,
		"Back on vertical line: output perpendicular to line direction")
	# Horizontal line -> vertical output
	var h_seg := _horizontal_seg(300.0)
	var h_dir := back.apply_forward(Vector2(200, 300), h_seg, Side.Value.LEFT).direction.to_normalized()
	assert_almost_eq(absf(h_dir.dot(Vector2(1, 0))), 0.0, 0.01,
		"Back on horizontal line: output perpendicular to line direction")

# --- Test 12: project_back color is DARK_ORANGE ---

func test_stage73_project_back_color_dark_orange() -> void:
	var back := LineNormalProjection.new(true)
	var through := LineNormalProjection.new(false)
	assert_eq(back.get_display_color(), Color(1.0, 0.4, 0.1),
		"Back-projection should render DARK_ORANGE")
	assert_eq(through.get_display_color(), Color(1.0, 0.8, 0.2),
		"Through-projection should still render ORANGE")

# --- Test 13: project_back display name ---

func test_stage73_project_back_display_name() -> void:
	var back := LineNormalProjection.new(true)
	assert_eq(back.get_display_name(), "line_normal_back",
		"Back-projection display name should be 'line_normal_back'")

# --- Test 14: project_back trace exits on same side ---

func test_stage73_project_back_trace() -> void:
	var surfaces := _room_walls()
	var proj_seg := _vertical_seg(400.0)
	var proj_surf := _projective_surface(proj_seg, true)
	surfaces.append(proj_surf)
	# Player at (100, 300) approaches from RIGHT side (x < 400)
	var path := _trace(Vector2(100, 300), Vector2(700, 450), surfaces)
	assert_gt(path.steps.size(), 1, "Should have multiple steps")
	var post_proj_idx := -1
	for i in range(path.steps.size()):
		if path.steps[i].surface_id == proj_surf.id:
			post_proj_idx = i + 1
			break
	assert_gt(post_proj_idx, 0, "Should find the projective surface hit")
	assert_lt(post_proj_idx, path.steps.size(), "Should have a step after projective")
	if post_proj_idx > 0 and post_proj_idx < path.steps.size():
		var post_step: Tracer.Step = path.steps[post_proj_idx]
		var step_dir := (post_step.end - post_step.start).normalized()
		assert_almost_eq(absf(step_dir.y), 0.0, 0.05,
			"Post-back-projection should be horizontal (perpendicular)")
		assert_lt(step_dir.x, 0.0,
			"Post-back-projection should go back toward entry side (negative x)")

# --- Test 15: default constructor is through-projection (backward compat) ---

func test_stage73_default_is_through() -> void:
	var effect := LineNormalProjection.new()
	assert_eq(effect.get_display_color(), Color(1.0, 0.8, 0.2),
		"Default should be through-projection (ORANGE)")
	assert_eq(effect.get_display_name(), "line_normal",
		"Default display name should be 'line_normal'")
	var seg := _vertical_seg(250.0)
	var through_explicit := LineNormalProjection.new(false)
	var dir_default := effect.apply_forward(Vector2(250, 200), seg, Side.Value.LEFT).direction.to_normalized()
	var dir_explicit := through_explicit.apply_forward(Vector2(250, 200), seg, Side.Value.LEFT).direction.to_normalized()
	assert_almost_eq(dir_default, dir_explicit, Vector2(0.01, 0.01),
		"Default and explicit false should produce same direction")
