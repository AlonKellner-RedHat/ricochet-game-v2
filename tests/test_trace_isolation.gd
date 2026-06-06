extends GutTest
## Isolated tests for the core systems:
## A: Cursor image propagation (aim direction)
## B: Physical path creation
## C: Planned path creation (now via trace with PLANNED mode)
## D: Path merging

func before_each() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()

func _mirror(x: float) -> Surface:
	var seg := Segment.new(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var config := SideConfig.new(refl, true)
	return Surface.new(seg, config, config, false, false)

func _wall(x: float) -> Surface:
	return RoomBuilder.create_block_surface(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))

func _step(path: Tracer.TracedPath, idx: int) -> Tracer.Step:
	return path.steps[idx]

# === Group A: Cursor image propagation ===

func test_aim_no_plan() -> void:
	var dir := Planner.compute_aim_direction(Vector2(100, 300), Vector2(500, 300), [], [], GameState.new())
	assert_almost_eq(dir.to_normalized().x, 1.0, 0.01, "No plan: aim right toward cursor")

func test_aim_single_mirror_same_side() -> void:
	var m := _mirror(400)
	var plan: Array = [PlanManager.PlanEntry.new(m.id, Side.Value.LEFT)]
	var dir := Planner.compute_aim_direction(Vector2(600, 300), Vector2(300, 300), plan, [m], GameState.new())
	assert_lt(dir.to_normalized().x, 0.0, "Should aim left toward image")

func test_aim_single_mirror_opposite_side() -> void:
	var m := _mirror(400)
	var plan: Array = [PlanManager.PlanEntry.new(m.id, Side.Value.LEFT)]
	var dir := Planner.compute_aim_direction(Vector2(600, 300), Vector2(200, 300), plan, [m], GameState.new())
	assert_false(dir.is_zero_length(), "Should not produce zero-length direction")

func test_aim_deterministic() -> void:
	var m := _mirror(400)
	var plan: Array = [PlanManager.PlanEntry.new(m.id, Side.Value.LEFT)]
	var d1 := Planner.compute_aim_direction(Vector2(600, 300), Vector2(300, 250), plan, [m], GameState.new())
	var d2 := Planner.compute_aim_direction(Vector2(600, 300), Vector2(300, 250), plan, [m], GameState.new())
	assert_eq(d1.to_normalized(), d2.to_normalized(), "Same inputs → same direction")

# === Group B: Physical path creation ===

func test_physical_hits_wall() -> void:
	var w := _wall(500)
	var ray := Ray.new(Vector2(300, 300), Direction.new(Vector2(300, 300), Vector2(600, 300)))
	var path := Tracer.trace_ray(ray, [w], GameState.new())
	assert_gte(path.steps.size(), 1, "Should hit wall")
	var last := _step(path, path.steps.size() - 1)
	assert_not_null(last.hit, "Last step should have a hit")

func test_physical_bounces_mirror() -> void:
	var m := _mirror(400)
	var w := _wall(100)
	var ray := Ray.new(Vector2(600, 300), Direction.new(Vector2(600, 300), Vector2(300, 300)))
	var path := Tracer.trace_ray(ray, [m, w], GameState.new())
	assert_gte(path.steps.size(), 2, "Should bounce and hit wall")

func test_physical_steps_share_ray() -> void:
	var m := _mirror(400)
	var w := _wall(100)
	var ray := Ray.new(Vector2(600, 300), Direction.new(Vector2(600, 300), Vector2(300, 300)))
	var path := Tracer.trace_ray(ray, [m, w], GameState.new())
	for i in path.steps.size():
		assert_eq(_step(path, i).ray, ray, "Step %d should share the same Ray reference" % i)

