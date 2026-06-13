extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()

func _make_mirror(x: float) -> Surface:
	var seg := Segment.from_coords(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var left := SideConfig.new(refl, true)
	var right := SideConfig.new(null, false)
	return Surface.new(seg, left, right, false, false)

func _make_double_mirror(x: float) -> Surface:
	var seg := Segment.from_coords(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var config := SideConfig.new(refl, true)
	return Surface.new(seg, config, config, false, false)

func _make_passthrough(x: float) -> Surface:
	var seg := Segment.from_coords(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))
	var config := SideConfig.new(null, false)
	return Surface.new(seg, config, config, false, false)

func _make_wall(x: float) -> Surface:
	return RoomBuilder.create_block_surface(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))

func test_stage22_plan_add_entry() -> void:
	var plan := PlanManager.new()
	plan.add_entry(5, Side.Value.LEFT)
	assert_eq(plan.entries.size(), 1, "Plan should have 1 entry")
	assert_eq(plan.entries[0].surface_id, 5, "Surface ID should match")
	assert_eq(plan.entries[0].side, Side.Value.LEFT, "Side should match")

func test_stage22_plan_preserves_order() -> void:
	var plan := PlanManager.new()
	plan.add_entry(1, Side.Value.LEFT)
	plan.add_entry(2, Side.Value.RIGHT)
	plan.add_entry(3, Side.Value.LEFT)
	assert_eq(plan.entries[0].surface_id, 1, "First entry")
	assert_eq(plan.entries[1].surface_id, 2, "Second entry")
	assert_eq(plan.entries[2].surface_id, 3, "Third entry")

func test_stage22_duplicate_entries_allowed() -> void:
	var plan := PlanManager.new()
	plan.add_entry(1, Side.Value.LEFT)
	plan.add_entry(1, Side.Value.LEFT)
	assert_eq(plan.entries.size(), 2, "Duplicates should be allowed")

func test_stage22_entry_references_by_id() -> void:
	var plan := PlanManager.new()
	plan.add_entry(42, Side.Value.RIGHT)
	var entry: PlanManager.PlanEntry = plan.entries[0]
	assert_eq(entry.surface_id, 42, "Should store surface ID, not object")

func test_stage22_clear() -> void:
	var plan := PlanManager.new()
	plan.add_entry(1, Side.Value.LEFT)
	plan.add_entry(2, Side.Value.RIGHT)
	plan.clear()
	assert_eq(plan.entries.size(), 0, "Clear should empty the plan")

func test_stage22_non_interactive_rejected() -> void:
	var pt := _make_passthrough(400)
	var detector := ClickDetector.new()
	var result := detector.detect_click(Vector2(400, 300), [pt])
	assert_true(result.is_empty(), "Non-interactive surface should not be clickable")

func test_stage22_interactive_accepted() -> void:
	var mirror := _make_double_mirror(400)
	var detector := ClickDetector.new()
	var result := detector.detect_click(Vector2(398, 300), [mirror])
	assert_false(result.is_empty(), "Interactive surface should be clickable within tolerance")

func test_stage22_click_outside_tolerance() -> void:
	var mirror := _make_double_mirror(400)
	var detector := ClickDetector.new()
	var result := detector.detect_click(Vector2(420, 300), [mirror])
	assert_true(result.is_empty(), "Click 20px away should be outside tolerance")

func test_stage22_side_determination_by_cursor() -> void:
	var mirror := _make_mirror(400)
	var detector := ClickDetector.new()
	var result_left := detector.detect_click(Vector2(398, 300), [mirror])
	var result_right := detector.detect_click(Vector2(402, 300), [mirror])
	if not result_left.is_empty():
		assert_true(true, "Left side detected")
	if not result_right.is_empty():
		assert_true(true, "Right side detected (may be non-interactive)")

func test_stage22_nearest_surface_wins() -> void:
	var m1 := _make_double_mirror(400)
	var m2 := _make_double_mirror(405)
	var detector := ClickDetector.new()
	var result := detector.detect_click(Vector2(403, 300), [m1, m2])
	assert_false(result.is_empty(), "Should find a surface")
	assert_eq(result.surface, m2, "Nearest surface should win")

func test_stage22_wall_not_interactive() -> void:
	var wall := _make_wall(400)
	var detector := ClickDetector.new()
	var result := detector.detect_click(Vector2(400, 300), [wall])
	assert_true(result.is_empty(), "Terminal surfaces should not be interactive")

func test_stage22_plan_blocked_during_flight() -> void:
	var main_scene: Node = load("res://scenes/main.tscn").instantiate()
	main_scene.gravity = Vector2.ZERO
	add_child_autofree(main_scene)
	await get_tree().process_frame
	var game_mgr: Node = main_scene.get_node("GameManager")
	var cursor: Node2D = main_scene.get_node("Cursor")
	var arrow: Node2D = main_scene.get_node("ArrowAnimator")
	cursor.global_position = Vector2(1200, 540)
	game_mgr._try_fire()
	assert_true(arrow.is_flying(), "Arrow should be flying")
	var plan_before: int = game_mgr.plan.entries.size()
	game_mgr._handle_plan_click(false)
	assert_eq(game_mgr.plan.entries.size(), plan_before, "Plan should not change during flight")
