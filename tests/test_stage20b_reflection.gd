extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()

func _make_double_mirror(x: float, y_start: float, y_end: float) -> Surface:
	var seg := Segment.new(Vector2(x, y_start), Vector2(x, y_end), Vector2(x, (y_start + y_end) / 2.0))
	var carrier := seg.get_carrier()
	var reflection := ReflectionEffect.new(carrier)
	var config := SideConfig.new(reflection, true)
	return Surface.new(seg, config, config, false, false)

func _make_one_sided_mirror(seg: Segment, reflect_side: Side.Value) -> Surface:
	var carrier := seg.get_carrier()
	var reflection := ReflectionEffect.new(carrier)
	var refl_config := SideConfig.new(reflection, true)
	var pass_config := SideConfig.new(null, false)
	if reflect_side == Side.Value.LEFT:
		return Surface.new(seg, refl_config, pass_config, false, false)
	else:
		return Surface.new(seg, pass_config, refl_config, false, false)

func test_stage20b_reflection_known_point() -> void:
	var carrier := GeneralizedCircle.from_line(1, 0, -200)
	var refl := ReflectionEffect.new(carrier)
	var m := refl.get_mobius()
	var result := m.apply(Vector2(300, 250))
	assert_almost_eq(result.x, 100.0, 0.01, "Reflect (300,250) across x=200 → x=100")
	assert_almost_eq(result.y, 250.0, 0.01, "y should be preserved")

func test_stage20b_reflection_on_carrier() -> void:
	var carrier := GeneralizedCircle.from_line(1, 0, -200)
	var refl := ReflectionEffect.new(carrier)
	var m := refl.get_mobius()
	var result := m.apply(Vector2(200, 300))
	assert_almost_eq(result.x, 200.0, 0.01, "Point on carrier maps to itself")
	assert_almost_eq(result.y, 300.0, 0.01, "y preserved on carrier")

func test_stage20b_reflection_self_inverse() -> void:
	var carrier := GeneralizedCircle.from_line(1, 0, -200)
	var refl := ReflectionEffect.new(carrier)
	var m := refl.get_mobius()
	var p := Vector2(300, 250)
	var reflected := m.apply(p)
	var back := m.apply(reflected)
	assert_almost_eq(back.x, p.x, 0.01, "Double reflection returns to original x")
	assert_almost_eq(back.y, p.y, 0.01, "Double reflection returns to original y")

func test_stage20b_conjugating_flag() -> void:
	var carrier := GeneralizedCircle.from_line(1, 0, -200)
	var refl := ReflectionEffect.new(carrier)
	assert_true(refl.get_mobius().conjugating, "Reflection should be anti-conformal")

func test_stage20b_trace_bounces() -> void:
	var mirror := _make_double_mirror(500, 0, 600)
	var wall := RoomBuilder.create_block_surface(Vector2(200, 0), Vector2(200, 600), Vector2(200, 300))
	var surfaces: Array[Surface] = [mirror, wall]
	var dir := Direction.new(Vector2(300, 300), Vector2(600, 300))
	var path := Tracer.trace(Vector2(300, 300), dir, surfaces, GameState.new())
	assert_gte(path.steps.size(), 2, "Should bounce and continue")
	assert_almost_eq(path.steps[0].end.x, 500.0, 0.1, "First step hits mirror")
	assert_lt(path.steps[1].end.x, 500.0, "After bounce, ray should go left toward wall")

func test_stage20b_trace_one_sided_passes_through() -> void:
	var seg := Segment.new(Vector2(500, 600), Vector2(500, 0), Vector2(500, 300))
	var side := seg.determine_side(Vector2(700, 300))
	var mirror := _make_one_sided_mirror(seg, side)
	var wall := RoomBuilder.create_block_surface(Vector2(200, 0), Vector2(200, 600), Vector2(200, 300))
	var surfaces: Array[Surface] = [mirror, wall]
	var dir := Direction.new(Vector2(700, 300), Vector2(100, 300))
	var path := Tracer.trace(Vector2(700, 300), dir, surfaces, GameState.new())
	var hit_wall := false
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		if step.hit and absf(step.end.x - 200.0) < 0.1:
			hit_wall = true
	assert_true(hit_wall, "Approaching from pass-through side should reach the wall")

func test_stage20b_S12_side_at_hit() -> void:
	var mirror := _make_double_mirror(500, 0, 600)
	var wall := RoomBuilder.create_block_surface(Vector2(800, 0), Vector2(800, 600), Vector2(800, 300))
	var surfaces: Array[Surface] = [mirror, wall]
	var dir := Direction.new(Vector2(300, 300), Vector2(600, 300))
	var path := Tracer.trace(Vector2(300, 300), dir, surfaces, GameState.new())
	assert_not_null(path.steps[0].hit, "Should hit the mirror")

func test_stage20b_S16_reflection_no_nan() -> void:
	var carrier := GeneralizedCircle.from_line(1, 0, -200)
	var refl := ReflectionEffect.new(carrier)
	var m := refl.get_mobius()
	var result := m.apply(Vector2(500, 700))
	assert_false(is_nan(result.x), "S16: reflected x not NaN")
	assert_false(is_nan(result.y), "S16: reflected y not NaN")

func test_stage20b_reflection_with_determinant_carrier() -> void:
	var seg := Segment.new(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var m := refl.get_mobius()
	var result := m.apply(Vector2(300, 250))
	assert_almost_eq(result.x, 700.0, 0.1, "Reflect (300,250) across x=500 → x=700")
	assert_almost_eq(result.y, 250.0, 0.1, "y should be preserved")