func test_physical_passes_through() -> void:
	var seg := Segment.new(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var config := SideConfig.new(null, false)
	var pt := Surface.new(seg, config, config, false, false)
	var w := _wall(600)
	var ray := Ray.new(Vector2(300, 300), Direction.new(Vector2(300, 300), Vector2(500, 300)))
	var path := Tracer.trace_ray(ray, [pt, w], GameState.new())
	assert_gte(path.steps.size(), 2, "Should pass through and hit wall")

# === Group C: Planned path creation (via unified trace) ===

func test_planned_single_mirror() -> void:
	var m := _mirror(400)
	var w := _wall(100)
	var plan: Array = [PlanManager.PlanEntry.new(m.id, Side.Value.LEFT)]
	var aim := Planner.compute_aim_direction(Vector2(600, 300), Vector2(300, 300), plan, [m, w], GameState.new())
	var ray := Ray.new(Vector2(600, 300), aim)
	var path := Tracer.trace(ray.origin, aim, [m, w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray, -1.0, Tracer.TraceMode.PLANNED, plan)
	assert_gte(path.steps.size(), 1, "Should have at least 1 step")

func test_planned_steps_share_ray() -> void:
	var m := _mirror(400)
	var w := _wall(100)
	var plan: Array = [PlanManager.PlanEntry.new(m.id, Side.Value.LEFT)]
	var aim := Planner.compute_aim_direction(Vector2(600, 300), Vector2(300, 300), plan, [m, w], GameState.new())
	var ray := Ray.new(Vector2(600, 300), aim)
	var path := Tracer.trace(ray.origin, aim, [m, w], GameState.new(), Tracer.DEFAULT_BOUNDS, ray, -1.0, Tracer.TraceMode.PLANNED, plan)
	for i in path.steps.size():
		assert_eq(_step(path, i).ray, ray, "Planned step %d should share the same Ray" % i)

# === Group D: Merging ===

func test_merge_aligned_same_ray() -> void:
	var ray := Ray.new(Vector2(0, 0), Direction.new(Vector2(0, 0), Vector2(100, 0)))
	var frame := MobiusTransform.identity()
	var planned: Array = [Tracer.Step.new(Vector2(0, 0), Vector2(100, 0), frame.id, null, ray, frame)]
	var physical: Array = [Tracer.Step.new(Vector2(0, 0), Vector2(100, 0), frame.id, null, ray, frame)]
	var merged := StepTreeMerge.merge(planned, physical, 1)
	assert_eq(merged[0].type, StepTypes.Type.ALIGNED, "Same frame+geometry = ALIGNED")

func test_mirror_before_cursor_has_diverged_physical() -> void:
	var m := _mirror(800)
	var w_left := _wall(560)
	var w_top := RoomBuilder.create_block_surface(Vector2(560, 240), Vector2(1360, 240), Vector2(960, 240))
	var w_right := _wall(1360)
	var surfaces: Array[Surface] = [m, w_left, w_top, w_right]

	var player := Vector2(960, 500)
	var cursor := Vector2(600, 500)
	var target_dist: float = player.distance_to(cursor)
	var aim_dir := Direction.new(player, cursor)
	var aim_ray := Ray.new(player, aim_dir)
	var bounds := Tracer.DEFAULT_BOUNDS

	# Three-trace model
	var physical := Tracer.trace(player, aim_dir, surfaces, GameState.new(), bounds, aim_ray, target_dist, Tracer.TraceMode.PHYSICAL)
	var planned_full := Tracer.trace(player, aim_dir, surfaces, GameState.new(), bounds, aim_ray, target_dist, Tracer.TraceMode.PLANNED, [])

	var ci: int = planned_full.cursor_index
	var cursor_reached: bool = ci >= 0
	if not cursor_reached:
		ci = planned_full.steps.size()
	var combined: Array = planned_full.steps.slice(0, ci)
	if cursor_reached and ci > 0 and ci <= planned_full.steps.size():
		var last: Tracer.Step = combined[ci - 1]
		var post := Tracer.trace(last.end, aim_dir, surfaces, GameState.new(), bounds, aim_ray, -1.0, Tracer.TraceMode.PHYSICAL, [], last.frame)
		for i in post.steps.size():
			combined.append(post.steps[i])

	var merged := StepTreeMerge.merge(combined, physical.steps, ci)

	var has_aligned := false
	var has_div_planned := false
	var has_div_physical := false
	for i in merged.size():
		var ms: StepTreeMerge.MergedStep = merged[i]
		if ms.type == StepTypes.Type.ALIGNED:
			has_aligned = true
		if ms.type == StepTypes.Type.DIVERGED_PLANNED:
			has_div_planned = true
		if ms.type == StepTypes.Type.DIVERGED_PHYSICAL:
			has_div_physical = true

	assert_true(has_aligned, "Should have ALIGNED before mirror")
	assert_true(has_div_planned, "Should have DIVERGED_PLANNED to cursor")
	assert_true(has_div_physical, "Should have DIVERGED_PHYSICAL for bounce")
