extends GutTest

# Investigation: accumulating errors after 5 consecutive circle inversions.
# Read-only diagnostics — no production code changes.

var _surfaces: Array[Surface] = []
var _circle_centers: Array[Vector2] = []
var _circle_radius: float = 60.0

func _build_grid() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()
	_surfaces.clear()
	_circle_centers.clear()

	var centers := [
		Vector2(760, 380), Vector2(960, 380), Vector2(1160, 380),
		Vector2(760, 540), Vector2(960, 540), Vector2(1160, 540),
		Vector2(760, 700), Vector2(960, 700), Vector2(1160, 700),
	]

	for center in centers:
		_circle_centers.append(center)
		var carrier := GeneralizedCircle.from_circle(center, _circle_radius)
		var seg := Segment.full_from_carrier(carrier)
		var inv := CircleInversionEffect.new(carrier)
		var surf := Surface.new(seg, SideConfig.new(inv, true), SideConfig.new(inv, true), false, true)
		_surfaces.append(surf)

	var screen_bounds: Array[Vector4] = [
		Vector4(0, 0, 1920, 0),
		Vector4(1920, 0, 1920, 1080),
		Vector4(1920, 1080, 0, 1080),
		Vector4(0, 1080, 0, 0),
	]
	for line_def in screen_bounds:
		var seg := Segment.from_coords(
			Vector2(line_def.x, line_def.y), Vector2(line_def.z, line_def.w),
			Vector2((line_def.x + line_def.z) / 2.0, (line_def.y + line_def.w) / 2.0))
		var config := SideConfig.new(null, false)
		_surfaces.append(Surface.new(seg, config, config, false, false))

func _surface_by_center(center: Vector2) -> Surface:
	for i in _circle_centers.size():
		if _circle_centers[i].distance_to(center) < 1.0:
			return _surfaces[i]
	return null

func _make_plan(centers: Array) -> Array:
	var entries: Array = []
	for c in centers:
		var surf := _surface_by_center(c)
		entries.append(PlanManager.PlanEntry.new(surf.id, Side.Value.LEFT))
	return entries

func _trace_planned(origin: Vector2, cursor: Vector2, plan: Array) -> Tracer.TracedPath:
	var gs := GameState.new()
	var cache := TransformCache.new()
	var aim := Planner.compute_aim_direction(origin, cursor, plan, _surfaces, gs, cache)
	return Tracer.trace(origin, aim, _surfaces, gs, null, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan, cache, cursor)


# ==========================================================================
# Experiment 1: Reproduce the failure
# ==========================================================================
func test_exp1_reproduce_failure():
	_build_grid()
	var origin := Vector2(620, 540)
	var cursor := Vector2(1200, 400)
	var plan_centers := [
		Vector2(760, 700), Vector2(760, 540), Vector2(960, 380),
		Vector2(1160, 380), Vector2(1160, 540),
	]
	var plan := _make_plan(plan_centers)

	print("\n=== EXPERIMENT 1: Reproduce Failure ===")
	print("Origin: %s  Cursor: %s" % [origin, cursor])
	print("Plan: %s" % [plan.map(func(e): return "surf_%d(%s)" % [e.surface_id, e.side])])

	var gs := GameState.new()
	var cache := TransformCache.new()
	var aim := Planner.compute_aim_direction(origin, cursor, plan, _surfaces, gs, cache)
	print("Planner aim: dir=(%s) end=(%s)" % [aim.to_vector(), aim.end.coords])

	var path := Tracer.trace(origin, aim, _surfaces, gs, null, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan, cache, cursor)

	var max_coord := 0.0
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		print("  Step %d: start=%s end=%s fid=%d sid=%d t=%.6f arc=%s" % [
			i, s.start, s.end, s.frame_id, s.surface_id,
			s.hit.t if s.hit else -1.0, s.is_arc_step])
		max_coord = maxf(max_coord, maxf(absf(s.end.x), absf(s.end.y)))

	print("Max coordinate magnitude: %.1f" % max_coord)
	print("Steps: %d  Cursor index: %d" % [path.steps.size(), path.cursor_index])

	if max_coord > 5000.0:
		print("CONFIRMED: Coordinate explosion detected (max=%.1f > 5000)" % max_coord)
	if path.cursor_index < 0:
		print("CONFIRMED: Trace never reached cursor")

	gut.p("Exp1: max_coord=%.1f steps=%d cursor_idx=%d" % [max_coord, path.steps.size(), path.cursor_index])
	pass_test("Exp1 complete — see output")


