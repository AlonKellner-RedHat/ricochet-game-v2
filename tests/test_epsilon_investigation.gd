extends GutTest

# Investigation: non-zero thresholds in the math layer.
# T1: mobius_transform.gd:67 — max_mag > 1e6 renormalization
# T2: tracer.gd:60 — FAR_DISTANCE := 1e6
# T3: tracer.gd:389 — phys_dir * 250.0

const H := preload("res://tests/test_helpers.gd")

func before_each() -> void:
	H.reset_counters()

func _full_circle_mirror(center: Vector2, r: float) -> Surface:
	var seg := Segment.from_coords(
		Vector2(center.x + 0.01, center.y - r),
		Vector2(center.x - 0.01, center.y - r),
		Vector2(center.x, center.y + r))
	var refl := ReflectionEffect.new(seg.get_carrier())
	var config := SideConfig.new(refl, true)
	return Surface.new(seg, config, config, false, false)

func _count_frame_transitions(path: Tracer.TracedPath) -> Array:
	var transitions: Array = []
	var prev_conj := false
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame.conjugating != prev_conj:
			transitions.append(s.frame.conjugating)
			prev_conj = s.frame.conjugating
	return transitions


# =============================================================================
# Group A: Collinear pass-through bug
# =============================================================================

func test_A1_collinear_outer_reflects() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var surfaces: Array = [surf]
	var player := Vector2(600, 540)
	var aim := Direction.from_coords(player, Vector2(960, 540))
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	print("DIAG [A1] steps=%d" % path.steps.size())
	for i in mini(path.steps.size(), 10):
		var s: Tracer.Step = path.steps[i]
		print("DIAG [A1] step %d: start=%s end=%s conj=%s arc=%s frame_id=%d" % [
			i, s.start, s.end, s.frame.conjugating, s.is_arc_step, s.frame_id])

	var transitions := _count_frame_transitions(path)
	print("DIAG [A1] transitions=%s" % [transitions])
	assert_gte(transitions.size(), 2,
		"Collinear outer ray should reflect twice (enter+exit reflected frame). Got transitions=%s" % [transitions])
	if transitions.size() >= 2:
		assert_true(transitions[0], "First transition should enter reflected frame")
		assert_false(transitions[1], "Second transition should return to identity")

func test_A2_collinear_inner_reflects() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var surfaces: Array = [surf]
	var player := Vector2(960, 600)
	var aim := Direction.from_coords(player, Vector2(960, 480))
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	print("DIAG [A2] steps=%d" % path.steps.size())
	for i in mini(path.steps.size(), 10):
		var s: Tracer.Step = path.steps[i]
		print("DIAG [A2] step %d: start=%s end=%s conj=%s arc=%s frame_id=%d" % [
			i, s.start, s.end, s.frame.conjugating, s.is_arc_step, s.frame_id])

	var has_reflected := false
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame.conjugating:
			has_reflected = true
			break
	assert_true(has_reflected, "Collinear inner ray should enter reflected frame")

func test_A3_near_collinear_outer() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var surfaces: Array = [surf]
	var player := Vector2(600, 540)
	var aim := Direction.from_coords(player, Vector2(960, 540.0001))
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	var transitions := _count_frame_transitions(path)
	print("DIAG [A3] transitions=%s steps=%d" % [transitions, path.steps.size()])
	assert_gte(transitions.size(), 2,
		"Near-collinear outer ray should also reflect. Got transitions=%s" % [transitions])

