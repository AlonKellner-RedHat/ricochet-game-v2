extends GutTest

const H := preload("res://tests/test_helpers.gd")

func before_each() -> void:
	H.reset_counters()

func _build_debug_scene() -> Dictionary:
	var room_walls := RoomBuilder.create_room_surfaces(Rect2(160, 90, 1600, 900))
	var mirror_left := _mirror_line(Vector2(500, 200), Vector2(500, 700))
	var mirror_right := _mirror_line(Vector2(1400, 300), Vector2(1400, 800))
	var mirror_bottom := _mirror_line(Vector2(700, 800), Vector2(1200, 800))
	var mirror_mid := _mirror_right_line(Vector2(960, 200), Vector2(960, 500))
	var inv_seg := Segment.from_coords(Vector2(1100, 400), Vector2(1100, 700), Vector2(1230, 550))
	var inv_effect := CircleInversionEffect.new(inv_seg.get_carrier())
	var inv_surf := Surface.new(inv_seg, SideConfig.new(inv_effect, true), SideConfig.new(null, false), false, true)
	var screen_bounds := _screen_bounds()
	var surfaces: Array = []
	surfaces.append_array(room_walls)
	surfaces.append(mirror_left)
	surfaces.append(mirror_right)
	surfaces.append(mirror_bottom)
	surfaces.append(mirror_mid)
	surfaces.append(inv_surf)
	surfaces.append_array(screen_bounds)
	return {"surfaces": surfaces, "inversion": inv_surf}

func _mirror_line(start: Vector2, end_v: Vector2) -> Surface:
	var mid := (start + end_v) / 2.0
	var seg := Segment.from_coords(start, end_v, mid)
	var refl := ReflectionEffect.new(seg.get_carrier())
	return Surface.new(seg, SideConfig.new(refl, true), SideConfig.new(null, false), false, false)

func _mirror_right_line(start: Vector2, end_v: Vector2) -> Surface:
	var mid := (start + end_v) / 2.0
	var seg := Segment.from_coords(start, end_v, mid)
	var refl := ReflectionEffect.new(seg.get_carrier())
	return Surface.new(seg, SideConfig.new(null, false), SideConfig.new(refl, true), false, false)

func _screen_bounds() -> Array:
	var result: Array = []
	var bounds_defs := [
		[Vector2(0, 0), Vector2(1920, 0)],
		[Vector2(1920, 0), Vector2(1920, 1080)],
		[Vector2(1920, 1080), Vector2(0, 1080)],
		[Vector2(0, 1080), Vector2(0, 0)],
	]
	for bd in bounds_defs:
		var s: Vector2 = bd[0]
		var e: Vector2 = bd[1]
		var config := SideConfig.new(null, false)
		result.append(Surface.new(Segment.from_coords(s, e, (s + e) / 2.0), config, config, false, false))
	return result

# ==========================================================================
# Phase 1: Reproduce the bug — exact debug state
# ==========================================================================

func test_phase1_trace_hits_inversion_surface() -> void:
	var scene := _build_debug_scene()
	var surfaces: Array = scene.surfaces
	var inv_surf: Surface = scene.inversion
	var player := Vector2(1194.262, 755.5463)
	var cursor := Vector2(1183.232, 715.3248)
	var aim := Direction.from_coords(player, cursor)
	var aim_ray := Ray.from_coords(player, aim)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(),
		aim_ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, [], null, cursor)
	var hit_inversion := false
	for step in path.steps:
		var s: Tracer.Step = step
		if s.hit != null and s.hit.segment == inv_surf.segment:
			hit_inversion = true
	assert_true(hit_inversion, "Trace should hit the inversion arc surface")

func test_phase1_post_inversion_hits_surfaces() -> void:
	var scene := _build_debug_scene()
	var surfaces: Array = scene.surfaces
	var player := Vector2(1194.262, 755.5463)
	var cursor := Vector2(1183.232, 715.3248)
	var aim := Direction.from_coords(player, cursor)
	var aim_ray := Ray.from_coords(player, aim)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(),
		aim_ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, [], null, cursor)
	var found_inversion_frame := false
	var post_inversion_hits := 0
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame_id != MobiusTransform.IDENTITY_ID:
			found_inversion_frame = true
			if s.hit != null:
				post_inversion_hits += 1
	assert_true(found_inversion_frame, "Should have steps in inverted frame")
	gut.p("Post-inversion surface hits: %d" % post_inversion_hits)
	assert_gt(post_inversion_hits, 0,
		"BUG: After inversion, ray should hit surfaces (walls) but escapes to bounds instead")

