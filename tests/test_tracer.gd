extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()

func _wall(x: float) -> Surface:
	return RoomBuilder.create_block_surface(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))

func _mirror(x: float) -> Surface:
	var seg := Segment.new(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var config := SideConfig.new(refl, true)
	return Surface.new(seg, config, config, false, false)

func _passthrough(x: float) -> Surface:
	var seg := Segment.new(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))
	var config := SideConfig.new(null, false)
	return Surface.new(seg, config, config, false, false)

func _step(path: Tracer.TracedPath, idx: int) -> Tracer.Step:
	return path.steps[idx]

# --- Basic tracing ---

func test_ray_hits_wall() -> void:
	var w := _wall(500)
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(600, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, [w], GameState.new())
	assert_gte(path.steps.size(), 1, "Should have at least 1 step")
	var last := _step(path, path.steps.size() - 1)
	assert_not_null(last.hit, "Last step should hit the wall")

func test_ray_escapes_no_surfaces() -> void:
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(600, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, [], GameState.new())
	assert_gte(path.steps.size(), 1, "Should have escape steps")

func test_no_nan_in_steps() -> void:
	var w := _wall(500)
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(600, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, [w], GameState.new())
	for i in path.steps.size():
		var s := _step(path, i)
		assert_false(is_nan(s.start.x) or is_nan(s.start.y), "No NaN in step %d start" % i)
		assert_false(is_nan(s.end.x) or is_nan(s.end.y), "No NaN in step %d end" % i)

# --- Cursor virtual hitpoint ---

func test_cursor_injected() -> void:
	var w := _wall(600)
	var player := Vector2(200, 300)
	var cursor := Vector2(300, 300)
	var ray := Ray.new(player, Direction.new(player, Vector2(800, 300)))
	var path := Tracer.trace(player, ray.direction, [w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, [], cursor)
	assert_gte(path.steps.size(), 2, "Should have cursor step + post-cursor")
	var cursor_step := _step(path, 0)
	assert_almost_eq(cursor_step.end.x, cursor.x, 1.0, "Cursor step ends at cursor")

func test_cursor_index_set() -> void:
	var w := _wall(600)
	var player := Vector2(200, 300)
	var cursor := Vector2(300, 300)
	var ray := Ray.new(player, Direction.new(player, Vector2(800, 300)))
	var path := Tracer.trace(player, ray.direction, [w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, [], cursor)
	assert_eq(path.cursor_index, 1, "cursor_index should be 1 (first post-cursor step)")

func test_cursor_not_reached_wall_blocks() -> void:
	var w := _wall(250)
	var player := Vector2(200, 300)
	var cursor := Vector2(500, 300)
	var ray := Ray.new(player, Direction.new(player, Vector2(800, 300)))
	var path := Tracer.trace(player, ray.direction, [w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, [], cursor)
	assert_eq(path.cursor_index, -1, "Cursor not reached when wall blocks first")

# --- Mirror reflection ---

func test_mirror_changes_frame() -> void:
	var m := _mirror(400)
	var w := _wall(100)
	var ray := Ray.new(Vector2(600, 300), Direction.new(Vector2(600, 300), Vector2(200, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, [m, w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	var first_fid: int = _step(path, 0).frame_id
	var found_change := false
	for i in range(1, path.steps.size()):
		if _step(path, i).frame_id != first_fid:
			found_change = true
			break
	assert_true(found_change, "Mirror should change frame")

func test_multi_bounce() -> void:
	var m1 := _mirror(300)
	var m2 := _mirror(600)
	var ray := Ray.new(Vector2(450, 300), Direction.new(Vector2(450, 300), Vector2(200, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, [m1, m2], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	assert_gte(path.steps.size(), 3, "Should bounce between mirrors multiple times")

# --- Pass-through ---

func test_passthrough_excluded() -> void:
	var pt := _passthrough(400)
	var w := _wall(600)
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(800, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, [pt, w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	assert_gte(path.steps.size(), 2, "Should pass through and hit wall")

# --- Shared ray provenance ---

func test_all_steps_share_ray() -> void:
	var m := _mirror(400)
	var w := _wall(100)
	var ray := Ray.new(Vector2(600, 300), Direction.new(Vector2(600, 300), Vector2(200, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, [m, w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	for i in path.steps.size():
		assert_eq(_step(path, i).ray, ray, "Step %d should share the same Ray" % i)

# --- Determinism ---

func test_deterministic() -> void:
	var m := _mirror(400)
	var w := _wall(100)
	var ray := Ray.new(Vector2(600, 300), Direction.new(Vector2(600, 300), Vector2(200, 300)))
	var path1 := Tracer.trace(ray.origin, ray.direction, [m, w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	var path2 := Tracer.trace(ray.origin, ray.direction, [m, w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	assert_eq(path1.steps.size(), path2.steps.size(), "Same step count")
	for i in path1.steps.size():
		assert_eq(_step(path1, i).start, _step(path2, i).start, "Same start at step %d" % i)
		assert_eq(_step(path1, i).end, _step(path2, i).end, "Same end at step %d" % i)

# --- Target tracking ---

func test_target_surface_tracked() -> void:
	var seg := Segment.new(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var config := SideConfig.new(TerminalEffect.new())
	var target := Surface.new(seg, config, config, true, false)
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(600, 300)))
	var path := Tracer.trace(ray.origin, ray.direction, [target], GameState.new(), Tracer.DEFAULT_BOUNDS, ray)
	assert_true(path.targets_hit.has(target.id), "Target should be tracked")

# --- trace_ray convenience ---

func test_trace_ray_convenience() -> void:
	var w := _wall(500)
	var ray := Ray.new(Vector2(200, 300), Direction.new(Vector2(200, 300), Vector2(600, 300)))
	var path := Tracer.trace_ray(ray, [w], GameState.new())
	assert_gte(path.steps.size(), 1, "trace_ray should work")