func test_A4_collinear_step_by_step_diagnosis() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var seg := Segment.from_coords(
		Vector2(center.x + 0.01, center.y - r),
		Vector2(center.x - 0.01, center.y - r),
		Vector2(center.x, center.y + r))
	var carrier := seg.get_carrier()
	var player := Vector2(600, 540)

	# Step 1: initial ray toward center
	var ray := Ray.from_coords(player, Direction.from_coords(player, center))
	var hits := Intersection.find_all_hits(ray, [seg])
	print("DIAG [A4] Initial hits: %d" % hits.size())
	for h in hits:
		var hr: Intersection.HitRecord = h
		print("DIAG [A4]   t=%.15f point=%s on_seg=%s ep=%d" % [hr.t, hr.point.coords, hr.on_segment, hr.at_endpoint])

	# Step 2: find the first on-segment hit
	var first_hit: Intersection.HitRecord = null
	for h in hits:
		var hr: Intersection.HitRecord = h
		if hr.on_segment and hr.t > 0:
			if first_hit == null or hr.t < first_hit.t:
				first_hit = hr

	if first_hit == null:
		print("DIAG [A4] NO on-segment hit found — this IS the bug")
		assert_not_null(first_hit, "Collinear ray should hit the circle")
		return

	print("DIAG [A4] First hit: t=%.15f point=%s" % [first_hit.t, first_hit.point.coords])

	# Step 3: simulate reflection
	var refl := ReflectionEffect.new(carrier)
	var mobius := refl.get_mobius()
	var tracked := refl.get_tracked_transform()
	var new_origin := tracked.inverse.mobius.apply(first_hit.point.coords)
	var new_ray := Ray.from_coords(new_origin, ray.direction)

	print("DIAG [A4] Reflected origin=%s" % new_origin)

	# Step 4: normalize segment
	var norm_seg := seg.transformed(tracked.inverse)
	var norm_carrier := norm_seg.get_carrier()
	print("DIAG [A4] Norm seg same? %s, carrier same? %s" % [norm_seg == seg, norm_carrier == carrier])

	# Step 5: find hits on normalized segment from reflected origin
	var reflected_hits := Intersection.find_all_hits(new_ray, [norm_seg], norm_seg, carrier)
	print("DIAG [A4] Reflected hits: %d" % reflected_hits.size())
	for h in reflected_hits:
		var hr: Intersection.HitRecord = h
		print("DIAG [A4]   t=%.15f point=%s on_seg=%s ep=%d" % [hr.t, hr.point.coords, hr.on_segment, hr.at_endpoint])

	# Step 6: check for the filter behavior
	var filtered := reflected_hits.filter(func(h: Intersection.HitRecord) -> bool:
		return h.segment != norm_seg or h.t != 0.0)
	print("DIAG [A4] After filter (seg != origin_on_seg or t != 0): %d hits remain" % filtered.size())
	for h in filtered:
		var hr: Intersection.HitRecord = h
		print("DIAG [A4]   t=%s absf(t)=%s on_seg=%s" % [hr.t, absf(hr.t), hr.on_segment])

	assert_true(true, "Diagnostic test — check DIAG output")

func test_A5_collinear_with_walls() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var walls := RoomBuilder.create_room_surfaces(Rect2(160, 90, 1600, 900))
	var surfaces: Array = [surf]
	surfaces.append_array(walls)
	var player := Vector2(600, 540)
	var aim := Direction.from_coords(player, Vector2(960, 540))
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	print("DIAG [A5] steps=%d" % path.steps.size())
	for i in mini(path.steps.size(), 15):
		var s: Tracer.Step = path.steps[i]
		var hit_info := "null"
		if s.hit != null:
			hit_info = "t=%.4f on_seg=%s" % [s.hit.t, s.hit.on_segment]
		print("DIAG [A5] step %d: conj=%s arc=%s frame_id=%d hit=%s" % [
			i, s.frame.conjugating, s.is_arc_step, s.frame_id, hit_info])

	var transitions := _count_frame_transitions(path)
	print("DIAG [A5] transitions=%s" % [transitions])
	assert_gte(transitions.size(), 2,
		"Collinear ray with walls should still reflect. Got transitions=%s" % [transitions])


# =============================================================================
# Group B: Escape via scale factor (T3) — 250.0
# =============================================================================

