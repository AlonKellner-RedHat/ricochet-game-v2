extends GutTest

const H := preload("res://tests/test_helpers.gd")
const TOL := Vector2(1.0, 1.0)

func before_each() -> void:
	H.reset_counters()

# --- Helpers ---

# Right semicircle: center (300,300), r=100
# LEFT = outside circle, RIGHT = inside circle
func _standard_arc() -> Segment:
	return Segment.from_coords(Vector2(300, 200), Vector2(300, 400), Vector2(400, 300))

func _projective_arc_surface(seg: Segment, normal: Vector2, project_back: bool = false) -> Surface:
	var effect := CircleDirectionalProjection.new(normal, project_back)
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

# --- Test 1: exit direction from inside (RIGHT) ---

func test_stage75_exit_direction_from_right() -> void:
	var seg := _standard_arc()
	var effect := CircleDirectionalProjection.new(Vector2(1, 0))
	var result := effect.apply_forward(Vector2(400, 300), seg, Side.Value.RIGHT)
	assert_not_null(result, "apply_forward should return a Ray")
	var dir := result.direction.to_normalized()
	assert_almost_eq(dir.x, 1.0, 0.01, "From inside: exit should be +normal (rightward)")
	assert_almost_eq(dir.y, 0.0, 0.01, "From inside: exit y should be 0")

# --- Test 2: exit direction from outside (LEFT) ---

func test_stage75_exit_direction_from_left() -> void:
	var seg := _standard_arc()
	var effect := CircleDirectionalProjection.new(Vector2(1, 0))
	var result := effect.apply_forward(Vector2(400, 300), seg, Side.Value.LEFT)
	assert_not_null(result, "apply_forward should return a Ray")
	var dir := result.direction.to_normalized()
	assert_almost_eq(dir.x, -1.0, 0.01, "From outside: exit should be -normal (leftward)")
	assert_almost_eq(dir.y, 0.0, 0.01, "From outside: exit y should be 0")

# --- Test 3: hit position independent ---

func test_stage75_hit_position_independent() -> void:
	var seg := _standard_arc()
	var effect := CircleDirectionalProjection.new(Vector2(1, 0))
	var hits := [Vector2(400, 300), Vector2(350, 213.4), Vector2(350, 386.6)]
	var first_dir := effect.apply_forward(hits[0], seg, Side.Value.RIGHT).direction.to_normalized()
	for i in range(1, hits.size()):
		var dir := effect.apply_forward(hits[i], seg, Side.Value.RIGHT).direction.to_normalized()
		assert_almost_eq(dir, first_dir, Vector2(0.01, 0.01),
			"Hit at position %d should produce same direction as position 0" % i)

# --- Test 4: back_propagate on arc ---

func test_stage75_back_propagate_on_arc() -> void:
	var seg := _standard_arc()
	var effect := CircleDirectionalProjection.new(Vector2(1, 0))
	var result = effect.back_propagate(Vector2(500, 300), seg)
	assert_not_null(result, "Should return point on arc")
	assert_almost_eq(result, Vector2(400, 300), TOL,
		"Line from (500,300) in normal dir should hit arc at (400,300)")

# --- Test 5: back_propagate null ---

func test_stage75_back_propagate_null() -> void:
	var seg := _standard_arc()
	var effect := CircleDirectionalProjection.new(Vector2(1, 0))
	var result = effect.back_propagate(Vector2(300, 500), seg)
	assert_null(result, "Line at y=500 in normal dir misses circle entirely")

# --- Test 6: S10 - frame resets ---

func test_stage75_S10_frame_resets() -> void:
	var surfaces := _room_walls()
	var source_seg := Segment.from_coords(
		Vector2(100, 100), Vector2(100, 500), Vector2(100, 300))
	var portal_data := RigidMotionEffect.create_portal_pair(source_seg, 0.0, Vector2(100, 0))
	var src_cfg := SideConfig.new(portal_data.source_effect, true)
	var tgt_cfg := SideConfig.new(portal_data.target_effect, true)
	var source_surf := Surface.new(source_seg, src_cfg, src_cfg, false, false)
	var target_surf := Surface.new(portal_data.target_segment, tgt_cfg, tgt_cfg, false, false)
	surfaces.append(source_surf)
	surfaces.append(target_surf)
	var proj_seg := _standard_arc()
	var proj_surf := _projective_arc_surface(proj_seg, Vector2(1, 0))
	surfaces.append(proj_surf)
	var path := _trace(Vector2(50, 300), Vector2(750, 300), surfaces)
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

