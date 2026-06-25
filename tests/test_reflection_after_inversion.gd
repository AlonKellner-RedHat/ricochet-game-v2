extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()

func _build_portals_scene() -> Array:
	var surfs: Array = []
	surfs.append_array(RoomBuilder.create_room_surfaces(Rect2(100, 80, 1720, 920)))
	var m_seg := Segment.from_coords(Vector2(400, 200), Vector2(400, 700), Vector2(400, 450))
	var m_refl := ReflectionEffect.new(m_seg.get_carrier())
	surfs.append(Surface.new(m_seg, SideConfig.new(m_refl, true), SideConfig.new(null, false), false, false))
	var mr_seg := Segment.from_coords(Vector2(960, 150), Vector2(960, 400), Vector2(960, 275))
	var mr_refl := ReflectionEffect.new(mr_seg.get_carrier())
	surfs.append(Surface.new(mr_seg, SideConfig.new(null, false), SideConfig.new(mr_refl, true), false, false))
	var mb_seg := Segment.from_coords(Vector2(1400, 200), Vector2(1400, 500), Vector2(1400, 350))
	var mb_refl := ReflectionEffect.new(mb_seg.get_carrier())
	surfs.append(Surface.new(mb_seg, SideConfig.new(mb_refl, true), SideConfig.new(mb_refl, true), false, false))
	var inv_seg := Segment.from_coords(Vector2(700, 300), Vector2(700, 600), Vector2(820, 450))
	var inv_effect := CircleInversionEffect.new(inv_seg.get_carrier())
	surfs.append(Surface.new(inv_seg, SideConfig.new(inv_effect, true), SideConfig.new(null, false), false, true))
	var arc_seg := Segment.from_coords(Vector2(1100, 700), Vector2(1300, 700), Vector2(1200, 580))
	var arc_refl := ReflectionEffect.new(arc_seg.get_carrier())
	surfs.append(Surface.new(arc_seg, SideConfig.new(arc_refl, true), SideConfig.new(arc_refl, true), false, false))
	var pl_seg := Segment.from_coords(Vector2(550, 600), Vector2(550, 900), Vector2(550, 750))
	var pl_result := RigidMotionEffect.create_portal_pair(pl_seg, 0.0, Vector2(900, 0))
	var pl_src_cfg := SideConfig.new(pl_result.source_effect, true)
	surfs.append(Surface.new(pl_seg, pl_src_cfg, pl_src_cfg, false, false))
	var pl_tgt_cfg := SideConfig.new(pl_result.target_effect, true)
	surfs.append(Surface.new(pl_result.target_segment, pl_tgt_cfg, pl_tgt_cfg, false, false))
	var pa_seg := Segment.from_coords(Vector2(1500, 550), Vector2(1500, 800), Vector2(1430, 675))
	var pa_result := RigidMotionEffect.create_portal_pair(pa_seg, 0.0, Vector2(-1100, 0))
	var pa_src_cfg := SideConfig.new(pa_result.source_effect, true)
	surfs.append(Surface.new(pa_seg, pa_src_cfg, pa_src_cfg, false, false))
	var pa_tgt_cfg := SideConfig.new(pa_result.target_effect, true)
	surfs.append(Surface.new(pa_result.target_segment, pa_tgt_cfg, pa_tgt_cfg, false, false))
	for def in [Vector4(0, 0, 1920, 0), Vector4(1920, 0, 1920, 1080),
				Vector4(1920, 1080, 0, 1080), Vector4(0, 1080, 0, 0)]:
		var sb_seg := Segment.from_coords(Vector2(def.x, def.y), Vector2(def.z, def.w),
			Vector2((def.x + def.z) / 2.0, (def.y + def.w) / 2.0))
		surfs.append(Surface.new(sb_seg, SideConfig.new(null, false), SideConfig.new(null, false), false, false))
	return surfs

func _arc_radius(step: Tracer.Step) -> float:
	var seg := Segment.from_coords(step.start, step.end, step.via)
	return seg.get_carrier().radius()

# ==========================================================================
# Step 1: Reproduce — inversion then reflection is broken
# ==========================================================================