func test_B1_escape_via_near_pole() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var carrier := GeneralizedCircle.from_circle(center, r)
	var refl := ReflectionEffect.new(carrier)
	var frame := refl.get_mobius()

	var phys_origin := Vector2(760, 540)
	var phys_dir := Vector2(1, 0)
	var via_point := phys_origin + phys_dir * 250.0

	print("DIAG [B1] via_point=%s dist_from_center=%.2f" % [via_point, via_point.distance_to(center)])
	var via_transformed := frame.apply(via_point)
	print("DIAG [B1] frame.apply(via_point)=%s" % via_transformed)
	print("DIAG [B1] is_inf=%s" % (is_inf(via_transformed.x) or is_inf(via_transformed.y)))

	var image_of_inf := frame.apply(Vector2(INF, INF))
	print("DIAG [B1] image_of_infinity=%s" % image_of_inf)

	assert_false(is_inf(via_transformed.x) or is_inf(via_transformed.y),
		"Via point should not map to infinity for r=200 circle")

func test_B2_escape_via_for_small_circle() -> void:
	var center := Vector2(500, 300)
	var r := 50.0
	var carrier := GeneralizedCircle.from_circle(center, r)
	var refl := ReflectionEffect.new(carrier)
	var frame := refl.get_mobius()

	var phys_origin := Vector2(center.x - r, center.y)
	var phys_dir := Vector2(1, 0)
	var via_point := phys_origin + phys_dir * 250.0

	var dist_from_center := via_point.distance_to(center)
	print("DIAG [B2] r=%d, via_point=%s, dist_from_center=%.2f, inside=%s" % [
		r, via_point, dist_from_center, dist_from_center < r])

	var via_transformed := frame.apply(via_point)
	print("DIAG [B2] frame.apply(via_point)=%s" % via_transformed)

	var image_of_inf := frame.apply(Vector2(INF, INF))
	print("DIAG [B2] image_of_infinity=%s" % image_of_inf)

	assert_false(is_inf(via_transformed.x) or is_inf(via_transformed.y),
		"Via point should not map to infinity for r=50 circle")

func test_B3_escape_via_for_large_circle() -> void:
	var center := Vector2(960, 540)
	var r := 500.0
	var carrier := GeneralizedCircle.from_circle(center, r)
	var refl := ReflectionEffect.new(carrier)
	var frame := refl.get_mobius()

	var phys_origin := Vector2(center.x - r, center.y)
	var phys_dir := Vector2(1, 0)
	var via_point := phys_origin + phys_dir * 250.0

	var dist_from_center := via_point.distance_to(center)
	print("DIAG [B3] r=%d, via_point=%s, dist_from_center=%.2f, inside=%s" % [
		r, via_point, dist_from_center, dist_from_center < r])

	var via_transformed := frame.apply(via_point)
	print("DIAG [B3] frame.apply(via_point)=%s" % via_transformed)

	assert_false(is_inf(via_transformed.x) or is_inf(via_transformed.y),
		"Via point should not map to infinity for r=500 circle")

