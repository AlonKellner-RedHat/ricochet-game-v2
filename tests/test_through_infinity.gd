extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()

func _make_open_room() -> Array[Surface]:
	var top := RoomBuilder.create_block_surface(Vector2(560, 240), Vector2(1360, 240), Vector2(960, 240))
	var bottom := RoomBuilder.create_block_surface(Vector2(1360, 840), Vector2(560, 840), Vector2(960, 840))
	var left := RoomBuilder.create_block_surface(Vector2(560, 840), Vector2(560, 240), Vector2(560, 540))
	return [top, bottom, left]

func test_through_infinity_hits_behind_surface() -> void:
	var surfaces := _make_open_room()
	var dir := Direction.new(Vector2(960, 540), Vector2(1400, 540))
	var path := Tracer.trace(Vector2(960, 540), dir, surfaces, GameState.new())
	assert_gte(path.steps.size(), 2, "Should have escape + return-from-infinity steps")
	assert_null(path.steps[0].hit, "First step should be escape (no hit)")
	assert_not_null(path.steps[1].hit, "Second step should be the through-infinity hit")

func test_through_infinity_hits_left_wall() -> void:
	var surfaces := _make_open_room()
	var dir := Direction.new(Vector2(960, 540), Vector2(1400, 540))
	var path := Tracer.trace(Vector2(960, 540), dir, surfaces, GameState.new())
	var last_hit_step: Tracer.Step = null
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		if step.hit != null:
			last_hit_step = step
	assert_not_null(last_hit_step, "Should have a hit somewhere")
	assert_almost_eq(last_hit_step.end.x, 560.0, 0.1, "Should hit left wall through infinity")

func test_through_infinity_escape_goes_forward() -> void:
	var surfaces := _make_open_room()
	var dir := Direction.new(Vector2(960, 540), Vector2(1400, 540))
	var path := Tracer.trace(Vector2(960, 540), dir, surfaces, GameState.new())
	var first_step: Tracer.Step = path.steps[0]
	assert_gt(first_step.end.x, first_step.start.x, "Escape step should go forward (rightward)")

func test_through_infinity_return_comes_from_behind() -> void:
	var surfaces := _make_open_room()
	var dir := Direction.new(Vector2(960, 540), Vector2(1400, 540))
	var path := Tracer.trace(Vector2(960, 540), dir, surfaces, GameState.new())
	if path.steps.size() >= 2:
		var return_step: Tracer.Step = path.steps[1]
		assert_lt(return_step.start.x, return_step.end.x, "Return step should come from far left toward hit")

func test_through_infinity_no_nan() -> void:
	var surfaces := _make_open_room()
	var dir := Direction.new(Vector2(960, 540), Vector2(1400, 540))
	var path := Tracer.trace(Vector2(960, 540), dir, surfaces, GameState.new())
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		assert_false(is_nan(step.start.x) or is_nan(step.start.y), "S16: no NaN in step %d start" % i)
		assert_false(is_nan(step.end.x) or is_nan(step.end.y), "S16: no NaN in step %d end" % i)
		assert_false(is_inf(step.start.x) or is_inf(step.start.y), "S16: no Inf in step %d start" % i)
		assert_false(is_inf(step.end.x) or is_inf(step.end.y), "S16: no Inf in step %d end" % i)

func test_through_infinity_terminal_stops() -> void:
	var surfaces := _make_open_room()
	var dir := Direction.new(Vector2(960, 540), Vector2(1400, 540))
	var path := Tracer.trace(Vector2(960, 540), dir, surfaces, GameState.new())
	var last_step: Tracer.Step = path.steps[path.steps.size() - 1]
	assert_not_null(last_step.hit, "Last step should end at a terminal hit")

func test_through_infinity_full_loop_no_surfaces() -> void:
	var origin := Vector2(960, 540)
	var dir := Direction.new(origin, Vector2(1400, 540))
	var path := Tracer.trace(origin, dir, [], GameState.new())
	assert_eq(path.steps.size(), 2, "Full loop: escape + return")
	var escape_step: Tracer.Step = path.steps[0]
	var return_step: Tracer.Step = path.steps[1]
	assert_eq(escape_step.start, origin, "Escape starts at origin")
	assert_gt(escape_step.end.x, origin.x, "Escape goes forward")
	assert_lt(return_step.start.x, origin.x, "Return comes from behind")
	assert_almost_eq(return_step.end.x, origin.x, 0.1, "Return ends at origin")
	assert_almost_eq(return_step.end.y, origin.y, 0.1, "Return y matches origin")

func test_through_infinity_single_loop_only() -> void:
	var origin := Vector2(960, 540)
	var dir := Direction.new(origin, Vector2(1400, 540))
	var path := Tracer.trace(origin, dir, [], GameState.new())
	assert_eq(path.steps.size(), 2, "Should be exactly one loop, not more")