func test_phase1_post_inversion_has_surface_hits() -> void:
	var scene := _build_debug_scene()
	var surfaces: Array = scene.surfaces
	var player := Vector2(1194.262, 755.5463)
	var cursor := Vector2(1183.232, 715.3248)
	var aim := Direction.from_coords(player, cursor)
	var aim_ray := Ray.from_coords(player, aim)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(),
		aim_ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, [], null, cursor)
	var hit_count := 0
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame_id != MobiusTransform.IDENTITY_ID and s.hit != null:
			hit_count += 1
	gut.p("Post-inversion surface hits: %d" % hit_count)
	assert_gt(hit_count, 0,
		"After inversion, ray should hit surfaces (walls bounce correctly)")

# ==========================================================================
# Phase 2: Prove root cause — normalized carriers are wrong
# ==========================================================================

func test_phase2_lines_become_circles_after_inversion() -> void:
	var room_walls := RoomBuilder.create_room_surfaces(Rect2(160, 90, 1600, 900))
	var inv_seg := Segment.from_coords(Vector2(1100, 400), Vector2(1100, 700), Vector2(1230, 550))
	var inv_effect := CircleInversionEffect.new(inv_seg.get_carrier())
	var frame := inv_effect.get_mobius()
	assert_true(frame.maps_lines_to_arcs(), "Inversion frame should map lines to arcs")
	var inv_frame := frame.invert()
	var line_becomes_circle := 0
	var line_surfaces_total := 0
	for wall in room_walls:
		var w: Surface = wall
		if not w.segment.is_line():
			continue
		line_surfaces_total += 1
		var s := inv_frame.apply(w.segment.start.coords)
		var e := inv_frame.apply(w.segment.end.coords)
		var v := inv_frame.apply(w.segment.via.coords)
		var norm_seg := Segment.from_coords(s, e, v)
		if not norm_seg.get_carrier().is_line():
			line_becomes_circle += 1
	gut.p("Line surfaces that become circles after inversion: %d/%d" % [line_becomes_circle, line_surfaces_total])
	assert_eq(line_becomes_circle, line_surfaces_total,
		"All line surfaces should become circles under inversion (via correctly transformed)")

func test_phase2_correct_carrier_is_circle() -> void:
	var wall := RoomBuilder.create_block_surface(
		Vector2(160, 90), Vector2(1760, 90), Vector2(960, 90))
	var inv_seg := Segment.from_coords(Vector2(1100, 400), Vector2(1100, 700), Vector2(1230, 550))
	var inv_effect := CircleInversionEffect.new(inv_seg.get_carrier())
	var frame := inv_effect.get_mobius()
	var inv_frame := frame.invert()
	var s := inv_frame.apply(wall.segment.start.coords)
	var e := inv_frame.apply(wall.segment.end.coords)
	var mid_original := (wall.segment.start.coords + wall.segment.end.coords) / 2.0
	var v_correct := inv_frame.apply(mid_original)
	var correct_seg := Segment.from_coords(s, e, v_correct)
	var correct_carrier := correct_seg.get_carrier()
	gut.p("Correct carrier: a=%f (is_line=%s)" % [correct_carrier.a, correct_carrier.is_line()])
	assert_false(correct_carrier.is_line(),
		"With correct via point, carrier should be a circle (a != 0), not a line")