# ==========================================================================
# Experiment 2: Frame composition health check
# ==========================================================================
func test_exp2_frame_composition_health():
	_build_grid()

	print("\n=== EXPERIMENT 2: Frame Composition Health ===")

	var plan_centers := [
		Vector2(760, 700), Vector2(760, 540), Vector2(960, 380),
		Vector2(1160, 380), Vector2(1160, 540),
	]

	var cache := TransformCache.new()
	var frame := MobiusTransform.identity()

	for k in plan_centers.size():
		var surf := _surface_by_center(plan_centers[k])
		var config: SideConfig = surf.active_side_config(Side.Value.LEFT, GameState.new())
		var mobius: MobiusTransform = config.effect.get_mobius()

		frame = cache.compose_cached(mobius, frame)
		var frame_inv := cache.invert_cached(frame)
		var roundtrip := frame.compose(frame_inv)

		print("\n--- After inversion %d (surface %d, center=%s) ---" % [k + 1, surf.id, plan_centers[k]])
		print("  Frame conjugating: %s" % frame.conjugating)
		print("  f64: a=(%.8f,%.8f) b=(%.8f,%.8f) c=(%.8f,%.8f) d=(%.8f,%.8f)" % [
			frame.a_re, frame.a_im, frame.b_re, frame.b_im,
			frame.c_re, frame.c_im, frame.d_re, frame.d_im])

		var f64_a_len := sqrt(frame.a_re * frame.a_re + frame.a_im * frame.a_im)
		var f64_b_len := sqrt(frame.b_re * frame.b_re + frame.b_im * frame.b_im)
		var f64_c_len := sqrt(frame.c_re * frame.c_re + frame.c_im * frame.c_im)
		var f64_d_len := sqrt(frame.d_re * frame.d_re + frame.d_im * frame.d_im)
		var f64_max := maxf(maxf(f64_a_len, f64_b_len), maxf(f64_c_len, f64_d_len))
		print("  Coefficient magnitudes: f64_max=%.6f" % f64_max)

		print("  Roundtrip (frame*frame_inv): a=(%.8f,%.8f) b=(%.8f,%.8f) c=(%.8f,%.8f) d=(%.8f,%.8f) conj=%s" % [
			roundtrip.a_re, roundtrip.a_im, roundtrip.b_re, roundtrip.b_im,
			roundtrip.c_re, roundtrip.c_im, roundtrip.d_re, roundtrip.d_im, roundtrip.conjugating])

		var c_vec := Vector2(frame.c_re, frame.c_im)
		if c_vec.length() > 1e-12:
			var d_vec := Vector2(frame.d_re, frame.d_im)
			var pole: Vector2
			if frame.conjugating:
				var neg_d := Vector2(-d_vec.x, -d_vec.y)
				var c_conj := Vector2(c_vec.x, -c_vec.y)
				var den_sq := c_conj.x * c_conj.x + c_conj.y * c_conj.y
				pole = Vector2(
					(neg_d.x * c_conj.x + neg_d.y * c_conj.y) / den_sq,
					(neg_d.y * c_conj.x - neg_d.x * c_conj.y) / den_sq)
				pole = Vector2(pole.x, -pole.y)
			else:
				var den_sq := c_vec.x * c_vec.x + c_vec.y * c_vec.y
				pole = Vector2(
					(-d_vec.x * c_vec.x - d_vec.y * c_vec.y) / den_sq,
					(-d_vec.y * c_vec.x + d_vec.x * c_vec.y) / den_sq)
			print("  Pole (maps to infinity): %s" % pole)

	pass_test("Exp2 complete — see output")