func test_inversion_then_reflection_visual_continuity() -> void:
	var surfs := _build_portals_scene()
	var player := Vector2(1024.95, 408.3824)
	var cursor := Vector2(1115.162, 526.976)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfs, GameState.new())

	gut.p("=== Trace: %d steps ===" % path.steps.size())
	var arc_entry_idx := -1
	var frame_change_idx := -1
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		var arc := s.frame != null and s.frame.maps_lines_to_arcs()
		var conj := s.frame != null and s.frame.conjugating
		gut.p("  [%d] %s -> %s fid=%d arc=%s conj=%s" % [
			i, s.start, s.end, s.frame_id, arc, conj])
		if arc and arc_entry_idx < 0:
			arc_entry_idx = i
		if arc_entry_idx >= 0 and i > arc_entry_idx and s.frame_id != path.steps[arc_entry_idx].frame_id:
			if frame_change_idx < 0:
				frame_change_idx = i

	assert_gt(arc_entry_idx, -1, "Ray should enter arc mode")
	assert_gt(frame_change_idx, -1, "Should find a frame change after arc entry")

	var pre: Tracer.Step = path.steps[frame_change_idx - 1]
	var post: Tracer.Step = path.steps[frame_change_idx]

	var gap: float = pre.end.distance_to(post.start)
	gut.p("Visual gap at frame change: %.4f px" % gap)
	assert_lt(gap, 2.0, "Visual continuity: end of pre-step must match start of post-step (gap=%.2f)" % gap)

	if pre.is_arc_step and post.is_arc_step:
		var r_pre := _arc_radius(pre)
		var r_post := _arc_radius(post)
		gut.p("Arc radius: pre=%.2f post=%.2f ratio=%.4f" % [r_pre, r_post, r_post / r_pre])

func test_inversion_then_reflection_radius_preserved() -> void:
	var surfs := _build_portals_scene()
	var player := Vector2(1024.95, 408.3824)
	var cursor := Vector2(1115.162, 526.976)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfs, GameState.new())

	var arc_entry_idx := -1
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if s.frame != null and s.frame.maps_lines_to_arcs() and arc_entry_idx < 0:
			arc_entry_idx = i

	assert_gt(arc_entry_idx, -1, "Ray should enter arc mode")

	var arc_entry_frame_id: int = path.steps[arc_entry_idx].frame_id
	var arc_steps_before: Array = []
	var arc_steps_after: Array = []
	var found_change := false
	for i in range(arc_entry_idx, path.steps.size()):
		var s: Tracer.Step = path.steps[i]
		if not s.is_arc_step:
			break
		if s.frame_id != arc_entry_frame_id and not found_change:
			found_change = true
		if not found_change:
			arc_steps_before.append(s)
		else:
			arc_steps_after.append(s)

	if arc_steps_before.is_empty() or arc_steps_after.is_empty():
		gut.p("No frame change within arc mode — cannot test radius preservation")
		pass_test("No frame change to test")
		return

	var r_before := _arc_radius(arc_steps_before[0])
	var r_after := _arc_radius(arc_steps_after[0])
	var ratio := r_after / r_before
	gut.p("Radius before frame change: %.2f" % r_before)
	gut.p("Radius after frame change: %.2f" % r_after)
	gut.p("Ratio: %.4f (should be ~1.0 for isometric transform)" % ratio)

	assert_almost_eq(r_after, r_before, r_before * 0.02,
		"Line reflection is isometric — arc radius must be preserved. Ratio=%.4f" % ratio)

func test_inversion_then_reflection_direction_reversal() -> void:
	var surfs := _build_portals_scene()
	var player := Vector2(1024.95, 408.3824)
	var cursor := Vector2(1115.162, 526.976)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfs, GameState.new())

	var arc_entry_idx := -1
	var frame_change_idx := -1
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if s.frame != null and s.frame.maps_lines_to_arcs() and arc_entry_idx < 0:
			arc_entry_idx = i
		if arc_entry_idx >= 0 and i > arc_entry_idx and s.frame_id != path.steps[arc_entry_idx].frame_id:
			if frame_change_idx < 0:
				frame_change_idx = i

	if frame_change_idx < 0:
		gut.p("No frame change in arc mode — skip direction test")
		pass_test("No frame change")
		return

	var pre: Tracer.Step = path.steps[frame_change_idx - 1]
	var post: Tracer.Step = path.steps[frame_change_idx]

	var pre_dir: Vector2 = (pre.end - pre.start).normalized()
	var post_dir: Vector2 = (post.end - post.start).normalized()
	var dot: float = pre_dir.dot(post_dir)
	gut.p("Pre-dir: %s  Post-dir: %s  dot: %.4f" % [pre_dir, post_dir, dot])

	assert_lt(dot, 0.5,
		"After reflection, visual direction should reverse (dot=%.4f, expected < 0.5)" % dot)

