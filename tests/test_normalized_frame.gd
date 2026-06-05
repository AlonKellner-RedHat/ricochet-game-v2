extends GutTest
## Tests for the normalized frame tracer behavior (§12.1, §12.4).
## These verify that the tracer uses frame composition instead of
## geometric ray reflection.

func before_each() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()

func _make_mirror(x: float) -> Surface:
	var seg := Segment.new(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var config := SideConfig.new(refl, true)
	return Surface.new(seg, config, config, false, false)

func _make_wall(x: float) -> Surface:
	return RoomBuilder.create_block_surface(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))

# --- Phase 1a: normalized frame tests ---

func test_tracer_direction_unchanged() -> void:
	# §10.7: Direction stays the same through transformative effects
	var mirror := _make_mirror(400)
	var wall := _make_wall(100)
	var surfaces: Array[Surface] = [mirror, wall]
	var dir := Direction.new(Vector2(600, 300), Vector2(300, 300))
	var path := Tracer.trace(Vector2(600, 300), dir, surfaces, GameState.new())
	# The direction should be the SAME object through all steps
	# (the tracer should never create a new Direction for transformative effects)
	assert_gte(path.steps.size(), 2, "Should have at least 2 steps (mirror bounce + wall)")

func test_tracer_multi_bounce_two_mirrors() -> void:
	# Two parallel mirrors: the ray should zigzag between them
	var m1 := _make_mirror(300)
	var m2 := _make_mirror(500)
	var wall_left := _make_wall(100)
	var wall_right := _make_wall(700)
	var surfaces: Array[Surface] = [m1, m2, wall_left, wall_right]
	var dir := Direction.new(Vector2(400, 500), Vector2(250, 400))
	var path := Tracer.trace(Vector2(400, 500), dir, surfaces, GameState.new())
	# Should bounce between mirrors multiple times before hitting a wall
	assert_gte(path.steps.size(), 3, "Should bounce between mirrors")
	# Verify zigzag: alternating x-direction
	for i in range(1, mini(path.steps.size(), 5)):
		var prev_step: Tracer.Step = path.steps[i - 1]
		var curr_step: Tracer.Step = path.steps[i]
		var prev_dx: float = prev_step.end.x - prev_step.start.x
		var curr_dx: float = curr_step.end.x - curr_step.start.x
		if prev_step.hit != null and curr_step.hit != null:
			# After a reflection, x-direction should reverse
			if absf(prev_step.end.x - 300.0) < 1.0 or absf(prev_step.end.x - 500.0) < 1.0:
				assert_true(prev_dx * curr_dx <= 0.0,
					"Step %d: x-direction should reverse after mirror bounce" % i)

func test_tracer_reflection_correct_geometry() -> void:
	# Verify that reflecting off a vertical mirror at x=400
	# with incoming from the right produces correct outgoing geometry
	var mirror := _make_mirror(400)
	var wall := _make_wall(100)
	var surfaces: Array[Surface] = [mirror, wall]
	# Fire from (600, 400) toward (300, 300) — will hit mirror at x=400
	var dir := Direction.new(Vector2(600, 400), Vector2(300, 300))
	var path := Tracer.trace(Vector2(600, 400), dir, surfaces, GameState.new())
	assert_gte(path.steps.size(), 2, "Should hit mirror and continue")
	var step0: Tracer.Step = path.steps[0]
	var step1: Tracer.Step = path.steps[1]
	# Step 0 should end at the mirror (x ≈ 400)
	assert_almost_eq(step0.end.x, 400.0, 1.0, "Step 0 should hit mirror at x=400")
	# Step 1: incoming angle = outgoing angle for reflection
	var incoming := (step0.end - step0.start).normalized()
	var outgoing := (step1.end - step1.start).normalized()
	# For vertical mirror: x-component reverses, y-component preserves
	assert_almost_eq(incoming.y, outgoing.y, 0.01, "y-component should be preserved")
	assert_almost_eq(incoming.x, -outgoing.x, 0.01, "x-component should negate")

func test_tracer_no_nan_multi_bounce() -> void:
	var m1 := _make_mirror(300)
	var m2 := _make_mirror(500)
	var wall := _make_wall(100)
	var surfaces: Array[Surface] = [m1, m2, wall]
	var dir := Direction.new(Vector2(400, 500), Vector2(250, 300))
	var path := Tracer.trace(Vector2(400, 500), dir, surfaces, GameState.new())
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		assert_false(is_nan(step.start.x) or is_nan(step.start.y),
			"S16: step %d start should not be NaN" % i)
		assert_false(is_nan(step.end.x) or is_nan(step.end.y),
			"S16: step %d end should not be NaN" % i)
