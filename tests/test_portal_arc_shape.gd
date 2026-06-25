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
	var carrier := seg.get_carrier()
	return carrier.radius()

# === Step 1: Reproduce — arc radius changes after portal ===

func test_step1_arc_radius_changes_after_portal() -> void:
	var surfs := _build_portals_scene()
	var player := Vector2(1280.003, 976.664)
	var cursor := Vector2(1408.467, 861.5956)
	var plan_entries: Array = [
		PlanManager.PlanEntry.new(8, Side.Value.LEFT),
		PlanManager.PlanEntry.new(10, Side.Value.LEFT),
	]
	var cache := TransformCache.new()
	var aim := Planner.compute_aim_direction(player, cursor, plan_entries, surfs, GameState.new(), cache)
	var ray := Ray.from_coords(player, aim)
	var path := Tracer.trace(player, aim, surfs, GameState.new(), ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, plan_entries, cache, cursor)

	# Dump all steps
	gut.p("Trace: %d steps, cursor_index=%d" % [path.steps.size(), path.cursor_index])
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		var hit_info := "virt"
		if s.hit != null:
			hit_info = "t=%.4f side=%d on_seg=%s" % [s.hit.t, s.hit.side, s.hit.on_segment]
		gut.p("  [%d] %s → %s fid=%d arc=%s portal=%s [%s]" % [
			i, s.start, s.end, s.frame_id, s.is_arc_step, s.after_portal, hit_info])

	# Find the FIRST portal crossing where the pre-step is an arc
	var pre_portal: Tracer.Step = null
	var post_portal: Tracer.Step = null
	for i in range(1, path.steps.size()):
		var s: Tracer.Step = path.steps[i]
		if s.after_portal:
			var prev: Tracer.Step = path.steps[i - 1]
			gut.p("Portal found at step %d: pre-arc=%s post-arc=%s" % [i, prev.is_arc_step, s.is_arc_step])
			if prev.is_arc_step:
				pre_portal = prev
				post_portal = s
				break

	assert_not_null(pre_portal, "Should find an arc step before a portal")
	assert_not_null(post_portal, "Should find a step after the portal")
	assert_true(post_portal.is_arc_step, "Post-portal step should be an arc")

	var r_pre := _arc_radius(pre_portal)
	var r_post := _arc_radius(post_portal)

	gut.p("Pre-portal arc: %s → %s via %s, radius=%.2f" % [
		pre_portal.start, pre_portal.end, pre_portal.via, r_pre])
	gut.p("Post-portal arc: %s → %s via %s, radius=%.2f" % [
		post_portal.start, post_portal.end, post_portal.via, r_post])
	gut.p("Radius ratio: %.4f (should be 1.0)" % (r_post / r_pre))

	var tolerance := r_pre * 0.01
	assert_almost_eq(r_post, r_pre, tolerance,
		"Portal (rigid motion) must preserve arc radius. Pre=%.2f Post=%.2f ratio=%.4f" % [
			r_pre, r_post, r_post / r_pre])

# === Step 2: Prove frame composition order is the cause ===