# ==========================================================================
# Experiment 3: aim_in_frame precision comparison
# ==========================================================================
func test_exp3_aim_precision():
	_build_grid()

	print("\n=== EXPERIMENT 3: aim_in_frame Precision ===")

	var cursor := Vector2(1200, 400)
	var plan_centers := [
		Vector2(760, 700), Vector2(760, 540), Vector2(960, 380),
		Vector2(1160, 380), Vector2(1160, 540),
	]

	var cache := TransformCache.new()
	var frame := MobiusTransform.identity()
	var transforms: Array = []

	for k in plan_centers.size():
		var surf := _surface_by_center(plan_centers[k])
		var config: SideConfig = surf.active_side_config(Side.Value.LEFT, GameState.new())
		var mobius: MobiusTransform = config.effect.get_mobius()
		transforms.append(mobius)

		frame = cache.compose_cached(mobius, frame)
		var frame_inv := cache.invert_cached(frame)

		var composed_f32: Vector2 = frame_inv.apply(cursor)
		var composed_f64: Vector2 = frame_inv.apply(cursor)

		var sequential := cursor
		for j in range(k, -1, -1):
			sequential = transforms[j].apply(sequential)

		var seq_f64 := cursor
		for j in range(k, -1, -1):
			seq_f64 = transforms[j].apply(seq_f64)

		print("\n--- After %d inversions ---" % [k + 1])
		print("  Composed f32: %s" % composed_f32)
		print("  Composed f64: %s" % composed_f64)
		print("  Sequential f32: %s" % sequential)
		print("  Sequential f64: %s" % seq_f64)
		print("  Diff (composed_f32 - composed_f64): %s (dist=%.6f)" % [
			composed_f32 - composed_f64, composed_f32.distance_to(composed_f64)])
		print("  Diff (composed_f32 - sequential_f32): %s (dist=%.6f)" % [
			composed_f32 - sequential, composed_f32.distance_to(sequential)])
		print("  Diff (composed_f64 - sequential_f64): %s (dist=%.6f)" % [
			composed_f64 - seq_f64, composed_f64.distance_to(seq_f64)])

		if composed_f32.distance_to(composed_f64) > 1.0:
			print("  ** SIGNIFICANT f32/f64 divergence: %.2f pixels **" % composed_f32.distance_to(composed_f64))

	pass_test("Exp3 complete — see output")


# ==========================================================================
# Experiment 4: Normalized surface distortion
# ==========================================================================
func test_exp4_normalized_surface_distortion():
	_build_grid()

	print("\n=== EXPERIMENT 4: Normalized Surface Distortion ===")

	var plan_centers := [
		Vector2(760, 700), Vector2(760, 540), Vector2(960, 380),
		Vector2(1160, 380), Vector2(1160, 540),
	]

	var cache := TransformCache.new()
	var frame := MobiusTransform.identity()

	for k in plan_centers.size():
		var surf := _surface_by_center(plan_centers[k])
		var config: SideConfig = surf.active_side_config(Side.Value.LEFT, GameState.new())
		var mobius: MobiusTransform = config.effect.get_mobius()
		frame = cache.compose_cached(mobius, frame)

	print("Frame after %d inversions: conjugating=%s" % [plan_centers.size(), frame.conjugating])

	var frame_inv := cache.invert_cached(frame)

	for i in _surfaces.size():
		if i >= _circle_centers.size():
			continue
		var surf: Surface = _surfaces[i]
		var center := _circle_centers[i]

		var norm_start: Vector2 = frame_inv.apply(surf.segment.start.coords)
		var norm_end: Vector2 = frame_inv.apply(surf.segment.end.coords)
		var norm_via: Vector2 = frame_inv.apply(surf.segment.via.coords)

		var norm_start_f64: Vector2 = frame_inv.apply(surf.segment.start.coords)
		var norm_end_f64: Vector2 = frame_inv.apply(surf.segment.end.coords)
		var norm_via_f64: Vector2 = frame_inv.apply(surf.segment.via.coords)

		var norm_seg := Segment.from_coords(norm_start, norm_end, norm_via)
		norm_seg.full = surf.segment.full
		var norm_carrier := norm_seg.get_carrier()

		var norm_seg_f64 := Segment.from_coords(norm_start_f64, norm_end_f64, norm_via_f64)
		norm_seg_f64.full = surf.segment.full
		var norm_carrier_f64 := norm_seg_f64.get_carrier()

		var r_f32 := norm_carrier.radius() if not norm_carrier.is_line() else INF
		var r_f64 := norm_carrier_f64.radius() if not norm_carrier_f64.is_line() else INF

		print("\n  Surface %d (center=%s, r=%.0f):" % [surf.id, center, _circle_radius])
		print("    f32 norm: start=%s end=%s via=%s" % [norm_start, norm_end, norm_via])
		print("    f64 norm: start=%s end=%s via=%s" % [norm_start_f64, norm_end_f64, norm_via_f64])
		print("    f32 carrier: center=%s radius=%.4f" % [
			norm_carrier.center() if not norm_carrier.is_line() else "LINE", r_f32])
		print("    f64 carrier: center=%s radius=%.4f" % [
			norm_carrier_f64.center() if not norm_carrier_f64.is_line() else "LINE", r_f64])

		if not is_inf(r_f32) and not is_inf(r_f64):
			print("    Radius ratio f32/f64: %.6f" % (r_f32 / r_f64))
		if r_f32 < 1.0:
			print("    ** PULLBACK WOULD BE USED (radius < 1.0) **")

		var start_diff := norm_start.distance_to(norm_start_f64)
		if start_diff > 1.0:
			print("    ** f32/f64 endpoint divergence: %.2f px **" % start_diff)

	pass_test("Exp4 complete — see output")