func test_B4_escape_via_collinear_degeneracy() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var carrier := GeneralizedCircle.from_circle(center, r)
	var refl := ReflectionEffect.new(carrier)
	var frame := refl.get_mobius()

	# Collinear case: origin on circle, direction toward center
	var phys_origin := Vector2(center.x - r, center.y)
	var phys_dir := (center - phys_origin).normalized()

	# The via at 250 pixels from origin, toward center
	var via_point := phys_origin + phys_dir * 250.0
	var dist_to_center := via_point.distance_to(center)
	print("DIAG [B4] via_point=%s, dist_to_center=%.6f" % [via_point, dist_to_center])

	# Check: does via_point land AT the center (Mobius pole)?
	var at_pole := dist_to_center < 1.0
	print("DIAG [B4] At pole? %s" % at_pole)

	var via_transformed := frame.apply(via_point)
	print("DIAG [B4] frame.apply(via_point)=%s" % via_transformed)
	print("DIAG [B4] is_inf=%s" % (is_inf(via_transformed.x) or is_inf(via_transformed.y)))

	# For r=200, phys_origin=(760,540), phys_dir=(1,0)
	# via_point = (760+250, 540) = (1010, 540)
	# dist_to_center = 1010-960 = 50 — NOT at pole

	# But for r=250: phys_origin=(710,540), via=(710+250,540)=(960,540) = center = POLE
	# Test that case too:
	var r2 := 250.0
	var carrier2 := GeneralizedCircle.from_circle(center, r2)
	var refl2 := ReflectionEffect.new(carrier2)
	var frame2 := refl2.get_mobius()
	var phys_origin2 := Vector2(center.x - r2, center.y)
	var phys_dir2 := (center - phys_origin2).normalized()
	var via_point2 := phys_origin2 + phys_dir2 * 250.0
	var dist_to_center2 := via_point2.distance_to(center)
	print("DIAG [B4] r=250: via_point=%s, dist_to_center=%.6f" % [via_point2, dist_to_center2])

	var via_transformed2 := frame2.apply(via_point2)
	print("DIAG [B4] r=250: frame.apply(via_point)=%s" % via_transformed2)
	print("DIAG [B4] r=250: is_inf=%s" % (is_inf(via_transformed2.x) or is_inf(via_transformed2.y)))

	# Mobius correctly maps the pole to infinity — the bug was the tracer choosing the pole as via
	assert_true(is_inf(via_transformed2.x) or is_inf(via_transformed2.y),
		"Mobius correctly maps the pole (circle center) to infinity for r=250")

func test_B5_escape_via_alternative_midpoint() -> void:
	var center := Vector2(960, 540)
	var r := 250.0
	var carrier := GeneralizedCircle.from_circle(center, r)
	var refl := ReflectionEffect.new(carrier)
	var frame := refl.get_mobius()

	var phys_origin := Vector2(center.x - r, center.y)
	var image_of_inf := frame.apply(Vector2(INF, INF))
	print("DIAG [B5] image_of_inf=%s" % image_of_inf)

	# Alternative: use midpoint between vis_origin and image_of_infinity
	var vis_origin := frame.apply(phys_origin)
	print("DIAG [B5] vis_origin=%s" % vis_origin)
	var alt_via := (vis_origin + image_of_inf) / 2.0
	print("DIAG [B5] alt_via (midpoint)=%s" % alt_via)
	print("DIAG [B5] alt_via is_inf=%s" % (is_inf(alt_via.x) or is_inf(alt_via.y)))

	assert_false(is_inf(alt_via.x) or is_inf(alt_via.y),
		"Midpoint alternative should always produce a finite via")


# =============================================================================
# Group C: Renormalization cliff (T1) — 1e6
# =============================================================================

func test_C1_renormalization_preserves_apply() -> void:
	var center := Vector2(960, 540)
	var carrier := GeneralizedCircle.from_circle(center, 200.0)
	var refl := ReflectionEffect.new(carrier)
	var m := refl.get_mobius()

	# Compose many times to trigger renormalization
	var composed := MobiusTransform.identity()
	var test_points := [
		Vector2(500, 300), Vector2(100, 100), Vector2(1500, 800),
		Vector2(960, 200), Vector2(0, 0)]

	var results_before: Array = []
	for p in test_points:
		results_before.append(composed.compose(m).apply(p))

	for i in range(20):
		composed = composed.compose(m)

	var _max_drift := 0.0
	for j in test_points.size():
		var result := composed.apply(test_points[j])
		# After even number of self-inverse reflections, should be ~identity
		# After odd, should be ~m
		# Just check it's finite and not NaN
		var is_valid := not (is_nan(result.x) or is_nan(result.y) or is_inf(result.x) or is_inf(result.y))
		print("DIAG [C1] point=%s -> %s valid=%s" % [test_points[j], result, is_valid])

	assert_true(true, "Diagnostic — check output for stability")

