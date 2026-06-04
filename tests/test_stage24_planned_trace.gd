extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()

func _make_mirror(x: float) -> Surface:
	var seg := Segment.new(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var config := SideConfig.new(refl, true)
	return Surface.new(seg, config, config, false, false)

func test_stage24_backward_image_reflection() -> void:
	var carrier := GeneralizedCircle.from_line(1, 0, -200)
	var refl := ReflectionEffect.new(carrier)
	var inv := refl.get_inverse_mobius()
	var image: Vector2 = inv.apply(Vector2(400, 300))
	assert_almost_eq(image.x, 0.0, 0.1, "Image of (400,300) reflected across x=200 should be x=0")
	assert_almost_eq(image.y, 300.0, 0.1, "y should be preserved")

func test_stage24_intersect_line_with_carrier() -> void:
	var carrier := GeneralizedCircle.from_line(1, 0, -100)
	var ray := Ray.new(Vector2(50, 450), Direction.new(Vector2(50, 450), Vector2(200, 300)))
	var hits := Intersection.intersect_line_with_carrier(ray, carrier)
	assert_gte(hits.size(), 1, "Should find intersection with carrier")
	assert_almost_eq(hits[0].point.x, 100.0, 0.1, "Hit should be on x=100")

func test_stage24_intersect_line_with_carrier_no_bounds() -> void:
	var seg := Segment.new(Vector2(100, 200), Vector2(100, 400), Vector2(100, 300))
	var carrier := seg.get_carrier()
	var ray := Ray.new(Vector2(50, 100), Direction.new(Vector2(50, 100), Vector2(200, 100)))
	var bounded := Intersection.intersect_line_with_gcircle(ray, seg)
	var unbounded := Intersection.intersect_line_with_carrier(ray, carrier)
	assert_eq(bounded.size(), 0, "Bounded should miss (y=100 outside 200-400)")
	assert_gte(unbounded.size(), 1, "Unbounded should find hit on carrier at y=100")

func test_stage24_single_reflection_plan() -> void:
	var mirror := _make_mirror(200)
	var surfaces: Array[Surface] = [mirror]
	var plan := PlanManager.new()
	plan.add_entry(mirror.id, Side.Value.LEFT)
	var planned := Planner.plan_transformative_subchain(
		Vector2(50, 300), Vector2(400, 300), plan.entries, surfaces, GameState.new())
	assert_eq(planned.steps.size(), 2, "Should have 2 steps: to mirror + mirror to cursor")
	assert_almost_eq(planned.steps[0].end.x, 200.0, 0.1, "Bounce at mirror x=200")
	assert_almost_eq(planned.steps[1].end.x, 400.0, 0.1, "Ends at cursor x=400")

func test_stage24_plan_produces_steps() -> void:
	var mirror := _make_mirror(200)
	var surfaces: Array[Surface] = [mirror]
	var plan := PlanManager.new()
	plan.add_entry(mirror.id, Side.Value.LEFT)
	var planned := Planner.plan_transformative_subchain(
		Vector2(50, 300), Vector2(400, 300), plan.entries, surfaces, GameState.new())
	for i in planned.steps.size():
		var step: Tracer.Step = planned.steps[i]
		assert_false(is_nan(step.start.x), "Step %d start x not NaN" % i)
		assert_false(is_nan(step.end.x), "Step %d end x not NaN" % i)

func test_stage24_single_reflection_angled() -> void:
	var mirror := _make_mirror(100)
	var surfaces: Array[Surface] = [mirror]
	var plan := PlanManager.new()
	plan.add_entry(mirror.id, Side.Value.LEFT)
	var planned := Planner.plan_transformative_subchain(
		Vector2(50, 450), Vector2(475, 300), plan.entries, surfaces, GameState.new())
	assert_gte(planned.steps.size(), 2, "Should have at least 2 steps")
	assert_almost_eq(planned.steps[0].end.x, 100.0, 0.1, "Bounce at mirror x=100")

func test_stage24_plan_empty_no_crash() -> void:
	var mirror := _make_mirror(200)
	var surfaces: Array[Surface] = [mirror]
	var planned := Planner.plan_transformative_subchain(
		Vector2(50, 300), Vector2(400, 300), [], surfaces, GameState.new())
	assert_eq(planned.steps.size(), 0, "Empty plan should produce no steps")

func test_stage24_through_infinity_bounce() -> void:
	var mirror := _make_mirror(800)
	var surfaces: Array[Surface] = [mirror]
	var plan := PlanManager.new()
	plan.add_entry(mirror.id, Side.Value.LEFT)
	# Player at x=960 (right), cursor at x=700 (left) — cursor on opposite side
	var planned := Planner.plan_transformative_subchain(
		Vector2(960, 500), Vector2(700, 500), plan.entries, surfaces, GameState.new())
	assert_gte(planned.steps.size(), 2, "Through-infinity: should have at least 2 steps")
	# The bounce should be on the carrier at x=800
	var found_bounce := false
	for i in planned.steps.size():
		var step: Tracer.Step = planned.steps[i]
		if absf(step.end.x - 800.0) < 0.1:
			found_bounce = true
	assert_true(found_bounce, "Should find a bounce at x=800 (via through-infinity)")

func test_stage24_through_infinity_reaches_cursor() -> void:
	var mirror := _make_mirror(800)
	var surfaces: Array[Surface] = [mirror]
	var plan := PlanManager.new()
	plan.add_entry(mirror.id, Side.Value.LEFT)
	var cursor := Vector2(700, 500)
	var planned := Planner.plan_transformative_subchain(
		Vector2(960, 500), cursor, plan.entries, surfaces, GameState.new())
	if planned.steps.size() > 0:
		var last_step: Tracer.Step = planned.steps[planned.steps.size() - 1]
		assert_almost_eq(last_step.end.x, cursor.x, 0.1, "Plan should reach cursor x")
		assert_almost_eq(last_step.end.y, cursor.y, 0.1, "Plan should reach cursor y")

func test_stage24_S16_no_nan() -> void:
	var mirror := _make_mirror(300)
	var surfaces: Array[Surface] = [mirror]
	var plan := PlanManager.new()
	plan.add_entry(mirror.id, Side.Value.LEFT)
	var planned := Planner.plan_transformative_subchain(
		Vector2(100, 200), Vector2(500, 400), plan.entries, surfaces, GameState.new())
	for i in planned.steps.size():
		var step: Tracer.Step = planned.steps[i]
		assert_false(is_nan(step.start.x) or is_nan(step.start.y), "S16: step %d start" % i)
		assert_false(is_nan(step.end.x) or is_nan(step.end.y), "S16: step %d end" % i)
