extends GutTest
## Isolated tests for the four core systems:
## A: Cursor image propagation (aim direction)
## B: Physical path creation
## C: Planned path creation
## D: Path merging with ray provenance

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
	# Player at x=600, cursor at x=200 — cursor on opposite side
	var dir := Planner.compute_aim_direction(Vector2(600, 300), Vector2(200, 300), plan, [m], GameState.new())
	# Image = reflect(200) across x=400 = 600. Player at 600, image at 600 — zero length!
	# Actually image = 2*400 - 200 = 600. Player IS at 600. Direction is zero-length.
	# This is an edge case — aim should fall back to cursor direction
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
	var last: Tracer.Step = path.steps[path.steps.size() - 1]
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
		var step: Tracer.Step = path.steps[i]
		assert_eq(step.ray, ray, "Step %d should share the same Ray reference" % i)

func test_physical_passes_through() -> void:
	var seg := Segment.new(Vector2(400, 0), Vector2(400, 600), Vector2(400, 300))
	var config := SideConfig.new(null, false)
	var pt := Surface.new(seg, config, config, false, false)
	var w := _wall(600)
	var ray := Ray.new(Vector2(300, 300), Direction.new(Vector2(300, 300), Vector2(500, 300)))
	var path := Tracer.trace_ray(ray, [pt, w], GameState.new())
	assert_gte(path.steps.size(), 2, "Should pass through and hit wall")

# === Group C: Planned path creation ===

func test_planned_empty() -> void:
	var ray := Ray.new(Vector2(300, 300), Direction.new(Vector2(300, 300), Vector2(500, 300)))
	var path := Tracer.trace_planned(Vector2(300, 300), ray.direction, [], [], GameState.new(), Vector2(500, 300), ray)
	assert_eq(path.steps.size(), 0, "Empty plan: no steps")

func test_planned_single_mirror() -> void:
	var m := _mirror(400)
	var plan: Array = [PlanManager.PlanEntry.new(m.id, Side.Value.LEFT)]
	var aim := Planner.compute_aim_direction(Vector2(600, 300), Vector2(300, 300), plan, [m], GameState.new())
	var ray := Ray.new(Vector2(600, 300), aim)
	var path := Tracer.trace_planned(Vector2(600, 300), aim, plan, [m], GameState.new(), Vector2(300, 300), ray)
	assert_gte(path.steps.size(), 1, "Should have at least 1 step")

func test_planned_reaches_cursor() -> void:
	var m := _mirror(400)
	var plan: Array = [PlanManager.PlanEntry.new(m.id, Side.Value.LEFT)]
	var cursor := Vector2(300, 300)
	var aim := Planner.compute_aim_direction(Vector2(600, 300), cursor, plan, [m], GameState.new())
	var ray := Ray.new(Vector2(600, 300), aim)
	var path := Tracer.trace_planned(Vector2(600, 300), aim, plan, [m], GameState.new(), cursor, ray)
	if path.steps.size() > 0:
		var last: Tracer.Step = path.steps[path.steps.size() - 1]
		assert_almost_eq(last.end.x, cursor.x, 1.0, "Should reach cursor x")
		assert_almost_eq(last.end.y, cursor.y, 1.0, "Should reach cursor y")

func test_planned_steps_share_ray() -> void:
	var m := _mirror(400)
	var plan: Array = [PlanManager.PlanEntry.new(m.id, Side.Value.LEFT)]
	var aim := Planner.compute_aim_direction(Vector2(600, 300), Vector2(300, 300), plan, [m], GameState.new())
	var ray := Ray.new(Vector2(600, 300), aim)
	var path := Tracer.trace_planned(Vector2(600, 300), aim, plan, [m], GameState.new(), Vector2(300, 300), ray)
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		assert_eq(step.ray, ray, "Planned step %d should share the same Ray" % i)

# === Group D: Merging with ray provenance ===

func test_merge_aligned_same_ray() -> void:
	var ray := Ray.new(Vector2(0, 0), Direction.new(Vector2(0, 0), Vector2(100, 0)))
	var frame := MobiusTransform.identity()
	var planned: Array = [Tracer.Step.new(Vector2(0, 0), Vector2(100, 0), frame.id, null, ray, frame)]
	var physical: Array = [Tracer.Step.new(Vector2(0, 0), Vector2(100, 0), frame.id, null, ray, frame)]
	var merged := StepTreeMerge.merge(planned, physical, 1)
	assert_eq(merged[0].type, StepTypes.Type.ALIGNED, "Same ray+frame+start+end = ALIGNED")

func test_merge_diverged_different_ray() -> void:
	var ray1 := Ray.new(Vector2(0, 0), Direction.new(Vector2(0, 0), Vector2(100, 0)))
	var ray2 := Ray.new(Vector2(0, 0), Direction.new(Vector2(0, 0), Vector2(100, 0)))
	var frame := MobiusTransform.identity()
	var planned: Array = [Tracer.Step.new(Vector2(0, 0), Vector2(100, 0), frame.id, null, ray1, frame)]
	var physical: Array = [Tracer.Step.new(Vector2(0, 0), Vector2(100, 0), frame.id, null, ray2, frame)]
	var merged := StepTreeMerge.merge(planned, physical, 1)
	# Different Ray objects (even if same values) → diverged
	assert_ne(merged[0].type, StepTypes.Type.ALIGNED, "Different Ray ref → not aligned")

func test_merge_partial_same_ray_diff_end() -> void:
	var ray := Ray.new(Vector2(0, 0), Direction.new(Vector2(0, 0), Vector2(200, 0)))
	var frame := MobiusTransform.identity()
	var planned: Array = [Tracer.Step.new(Vector2(0, 0), Vector2(150, 0), frame.id, null, ray, frame)]
	var physical: Array = [Tracer.Step.new(Vector2(0, 0), Vector2(100, 0), frame.id, null, ray, frame)]
	var merged := StepTreeMerge.merge(planned, physical, 1)
	assert_eq(merged[0].type, StepTypes.Type.ALIGNED, "Partial: aligned portion at shorter end")
	var has_div := false
	for i in merged.size():
		if merged[i].type == StepTypes.Type.DIVERGED_PLANNED:
			has_div = true
	assert_true(has_div, "Should have DIVERGED_PLANNED remainder")

func test_merge_diverged_different_start() -> void:
	var ray := Ray.new(Vector2(0, 0), Direction.new(Vector2(0, 0), Vector2(100, 0)))
	var frame := MobiusTransform.identity()
	var planned: Array = [Tracer.Step.new(Vector2(0, 0), Vector2(100, 0), frame.id, null, ray, frame)]
	var physical: Array = [Tracer.Step.new(Vector2(5, 0), Vector2(100, 0), frame.id, null, ray, frame)]
	var merged := StepTreeMerge.merge(planned, physical, 1)
	assert_ne(merged[0].type, StepTypes.Type.ALIGNED, "Different start → not aligned")