# ==========================================================================
# Experiment 5: Intersection audit for divergent step
# ==========================================================================
func test_exp5_intersection_audit():
	_build_grid()

	print("\n=== EXPERIMENT 5: Intersection Audit ===")

	var origin := Vector2(620, 540)
	var cursor := Vector2(1200, 400)
	var plan_centers := [
		Vector2(760, 700), Vector2(760, 540), Vector2(960, 380),
		Vector2(1160, 380), Vector2(1160, 540),
	]
	var plan := _make_plan(plan_centers)

	var gs := GameState.new()
	var cache := TransformCache.new()
	var aim := Planner.compute_aim_direction(origin, cursor, plan, _surfaces, gs, cache)

	var frame := MobiusTransform.identity()
	var transforms: Array = []
	for k in range(3):
		var surf := _surface_by_center(plan_centers[k])
		var config: SideConfig = surf.active_side_config(Side.Value.LEFT, gs)
		var mobius: MobiusTransform = config.effect.get_mobius()
		transforms.append(mobius)
		frame = cache.compose_cached(mobius, frame)

	var frame_inv := cache.invert_cached(frame)
	print("Frame after 3 inversions: conjugating=%s" % frame.conjugating)

	var bounce_point := Vector2(804.79, 528.75)
	var aim_in_frame_f32: Vector2 = frame_inv.apply(cursor)
	var aim_in_frame_f64: Vector2 = frame_inv.apply(cursor)
	print("aim_in_frame f32: %s" % aim_in_frame_f32)
	print("aim_in_frame f64: %s" % aim_in_frame_f64)
	print("aim_in_frame diff: %.4f px" % aim_in_frame_f32.distance_to(aim_in_frame_f64))

	var ray_dir_f32 := (aim_in_frame_f32 - bounce_point).normalized()
	var ray_dir_f64 := (aim_in_frame_f64 - bounce_point).normalized()
	print("Ray direction f32: %s" % ray_dir_f32)
	print("Ray direction f64: %s" % ray_dir_f64)
	print("Direction angle diff: %.4f degrees" % rad_to_deg(ray_dir_f32.angle_to(ray_dir_f64)))

	var remaining_surfs := [_surface_by_center(plan_centers[3]), _surface_by_center(plan_centers[4])]
	for rs in remaining_surfs:
		print("\n  Testing intersection with surface %d (center=%s):" % [rs.id, _circle_centers[rs.id - 1]])
		var norm_start := frame_inv.apply(rs.segment.start.coords)
		var norm_end := frame_inv.apply(rs.segment.end.coords)
		var norm_via := frame_inv.apply(rs.segment.via.coords)
		var norm_seg := Segment.from_coords(norm_start, norm_end, norm_via)
		norm_seg.full = rs.segment.full
		var norm_carrier := norm_seg.get_carrier()

		var norm_start_f64 := frame_inv.apply(rs.segment.start.coords)
		var norm_end_f64 := frame_inv.apply(rs.segment.end.coords)
		var norm_via_f64 := frame_inv.apply(rs.segment.via.coords)
		var norm_seg_f64 := Segment.from_coords(norm_start_f64, norm_end_f64, norm_via_f64)
		norm_seg_f64.full = rs.segment.full
		var norm_carrier_f64 := norm_seg_f64.get_carrier()

		print("    f32 carrier: center=%s radius=%.4f" % [
			norm_carrier.center() if not norm_carrier.is_line() else "LINE",
			norm_carrier.radius() if not norm_carrier.is_line() else INF])
		print("    f64 carrier: center=%s radius=%.4f" % [
			norm_carrier_f64.center() if not norm_carrier_f64.is_line() else "LINE",
			norm_carrier_f64.radius() if not norm_carrier_f64.is_line() else INF])

		var ray_f32 := Ray.from_coords(bounce_point, Direction.from_coords(bounce_point, bounce_point + ray_dir_f32))
		var ray_f64 := Ray.from_coords(bounce_point, Direction.from_coords(bounce_point, bounce_point + ray_dir_f64))

		var hits_f32 := Intersection.intersect_line_with_carrier(ray_f32, norm_carrier)
		var hits_f64 := Intersection.intersect_line_with_carrier(ray_f64, norm_carrier_f64)

		print("    f32 hits: %d" % hits_f32.size())
		for h in hits_f32:
			print("      t=%.6f point=%s" % [h.t, h.point])
		print("    f64 hits: %d" % hits_f64.size())
		for h in hits_f64:
			print("      t=%.6f point=%s" % [h.t, h.point])

		var vis_carrier: GeneralizedCircle = rs.segment.get_carrier()
		var pullback_f32 := Intersection.inversive_pullback_intersect(ray_f32, vis_carrier, frame)
		print("    pullback hits: %d" % pullback_f32.size())
		for h in pullback_f32:
			print("      t=%.6f point=%s" % [h.t, h.point])

	pass_test("Exp5 complete — see output")