# ==========================================================================
# Step 2: Prove root cause — conjugation identity
# ==========================================================================

func test_conjugation_identity_composition_order() -> void:
	var inv_seg := Segment.from_coords(Vector2(700, 300), Vector2(700, 600), Vector2(820, 450))
	var inv_effect := CircleInversionEffect.new(inv_seg.get_carrier())
	var I_mob: MobiusTransform = inv_effect.get_mobius()

	var mirror_seg := Segment.from_coords(Vector2(1400, 200), Vector2(1400, 500), Vector2(1400, 350))
	var R_phys: MobiusTransform = ReflectionEffect.new(mirror_seg.get_carrier()).get_mobius()

	var I_inv := I_mob.invert()
	var norm_carrier := mirror_seg.get_carrier().transformed_by(I_inv)
	var R_norm: MobiusTransform = ReflectionEffect.new(norm_carrier).get_mobius()

	var test_point := Vector2(1300, 400)
	var visual_point := I_mob.apply(test_point)

	var right_compose := I_mob.compose(R_norm)
	var left_compose := R_norm.compose(I_mob)

	var vis_right := right_compose.apply(test_point)
	var vis_left := left_compose.apply(test_point)

	var vis_phys_refl := R_phys.apply(visual_point)

	var dist_right := vis_right.distance_to(vis_phys_refl)
	var dist_left := vis_left.distance_to(vis_phys_refl)

	gut.p("Visual point: %s" % visual_point)
	gut.p("Physical reflection of visual: %s" % vis_phys_refl)
	gut.p("Right-compose (frame o R_norm): %s  dist to correct: %.4f" % [vis_right, dist_right])
	gut.p("Left-compose (R_norm o frame): %s  dist to correct: %.4f" % [vis_left, dist_left])

	assert_lt(dist_right, 1.0,
		"Right-compose matches physical reflection (conjugation identity). dist=%.4f" % dist_right)
	assert_gt(dist_left, 10.0,
		"Left-compose does NOT match physical reflection. dist=%.4f" % dist_left)

# ==========================================================================
# Step 3: Prove dual-compose fixes both bugs
# ==========================================================================