# --- Test 7: trace through semicircle ---

func test_stage75_trace_through_semicircle() -> void:
	var surfaces := _room_walls()
	var proj_seg := _standard_arc()
	var proj_surf := _projective_arc_surface(proj_seg, Vector2(1, 0))
	surfaces.append(proj_surf)
	var path := _trace(Vector2(200, 300), Vector2(500, 350), surfaces)
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
		assert_almost_eq(step_dir.x, 1.0, 0.05,
			"Post-projection should go in +normal direction (rightward)")
		assert_almost_eq(absf(step_dir.y), 0.0, 0.05,
			"Post-projection should have no y component")
		assert_eq(post_step.frame_id, MobiusTransform.IDENTITY_ID,
			"Frame should be identity after projective hit")

# --- Test 8: S16 - no NaN/Inf ---

func test_stage75_S16_no_nan_inf() -> void:
	var seg := _standard_arc()
	var effect := CircleDirectionalProjection.new(Vector2(1, 0))
	var ray := effect.apply_forward(Vector2(400, 300), seg, Side.Value.RIGHT)
	assert_false(is_nan(ray.origin.coords.x), "origin.x not NaN")
	assert_false(is_nan(ray.origin.coords.y), "origin.y not NaN")
	assert_false(is_inf(ray.origin.coords.x), "origin.x not Inf")
	assert_false(is_inf(ray.origin.coords.y), "origin.y not Inf")
	var dir := ray.direction.to_normalized()
	assert_false(is_nan(dir.x), "direction.x not NaN")
	assert_false(is_nan(dir.y), "direction.y not NaN")
	var proj = effect.back_propagate(Vector2(500, 300), seg)
	if proj != null:
		assert_false(is_nan(proj.x), "back_propagate x not NaN")
		assert_false(is_nan(proj.y), "back_propagate y not NaN")

# --- Test 9: kind is projective ---

func test_stage75_kind_is_projective() -> void:
	var effect := CircleDirectionalProjection.new(Vector2(1, 0))
	assert_eq(effect.kind(), Effect.Kind.PROJECTIVE, "Kind should be PROJECTIVE")

# --- Test 10: project_back exits same side ---

func test_stage75_project_back_exits_same_side() -> void:
	var seg := _standard_arc()
	var through := CircleDirectionalProjection.new(Vector2(1, 0), false)
	var back := CircleDirectionalProjection.new(Vector2(1, 0), true)
	var hit := Vector2(400, 300)
	var through_dir := through.apply_forward(hit, seg, Side.Value.RIGHT).direction.to_normalized()
	var back_dir := back.apply_forward(hit, seg, Side.Value.RIGHT).direction.to_normalized()
	assert_almost_eq(through_dir.x + back_dir.x, 0.0, 0.01,
		"Through and back should have opposite directions")

# --- Test 11: project_back color ---

func test_stage75_project_back_color() -> void:
	var back := CircleDirectionalProjection.new(Vector2(1, 0), true)
	var through := CircleDirectionalProjection.new(Vector2(1, 0), false)
	assert_eq(back.get_display_color(), Color(1.0, 0.4, 0.1),
		"Back should be red-orange")
	assert_eq(through.get_display_color(), Color(1.0, 0.8, 0.2),
		"Through should be yellow-orange")

# --- Test 12: project_back display name ---

func test_stage75_project_back_display_name() -> void:
	var back := CircleDirectionalProjection.new(Vector2(1, 0), true)
	assert_eq(back.get_display_name(), "circle_directional_back",
		"Back display name")

# --- Test 13: default is through ---

func test_stage75_default_is_through() -> void:
	var normal := Vector2(1, 0)
	var effect := CircleDirectionalProjection.new(normal)
	assert_eq(effect.get_display_color(), Color(1.0, 0.8, 0.2),
		"Default should be through (yellow-orange)")
	assert_eq(effect.get_display_name(), "circle_directional",
		"Default display name")
	var seg := _standard_arc()
	var explicit := CircleDirectionalProjection.new(normal, false)
	var dir_default := effect.apply_forward(Vector2(400, 300), seg, Side.Value.RIGHT).direction.to_normalized()
	var dir_explicit := explicit.apply_forward(Vector2(400, 300), seg, Side.Value.RIGHT).direction.to_normalized()
	assert_almost_eq(dir_default, dir_explicit, Vector2(0.01, 0.01),
		"Default and explicit false should produce same direction")
