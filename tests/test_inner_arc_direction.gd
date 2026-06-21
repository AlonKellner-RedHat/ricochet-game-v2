extends GutTest

const H := preload("res://tests/test_helpers.gd")

func before_each() -> void:
	H.reset_counters()

func _full_circle_mirror(center: Vector2, r: float) -> Surface:
	var carrier := GeneralizedCircle.from_circle(center, r)
	var seg := Segment.full_from_carrier(carrier)
	var refl := ReflectionEffect.new(carrier)
	var config := SideConfig.new(refl, true)
	return Surface.new(seg, config, config, false, false)

func _inner_trace() -> Dictionary:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var carrier := surf.segment.get_carrier()
	var surfaces: Array = [surf]
	var player := Vector2(960, 600)
	var aim := Direction.from_coords(player, Vector2(700, 540))
	var path := Tracer.trace(player, aim, surfaces, GameState.new())
	return {"path": path, "carrier": carrier, "center": center, "r": r, "surf": surf, "player": player}

func _outer_trace() -> Dictionary:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var carrier := surf.segment.get_carrier()
	var surfaces: Array = [surf]
	var player := Vector2(600, 540)
	var aim := Direction.from_coords(player, Vector2(1300, 540))
	var path := Tracer.trace(player, aim, surfaces, GameState.new())
	return {"path": path, "carrier": carrier, "center": center, "r": r, "surf": surf, "player": player}

func _first_reflected_arc(path: Tracer.TracedPath) -> Tracer.Step:
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if s.frame.conjugating and s.is_arc_step:
			return s
	return null


func test_arc_via_on_carrier_circle() -> void:
	var d := _inner_trace()
	var path: Tracer.TracedPath = d["path"]
	var surface_carrier: GeneralizedCircle = d["carrier"]

	var arc_step := _first_reflected_arc(path)
	assert_not_null(arc_step, "Should have a reflected arc step")
	if arc_step == null:
		return

	var eval_via := absf(surface_carrier.evaluate(arc_step.via))
	assert_lt(eval_via, 1.0,
		"Via should be on the surface carrier circle (|eval|=%.4f)" % eval_via)


func test_arc_visually_crosses_surface() -> void:
	var d := _inner_trace()
	var path: Tracer.TracedPath = d["path"]
	var surface_carrier: GeneralizedCircle = d["carrier"]

	var arc_step := _first_reflected_arc(path)
	assert_not_null(arc_step, "Should have a reflected arc step")
	if arc_step == null:
		return

	var params := VisualConverter.arc_params(arc_step.start, arc_step.via, arc_step.end)
	var ctr: Vector2 = params["center"]
	var r: float = params["radius"]
	var sa: float = params["start_angle"]
	var ea: float = params["end_angle"]

	var outside_count := 0
	var samples := 20
	for i in samples + 1:
		var t := float(i) / float(samples)
		var angle := sa + (ea - sa) * t
		var pt := ctr + Vector2(cos(angle), sin(angle)) * r
		var eval_val := surface_carrier.evaluate(pt)
		if eval_val > 100.0:
			outside_count += 1

	assert_eq(outside_count, 0,
		"Inner-reflected arc should stay inside the surface circle, but %d/%d samples are outside" % [outside_count, samples + 1])


func test_physical_ray_does_not_cross_surface() -> void:
	var d := _inner_trace()
	var path: Tracer.TracedPath = d["path"]
	var surface_carrier: GeneralizedCircle = d["carrier"]

	var arc_step := _first_reflected_arc(path)
	assert_not_null(arc_step, "Should have a reflected arc step")
	if arc_step == null:
		return

	var frame_inv := arc_step.frame.invert()
	var phys_start := frame_inv.apply(arc_step.start)
	var phys_end := frame_inv.apply(arc_step.end)

	print("DIAG [test3] Physical coords: start=%s end=%s" % [phys_start, phys_end])

	var all_inside := true
	var all_outside := true
	var samples := 20
	for i in samples + 1:
		var t := float(i) / float(samples)
		var pt := phys_start + (phys_end - phys_start) * t
		var eval_val := surface_carrier.evaluate(pt)
		if eval_val > 1.0:
			all_inside = false
		if eval_val < -1.0:
			all_outside = false

	print("DIAG [test3] Physical ray: all_inside=%s all_outside=%s" % [all_inside, all_outside])
	print("DIAG [test3] Bug is visual-only: %s (physical ray stays on one side)" % (all_inside or all_outside))

	assert_true(all_inside or all_outside,
		"Physical ray should not cross the surface — bug should be visual-only")


func test_midpoint_via_produces_correct_side() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var carrier := GeneralizedCircle.from_circle(center, r)

	var refl := ReflectionEffect.new(carrier)
	var frame := refl.get_mobius()

	var phys_start := Vector2(960, 600)
	var phys_end := Vector2(860, 560)
	var midpoint := (phys_start + phys_end) / 2.0
	var via := frame.apply(midpoint)

	var eval_via := carrier.evaluate(via)
	var eval_phys := carrier.evaluate(phys_start)

	assert_true(eval_phys < 0, "Physical point should be inside circle")
	assert_true(eval_via > 0,
		"Conjugation maps inside midpoint to outside (expected). eval=%.2f" % eval_via)


