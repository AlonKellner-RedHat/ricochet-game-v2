extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()

func _make_mirror(x: float, y_start: float, y_end: float) -> Surface:
	var seg := Segment.new(Vector2(x, y_start), Vector2(x, y_end), Vector2(x, (y_start + y_end) / 2.0))
	var carrier := seg.get_carrier()
	var reflection := ReflectionEffect.new(carrier)
	var config := SideConfig.new(reflection, true)
	return Surface.new(seg, config, config, false, false)

func _make_wall(x: float) -> Surface:
	return RoomBuilder.create_block_surface(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))

func test_stage21_double_bounce() -> void:
	var m1 := _make_mirror(200, 0, 600)
	var m2 := _make_mirror(600, 0, 600)
	var wall := _make_wall(800)
	var surfaces: Array[Surface] = [m1, m2, wall]
	var dir := Direction.new(Vector2(100, 300), Vector2(700, 300))
	var path := Tracer.trace(Vector2(100, 300), dir, surfaces, GameState.new())
	assert_gte(path.steps.size(), 3, "Should have at least 3 steps: hit m1, hit m2, hit wall")

func test_stage21_bounce_direction_changes() -> void:
	var m1 := _make_mirror(400, 0, 600)
	var wall_left := _make_wall(100)
	var wall_right := _make_wall(700)
	var surfaces: Array[Surface] = [m1, wall_left, wall_right]
	var dir := Direction.new(Vector2(300, 300), Vector2(500, 300))
	var path := Tracer.trace(Vector2(300, 300), dir, surfaces, GameState.new())
	assert_gte(path.steps.size(), 2, "Should bounce off mirror")
	var step0: Tracer.Step = path.steps[0]
	var step1: Tracer.Step = path.steps[1]
	var dir0: Vector2 = (step0.end - step0.start).normalized()
	var dir1: Vector2 = (step1.end - step1.start).normalized()
	assert_gt(dir0.x, 0.0, "First step should go right")
	assert_lt(dir1.x, 0.0, "After bounce, should go left")

func test_stage21_bounce_angles_correct() -> void:
	var m1 := _make_mirror(400, 0, 600)
	var surfaces: Array[Surface] = [m1]
	var dir := Direction.new(Vector2(300, 200), Vector2(400, 300))
	var path := Tracer.trace(Vector2(300, 200), dir, surfaces, GameState.new())
	assert_gte(path.steps.size(), 2, "Should bounce")
	var step0: Tracer.Step = path.steps[0]
	var step1: Tracer.Step = path.steps[1]
	var incoming: Vector2 = (step0.end - step0.start).normalized()
	var outgoing: Vector2 = (step1.end - step1.start).normalized()
	assert_almost_eq(incoming.y, outgoing.y, 0.01, "y component should be preserved in reflection across vertical line")
	assert_almost_eq(incoming.x, -outgoing.x, 0.01, "x component should be negated")

func test_stage21_S3_determinism_multi_bounce() -> void:
	var m1 := _make_mirror(400, 0, 600)
	var wall := _make_wall(100)
	var surfaces: Array[Surface] = [m1, wall]
	var dir := Direction.new(Vector2(300, 300), Vector2(500, 300))
	var state := GameState.new()
	var path1 := Tracer.trace(Vector2(300, 300), dir, surfaces, state)
	var path2 := Tracer.trace(Vector2(300, 300), dir, surfaces, state)
	assert_eq(path1.steps.size(), path2.steps.size(), "S3: Same step count")
	for i in path1.steps.size():
		var s1: Tracer.Step = path1.steps[i]
		var s2: Tracer.Step = path2.steps[i]
		assert_almost_eq(s1.start.x, s2.start.x, 0.01, "S3: Same start x at step %d" % i)
		assert_almost_eq(s1.end.x, s2.end.x, 0.01, "S3: Same end x at step %d" % i)

func test_stage21_S16_no_nan_multi_bounce() -> void:
	var m1 := _make_mirror(200, 0, 600)
	var m2 := _make_mirror(600, 0, 600)
	var wall := _make_wall(800)
	var surfaces: Array[Surface] = [m1, m2, wall]
	var dir := Direction.new(Vector2(100, 250), Vector2(700, 350))
	var path := Tracer.trace(Vector2(100, 250), dir, surfaces, GameState.new())
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		assert_false(is_nan(step.start.x) or is_nan(step.start.y), "S16: step %d start" % i)
		assert_false(is_nan(step.end.x) or is_nan(step.end.y), "S16: step %d end" % i)

func test_stage21_transform_all_identity() -> void:
	var m1 := _make_mirror(400, 0, 600)
	var identity := MobiusTransform.identity()
	var transformed := Tracer.transform_all([m1], identity)
	assert_eq(transformed.size(), 1, "Should have 1 surface")
	assert_almost_eq(transformed[0].segment.start.x, 400.0, 0.01, "Identity preserves x")

func test_stage21_transform_all_reflection() -> void:
	var carrier := GeneralizedCircle.from_line(1, 0, -300)
	var refl := ReflectionEffect.new(carrier)
	var m := refl.get_mobius()
	var surf := _make_wall(500)
	var transformed := Tracer.transform_all([surf], m)
	assert_almost_eq(transformed[0].segment.start.x, 100.0, 0.1, "Reflected x=500 across x=300 → x=100")

func test_stage21_wall_stops_after_bounces() -> void:
	var m1 := _make_mirror(400, 0, 600)
	var wall := _make_wall(100)
	var surfaces: Array[Surface] = [m1, wall]
	var dir := Direction.new(Vector2(300, 300), Vector2(500, 300))
	var path := Tracer.trace(Vector2(300, 300), dir, surfaces, GameState.new())
	var last_step: Tracer.Step = path.steps[path.steps.size() - 1]
	assert_not_null(last_step.hit, "Should end at wall")
	assert_almost_eq(last_step.end.x, 100.0, 0.1, "Should hit left wall after bounce")

func test_stage21_multi_bounce_perf_gate() -> void:
	var surfaces: Array[Surface] = []
	surfaces.append(_make_mirror(300, 0, 600))
	surfaces.append(_make_mirror(500, 0, 600))
	surfaces.append(_make_wall(100))
	surfaces.append(_make_wall(700))
	surfaces.append(RoomBuilder.create_block_surface(Vector2(100, 0), Vector2(700, 0), Vector2(400, 0)))
	surfaces.append(RoomBuilder.create_block_surface(Vector2(700, 600), Vector2(100, 600), Vector2(400, 600)))
	var dir := Direction.new(Vector2(200, 250), Vector2(600, 350))
	var start_time := Time.get_ticks_usec()
	var _path := Tracer.trace(Vector2(200, 250), dir, surfaces, GameState.new())
	var elapsed := Time.get_ticks_usec() - start_time
	assert_lt(elapsed, 10000, "Multi-bounce trace should complete in < 10ms (took %d μs)" % elapsed)