# ==========================================================================
# Experiment 6: Mathematical pole analysis
# ==========================================================================
func test_exp6_pole_analysis():
	_build_grid()

	print("\n=== EXPERIMENT 6: Pole Analysis ===")

	var plan_centers := [
		Vector2(760, 700), Vector2(760, 540), Vector2(960, 380),
		Vector2(1160, 380), Vector2(1160, 540),
	]

	var cache := TransformCache.new()
	var frame := MobiusTransform.identity()

	for k in plan_centers.size():
		var surf := _surface_by_center(plan_centers[k])
		var config: SideConfig = surf.active_side_config(Side.Value.LEFT, GameState.new())
		var mobius: MobiusTransform = config.effect.get_mobius()
		frame = cache.compose_cached(mobius, frame)

		var c_re: float = frame.c_re
		var c_im: float = frame.c_im
		var d_re: float = frame.d_re
		var d_im: float = frame.d_im
		var c_mag2: float = c_re * c_re + c_im * c_im

		if c_mag2 < 1e-20:
			print("After %d inversions: c≈0, no finite pole" % [k + 1])
			continue

		var pole: Vector2
		if frame.conjugating:
			var neg_d_re: float = -d_re
			var neg_d_im: float = -d_im
			var c_conj_re: float = c_re
			var c_conj_im: float = -c_im
			var den_sq: float = c_conj_re * c_conj_re + c_conj_im * c_conj_im
			var q_re: float = (neg_d_re * c_conj_re + neg_d_im * c_conj_im) / den_sq
			var q_im: float = (neg_d_im * c_conj_re - neg_d_re * c_conj_im) / den_sq
			pole = Vector2(q_re, -q_im)
		else:
			var neg_d_re: float = -d_re
			var neg_d_im: float = -d_im
			pole = Vector2(
				(neg_d_re * c_re + neg_d_im * c_im) / c_mag2,
				(neg_d_im * c_re - neg_d_re * c_im) / c_mag2)

		var test_points := [
			Vector2(620, 540), Vector2(800, 530), Vector2(960, 400),
			Vector2(1100, 380), Vector2(1200, 400),
		]

		print("\nAfter %d inversions (conjugating=%s):" % [k + 1, frame.conjugating])
		print("  Pole: %s" % pole)
		print("  Points near pole:")
		for p in test_points:
			var dist: float = p.distance_to(pole)
			var mapped := frame.apply(p)
			print("    %s → %s (dist_to_pole=%.1f, mapped_mag=%.1f)" % [
				p, mapped, dist, mapped.length()])

	pass_test("Exp6 complete — see output")