func test_step2_frame_composition_order() -> void:
	# Run the actual trace to get the real normalized ray
	var surfs := _build_portals_scene()
	var player := Vector2(1280.003, 976.664)
	var cursor := Vector2(1408.467, 861.5956)
	var plan_entries: Array = [
		PlanManager.PlanEntry.new(8, Side.Value.LEFT),
		PlanManager.PlanEntry.new(10, Side.Value.LEFT),
	]
	var cache := TransformCache.new()
	var aim := Planner.compute_aim_direction(player, cursor, plan_entries, surfs, GameState.new(), cache)
	var ray := Ray.from_coords(player, aim)
	cache = TransformCache.new()
	var path := Tracer.trace(player, aim, surfs, GameState.new(), ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, plan_entries, cache, cursor)

	# Find the pre-portal arc step and extract its frame
	var pre_step: Tracer.Step = null
	var post_step: Tracer.Step = null
	for i in range(1, path.steps.size()):
		var s: Tracer.Step = path.steps[i]
		if s.after_portal and path.steps[i - 1].is_arc_step:
			pre_step = path.steps[i - 1]
			post_step = s
			break
	assert_not_null(pre_step, "Must find pre-portal arc step")

	var I_mob: MobiusTransform = pre_step.frame

	# Get the portal Möbius from the surfaces
	var portal_src: Surface = surfs[9]  # portal_lines source (10th surface, index 9)
	var T_mob: MobiusTransform = portal_src.active_side_config(Side.Value.LEFT, GameState.new()).effect.get_mobius()

	# Compute the normalized ray (from visual coords using I^-1 = I for self-inverse)
	var norm_start := I_mob.apply(pre_step.start)
	var norm_end := I_mob.apply(pre_step.end)
	var norm_mid := I_mob.apply(pre_step.via)

	gut.p("Normalized ray: %s → %s via %s" % [norm_start, norm_end, norm_mid])

	# Pre-portal visual: I(normalized line) — the arc we see before portal
	var vis_pre := Segment.from_coords(pre_step.start, pre_step.end, pre_step.via)
	var r_pre := vis_pre.get_carrier().radius()

	# Current code: frame = I ∘ T → visual = I(T(normalized))
	var IT := I_mob.compose(T_mob)
	var vis_IT_s := IT.apply(norm_start)
	var vis_IT_e := IT.apply(norm_end)
	var vis_IT_m := IT.apply(norm_mid)
	var seg_IT := Segment.from_coords(vis_IT_s, vis_IT_e, vis_IT_m)
	var r_IT := seg_IT.get_carrier().radius()

	# Correct: frame = T ∘ I → visual = T(I(normalized)) — translation preserves shape
	var TI := T_mob.compose(I_mob)
	var vis_TI_s := TI.apply(norm_start)
	var vis_TI_e := TI.apply(norm_end)
	var vis_TI_m := TI.apply(norm_mid)
	var seg_TI := Segment.from_coords(vis_TI_s, vis_TI_e, vis_TI_m)
	var r_TI := seg_TI.get_carrier().radius()

	gut.p("Pre-portal (frame=I) radius: %.4f" % r_pre)
	gut.p("Current code (frame=I∘T) radius: %.4f (ratio=%.4f)" % [r_IT, r_IT / r_pre])
	gut.p("Correct order (frame=T∘I) radius: %.4f (ratio=%.4f)" % [r_TI, r_TI / r_pre])
	gut.p("Actual post-portal radius: %.4f" % _arc_radius(post_step))

	# T∘I should preserve the radius (translate the arc)
	assert_almost_eq(r_TI, r_pre, r_pre * 0.001,
		"T∘I composition must preserve radius (translate the arc)")

	# I∘T should NOT preserve the radius — must differ significantly
	var ratio := r_IT / r_pre
	assert_true(absf(ratio - 1.0) > 0.01,
		"I∘T composition changes radius (ratio=%.4f) — proves composition order is the cause" % ratio)

# === Step 3: Verify reflection+portal is NOT affected ===

func test_step3_line_reflection_portal_shape_preserved() -> void:
	# Reflection across a LINE (a=0) + portal
	var refl_seg := Segment.from_coords(Vector2(400, 200), Vector2(400, 700), Vector2(400, 450))
	var R_mob: MobiusTransform = ReflectionEffect.new(refl_seg.get_carrier()).get_mobius()

	var pl_seg := Segment.from_coords(Vector2(550, 600), Vector2(550, 900), Vector2(550, 750))
	var pl_result := RigidMotionEffect.create_portal_pair(pl_seg, 0.0, Vector2(900, 0))
	var T_mob: MobiusTransform = pl_result.source_effect.get_mobius()

	# For line reflections: maps_lines_to_arcs() should be false
	assert_false(R_mob.maps_lines_to_arcs(),
		"Line reflection should not map lines to arcs")

	# Compose both ways
	var RT := R_mob.compose(T_mob)
	var TR := T_mob.compose(R_mob)

	# Both compositions should also not map lines to arcs
	assert_false(RT.maps_lines_to_arcs(),
		"R∘T (line reflection + portal) should not map lines to arcs")
	assert_false(TR.maps_lines_to_arcs(),
		"T∘R (portal + line reflection) should not map lines to arcs")

	gut.p("R.maps_lines_to_arcs = %s" % R_mob.maps_lines_to_arcs())
	gut.p("R∘T.maps_lines_to_arcs = %s" % RT.maps_lines_to_arcs())
	gut.p("T∘R.maps_lines_to_arcs = %s" % TR.maps_lines_to_arcs())
	gut.p("Line reflection + portal: both orders produce lines — shape always preserved")

# === Step 4: Arc-reflection + portal ===

