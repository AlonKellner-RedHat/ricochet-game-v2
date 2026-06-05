extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()

func _make_mirror(x: float) -> Surface:
	var seg := Segment.new(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var config := SideConfig.new(refl, true)
	return Surface.new(seg, config, config, false, false)

func _make_wall(x: float) -> Surface:
	return RoomBuilder.create_block_surface(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))

func _build_merged(player: Vector2, cursor: Vector2, surfaces: Array, plan_entries: Array = []) -> Array:
	var aim: Direction = Planner.compute_aim_direction(player, cursor, plan_entries, surfaces, GameState.new())
	var aim_ray := Ray.new(player, aim)
	var physical := Tracer.trace(player, aim, surfaces, GameState.new(), Tracer.DEFAULT_BOUNDS, aim_ray)
	var planned_steps: Array = []
	if plan_entries.size() > 0:
		var planned := Tracer.trace_planned(player, aim, plan_entries, surfaces, GameState.new(), cursor, aim_ray)
		planned_steps = planned.steps
	else:
		var identity := MobiusTransform.identity()
		planned_steps = [Tracer.Step.new(player, cursor, identity.id, null, aim_ray, identity)]
	return StepTreeMerge.merge(planned_steps, physical.steps, planned_steps.size())

func test_divergence_no_obstacle_has_aligned() -> void:
	# No surfaces — physical escapes to edge, planned goes to cursor
	# Should have ALIGNED portion from player toward cursor
	var surfaces: Array[Surface] = []
	var steps := _build_merged(Vector2(300, 300), Vector2(500, 300), surfaces)
	assert_gt(steps.size(), 0, "Should have steps")
	assert_eq(steps[0].type, StepTypes.Type.ALIGNED, "First step should be ALIGNED")

func test_divergence_cursor_beyond_mirror() -> void:
	var mirror := _make_mirror(400)
	var wall := _make_wall(100)
	var surfaces: Array[Surface] = [mirror, wall]
	var steps := _build_merged(Vector2(300, 300), Vector2(500, 300), surfaces)
	var has_aligned := false
	var has_post_planned := false
	for i in steps.size():
		var step: StepTreeMerge.MergedStep = steps[i]
		if step.type == StepTypes.Type.ALIGNED:
			has_aligned = true
		if step.type == StepTypes.Type.ALIGNED_POST_PLANNED:
			has_post_planned = true
	assert_true(has_aligned or has_post_planned, "No-plan trace should be aligned types")

func test_divergence_cursor_beyond_wall() -> void:
	# Wall between player and cursor — physical hits wall, planned goes straight to cursor
	var wall := _make_wall(400)
	var surfaces: Array[Surface] = [wall]
	var steps := _build_merged(Vector2(300, 300), Vector2(500, 300), surfaces)
	var has_aligned := false
	var has_div_planned := false
	for i in steps.size():
		var step: StepTreeMerge.MergedStep = steps[i]
		if step.type == StepTypes.Type.ALIGNED:
			has_aligned = true
		if step.type == StepTypes.Type.DIVERGED_PLANNED:
			has_div_planned = true
	assert_true(has_aligned, "Should have ALIGNED portion before wall")
	assert_true(has_div_planned, "Should have DIVERGED_PLANNED past wall to cursor")

func test_divergence_green_from_player() -> void:
	var mirror := _make_mirror(400)
	var wall := _make_wall(100)
	var surfaces: Array[Surface] = [mirror, wall]
	var steps := _build_merged(Vector2(300, 300), Vector2(500, 300), surfaces)
	assert_gt(steps.size(), 0, "Should have steps")
	var first: StepTreeMerge.MergedStep = steps[0]
	assert_true(
		first.type == StepTypes.Type.ALIGNED or first.type == StepTypes.Type.ALIGNED_POST_PLANNED,
		"First step should be aligned type")

func test_divergence_no_nan() -> void:
	var mirror := _make_mirror(400)
	var wall := _make_wall(100)
	var surfaces: Array[Surface] = [mirror, wall]
	var steps := _build_merged(Vector2(300, 300), Vector2(500, 300), surfaces)
	for i in steps.size():
		var step: StepTreeMerge.MergedStep = steps[i]
		assert_false(is_nan(step.start.x) or is_nan(step.start.y), "S16: step %d start" % i)
		assert_false(is_nan(step.end.x) or is_nan(step.end.y), "S16: step %d end" % i)

func test_divergence_with_plan_same_side() -> void:
	var mirror := _make_mirror(400)
	var wall := _make_wall(700)
	var surfaces: Array[Surface] = [mirror, wall]
	var plan: Array = [PlanManager.PlanEntry.new(mirror.id, Side.Value.LEFT)]
	var steps := _build_merged(Vector2(600, 300), Vector2(300, 300), surfaces, plan)
	for i in steps.size():
		var step: StepTreeMerge.MergedStep = steps[i]
		assert_false(is_nan(step.start.x) or is_nan(step.end.x), "No NaN with plan")
