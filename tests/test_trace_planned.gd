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

func _aim(player: Vector2, cursor: Vector2, plan: Array, surfaces: Array) -> Direction:
	return Planner.compute_aim_direction(player, cursor, plan, surfaces, GameState.new())

func test_trace_planned_empty_plan() -> void:
	var mirror := _make_mirror(400)
	var surfaces: Array[Surface] = [mirror]
	var dir := Direction.new(Vector2(600, 300), Vector2(300, 300))
	var path := Tracer.trace_planned(Vector2(600, 300), dir, [], surfaces, GameState.new(), Vector2(300, 300))
	assert_eq(path.steps.size(), 0, "Empty plan should produce no steps")

func test_trace_planned_hits_carrier_only() -> void:
	var seg := Segment.new(Vector2(400, 200), Vector2(400, 400), Vector2(400, 300))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var config := SideConfig.new(refl, true)
	var mirror := Surface.new(seg, config, config, false, false)
	var surfaces: Array[Surface] = [mirror]
	var plan: Array = [PlanManager.PlanEntry.new(mirror.id, Side.Value.LEFT)]
	var player := Vector2(600, 100)
	var cursor := Vector2(500, 100)
	var dir := _aim(player, cursor, plan, surfaces)
	var path := Tracer.trace_planned(player, dir, plan, surfaces, GameState.new(), cursor)
	assert_gte(path.steps.size(), 1, "Should hit carrier even outside segment bounds")

func test_trace_planned_one_surface_at_a_time() -> void:
	var m1 := _make_mirror(300)
	var m2 := _make_mirror(500)
	var surfaces: Array[Surface] = [m1, m2]
	var plan: Array = [
		PlanManager.PlanEntry.new(m1.id, Side.Value.LEFT),
		PlanManager.PlanEntry.new(m2.id, Side.Value.LEFT),
	]
	var player := Vector2(200, 300)
	var cursor := Vector2(600, 300)
	var dir := _aim(player, cursor, plan, surfaces)
	var path := Tracer.trace_planned(player, dir, plan, surfaces, GameState.new(), cursor)
	assert_gte(path.steps.size(), 2, "Should have at least 2 steps for 2 planned surfaces")

func test_trace_planned_reaches_cursor() -> void:
	var mirror := _make_mirror(400)
	var surfaces: Array[Surface] = [mirror]
	var plan: Array = [PlanManager.PlanEntry.new(mirror.id, Side.Value.LEFT)]
	var player := Vector2(600, 300)
	var cursor := Vector2(300, 300)
	var dir := _aim(player, cursor, plan, surfaces)
	var path := Tracer.trace_planned(player, dir, plan, surfaces, GameState.new(), cursor)
	if path.steps.size() > 0:
		var last: Tracer.Step = path.steps[path.steps.size() - 1]
		assert_almost_eq(last.end.x, cursor.x, 1.0, "Last step should end at cursor x")
		assert_almost_eq(last.end.y, cursor.y, 1.0, "Last step should end at cursor y")

func test_trace_planned_no_nan() -> void:
	var mirror := _make_mirror(400)
	var surfaces: Array[Surface] = [mirror]
	var plan: Array = [PlanManager.PlanEntry.new(mirror.id, Side.Value.LEFT)]
	var player := Vector2(600, 400)
	var cursor := Vector2(300, 250)
	var dir := _aim(player, cursor, plan, surfaces)
	var path := Tracer.trace_planned(player, dir, plan, surfaces, GameState.new(), cursor)
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		assert_false(is_nan(step.start.x) or is_nan(step.start.y), "S16: step %d start" % i)
		assert_false(is_nan(step.end.x) or is_nan(step.end.y), "S16: step %d end" % i)
