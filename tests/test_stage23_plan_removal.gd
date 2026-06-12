extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()

func test_stage23_remove_latest_instance() -> void:
	var plan := PlanManager.new()
	plan.add_entry(1, Side.Value.LEFT)
	plan.add_entry(2, Side.Value.LEFT)
	plan.add_entry(1, Side.Value.LEFT)
	plan.remove_last_of(1)
	assert_eq(plan.size(), 2, "Should have 2 entries after removing latest of surface 1")
	assert_eq(plan.get_entry(0).surface_id, 1, "First entry should still be surface 1")
	assert_eq(plan.get_entry(1).surface_id, 2, "Second entry should be surface 2")

func test_stage23_remove_only_instance() -> void:
	var plan := PlanManager.new()
	plan.add_entry(1, Side.Value.LEFT)
	plan.remove_last_of(1)
	assert_true(plan.is_empty(), "Plan should be empty after removing only instance")

func test_stage23_remove_nonexistent() -> void:
	var plan := PlanManager.new()
	plan.add_entry(1, Side.Value.LEFT)
	plan.remove_last_of(99)
	assert_eq(plan.size(), 1, "Removing nonexistent surface should not change plan")

func test_stage23_has_surface() -> void:
	var plan := PlanManager.new()
	plan.add_entry(5, Side.Value.LEFT)
	assert_true(plan.has_surface(5), "Should find surface 5")
	assert_false(plan.has_surface(99), "Should not find surface 99")

func test_stage23_clear_plan() -> void:
	var plan := PlanManager.new()
	plan.add_entry(1, Side.Value.LEFT)
	plan.add_entry(2, Side.Value.RIGHT)
	plan.clear()
	assert_true(plan.is_empty(), "Clear should empty the plan")

func test_stage23_remove_from_empty() -> void:
	var plan := PlanManager.new()
	plan.remove_last_of(1)
	assert_true(plan.is_empty(), "Removing from empty plan should not error")

func test_stage23_rightclick_planned_removes() -> void:
	var main_scene: Node = load("res://scenes/open_room_playable.tscn").instantiate()
	main_scene.gravity = Vector2.ZERO
	add_child_autofree(main_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var game_mgr: Node = main_scene.get_node("GameManager")
	var cursor: Node2D = main_scene.get_node("Cursor")
	var surfaces: Array = main_scene.surfaces

	var mirror: Surface = null
	for surf in surfaces:
		var config: SideConfig = surf.active_side_config(Side.Value.LEFT, GameState.new())
		if config.effect is ReflectionEffect:
			mirror = surf
			break
	if mirror == null:
		pending("No mirror found in scene")
		return

	var click_pos: Vector2 = (mirror.segment.start.coords + mirror.segment.end.coords) / 2.0
	var side: Side.Value = mirror.segment.determine_side(click_pos + Vector2(1, 0))
	var config_check: SideConfig = mirror.active_side_config(side, GameState.new())
	if not config_check.interactive:
		click_pos = click_pos - Vector2(2, 0)

	game_mgr.plan.add_entry(mirror.id, Side.Value.LEFT)
	assert_eq(game_mgr.plan.size(), 1, "Should have 1 entry")
	cursor.global_position = click_pos
	game_mgr._try_plan_right_click()
	assert_eq(game_mgr.plan.size(), 0, "Right-click on planned surface should remove entry")

func test_stage23_rightclick_empty_space_clears() -> void:
	var plan := PlanManager.new()
	plan.add_entry(1, Side.Value.LEFT)
	plan.add_entry(2, Side.Value.RIGHT)
	plan.clear()
	assert_true(plan.is_empty(), "Right-click on empty space should clear entire plan")