func test_inner_physical_midpoint_is_inside_carrier() -> void:
	var d := _inner_trace()
	var carrier: GeneralizedCircle = d["carrier"]
	var arc_step := _first_reflected_arc(d["path"])
	assert_not_null(arc_step, "Should have a reflected arc step")
	if arc_step == null:
		return

	var frame_inv := arc_step.frame.invert()
	var phys_start := frame_inv.apply(arc_step.start)
	var phys_end := frame_inv.apply(arc_step.end)
	var midpoint := (phys_start + phys_end) / 2.0

	var eval_mid := carrier.evaluate(midpoint)
	print("DIAG phys_start=%s phys_end=%s mid=%s eval=%.2f" % [phys_start, phys_end, midpoint, eval_mid])
	assert_true(eval_mid < 0,
		"Physical midpoint should be inside circle (eval < 0), got %.2f" % eval_mid)


func test_conjugation_maps_inside_midpoint_outside() -> void:
	var d := _inner_trace()
	var carrier: GeneralizedCircle = d["carrier"]
	var arc_step := _first_reflected_arc(d["path"])
	assert_not_null(arc_step, "Should have a reflected arc step")
	if arc_step == null:
		return

	var frame_inv := arc_step.frame.invert()
	var phys_start := frame_inv.apply(arc_step.start)
	var phys_end := frame_inv.apply(arc_step.end)
	var phys_mid := (phys_start + phys_end) / 2.0

	var vis_via := arc_step.frame.apply(phys_mid)
	var eval_phys := carrier.evaluate(phys_mid)
	var eval_vis := carrier.evaluate(vis_via)

	print("DIAG phys_mid eval=%.2f, vis_via=%s eval=%.2f" % [eval_phys, vis_via, eval_vis])
	assert_true(eval_phys < 0, "Physical midpoint should be inside (eval < 0)")
	assert_true(eval_vis > 0,
		"Conjugation should map inside midpoint to outside. eval=%.2f" % eval_vis)


func test_antipodal_via_is_inside_carrier() -> void:
	var d := _inner_trace()
	var carrier: GeneralizedCircle = d["carrier"]
	var arc_step := _first_reflected_arc(d["path"])
	assert_not_null(arc_step, "Should have a reflected arc step")
	if arc_step == null:
		return

	var frame_inv := arc_step.frame.invert()
	var phys_start := frame_inv.apply(arc_step.start)
	var phys_end := frame_inv.apply(arc_step.end)
	var phys_mid := (phys_start + phys_end) / 2.0
	var vis_via := arc_step.frame.apply(phys_mid)

	var params := VisualConverter.arc_params(arc_step.start, vis_via, arc_step.end)
	var arc_center: Vector2 = params["center"]
	var flipped_via := 2.0 * arc_center - vis_via

	var eval_flipped := carrier.evaluate(flipped_via)
	print("DIAG vis_via=%s eval=%.2f, flipped=%s eval=%.2f" % [vis_via, carrier.evaluate(vis_via), flipped_via, eval_flipped])
	assert_true(eval_flipped < 0,
		"Flipped via should be inside circle (eval < 0), got %.2f" % eval_flipped)

	var flipped_params := VisualConverter.arc_params(arc_step.start, flipped_via, arc_step.end)
	var ctr: Vector2 = flipped_params["center"]
	var r: float = flipped_params["radius"]
	var sa: float = flipped_params["start_angle"]
	var ea: float = flipped_params["end_angle"]
	var outside := 0
	var worst_eval := 0.0
	for i in 21:
		var t := float(i) / 20.0
		var angle := sa + (ea - sa) * t
		var pt := ctr + Vector2(cos(angle), sin(angle)) * r
		var ev := carrier.evaluate(pt)
		if ev > worst_eval:
			worst_eval = ev
		if ev > 100.0:
			outside += 1
			print("DIAG sample %d: angle=%.4f pt=%s eval=%.2f" % [i, angle, pt, ev])

	print("DIAG flipped arc: %d/21 outside, worst_eval=%.2f" % [outside, worst_eval])
	assert_eq(outside, 0,
		"Flipped-via arc should stay inside surface, but %d/21 samples are outside (worst=%.2f)" % [outside, worst_eval])


func test_wrapping_arc_via_is_on_carrier() -> void:
	var d := _inner_trace()
	var surface_carrier: GeneralizedCircle = d["carrier"]
	var arc_step := _first_reflected_arc(d["path"])
	assert_not_null(arc_step, "Should have a reflected arc step")
	if arc_step == null:
		return

	var eval_via := absf(surface_carrier.evaluate(arc_step.via))
	assert_lt(eval_via, 1.0,
		"Wrapping arc via should be on the surface carrier (evaluate=%.4f)" % eval_via)


func test_inner_arc_stays_inside_surface() -> void:
	var d_inner := _inner_trace()
	var surface_carrier: GeneralizedCircle = d_inner["carrier"]

	var inner_arc := _first_reflected_arc(d_inner["path"])
	assert_not_null(inner_arc, "Should have a reflected arc step")
	if inner_arc == null:
		return

	var params := VisualConverter.arc_params(inner_arc.start, inner_arc.via, inner_arc.end)
	var ctr: Vector2 = params["center"]
	var r: float = params["radius"]
	var sa: float = params["start_angle"]
	var ea: float = params["end_angle"]
	var outside := 0
	for i in 21:
		var t := float(i) / 20.0
		var angle := sa + (ea - sa) * t
		var pt := ctr + Vector2(cos(angle), sin(angle)) * r
		var ev := surface_carrier.evaluate(pt)
		if ev > 100.0:
			outside += 1

	assert_eq(outside, 0,
		"Inner-reflected arc should stay inside surface, but %d/21 samples are outside" % outside)