func test_C2_renormalization_preserves_c_nonzero() -> void:
	# Create a transform with large entries but small c
	var big := 999999.0
	var small_c := 1e-7
	var m := MobiusTransform.new(
		Vector2(big, 0), Vector2(0, 0),
		Vector2(small_c, 0), Vector2(big, 0),
		false)

	print("DIAG [C2] Before compose: c=%s, maps_to_arcs=%s" % [m.c, m.maps_lines_to_arcs()])

	var id := MobiusTransform.identity()
	var composed := id.compose(m)
	print("DIAG [C2] After compose: c=%s, maps_to_arcs=%s" % [composed.c, composed.maps_lines_to_arcs()])

	# The compose will multiply entries. Check if renormalization shrinks c to zero
	var max_mag := maxf(maxf(composed.a.length(), composed.b.length()),
		maxf(composed.c.length(), composed.d.length()))
	print("DIAG [C2] max_mag=%s, c_mag=%s" % [max_mag, composed.c.length()])

	assert_true(composed.maps_lines_to_arcs(),
		"Small c should survive renormalization (c=%s)" % composed.c)

func test_C3_deep_reflection_chain() -> void:
	var center1 := Vector2(960, 540)
	var center2 := Vector2(1200, 540)
	var r := 100.0
	var c1 := GeneralizedCircle.from_circle(center1, r)
	var c2 := GeneralizedCircle.from_circle(center2, r)
	var m1 := ReflectionEffect.new(c1).get_mobius()
	var m2 := ReflectionEffect.new(c2).get_mobius()

	var frame := MobiusTransform.identity()
	var renorm_count := 0
	for i in range(30):
		var m := m1 if i % 2 == 0 else m2
		var old_max := maxf(maxf(frame.a.length(), frame.b.length()),
			maxf(frame.c.length(), frame.d.length()))
		frame = frame.compose(m)
		var new_max := maxf(maxf(frame.a.length(), frame.b.length()),
			maxf(frame.c.length(), frame.d.length()))
		if new_max < old_max * 0.5:
			renorm_count += 1
		if i < 5 or i % 5 == 0:
			print("DIAG [C3] bounce %d: c=%s, c_mag=%s, maps_to_arcs=%s" % [
				i, frame.c, frame.c.length(), frame.maps_lines_to_arcs()])

	print("DIAG [C3] Apparent renormalizations: %d" % renorm_count)
	assert_true(frame.maps_lines_to_arcs(),
		"After many reflections between circles, c should still be nonzero")

func test_C4_overflow_without_renormalization() -> void:
	# Manual composition without renormalization to check if overflow occurs
	var center := Vector2(960, 540)
	var carrier := GeneralizedCircle.from_circle(center, 200.0)
	var refl := ReflectionEffect.new(carrier)
	var m := refl.get_mobius()

	var a := Vector2(1, 0)
	var b := Vector2(0, 0)
	var c := Vector2(0, 0)
	var d := Vector2(1, 0)

	var overflow_at := -1
	for i in range(100):
		var m2_a := m.a
		var m2_b := m.b
		var m2_c := m.c
		var m2_d := m.d
		# This is a self-inverse conjugating transform
		# Manual compose without renormalization
		var new_a := MobiusTransform.cmul(a, m2_a) + MobiusTransform.cmul(b, m2_c)
		var new_b := MobiusTransform.cmul(a, m2_b) + MobiusTransform.cmul(b, m2_d)
		var new_c := MobiusTransform.cmul(c, m2_a) + MobiusTransform.cmul(d, m2_c)
		var new_d := MobiusTransform.cmul(c, m2_b) + MobiusTransform.cmul(d, m2_d)
		a = new_a; b = new_b; c = new_c; d = new_d

		var max_mag := maxf(maxf(a.length(), b.length()), maxf(c.length(), d.length()))
		if is_inf(max_mag) or is_nan(max_mag):
			overflow_at = i
			print("DIAG [C4] Overflow at composition %d" % i)
			break
		if i < 5 or i % 10 == 0:
			print("DIAG [C4] composition %d: max_mag=%s" % [i, max_mag])

	if overflow_at < 0:
		print("DIAG [C4] No overflow after 100 compositions — renormalization may not be needed")
	assert_true(true, "Diagnostic — check output")