func test_step4_arc_reflection_portal_same_bug() -> void:
	# Reflection across a CIRCLE (a≠0) — same as surface 9 in portals scene
	var arc_seg := Segment.from_coords(Vector2(1100, 700), Vector2(1300, 700), Vector2(1200, 580))
	var R_arc: MobiusTransform = ReflectionEffect.new(arc_seg.get_carrier()).get_mobius()

	var pl_seg := Segment.from_coords(Vector2(550, 600), Vector2(550, 900), Vector2(550, 750))
	var pl_result := RigidMotionEffect.create_portal_pair(pl_seg, 0.0, Vector2(900, 0))
	var T_mob: MobiusTransform = pl_result.source_effect.get_mobius()

	# Arc reflection DOES map lines to arcs
	assert_true(R_arc.maps_lines_to_arcs(),
		"Arc reflection should map lines to arcs")

	# Use a line near the arc center (asymmetric to the portal translation)
	# Position chosen to amplify the composition order effect
	var p1 := Vector2(1150, 650)
	var p2 := Vector2(1250, 750)
	var p_mid := Vector2(1200, 700)

	# Pre-portal: frame = R_arc
	var vis_pre_s := R_arc.apply(p1)
	var vis_pre_e := R_arc.apply(p2)
	var vis_pre_m := R_arc.apply(p_mid)
	var seg_pre := Segment.from_coords(vis_pre_s, vis_pre_e, vis_pre_m)
	var r_pre := seg_pre.get_carrier().radius()

	# Current code: R_arc ∘ T
	var RT := R_arc.compose(T_mob)
	var vis_RT_s := RT.apply(p1)
	var vis_RT_e := RT.apply(p2)
	var vis_RT_m := RT.apply(p_mid)
	var seg_RT := Segment.from_coords(vis_RT_s, vis_RT_e, vis_RT_m)
	var r_RT := seg_RT.get_carrier().radius()

	# Correct: T ∘ R_arc
	var TR := T_mob.compose(R_arc)
	var vis_TR_s := TR.apply(p1)
	var vis_TR_e := TR.apply(p2)
	var vis_TR_m := TR.apply(p_mid)
	var seg_TR := Segment.from_coords(vis_TR_s, vis_TR_e, vis_TR_m)
	var r_TR := seg_TR.get_carrier().radius()

	gut.p("Arc reflection + portal:")
	gut.p("  Pre-portal (frame=R_arc) radius: %.4f" % r_pre)
	gut.p("  Current code (R_arc∘T) radius: %.4f (ratio=%.4f)" % [r_RT, r_RT / r_pre])
	gut.p("  Correct (T∘R_arc) radius: %.4f (ratio=%.4f)" % [r_TR, r_TR / r_pre])

	# T∘R_arc should preserve radius
	assert_almost_eq(r_TR, r_pre, r_pre * 0.01,
		"T∘R_arc must preserve radius")

	# R_arc∘T should change radius (same class of bug as inversion)
	# The effect depends on the line position relative to the arc center;
	# any measurable difference proves the principle
	var ratio := r_RT / r_pre
	gut.p("  Radius difference: %.6f%%" % (absf(ratio - 1.0) * 100.0))
	assert_true(absf(ratio - 1.0) > 0.0001,
		"R_arc∘T changes radius (ratio=%.6f) — arc reflection has same composition order issue" % ratio)

# === Step 5: Regression guard — portal push from identity frame ===

func test_step5_portal_push_origin_identity_frame() -> void:
	var pl_seg := Segment.from_coords(Vector2(550, 600), Vector2(550, 900), Vector2(550, 750))
	var pl_result := RigidMotionEffect.create_portal_pair(pl_seg, 0.0, Vector2(900, 0))

	var wall_seg := Segment.from_coords(Vector2(100, 80), Vector2(1820, 80), Vector2(960, 80))
	var surfs: Array = [
		Surface.new(wall_seg, SideConfig.new(null, false), SideConfig.new(null, false), false, false),
		Surface.new(pl_seg, SideConfig.new(pl_result.source_effect, true), SideConfig.new(pl_result.source_effect, true), false, false),
		Surface.new(pl_result.target_segment, SideConfig.new(pl_result.target_effect, true), SideConfig.new(pl_result.target_effect, true), false, false),
	]

	var player := Vector2(400, 750)
	var aim := Direction.from_coords(player, Vector2(550, 750))
	var ray := Ray.from_coords(player, aim)
	var cache := TransformCache.new()
	var path := Tracer.trace(player, aim, surfs, GameState.new(), ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, [], cache, Vector2(INF, INF))

	var portal_step: Tracer.Step = null
	for i in range(1, path.steps.size()):
		var s: Tracer.Step = path.steps[i]
		if s.after_portal:
			portal_step = s
			break

	assert_not_null(portal_step, "Should find a step after portal")
	var expected_x := 550.0 + 900.0
	assert_almost_eq(portal_step.start.x, expected_x, 1.0,
		"Post-portal step should start at source x + translation = %.0f" % expected_x)

# === Step 6: Portal push from non-identity frame (inversion + portal) ===

