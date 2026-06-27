extends GutTest

const H := preload("res://tests/test_helpers.gd")
const TOL := Vector2(1.0, 1.0)

func before_each() -> void:
	H.reset_counters()

# --- Helpers ---

func _standard_arc() -> Segment:
	return Segment.from_coords(Vector2(200, 100), Vector2(200, 300), Vector2(300, 200))

func _small_arc() -> Segment:
	return Segment.from_coords(Vector2(270, 130), Vector2(270, 270), Vector2(300, 200))

func _projective_arc_surface(seg: Segment, project_back: bool = false) -> Surface:
	var effect := CircleNormalProjection.new(project_back)
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

# --- Test 1: apply_forward radial outward from interior ---

func test_stage74_apply_forward_radial_outward() -> void:
	var seg := _standard_arc()
	var effect := CircleNormalProjection.new()
	var hit := Vector2(300, 200)
	var result := effect.apply_forward(hit, seg, Side.Value.RIGHT)
	assert_not_null(result, "apply_forward should return a Ray")
	assert_almost_eq(result.origin.coords, hit, TOL, "Origin at hit point")
	var dir := result.direction.to_normalized()
	assert_almost_eq(dir.x, 1.0, 0.01, "Radial outward x should be 1")
	assert_almost_eq(dir.y, 0.0, 0.01, "Radial outward y should be 0")

# --- Test 2: apply_forward at angled position ---

func test_stage74_apply_forward_angled() -> void:
	var seg := _standard_arc()
	var effect := CircleNormalProjection.new()
	var hit := Vector2(200, 300)
	var result := effect.apply_forward(hit, seg, Side.Value.RIGHT)
	assert_not_null(result, "apply_forward should return a Ray")
	var dir := result.direction.to_normalized()
	assert_almost_eq(dir.x, 0.0, 0.01, "Bottom hit: x should be 0")
	assert_almost_eq(dir.y, 1.0, 0.01, "Bottom hit: y should be 1 (radially outward)")

# --- Test 5: S10 - frame resets to identity ---

func test_stage74_S10_frame_resets() -> void:
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
	var proj_seg := Segment.from_coords(Vector2(400, 100), Vector2(400, 500), Vector2(500, 300))
	var proj_surf := _projective_arc_surface(proj_seg)
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

# --- Test 6: trace through circle projection ---

func test_stage74_trace_through_circle_projection() -> void:
	var surfaces := _room_walls()
	var proj_seg := Segment.from_coords(Vector2(400, 100), Vector2(400, 500), Vector2(500, 300))
	var proj_surf := _projective_arc_surface(proj_seg)
	surfaces.append(proj_surf)
	var path := _trace(Vector2(200, 300), Vector2(600, 300), surfaces)
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
		assert_eq(post_step.frame_id, MobiusTransform.IDENTITY_ID,
			"Frame should be identity after projective hit")

# --- Test 7: S16 - no NaN/Inf ---

func test_stage74_S16_no_nan_inf() -> void:
	var seg := _standard_arc()
	var effect := CircleNormalProjection.new()
	var ray := effect.apply_forward(Vector2(300, 200), seg, Side.Value.RIGHT)
	assert_false(is_nan(ray.origin.coords.x), "origin.x not NaN")
	assert_false(is_nan(ray.origin.coords.y), "origin.y not NaN")
	assert_false(is_inf(ray.origin.coords.x), "origin.x not Inf")
	assert_false(is_inf(ray.origin.coords.y), "origin.y not Inf")
	var dir := ray.direction.to_normalized()
	assert_false(is_nan(dir.x), "direction.x not NaN")
	assert_false(is_nan(dir.y), "direction.y not NaN")

# --- Test 9: project_back exits same side ---

func test_stage74_project_back_exits_same_side() -> void:
	var seg := _standard_arc()
	var through := CircleNormalProjection.new(false)
	var back := CircleNormalProjection.new(true)
	var hit := Vector2(300, 200)
	var through_dir := through.apply_forward(hit, seg, Side.Value.RIGHT).direction.to_normalized()
	var back_dir := back.apply_forward(hit, seg, Side.Value.RIGHT).direction.to_normalized()
	assert_almost_eq(through_dir.x + back_dir.x, 0.0, 0.01,
		"Through and back should have opposite x directions")

# --- Test 10: project_back color ---

func test_stage74_project_back_color() -> void:
	var back := CircleNormalProjection.new(true)
	var through := CircleNormalProjection.new(false)
	assert_eq(back.get_display_color(), Color(1.0, 0.4, 0.1),
		"Back should be red-orange")
	assert_eq(through.get_display_color(), Color(1.0, 0.8, 0.2),
		"Through should be yellow-orange")

# --- Test 11: project_back display name ---

func test_stage74_project_back_display_name() -> void:
	var back := CircleNormalProjection.new(true)
	assert_eq(back.get_display_name(), "circle_normal_back",
		"Back display name should be 'circle_normal_back'")

# --- Test 12: default is through ---

func test_stage74_default_is_through() -> void:
	var effect := CircleNormalProjection.new()
	assert_eq(effect.get_display_color(), Color(1.0, 0.8, 0.2),
		"Default should be through (yellow-orange)")
	assert_eq(effect.get_display_name(), "circle_normal",
		"Default display name should be 'circle_normal'")
	var seg := _standard_arc()
	var explicit := CircleNormalProjection.new(false)
	var dir_default := effect.apply_forward(Vector2(300, 200), seg, Side.Value.RIGHT).direction.to_normalized()
	var dir_explicit := explicit.apply_forward(Vector2(300, 200), seg, Side.Value.RIGHT).direction.to_normalized()
	assert_almost_eq(dir_default, dir_explicit, Vector2(0.01, 0.01),
		"Default and explicit false should produce same direction")

# --- Test 13: kind is projective ---

func test_stage74_kind_is_projective() -> void:
	var effect := CircleNormalProjection.new()
	assert_eq(effect.kind(), Effect.Kind.PROJECTIVE, "Kind should be PROJECTIVE")
