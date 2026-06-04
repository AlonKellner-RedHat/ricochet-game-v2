extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()

func _make_passthrough(start: Vector2, end_v: Vector2) -> Surface:
	var seg := Segment.new(start, end_v, (start + end_v) / 2.0)
	var config := SideConfig.new(null, false)
	return Surface.new(seg, config, config, false, false)

func _make_block(start: Vector2, end_v: Vector2) -> Surface:
	return RoomBuilder.create_block_surface(start, end_v, (start + end_v) / 2.0)

func test_stage19_passthrough_surface_construction() -> void:
	var surf := _make_passthrough(Vector2(400, 100), Vector2(400, 500))
	var state := GameState.new()
	var left := surf.active_side_config(Side.Value.LEFT, state)
	var right := surf.active_side_config(Side.Value.RIGHT, state)
	assert_null(left.effect, "Left effect should be null (pass-through)")
	assert_null(right.effect, "Right effect should be null (pass-through)")
	assert_false(left.interactive, "Left should not be interactive")
	assert_false(right.interactive, "Right should not be interactive")

func test_stage19_trace_through_passthrough() -> void:
	var pt := _make_passthrough(Vector2(400, 0), Vector2(400, 600))
	var wall := _make_block(Vector2(700, 0), Vector2(700, 600))
	var surfaces: Array[Surface] = [pt, wall]
	var dir := Direction.new(Vector2(100, 300), Vector2(800, 300))
	var path := Tracer.trace(Vector2(100, 300), dir, surfaces, GameState.new())
	assert_gte(path.steps.size(), 2, "Should pass through and hit wall")
	var last_step: Tracer.Step = path.steps[path.steps.size() - 1]
	assert_not_null(last_step.hit, "Last step should hit the wall")
	assert_almost_eq(last_step.end.x, 700.0, 0.1, "Should end at wall")

func test_stage19_passthrough_hit_recorded() -> void:
	var pt := _make_passthrough(Vector2(400, 0), Vector2(400, 600))
	var wall := _make_block(Vector2(700, 0), Vector2(700, 600))
	var surfaces: Array[Surface] = [pt, wall]
	var dir := Direction.new(Vector2(100, 300), Vector2(800, 300))
	var path := Tracer.trace(Vector2(100, 300), dir, surfaces, GameState.new())
	var found_passthrough := false
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		if step.hit and absf(step.end.x - 400.0) < 0.1:
			found_passthrough = true
	assert_true(found_passthrough, "Pass-through hit should be recorded as a step")

func test_stage19_passthrough_exclusion() -> void:
	var pt := _make_passthrough(Vector2(400, 0), Vector2(400, 600))
	var wall := _make_block(Vector2(700, 0), Vector2(700, 600))
	var surfaces: Array[Surface] = [pt, wall]
	var dir := Direction.new(Vector2(100, 300), Vector2(800, 300))
	var path := Tracer.trace(Vector2(100, 300), dir, surfaces, GameState.new())
	var pt_hit_count := 0
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		if step.hit and step.hit.segment == pt.segment:
			pt_hit_count += 1
	assert_eq(pt_hit_count, 1, "S9: Pass-through should be hit exactly once")

func test_stage19_passthrough_not_interactive() -> void:
	var surf := _make_passthrough(Vector2(400, 100), Vector2(400, 500))
	var state := GameState.new()
	assert_false(surf.active_side_config(Side.Value.LEFT, state).interactive, "Left not interactive")
	assert_false(surf.active_side_config(Side.Value.RIGHT, state).interactive, "Right not interactive")
