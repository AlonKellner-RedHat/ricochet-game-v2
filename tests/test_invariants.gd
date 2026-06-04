extends GutTest

const TEST_LEVELS_DIR := "res://scenes/test_levels/"

func test_invariant_sweep_all_scenes() -> void:
	var scene_paths := _discover_test_scenes()
	assert_gt(scene_paths.size(), 0, "Should find at least one test scene in %s" % TEST_LEVELS_DIR)

	var total_failures: Array[Dictionary] = []
	var total_combos := 0

	for scene_path in scene_paths:
		var scene: Node = load(scene_path).instantiate()
		scene.gravity = Vector2.ZERO
		add_child_autofree(scene)

		var runner := SweepRunner.new().configure(5, 10, 42)
		var result: Dictionary = runner.sweep(scene)
		total_combos += result.total_combos

		var failures: Array = result.failures
		for failure: Dictionary in failures:
			var violations: Array = failure.violations
			for violation: String in violations:
				total_failures.append({
					"scene": scene_path,
					"player_pos": failure.player_pos,
					"cursor_pos": failure.cursor_pos,
					"violation": violation,
				})

	if total_failures.size() > 0:
		var report := "Invariant violations found (%d):\n" % total_failures.size()
		for f in total_failures.slice(0, 10):
			report += "  [%s] player=%s cursor=%s: %s\n" % [
				f.scene, f.player_pos, f.cursor_pos, f.violation]
		if total_failures.size() > 10:
			report += "  ... and %d more\n" % (total_failures.size() - 10)
		fail_test(report)
	else:
		pass_test("All invariants passed across %d combos in %d scenes" % [total_combos, scene_paths.size()])

func test_invariant_S11_S12_segments() -> void:
	var test_segments: Array[Segment] = [
		Segment.new(Vector2(0, 0), Vector2(10, 0), Vector2(5, 0)),
		Segment.new(Vector2(100, 400), Vector2(100, 200), Vector2(100, 300)),
		Segment.new(Vector2(200, 100), Vector2(200, 300), Vector2(300, 200)),
		Segment.new(Vector2(0, 0), Vector2(10, 0), Vector2(INF, INF)),
		Segment.new(Vector2(0, 0), Vector2(100, 100), Vector2(50, 50)),
	]

	var test_points: Array[Vector2] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 20:
		test_points.append(Vector2(rng.randf_range(-200, 600), rng.randf_range(-200, 600)))

	var all_violations: Array[String] = []
	for seg in test_segments:
		all_violations.append_array(InvariantChecker.check_S11(seg))
		all_violations.append_array(InvariantChecker.check_S12(seg, test_points))

	if all_violations.size() > 0:
		var report := "S11/S12 violations (%d):\n" % all_violations.size()
		for v in all_violations.slice(0, 10):
			report += "  %s\n" % v
		fail_test(report)
	else:
		pass_test("S11/S12 passed across %d segments × %d test points" % [test_segments.size(), test_points.size()])

func test_invariant_S1_carrier_roundtrip() -> void:
	Point.reset_id_counter()
	var cache := TransformCache.new()
	var test_configs: Array[Array] = [
		[Vector2(0, 0), Vector2(10, 0), Vector2(5, 0)],
		[Vector2(100, 400), Vector2(100, 200), Vector2(100, 300)],
		[Vector2(200, 100), Vector2(200, 300), Vector2(300, 200)],
		[Vector2(0, 0), Vector2(10, 0), Vector2(INF, INF)],
	]

	var all_violations: Array[String] = []
	for tc: Array in test_configs:
		var start := Point.new(tc[0] as Vector2, Point.Provenance.SEGMENT_START)
		var end_pt := Point.new(tc[1] as Vector2, Point.Provenance.SEGMENT_END)
		var via := Point.new(tc[2] as Vector2, Point.Provenance.SEGMENT_VIA)
		all_violations.append_array(InvariantChecker.check_S1(cache, start, end_pt, via))

	if all_violations.size() > 0:
		fail_test("S1 violations: %s" % str(all_violations))
	else:
		pass_test("S1 passed across %d segment configs" % test_configs.size())

func test_invariant_S17_unique_ids() -> void:
	Point.reset_id_counter()
	var points: Array[Point] = []
	for i in 50:
		points.append(Point.new(Vector2(i, i), Point.Provenance.values()[i % Point.Provenance.size()]))
	var violations := InvariantChecker.check_S17(points)
	if violations.size() > 0:
		fail_test("S17 violations: %s" % str(violations))
	else:
		pass_test("S17 passed: %d points all have unique IDs" % points.size())

func test_invariant_sweep_with_plan() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()
	var scene: Node = load("res://scenes/test_levels/divergence_room.tscn").instantiate()
	scene.gravity = Vector2.ZERO
	add_child_autofree(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var surfaces: Array = scene.surfaces
	var mirror: Surface = null
	for surf in surfaces:
		var config: SideConfig = surf.active_side_config(Side.Value.LEFT, GameState.new())
		if config.effect is ReflectionEffect:
			mirror = surf
			break

	if mirror == null:
		pending("No mirror found in divergence_room scene")
		return

	var plan := PlanManager.new()
	plan.add_entry(mirror.id, Side.Value.LEFT)

	var renderer: Node2D = scene.get_node_or_null("PathRenderer")
	if not renderer:
		pending("No PathRenderer in scene")
		return

	var room_rect: Rect2 = scene.room_rect
	var margin := 10.0
	var bounds_min: Vector2 = room_rect.position + Vector2(margin, margin)
	var bounds_max: Vector2 = room_rect.position + room_rect.size - Vector2(margin, margin)

	var positions: Array[Vector2] = []
	for y in 3:
		for x in 3:
			positions.append(Vector2(
				bounds_min.x + (bounds_max.x - bounds_min.x) * x / 2.0,
				bounds_min.y + (bounds_max.y - bounds_min.y) * y / 2.0))

	var player: Node2D = scene.get_node("Player")
	var cursor: Node2D = scene.get_node("Cursor")
	var failures: Array[String] = []

	for player_pos in positions:
		for cursor_pos in positions:
			if player_pos == cursor_pos:
				continue
			player.global_position = player_pos
			cursor.global_position = cursor_pos

			var planned := Planner.plan_transformative_subchain(
				player_pos, cursor_pos, plan.entries, surfaces, GameState.new())
			for i in planned.steps.size():
				var step: Tracer.Step = planned.steps[i]
				if is_nan(step.start.x) or is_nan(step.end.x):
					failures.append("NaN in plan step at player=%s cursor=%s" % [player_pos, cursor_pos])

	if failures.size() > 0:
		var report := "Plan sweep failures (%d):\n" % failures.size()
		for f in failures.slice(0, 5):
			report += "  %s\n" % f
		fail_test(report)
	else:
		pass_test("Plan sweep passed: %d combos with plan active" % (positions.size() * (positions.size() - 1)))

func _discover_test_scenes() -> Array[String]:
	var scenes: Array[String] = []
	var dir := DirAccess.open(TEST_LEVELS_DIR)
	if dir == null:
		return scenes
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tscn"):
			scenes.append(TEST_LEVELS_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	scenes.sort()
	return scenes
