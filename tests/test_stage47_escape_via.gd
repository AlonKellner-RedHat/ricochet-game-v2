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

# --- T3: Pole tests ---

func test_pole_is_preimage_of_infinity() -> void:
	for r in [50.0, 100.0, 200.0, 250.0, 500.0]:
		var center := Vector2(960, 540)
		var carrier := GeneralizedCircle.from_circle(center, r)
		var refl := ReflectionEffect.new(carrier)
		var frame := refl.get_mobius()
		var pole := frame.pole()
		var result := frame.apply(pole)
		assert_true(is_inf(result.x) or is_inf(result.y),
			"pole() must map to infinity for r=%d. pole=%s result=%s" % [r, pole, result])

func test_pole_equals_circle_center() -> void:
	for r in [50.0, 200.0, 250.0, 500.0]:
		var center := Vector2(960, 540)
		var carrier := GeneralizedCircle.from_circle(center, r)
		var refl := ReflectionEffect.new(carrier)
		var frame := refl.get_mobius()
		var pole := frame.pole()
		assert_almost_eq(pole, center, Vector2(0.01, 0.01),
			"For circle inversion, pole should be at center. r=%d pole=%s" % [r, pole])

func test_escape_via_finite_for_r250() -> void:
	var center := Vector2(960, 540)
	var r := 250.0
	var surf := _full_circle_mirror(center, r)
	var player := Vector2(center.x - r - 100, center.y)
	var aim := Direction.from_coords(player, center)
	var path := Tracer.trace(player, aim, [surf], GameState.new())
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		if step.is_arc_step:
			assert_false(is_inf(step.via.x) and is_inf(step.via.y),
				"Arc step %d via must be finite for r=250 collinear. via=%s" % [i, step.via])

func test_escape_via_finite_sweep() -> void:
	var center := Vector2(960, 540)
	var inf_count := 0
	for r_int in range(50, 510, 10):
		var r := float(r_int)
		var surf := _full_circle_mirror(center, r)
		var player := Vector2(center.x - r - 100, center.y)
		var aim := Direction.from_coords(player, center)
		H.reset_counters()
		var path := Tracer.trace(player, aim, [surf], GameState.new())
		for step: Tracer.Step in path.steps:
			if step.is_arc_step and (is_inf(step.via.x) and is_inf(step.via.y)):
				inf_count += 1
	assert_eq(inf_count, 0,
		"No arc step via should be infinite across r=50..500 collinear sweep. Found %d" % inf_count)

func test_escape_arc_side_correct() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var carrier := GeneralizedCircle.from_circle(center, r)
	var surf := _full_circle_mirror(center, r)
	var player := Vector2(center.x - r - 100, center.y + 50)
	var aim := Direction.from_coords(player, Vector2(center.x + r + 100, center.y - 50))
	var path := Tracer.trace(player, aim, [surf], GameState.new())
	var found_arc_escape := false
	for step: Tracer.Step in path.steps:
		if step.is_arc_step and step.hit == null:
			found_arc_escape = true
			var eval_via := carrier.evaluate(step.via)
			var eval_start := carrier.evaluate(step.start)
			assert_true(signf(eval_via) == signf(eval_start) or absf(eval_via) < 100.0,
				"Escape arc via should be on same side as start. eval_via=%.1f eval_start=%.1f" % [eval_via, eval_start])
	if not found_arc_escape:
		pass_test("No arc escape found — test is N/A for this configuration")

# --- T1: Always-normalize tests ---

func test_always_normalize_small_entries() -> void:
	var center := Vector2(960, 540)
	var r := 100.0
	var carrier := GeneralizedCircle.from_circle(center, r)
	var refl := ReflectionEffect.new(carrier)
	var m := refl.get_mobius()
	var composed := m.compose(m)
	var max_mag := maxf(
		maxf(sqrt(composed.a_re * composed.a_re + composed.a_im * composed.a_im),
			 sqrt(composed.b_re * composed.b_re + composed.b_im * composed.b_im)),
		maxf(sqrt(composed.c_re * composed.c_re + composed.c_im * composed.c_im),
			 sqrt(composed.d_re * composed.d_re + composed.d_im * composed.d_im)))
	assert_almost_eq(max_mag, 1.0, 0.01,
		"After compose, max entry magnitude should be ~1.0 (always normalized). Got %.4f" % max_mag)

# --- T2: FAR_DISTANCE removal tests ---

func test_line_escape_endpoint_is_infinity() -> void:
	var player := Vector2(500, 300)
	var aim := Direction.from_coords(player, Vector2(800, 300))
	var path := Tracer.trace(player, aim, [], GameState.new())
	assert_true(path.steps.size() > 0, "Should have escape steps")
	var has_inf_endpoint := false
	for step: Tracer.Step in path.steps:
		if is_inf(step.end.x) or is_inf(step.end.y) or is_inf(step.start.x) or is_inf(step.start.y):
			has_inf_endpoint = true
	assert_true(has_inf_endpoint,
		"Line escape endpoint should be infinity, not a finite far-away point")

func test_line_escape_via_stores_direction() -> void:
	var player := Vector2(500, 300)
	var aim := Direction.from_coords(player, Vector2(800, 300))
	var path := Tracer.trace(player, aim, [], GameState.new())
	var found_escape := false
	for step: Tracer.Step in path.steps:
		if step.hit == null and not step.is_arc_step:
			found_escape = true
			assert_false(is_inf(step.via.x) and is_inf(step.via.y),
				"Line escape via should store direction, not INF. via=%s" % step.via)
	assert_true(found_escape, "Should have line escape steps")

func test_line_escape_clips_correctly_after_display() -> void:
	var player := Vector2(500, 300)
	var aim := Direction.from_coords(player, Vector2(800, 300))
	var path := Tracer.trace(player, aim, [], GameState.new())
	var bounds := Rect2(0, 0, 1920, 1080)
	var display_path := VisualConverter.prepare_for_display(path, bounds)
	assert_true(display_path.steps.size() > 0, "Should have clipped steps")
	for step: Tracer.Step in display_path.steps:
		assert_false(is_inf(step.start.x) or is_inf(step.start.y),
			"After display, start should be finite. start=%s" % step.start)
		assert_false(is_inf(step.end.x) or is_inf(step.end.y),
			"After display, end should be finite. end=%s" % step.end)
		assert_true(bounds.grow(2.0).has_point(step.start) or bounds.grow(2.0).has_point(step.end),
			"After display, at least one endpoint should be near screen bounds")
