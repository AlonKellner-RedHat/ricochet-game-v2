extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()

func _make_room(rect: Rect2) -> Array[Surface]:
	return RoomBuilder.create_room_surfaces(rect)

func test_stage14_trace_single_step_hits_wall() -> void:
	var surfaces := _make_room(Rect2(100, 100, 600, 400))
	var dir := Direction.new(Vector2(400, 300), Vector2(700, 300))
	var path := Tracer.trace(Vector2(400, 300), dir, surfaces, GameState.new())
	assert_gte(path.steps.size(), 1, "Should have at least 1 step")
	assert_almost_eq(path.steps[0].start.x, 400.0, 0.1, "Step start x")
	assert_almost_eq(path.steps[0].end.x, 700.0, 0.1, "Step end should be at right wall")
	assert_not_null(path.steps[0].hit, "Step should have a hit record")

func test_stage14_trace_returns_traced_path() -> void:
	var surfaces := _make_room(Rect2(100, 100, 600, 400))
	var dir := Direction.new(Vector2(400, 300), Vector2(700, 300))
	var path := Tracer.trace(Vector2(400, 300), dir, surfaces, GameState.new())
	assert_true(path is Tracer.TracedPath, "Should return TracedPath")
	assert_true(path.steps is Array, "steps should be an Array")
	assert_true(path.targets_hit is Dictionary, "targets_hit should be a Dictionary")

func test_stage14_step_has_identity_frame() -> void:
	var surfaces := _make_room(Rect2(100, 100, 600, 400))
	var dir := Direction.new(Vector2(400, 300), Vector2(700, 300))
	var path := Tracer.trace(Vector2(400, 300), dir, surfaces, GameState.new())
	assert_eq(path.steps[0].frame_id, MobiusTransform.IDENTITY_ID, "Frame should be identity")

func test_stage14_trace_copies_game_state() -> void:
	var state := GameState.new({"counter": 0})
	var surfaces := _make_room(Rect2(100, 100, 600, 400))
	var dir := Direction.new(Vector2(400, 300), Vector2(700, 300))
	var _path := Tracer.trace(Vector2(400, 300), dir, surfaces, state)
	assert_eq(state.flags["counter"], 0, "Original game state should be unchanged")

func test_stage14_trace_target_tracking() -> void:
	var seg := Segment.new(Vector2(500, 100), Vector2(500, 500), Vector2(500, 300))
	var config := SideConfig.new(null, false)
	var target := Surface.new(seg, config, config, true, false)

	var walls := _make_room(Rect2(100, 100, 600, 400))
	var surfaces: Array[Surface] = []
	surfaces.append(target)
	surfaces.append_array(walls)

	var dir := Direction.new(Vector2(400, 300), Vector2(600, 300))
	var path := Tracer.trace(Vector2(400, 300), dir, surfaces, GameState.new())
	assert_true(path.targets_hit.has(target.id), "Target surface should be tracked")

func test_stage14_trace_no_hit_escape() -> void:
	var path := Tracer.trace(Vector2(400, 300), Direction.new(Vector2(400, 300), Vector2(500, 300)), [], GameState.new())
	assert_eq(path.steps.size(), 1, "Escape should produce 1 step")
	assert_null(path.steps[0].hit, "Escape step should have null hit")

func test_stage14_S3_determinism() -> void:
	var surfaces := _make_room(Rect2(100, 100, 600, 400))
	var dir := Direction.new(Vector2(400, 300), Vector2(600, 200))
	var state := GameState.new()
	var path1 := Tracer.trace(Vector2(400, 300), dir, surfaces, state)
	var path2 := Tracer.trace(Vector2(400, 300), dir, surfaces, state)
	assert_eq(path1.steps.size(), path2.steps.size(), "S3: Same step count")
	for i in path1.steps.size():
		assert_eq(path1.steps[i].start, path2.steps[i].start, "S3: Same start at step %d" % i)
		assert_eq(path1.steps[i].end, path2.steps[i].end, "S3: Same end at step %d" % i)

func test_stage14_trace_terminal_stops() -> void:
	var surfaces := _make_room(Rect2(100, 100, 600, 400))
	var dir := Direction.new(Vector2(400, 300), Vector2(700, 300))
	var path := Tracer.trace(Vector2(400, 300), dir, surfaces, GameState.new())
	assert_eq(path.steps.size(), 1, "Terminal effect should stop trace at 1 step")

func test_stage14_S16_no_nan_in_trace() -> void:
	var surfaces := _make_room(Rect2(100, 100, 600, 400))
	var dir := Direction.new(Vector2(400, 300), Vector2(600, 200))
	var path := Tracer.trace(Vector2(400, 300), dir, surfaces, GameState.new())
	for step in path.steps:
		assert_false(is_nan(step.start.x), "S16: step start x not NaN")
		assert_false(is_nan(step.start.y), "S16: step start y not NaN")
		assert_false(is_nan(step.end.x), "S16: step end x not NaN")
		assert_false(is_nan(step.end.y), "S16: step end y not NaN")