func test_phase2_circle_carriers_find_hits() -> void:
	var scene := _build_debug_scene()
	var surfaces: Array = scene.surfaces
	var inv_surf: Surface = scene.inversion
	var inv_effect: CircleInversionEffect = inv_surf.active_side_config(Side.Value.LEFT, GameState.new()).effect
	var frame := inv_effect.get_mobius()
	var inv_frame := frame.invert()
	var player := Vector2(1194.262, 755.5463)
	var cursor := Vector2(1183.232, 715.3248)
	var aim := Direction.from_coords(player, cursor)
	var aim_ray := Ray.from_coords(player, aim)
	var hits := Intersection.find_all_hits(aim_ray, [inv_surf.segment])
	assert_gt(hits.size(), 0, "Should have hits on inversion surface")
	var best_hit: Intersection.HitRecord = null
	for h in hits:
		var hr: Intersection.HitRecord = h
		if hr.t > 0 and (best_hit == null or hr.t < best_hit.t):
			best_hit = hr
	assert_not_null(best_hit, "Should find forward hit on inversion arc")
	var hp := best_hit.point.coords
	var new_origin := inv_frame.apply(hp)
	var ray_in_frame := Ray.from_coords(new_origin, aim)
	var circle_hit_count := 0
	for surf in surfaces:
		var s: Surface = surf
		if s == inv_surf:
			continue
		if not s.segment.is_line():
			continue
		var ns := inv_frame.apply(s.segment.start.coords)
		var ne := inv_frame.apply(s.segment.end.coords)
		var nv := inv_frame.apply(s.segment.via.coords)
		var norm_seg := Segment.from_coords(ns, ne, nv)
		assert_false(norm_seg.get_carrier().is_line(),
			"Normalized carrier should be a circle, not a line")
		var carrier_hits := Intersection.intersect_line_with_carrier(ray_in_frame, norm_seg.get_carrier())
		circle_hit_count += carrier_hits.size()
	gut.p("Circle carrier hits: %d" % circle_hit_count)
	assert_gt(circle_hit_count, 0,
		"Circle carriers (correctly transformed via) should find hits")

# ==========================================================================
# Phase 3: Prove escape-step arc flag issue
# ==========================================================================

func test_phase3_all_inversive_steps_are_arcs() -> void:
	var scene := _build_debug_scene()
	var surfaces: Array = scene.surfaces
	var player := Vector2(1194.262, 755.5463)
	var cursor := Vector2(1183.232, 715.3248)
	var aim := Direction.from_coords(player, cursor)
	var aim_ray := Ray.from_coords(player, aim)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(),
		aim_ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, [], null, cursor)
	var inversive_non_arc_steps := 0
	var inversive_total := 0
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame != null and s.frame.maps_lines_to_arcs() and s.hit != null:
			inversive_total += 1
			if not s.is_arc_step:
				inversive_non_arc_steps += 1
	gut.p("Inversive steps: %d total, %d non-arc" % [inversive_total, inversive_non_arc_steps])
	assert_gt(inversive_total, 0, "Should have steps in inversive frame")
	assert_eq(inversive_non_arc_steps, 0,
		"All steps in inversive frame should have is_arc_step=true")

# ==========================================================================
# Phase 4: Escape arc via points in inversive frames
# ==========================================================================

func test_phase4_escape_via_is_infinity_point() -> void:
	var scene := _build_debug_scene()
	var surfaces: Array = scene.surfaces
	var player := Vector2(1283.446, 843.0654)
	var cursor := Vector2(1220.271, 638.1819)
	var aim := Direction.from_coords(player, cursor)
	var aim_ray := Ray.from_coords(player, aim)
	var path := Tracer.trace(player, aim, surfaces, GameState.new(),
		aim_ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, [], null, cursor)
	var inversive_escapes: Array = []
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame != null and s.frame.maps_lines_to_arcs() and s.hit == null:
			inversive_escapes.append(s)
	assert_gt(inversive_escapes.size(), 0, "Should have escape steps in inversive frame")
	for step in inversive_escapes:
		var s: Tracer.Step = step
		var t_inf := s.frame.apply(Vector2(INF, INF))
		assert_true(s.is_arc_step, "Escape in inversive frame should have is_arc_step=true")
		assert_false(is_nan(s.start.x) or is_nan(s.start.y), "No NaN in start")
		assert_false(is_nan(s.end.x) or is_nan(s.end.y), "No NaN in end")
		assert_false(is_nan(s.via.x) or is_nan(s.via.y), "No NaN in via")
		assert_true(VisualConverter.is_arc(s.start, s.via, s.end),
			"Escape arc via should produce a valid arc (non-collinear)")
		# One endpoint of each escape step should be T(∞)
		var start_matches := s.start.distance_to(t_inf) < 1.0
		var end_matches := s.end.distance_to(t_inf) < 1.0
		assert_true(start_matches or end_matches,
			"Escape step should have T(INF) as one endpoint. start=%s end=%s t_inf=%s" % [
				s.start, s.end, t_inf])