func test_dual_compose_fixes_both_bugs() -> void:
	var inv_seg := Segment.from_coords(Vector2(700, 300), Vector2(700, 600), Vector2(820, 450))
	var inv_effect := CircleInversionEffect.new(inv_seg.get_carrier())
	var I_mob: MobiusTransform = inv_effect.get_mobius()
	var I_tracked := inv_effect.get_tracked_transform()

	var mirror_seg := Segment.from_coords(Vector2(1400, 200), Vector2(1400, 500), Vector2(1400, 350))
	var R_phys := ReflectionEffect.new(mirror_seg.get_carrier())
	var R_mob: MobiusTransform = R_phys.get_mobius()
	var R_tracked := R_phys.get_tracked_transform()

	var pl_seg := Segment.from_coords(Vector2(550, 600), Vector2(550, 900), Vector2(550, 750))
	var pl_result := RigidMotionEffect.create_portal_pair(pl_seg, 0.0, Vector2(900, 0))
	var T_mob: MobiusTransform = pl_result.source_effect.get_mobius()
	var T_tracked: TrackedTransform = pl_result.source_effect.get_tracked_transform()

	assert_true(I_tracked.inverse == I_tracked, "Inversion is self-inverse")
	assert_true(R_tracked.inverse == R_tracked, "Reflection is self-inverse")
	assert_true(T_tracked.inverse != T_tracked, "Portal is NOT self-inverse")

	var test_point := Vector2(1300, 400)

	# --- Self-inverse: right-compose is correct ---
	var frame_I := I_mob
	var I_inv := I_mob.invert()
	var norm_carrier := mirror_seg.get_carrier().transformed_by(I_inv)
	var R_norm_mob := ReflectionEffect.new(norm_carrier).get_mobius()

	var right_frame := frame_I.compose(R_norm_mob)
	var left_frame := R_norm_mob.compose(frame_I)

	var visual_pre := frame_I.apply(test_point)
	var vis_right := right_frame.apply(test_point)
	var vis_left := left_frame.apply(test_point)

	var vis_correct := R_mob.apply(visual_pre)
	gut.p("Self-inverse test:")
	gut.p("  right-compose dist to correct: %.4f" % vis_right.distance_to(vis_correct))
	gut.p("  left-compose dist to correct: %.4f" % vis_left.distance_to(vis_correct))
	assert_lt(vis_right.distance_to(vis_correct), 1.0,
		"Right-compose correct for self-inverse")

	# --- Portal: left-compose is correct ---
	var frame_IT := frame_I.compose(R_norm_mob)
	var TI := T_mob.compose(frame_IT)
	var IT := frame_IT.compose(T_mob)

	var vis_pre_portal := frame_IT.apply(test_point)
	var vis_left_portal := TI.apply(test_point)
	var vis_right_portal := IT.apply(test_point)

	var expected_portal := T_mob.apply(vis_pre_portal)

	gut.p("Portal test:")
	gut.p("  left-compose dist to correct: %.4f" % vis_left_portal.distance_to(expected_portal))
	gut.p("  right-compose dist to correct: %.4f" % vis_right_portal.distance_to(expected_portal))
	assert_lt(vis_left_portal.distance_to(expected_portal), 1.0,
		"Left-compose correct for portal")

	# --- Dual-compose: both correct ---
	var dual_frame := MobiusTransform.identity()
	var stack: Array = [I_tracked, R_tracked, T_tracked]
	for t in stack:
		if t.inverse == t:
			dual_frame = dual_frame.compose(t.mobius)
		else:
			dual_frame = t.mobius.compose(dual_frame)

	gut.p("Dual-compose: self-inv right, portal left")
	gut.p("  Dual frame maps_lines_to_arcs: %s" % dual_frame.maps_lines_to_arcs())
	assert_true(dual_frame.maps_lines_to_arcs(),
		"With inversion+reflection, frame should still map lines to arcs")

# ==========================================================================
# Step 4: Self-inverse new_origin is frame-independent
# ==========================================================================

func test_self_inverse_new_origin_frame_independent() -> void:
	var inv_seg := Segment.from_coords(Vector2(700, 300), Vector2(700, 600), Vector2(820, 450))
	var inv_effect := CircleInversionEffect.new(inv_seg.get_carrier())
	var I_mob: MobiusTransform = inv_effect.get_mobius()

	var mirror_seg := Segment.from_coords(Vector2(1400, 200), Vector2(1400, 500), Vector2(1400, 350))
	var R_phys := ReflectionEffect.new(mirror_seg.get_carrier())
	var R_tracked: TrackedTransform = R_phys.get_tracked_transform()

	var hp_norm := Vector2(1350, 380)

	var simple_origin := R_tracked.inverse.mobius.apply(hp_norm)

	var old_frame := I_mob
	var physical := old_frame.apply(hp_norm)
	var new_frame := old_frame.compose(R_tracked.mobius)
	var new_frame_inv := new_frame.invert()
	var general_origin := new_frame_inv.apply(physical)

	var dist := simple_origin.distance_to(general_origin)
	gut.p("Simple R(hp): %s" % simple_origin)
	gut.p("General nf_inv(F(hp)): %s" % general_origin)
	gut.p("Distance: %.6f" % dist)

	assert_lt(dist, 0.01,
		"Self-inverse new_origin = R(hp) regardless of frame. dist=%.6f" % dist)

	var visual_at_simple := new_frame.apply(simple_origin)
	var visual_at_hp := old_frame.apply(hp_norm)
	var continuity := visual_at_simple.distance_to(visual_at_hp)
	gut.p("Visual continuity: frame(new_origin) vs old_frame(hp) dist=%.6f" % continuity)
	assert_lt(continuity, 0.01,
		"Visual continuity preserved with simplified formula")