func test_step6_portal_push_origin_nonidentity_frame() -> void:
	var surfs := _build_portals_scene()
	var player := Vector2(1280.003, 976.664)
	var cursor := Vector2(1408.467, 861.5956)
	var plan_entries: Array = [
		PlanManager.PlanEntry.new(8, Side.Value.LEFT),
		PlanManager.PlanEntry.new(10, Side.Value.LEFT),
	]
	var cache := TransformCache.new()
	var aim := Planner.compute_aim_direction(player, cursor, plan_entries, surfs, GameState.new(), cache)
	var ray := Ray.from_coords(player, aim)
	var path := Tracer.trace(player, aim, surfs, GameState.new(), ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, plan_entries, cache, cursor)

	var pre_portal: Tracer.Step = null
	var post_portal: Tracer.Step = null
	for i in range(1, path.steps.size()):
		var s: Tracer.Step = path.steps[i]
		if s.after_portal and path.steps[i - 1].is_arc_step:
			pre_portal = path.steps[i - 1]
			post_portal = s
			break

	assert_not_null(pre_portal, "Must find pre-portal arc step")
	assert_not_null(post_portal, "Must find post-portal step")

	# The portal translates by (900, 0). The post-portal start should be
	# pre-portal end shifted by exactly (900, 0).
	var expected_start := pre_portal.end + Vector2(900, 0)
	assert_almost_eq(post_portal.start.x, expected_start.x, 1.0,
		"Post-portal start.x should be pre-portal end.x + 900")
	assert_almost_eq(post_portal.start.y, expected_start.y, 1.0,
		"Post-portal start.y should match pre-portal end.y")

	# The post-portal arc curvature direction should match the pre-portal direction.
	# Use cross product sign: (end-start) × (via-start) determines which side the arc bulges.
	var pre_chord := pre_portal.end - pre_portal.start
	var pre_cross := pre_chord.cross(pre_portal.via - pre_portal.start)
	var post_chord := post_portal.end - post_portal.start
	var post_cross := post_chord.cross(post_portal.via - post_portal.start)
	gut.p("Curvature cross: pre=%.2f post=%.2f (same sign = same direction)" % [pre_cross, post_cross])
	assert_true(pre_cross * post_cross > 0,
		"Arc curvature direction must be preserved after portal (pre=%.2f post=%.2f)" % [pre_cross, post_cross])

# === Step 7: Self-inverse push from non-identity frame ===

func test_step7_self_inverse_push_nonidentity_frame() -> void:
	# Build a scene: portal then line reflection
	var pl_seg := Segment.from_coords(Vector2(300, 200), Vector2(300, 800), Vector2(300, 500))
	var pl_result := RigidMotionEffect.create_portal_pair(pl_seg, 0.0, Vector2(500, 0))
	var mirror_seg := Segment.from_coords(Vector2(900, 200), Vector2(900, 800), Vector2(900, 500))
	var mirror_refl := ReflectionEffect.new(mirror_seg.get_carrier())
	var wall_r := Segment.from_coords(Vector2(1200, 200), Vector2(1200, 800), Vector2(1200, 500))

	var surfs: Array = [
		Surface.new(pl_seg, SideConfig.new(pl_result.source_effect, true), SideConfig.new(pl_result.source_effect, true), false, false),
		Surface.new(pl_result.target_segment, SideConfig.new(pl_result.target_effect, true), SideConfig.new(pl_result.target_effect, true), false, false),
		Surface.new(mirror_seg, SideConfig.new(mirror_refl, true), SideConfig.new(mirror_refl, true), false, false),
		Surface.new(wall_r, SideConfig.new(null, false), SideConfig.new(null, false), false, false),
	]

	# Ray goes right through portal at x=300, exits at x=800, hits mirror at x=900, reflects
	var player := Vector2(200, 500)
	var aim := Direction.from_coords(player, Vector2(1000, 500))
	var ray := Ray.from_coords(player, aim)
	var cache := TransformCache.new()
	var path := Tracer.trace(player, aim, surfs, GameState.new(), ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, [], cache, Vector2(INF, INF))

	gut.p("Trace: %d steps" % path.steps.size())
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		gut.p("  [%d] %s → %s fid=%d arc=%s portal=%s" % [
			i, s.start, s.end, s.frame_id, s.is_arc_step, s.after_portal])

	# Find the portal step and the mirror step
	var found_portal := false
	var mirror_step: Tracer.Step = null
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if s.after_portal:
			found_portal = true
		elif found_portal and s.hit != null and not s.after_portal:
			mirror_step = s
			break

	assert_true(found_portal, "Should go through portal")
	assert_not_null(mirror_step, "Should find step hitting mirror after portal")
	# The step before mirror should end at mirror (visual x=900), and the reflected step
	# should start from x=900 going back left. All steps should be lines (no arcs).
	assert_false(mirror_step.is_arc_step, "Line reflection after portal should produce lines, not arcs")
