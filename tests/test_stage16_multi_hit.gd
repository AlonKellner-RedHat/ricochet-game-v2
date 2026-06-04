extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()

func _block_surface(start: Vector2, end_v: Vector2) -> Surface:
	var seg := Segment.new(start, end_v, (start + end_v) / 2.0)
	var terminal := TerminalEffect.new()
	return Surface.new(seg, SideConfig.new(terminal), SideConfig.new(terminal))

func _passthrough_surface(start: Vector2, end_v: Vector2) -> Surface:
	var seg := Segment.new(start, end_v, (start + end_v) / 2.0)
	return Surface.new(seg, SideConfig.new(null, false), SideConfig.new(null, false), false, false)

func test_stage16_trace_through_passthrough() -> void:
	var wall := _block_surface(Vector2(500, 0), Vector2(500, 600))
	var pt_surf := _passthrough_surface(Vector2(300, 0), Vector2(300, 600))
	var surfaces: Array[Surface] = [pt_surf, wall]
	var dir := Direction.new(Vector2(100, 300), Vector2(600, 300))
	var path := Tracer.trace(Vector2(100, 300), dir, surfaces, GameState.new())
	assert_eq(path.steps.size(), 2, "Should have 2 steps: pass-through + wall")
	assert_almost_eq(path.steps[0].end.x, 300.0, 0.1, "First step ends at pass-through")
	assert_almost_eq(path.steps[1].end.x, 500.0, 0.1, "Second step ends at wall")

func test_stage16_passthrough_excluded_not_rehit() -> void:
	var pt_surf := _passthrough_surface(Vector2(300, 0), Vector2(300, 600))
	var wall := _block_surface(Vector2(500, 0), Vector2(500, 600))
	var surfaces: Array[Surface] = [pt_surf, wall]
	var dir := Direction.new(Vector2(100, 300), Vector2(600, 300))
	var path := Tracer.trace(Vector2(100, 300), dir, surfaces, GameState.new())
	var pass_count := 0
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		if step.hit and absf(step.end.x - 300.0) < 0.1:
			pass_count += 1
	assert_eq(pass_count, 1, "S9: Pass-through surface should be hit only once")

func test_stage16_terminal_stops_loop() -> void:
	var pt_surf := _passthrough_surface(Vector2(300, 0), Vector2(300, 600))
	var wall := _block_surface(Vector2(500, 0), Vector2(500, 600))
	var surfaces: Array[Surface] = [pt_surf, wall]
	var dir := Direction.new(Vector2(100, 300), Vector2(600, 300))
	var path := Tracer.trace(Vector2(100, 300), dir, surfaces, GameState.new())
	assert_eq(path.steps.size(), 2, "Terminal should stop after pass-through + wall hit")

func test_stage16_multiple_consecutive_passthroughs() -> void:
	var p1 := _passthrough_surface(Vector2(200, 0), Vector2(200, 600))
	var p2 := _passthrough_surface(Vector2(300, 0), Vector2(300, 600))
	var p3 := _passthrough_surface(Vector2(400, 0), Vector2(400, 600))
	var wall := _block_surface(Vector2(500, 0), Vector2(500, 600))
	var surfaces: Array[Surface] = [p1, p2, p3, wall]
	var dir := Direction.new(Vector2(100, 300), Vector2(600, 300))
	var path := Tracer.trace(Vector2(100, 300), dir, surfaces, GameState.new())
	assert_eq(path.steps.size(), 4, "Should have 4 steps: 3 pass-throughs + wall")

func test_stage16_escape_after_passthrough() -> void:
	var pt_surf := _passthrough_surface(Vector2(300, 0), Vector2(300, 600))
	var surfaces: Array[Surface] = [pt_surf]
	var dir := Direction.new(Vector2(100, 300), Vector2(600, 300))
	var path := Tracer.trace(Vector2(100, 300), dir, surfaces, GameState.new())
	assert_eq(path.steps.size(), 3, "Should have 3 steps: pass-through + escape + return")
	assert_null(path.steps[1].hit, "Escape step should have null hit")
	assert_null(path.steps[2].hit, "Return step should have null hit")

func test_stage16_S3_determinism_multi_step() -> void:
	var pt_surf := _passthrough_surface(Vector2(300, 0), Vector2(300, 600))
	var wall := _block_surface(Vector2(500, 0), Vector2(500, 600))
	var surfaces: Array[Surface] = [pt_surf, wall]
	var dir := Direction.new(Vector2(100, 300), Vector2(600, 300))
	var state := GameState.new()
	var path1 := Tracer.trace(Vector2(100, 300), dir, surfaces, state)
	var path2 := Tracer.trace(Vector2(100, 300), dir, surfaces, state)
	assert_eq(path1.steps.size(), path2.steps.size(), "S3: Same step count")
	for i in path1.steps.size():
		var s1: Tracer.Step = path1.steps[i]
		var s2: Tracer.Step = path2.steps[i]
		assert_eq(s1.start, s2.start, "S3: Same start at step %d" % i)
		assert_eq(s1.end, s2.end, "S3: Same end at step %d" % i)

func test_stage16_max_256_hits() -> void:
	var surfaces: Array[Surface] = []
	for j in 300:
		var x := 100.0 + j * 2.0
		surfaces.append(_passthrough_surface(Vector2(x, 0), Vector2(x, 600)))
	var dir := Direction.new(Vector2(50, 300), Vector2(800, 300))
	var path := Tracer.trace(Vector2(50, 300), dir, surfaces, GameState.new())
	assert_lte(path.steps.size(), 256, "Should not exceed 256 steps")

func test_stage16_passthrough_target_tracked() -> void:
	var seg := Segment.new(Vector2(300, 0), Vector2(300, 600), Vector2(300, 300))
	var config := SideConfig.new(null, false)
	var target := Surface.new(seg, config, config, true, false)
	var wall := _block_surface(Vector2(500, 0), Vector2(500, 600))
	var surfaces: Array[Surface] = [target, wall]
	var dir := Direction.new(Vector2(100, 300), Vector2(600, 300))
	var path := Tracer.trace(Vector2(100, 300), dir, surfaces, GameState.new())
	assert_true(path.targets_hit.has(target.id), "Target should be tracked even when pass-through")

func test_stage16_nogaps_multi_step() -> void:
	var p1 := _passthrough_surface(Vector2(200, 0), Vector2(200, 600))
	var p2 := _passthrough_surface(Vector2(300, 0), Vector2(300, 600))
	var wall := _block_surface(Vector2(500, 0), Vector2(500, 600))
	var surfaces: Array[Surface] = [p1, p2, wall]
	var dir := Direction.new(Vector2(100, 300), Vector2(600, 300))
	var path := Tracer.trace(Vector2(100, 300), dir, surfaces, GameState.new())
	for i in range(1, path.steps.size()):
		var prev: Tracer.Step = path.steps[i - 1]
		var curr: Tracer.Step = path.steps[i]
		assert_almost_eq(prev.end.x, curr.start.x, 0.01, "NOGAPS: step %d end should equal step %d start" % [i - 1, i])
		assert_almost_eq(prev.end.y, curr.start.y, 0.01, "NOGAPS: y should match too")
