extends GutTest

const TEST_LEVELS_DIR := "res://scenes/test_levels/"

func test_sweep_all_scenes() -> void:
	var scene_paths := _discover_scenes()
	assert_gt(scene_paths.size(), 0, "Should find test scenes in %s" % TEST_LEVELS_DIR)

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

func test_sweep_with_plans() -> void:
	var plan_scenes: Array[String] = [
		TEST_LEVELS_DIR + "three_mirrors.tscn",
		TEST_LEVELS_DIR + "mirror_and_wall.tscn",
		TEST_LEVELS_DIR + "parallel_mirrors.tscn",
		TEST_LEVELS_DIR + "divergence_room.tscn",
		TEST_LEVELS_DIR + "room_with_mirror.tscn",
		TEST_LEVELS_DIR + "two_mirrors.tscn",
	]

	var total_failures: Array[Dictionary] = []
	var total_combos := 0

	for scene_path in plan_scenes:
		if not FileAccess.file_exists(scene_path):
			continue
		var scene: Node = load(scene_path).instantiate()
		scene.gravity = Vector2.ZERO
		add_child_autofree(scene)
		await get_tree().process_frame
		await get_tree().process_frame

		var mirrors := _find_reflective_surfaces(scene)
		if mirrors.size() == 0:
			continue

		var plans := _generate_plans(mirrors)
		var checker := InvariantChecker.new()
		checker.setup(scene)

		var runner := SweepRunner.new().configure(5, 10, 42)
		if "room_rect" in scene:
			var rect: Rect2 = scene.room_rect
			runner.set_bounds(rect.position + Vector2(10, 10), rect.position + rect.size - Vector2(10, 10))
		var poi := runner._extract_points_of_interest(scene)
		var positions := runner.build_positions(poi)

		for plan in plans:
			for player_pos in positions:
				for cursor_pos in positions:
					if player_pos == cursor_pos:
						continue
					var violations := checker.check_all(player_pos, cursor_pos, plan)
					if violations.size() > 0:
						total_combos += 1
						for v: String in violations:
							total_failures.append({
								"scene": scene_path,
								"player_pos": player_pos,
								"cursor_pos": cursor_pos,
								"plan": _plan_to_str(plan),
								"violation": v,
							})
					else:
						total_combos += 1

	if total_failures.size() > 0:
		var report := "Plan sweep violations (%d):\n" % total_failures.size()
		for f in total_failures.slice(0, 10):
			report += "  [%s] plan=%s player=%s cursor=%s: %s\n" % [
				f.scene, f.plan, f.player_pos, f.cursor_pos, f.violation]
		if total_failures.size() > 10:
			report += "  ... and %d more\n" % (total_failures.size() - 10)
		fail_test(report)
	else:
		pass_test("Plan sweep passed: %d combos with plans" % total_combos)

func _find_reflective_surfaces(scene: Node) -> Array:
	var mirrors: Array = []
	if not "surfaces" in scene:
		return mirrors
	for surf in scene.surfaces:
		var s: Surface = surf
		var left: SideConfig = s.active_side_config(Side.Value.LEFT, GameState.new())
		var right: SideConfig = s.active_side_config(Side.Value.RIGHT, GameState.new())
		var left_reflects := left != null and left.effect is ReflectionEffect
		var right_reflects := right != null and right.effect is ReflectionEffect
		if left_reflects or right_reflects:
			mirrors.append({"surface": s, "left_reflects": left_reflects, "right_reflects": right_reflects})
	return mirrors

func _generate_plans(mirrors: Array) -> Array:
	var plans: Array = []
	# Single entries (each mirror × its reflective side)
	for m in mirrors:
		var s: Surface = m.surface
		if m.left_reflects:
			plans.append([PlanManager.PlanEntry.new(s.id, Side.Value.LEFT)])
		if m.right_reflects:
			plans.append([PlanManager.PlanEntry.new(s.id, Side.Value.RIGHT)])
	# One pair (first two mirrors) and one repeated (first mirror twice)
	if mirrors.size() >= 2:
		var s0: Surface = mirrors[0].surface
		var s1: Surface = mirrors[1].surface
		var side0: Side.Value = Side.Value.LEFT if mirrors[0].left_reflects else Side.Value.RIGHT
		var side1: Side.Value = Side.Value.LEFT if mirrors[1].left_reflects else Side.Value.RIGHT
		plans.append([PlanManager.PlanEntry.new(s0.id, side0), PlanManager.PlanEntry.new(s1.id, side1)])
	if mirrors.size() >= 1:
		var s0: Surface = mirrors[0].surface
		var side0: Side.Value = Side.Value.LEFT if mirrors[0].left_reflects else Side.Value.RIGHT
		plans.append([PlanManager.PlanEntry.new(s0.id, side0), PlanManager.PlanEntry.new(s0.id, side0)])
	return plans

func _plan_to_str(plan: Array) -> String:
	var parts: Array[String] = []
	for entry in plan:
		var e: PlanManager.PlanEntry = entry
		parts.append("%d/%s" % [e.surface_id, "L" if e.side == Side.Value.LEFT else "R"])
	return "[%s]" % ",".join(parts)

func _discover_scenes() -> Array[String]:
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
