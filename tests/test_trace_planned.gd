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

func _step(path: Tracer.TracedPath, idx: int) -> Tracer.Step:
	return path.steps[idx]

func test_planned_empty_plan_no_effects() -> void:
	var mirror := _make_mirror(400)
	var wall := RoomBuilder.create_block_surface(Vector2(700, 0), Vector2(700, 600), Vector2(700, 300))
	var surfaces: Array = [mirror, wall]
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(800, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, ray, -1.0, Tracer.TraceMode.PLANNED, [])
	var first_fid: int = _step(path, 0).frame_id
	for i in path.steps.size():
		assert_eq(_step(path, i).frame_id, first_fid, "Empty plan: no frame changes at step %d" % i)

func test_planned_hits_carrier_only() -> void:
	var seg := Segment.new(Vector2(400, 200), Vector2(400, 400), Vector2(400, 300))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var config := SideConfig.new(refl, true)
	var mirror := Surface.new(seg, config, config, false, false)
	var wall := RoomBuilder.create_block_surface(Vector2(100, 0), Vector2(100, 600), Vector2(100, 300))
	var surfaces: Array = [mirror, wall]
	var plan: Array = [PlanManager.PlanEntry.new(mirror.id, Side.Value.LEFT)]
	var player := Vector2(600, 100)
	var cursor := Vector2(500, 100)
	var dir := _aim(player, cursor, plan, surfaces)
	var ray := Ray.new(player, dir)
	var path := Tracer.trace(player, dir, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, ray, -1.0, Tracer.TraceMode.PLANNED, plan)
	var found_frame_change := false
	for i in range(1, path.steps.size()):
		if _step(path, i).frame_id != _step(path, 0).frame_id:
			found_frame_change = true
			break
	assert_true(found_frame_change, "Should apply effect at carrier hit even outside segment bounds")

func test_planned_two_surfaces() -> void:
	var m1 := _make_mirror(300)
	var m2 := _make_mirror(500)
	var surfaces: Array = [m1, m2]
	var plan: Array = [
		PlanManager.PlanEntry.new(m1.id, Side.Value.LEFT),
		PlanManager.PlanEntry.new(m2.id, Side.Value.LEFT),
	]
	var player := Vector2(200, 300)
	var cursor := Vector2(600, 300)
	var dir := _aim(player, cursor, plan, surfaces)
	var ray := Ray.new(player, dir)
	var path := Tracer.trace(player, dir, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, ray, -1.0, Tracer.TraceMode.PLANNED, plan)
	var frame_changes := 0
	for i in range(1, path.steps.size()):
		if _step(path, i).frame_id != _step(path, i - 1).frame_id:
			frame_changes += 1
	assert_gte(frame_changes, 2, "Should have at least 2 frame changes for 2 planned surfaces")

func test_planned_no_nan() -> void:
	var mirror := _make_mirror(400)
	var wall := RoomBuilder.create_block_surface(Vector2(100, 0), Vector2(100, 600), Vector2(100, 300))
	var surfaces: Array = [mirror, wall]
	var plan: Array = [PlanManager.PlanEntry.new(mirror.id, Side.Value.LEFT)]
	var player := Vector2(600, 400)
	var cursor := Vector2(300, 250)
	var dir := _aim(player, cursor, plan, surfaces)
	var ray := Ray.new(player, dir)
	var path := Tracer.trace(player, dir, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, ray, -1.0, Tracer.TraceMode.PLANNED, plan)
	for i in path.steps.size():
		var s := _step(path, i)
		assert_false(is_nan(s.start.x) or is_nan(s.start.y), "S16: step %d start" % i)
		assert_false(is_nan(s.end.x) or is_nan(s.end.y), "S16: step %d end" % i)