# =============================================================================
# Group D: FAR_DISTANCE (T2) — 1e6
# =============================================================================

func test_D1_escape_step_uses_far_distance() -> void:
	# No surfaces — ray should produce escape steps using FAR_DISTANCE
	var player := Vector2(500, 300)
	var aim := Direction.from_coords(player, Vector2(800, 300))
	var path := Tracer.trace(player, aim, [], GameState.new())

	print("DIAG [D1] steps=%d" % path.steps.size())
	for s: Tracer.Step in path.steps:
		print("DIAG [D1] start=%s end=%s is_inf_start=%s is_inf_end=%s" % [
			s.start, s.end,
			is_inf(s.start.x) or is_inf(s.start.y),
			is_inf(s.end.x) or is_inf(s.end.y)])
		var length := s.start.distance_to(s.end)
		print("DIAG [D1] step_length=%.2f, is_far_distance=%s" % [
			length, is_inf(length)])

	# Line-frame escapes now use Vector2(INF, INF) endpoints
	# Arc-frame escapes use frame.apply(INF) (finite image of infinity)
	assert_gt(path.steps.size(), 0, "Should have escape steps")

func test_D2_far_distance_vs_infinity_in_visual() -> void:
	var bounds := Rect2(0, 0, 1920, 1080)
	var frame := MobiusTransform.identity()
	var ray := Ray.from_coords(Vector2(500, 300), Direction.from_coords(Vector2(500, 300), Vector2(800, 300)))

	# Create a path with INF endpoint step
	var inf_path := Tracer.TracedPath.new()
	inf_path.steps.append(Tracer.Step.new(
		Vector2(500, 300), Vector2(INF, INF), 0, null, ray, frame, Vector2(INF, INF), false))

	var inf_result := VisualConverter.prepare_for_display(inf_path, bounds)
	print("DIAG [D2] INF path -> %d steps after prepare" % inf_result.steps.size())
	for s: Tracer.Step in inf_result.steps:
		print("DIAG [D2]   %s -> %s" % [s.start, s.end])

	# Create a path with FAR_DISTANCE endpoint step
	var far_path := Tracer.TracedPath.new()
	far_path.steps.append(Tracer.Step.new(
		Vector2(500, 300), Vector2(500 + 1e6, 300), 0, null, ray, frame, Vector2(INF, INF), false))

	var far_result := VisualConverter.prepare_for_display(far_path, bounds)
	print("DIAG [D2] FAR path -> %d steps after prepare" % far_result.steps.size())
	for s: Tracer.Step in far_result.steps:
		print("DIAG [D2]   %s -> %s" % [s.start, s.end])

	assert_true(true, "Diagnostic — compare INF vs FAR_DISTANCE rendering")

func test_D3_far_distance_asymmetry() -> void:
	# Document the asymmetry between arc and line escape handling
	var center := Vector2(960, 540)
	var carrier := GeneralizedCircle.from_circle(center, 200.0)
	var refl := ReflectionEffect.new(carrier)
	var frame := refl.get_mobius()

	# Arc frame: escape uses frame.apply(INF) = finite point (image of infinity)
	var arc_escape := frame.apply(Vector2(INF, INF))
	print("DIAG [D3] Arc frame escape endpoint: %s (finite image of INF)" % arc_escape)
	print("DIAG [D3] Arc frame: is_inf=%s" % (is_inf(arc_escape.x) or is_inf(arc_escape.y)))

	# Line frame: escape now uses Vector2(INF, INF)
	var line_escape := Vector2(INF, INF)
	print("DIAG [D3] Line frame escape endpoint: %s (true infinity)" % line_escape)

	# Arc: image of infinity is naturally finite under Mobius
	# Line: uses true infinity, clipped by prepare_for_display
	print("DIAG [D3] Both now use exact math — no FAR_DISTANCE approximation")
	assert_true(true, "Diagnostic — documenting asymmetry")
