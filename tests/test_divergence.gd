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

func _make_wall(x: float) -> Surface:
	return RoomBuilder.create_block_surface(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))

func _build_typed(player: Vector2, cursor: Vector2, surfaces: Array) -> Array:
	var dir := Direction.new(player, cursor)
	var path := Tracer.trace(player, dir, surfaces, GameState.new())
	return PreviewBuilder.build(path, player, cursor, surfaces)

func test_divergence_no_div_cursor_before_mirror() -> void:
	var mirror := _make_mirror(400)
	var wall := _make_wall(100)
	var surfaces: Array[Surface] = [mirror, wall]
	var steps := _build_typed(Vector2(300, 300), Vector2(350, 300), surfaces)
	for i in steps.size():
		var step: PreviewBuilder.TypedStep = steps[i]
		assert_true(
			step.type == StepTypes.Type.ALIGNED or step.type == StepTypes.Type.ALIGNED_POST_PLANNED,
			"No divergence: step %d should be ALIGNED or POST_PLANNED, got %d" % [i, step.type])

func test_divergence_cursor_beyond_mirror() -> void:
	var mirror := _make_mirror(400)
	var wall := _make_wall(100)
	var surfaces: Array[Surface] = [mirror, wall]
	var steps := _build_typed(Vector2(300, 300), Vector2(500, 300), surfaces)

	var has_aligned := false
	var has_div_planned := false
	var has_div_physical := false
	for i in steps.size():
		var step: PreviewBuilder.TypedStep = steps[i]
		if step.type == StepTypes.Type.ALIGNED:
			has_aligned = true
		elif step.type == StepTypes.Type.DIVERGED_PLANNED:
			has_div_planned = true
		elif step.type == StepTypes.Type.DIVERGED_PHYSICAL:
			has_div_physical = true
	assert_true(has_aligned, "Should have ALIGNED steps before divergence")
	assert_true(has_div_planned, "Should have DIVERGED_PLANNED to cursor")
	assert_true(has_div_physical, "Should have DIVERGED_PHYSICAL after bounce")

func test_divergence_cursor_beyond_wall() -> void:
	var wall := _make_wall(400)
	var surfaces: Array[Surface] = [wall]
	var steps := _build_typed(Vector2(300, 300), Vector2(500, 300), surfaces)

	var has_aligned := false
	var has_div_planned := false
	for i in steps.size():
		var step: PreviewBuilder.TypedStep = steps[i]
		if step.type == StepTypes.Type.ALIGNED:
			has_aligned = true
		elif step.type == StepTypes.Type.DIVERGED_PLANNED:
			has_div_planned = true
	assert_true(has_aligned, "Should have ALIGNED steps before wall")
	assert_true(has_div_planned, "Should have DIVERGED_PLANNED through wall to cursor")

func test_divergence_green_from_player() -> void:
	var mirror := _make_mirror(400)
	var wall := _make_wall(100)
	var surfaces: Array[Surface] = [mirror, wall]
	var steps := _build_typed(Vector2(300, 300), Vector2(500, 300), surfaces)
	assert_gt(steps.size(), 0, "Should have steps")
	var first: PreviewBuilder.TypedStep = steps[0]
	assert_eq(first.type, StepTypes.Type.ALIGNED, "First step should be ALIGNED (solid green)")

func test_divergence_solid_to_cursor() -> void:
	var mirror := _make_mirror(400)
	var wall := _make_wall(100)
	var surfaces: Array[Surface] = [mirror, wall]
	var cursor := Vector2(500, 300)
	var steps := _build_typed(Vector2(300, 300), cursor, surfaces)

	var solid_end := Vector2.ZERO
	for i in steps.size():
		var step: PreviewBuilder.TypedStep = steps[i]
		if StepTypes.is_solid(step.type):
			solid_end = step.end
	assert_almost_eq(solid_end.x, cursor.x, 0.1, "Solid path should reach cursor x")
	assert_almost_eq(solid_end.y, cursor.y, 0.1, "Solid path should reach cursor y")

func test_divergence_div_planned_is_straight() -> void:
	var mirror := _make_mirror(400)
	var wall := _make_wall(100)
	var surfaces: Array[Surface] = [mirror, wall]
	var player := Vector2(300, 300)
	var cursor := Vector2(500, 300)
	var steps := _build_typed(player, cursor, surfaces)

	for i in steps.size():
		var step: PreviewBuilder.TypedStep = steps[i]
		if step.type == StepTypes.Type.DIVERGED_PLANNED:
			var expected_dir: Vector2 = (cursor - player).normalized()
			var actual_dir: Vector2 = (step.end - step.start).normalized()
			assert_almost_eq(expected_dir.dot(actual_dir), 1.0, 0.01,
				"DIVERGED_PLANNED should follow straight line toward cursor")

func test_divergence_post_planned_obeys_physics() -> void:
	var mirror := _make_mirror(400)
	var wall_left := _make_wall(100)
	var wall_right := _make_wall(700)
	var surfaces: Array[Surface] = [mirror, wall_left, wall_right]
	var steps := _build_typed(Vector2(300, 300), Vector2(500, 300), surfaces)

	var post_planned_steps: Array = []
	for i in steps.size():
		var step: PreviewBuilder.TypedStep = steps[i]
		if step.type == StepTypes.Type.DIVERGED_POST_PLANNED:
			post_planned_steps.append(step)
	assert_gt(post_planned_steps.size(), 0, "Should have DIVERGED_POST_PLANNED steps")

func test_divergence_physical_from_bounce() -> void:
	var mirror := _make_mirror(400)
	var wall := _make_wall(100)
	var surfaces: Array[Surface] = [mirror, wall]
	var steps := _build_typed(Vector2(300, 300), Vector2(500, 300), surfaces)

	var phys_steps: Array = []
	for i in steps.size():
		var step: PreviewBuilder.TypedStep = steps[i]
		if step.type == StepTypes.Type.DIVERGED_PHYSICAL:
			phys_steps.append(step)
	assert_gt(phys_steps.size(), 0, "Should have DIVERGED_PHYSICAL steps")
	var first_phys: PreviewBuilder.TypedStep = phys_steps[0]
	assert_almost_eq(first_phys.start.x, 400.0, 0.1, "Physical should start at mirror (divergence point)")

func test_divergence_no_nan() -> void:
	var mirror := _make_mirror(400)
	var wall := _make_wall(100)
	var surfaces: Array[Surface] = [mirror, wall]
	var steps := _build_typed(Vector2(300, 300), Vector2(500, 300), surfaces)
	for i in steps.size():
		var step: PreviewBuilder.TypedStep = steps[i]
		assert_false(is_nan(step.start.x) or is_nan(step.start.y), "S16: step %d start" % i)
		assert_false(is_nan(step.end.x) or is_nan(step.end.y), "S16: step %d end" % i)
