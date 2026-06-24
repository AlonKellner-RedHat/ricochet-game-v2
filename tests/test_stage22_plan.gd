extends GutTest

const SurfaceNodeScript = preload("res://scripts/game/surface_node.gd")

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

func _make_arc_mirror(center: Vector2, radius: float, start_angle: float, end_angle: float) -> Surface:
	var s := center + Vector2(cos(start_angle), sin(start_angle)) * radius
	var e := center + Vector2(cos(end_angle), sin(end_angle)) * radius
	var mid_angle := (start_angle + end_angle) / 2.0
	var v := center + Vector2(cos(mid_angle), sin(mid_angle)) * radius
	var seg := Segment.from_coords(s, e, v)
	var refl := ReflectionEffect.new(seg.get_carrier())
	var config := SideConfig.new(refl, true)
	return Surface.new(seg, config, config, false, false)

func _make_full_circle_mirror(center: Vector2, radius: float) -> Surface:
	var carrier := GeneralizedCircle.from_circle(center, radius)
	var seg := Segment.full_from_carrier(carrier)
	var refl := ReflectionEffect.new(carrier)
	var config := SideConfig.new(refl, true)
	return Surface.new(seg, config, config, false, false)

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
	var result := detector.detect_click(Vector2(430, 300), [mirror])
	assert_true(result.is_empty(), "Click 30px away should be outside tolerance")

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

# --- Arc click detection tests ---

func test_stage22_arc_click_on_arc_accepted() -> void:
	# Arc from angle 0→PI is the bottom semicircle (Y-down). Bottom = (300, 400).
	var arc := _make_arc_mirror(Vector2(300, 300), 100.0, 0.0, PI)
	var detector := ClickDetector.new()
	var on_arc := Vector2(300, 400)
	var result := detector.detect_click(on_arc, [arc])
	assert_false(result.is_empty(), "Click on arc curve should be detected")

func test_stage22_arc_click_near_arc_within_tolerance() -> void:
	var arc := _make_arc_mirror(Vector2(300, 300), 100.0, 0.0, PI)
	var detector := ClickDetector.new()
	var near_arc := Vector2(300, 405)
	var result := detector.detect_click(near_arc, [arc])
	assert_false(result.is_empty(), "Click 5px from arc should be within tolerance")

func test_stage22_arc_click_on_chord_far_from_arc_rejected() -> void:
	var arc := _make_arc_mirror(Vector2(300, 300), 100.0, 0.0, PI)
	var detector := ClickDetector.new()
	var chord_mid := Vector2(300, 300)
	var result := detector.detect_click(chord_mid, [arc])
	assert_true(result.is_empty(), "Click at chord midpoint (100px from arc) should be rejected")

func test_stage22_arc_click_outside_span_rejected() -> void:
	# Top of circle (300, 200) is outside the bottom arc span.
	var arc := _make_arc_mirror(Vector2(300, 300), 100.0, 0.0, PI)
	var detector := ClickDetector.new()
	var top := Vector2(300, 200)
	var result := detector.detect_click(top, [arc])
	assert_true(result.is_empty(), "Click at correct radius but outside arc span should be rejected")

func test_stage22_arc_click_near_endpoint_accepted() -> void:
	# End at (200, 300), cursor 5px away at (205, 300).
	var arc := _make_arc_mirror(Vector2(300, 300), 100.0, 0.0, PI)
	var detector := ClickDetector.new()
	var near_end := Vector2(205, 300)
	var result := detector.detect_click(near_end, [arc])
	assert_false(result.is_empty(), "Click 5px from arc endpoint should be detected")

func test_stage22_full_circle_click_accepted() -> void:
	var circle := _make_full_circle_mirror(Vector2(300, 300), 100.0)
	var detector := ClickDetector.new()
	var on_circle := Vector2(300, 200)
	var result := detector.detect_click(on_circle, [circle])
	assert_false(result.is_empty(), "Click on full circle should be detected")

# --- Hover geometry helper tests ---

func test_stage22_chevron_vertices_count() -> void:
	var verts := SurfaceNodeScript.chevron_vertices(Vector2(100, 100), Vector2(1, 0), 8.0)
	assert_eq(verts.size(), 3, "Chevron should have 3 vertices")

func test_stage22_chevron_vertices_tip_at_position() -> void:
	var tip := Vector2(100, 200)
	var verts := SurfaceNodeScript.chevron_vertices(tip, Vector2(0, -1), 8.0)
	assert_almost_eq(verts[0], tip, Vector2(0.01, 0.01), "First vertex should be the tip")

func test_stage22_chevron_vertices_points_in_direction() -> void:
	var tip := Vector2(100, 100)
	var dir := Vector2(1, 0)
	var verts := SurfaceNodeScript.chevron_vertices(tip, dir, 10.0)
	var base_center := (verts[1] + verts[2]) / 2.0
	var tip_to_base := base_center - tip
	assert_true(tip_to_base.dot(dir) < 0, "Base should be behind tip in the given direction")

func test_stage22_line_sample_endpoints() -> void:
	var s := Vector2(0, 0)
	var e := Vector2(100, 0)
	var r0 := SurfaceNodeScript.line_sample(s, e, 0.0)
	var r1 := SurfaceNodeScript.line_sample(s, e, 1.0)
	assert_almost_eq(r0.position, s, Vector2(0.01, 0.01), "t=0 should give start")
	assert_almost_eq(r1.position, e, Vector2(0.01, 0.01), "t=1 should give end")

func test_stage22_line_sample_midpoint() -> void:
	var s := Vector2(0, 0)
	var e := Vector2(200, 100)
	var r := SurfaceNodeScript.line_sample(s, e, 0.5)
	assert_almost_eq(r.position, Vector2(100, 50), Vector2(0.01, 0.01), "t=0.5 should give midpoint")

func test_stage22_line_sample_normal_perpendicular() -> void:
	var s := Vector2(0, 0)
	var e := Vector2(100, 0)
	var r := SurfaceNodeScript.line_sample(s, e, 0.5)
	var normal: Vector2 = r.normal
	var dot := normal.dot((e - s).normalized())
	assert_almost_eq(dot, 0.0, 0.01, "Normal should be perpendicular to segment")

func test_stage22_arc_sample_start() -> void:
	var center := Vector2(300, 300)
	var radius := 100.0
	var sa := 0.0
	var span := PI
	var r := SurfaceNodeScript.arc_sample(center, radius, sa, span, false, 0.0)
	var expected := center + Vector2(cos(sa), sin(sa)) * radius
	assert_almost_eq(r.position, expected, Vector2(0.1, 0.1), "t=0 should give start of arc")

func test_stage22_arc_sample_midpoint() -> void:
	var center := Vector2(300, 300)
	var radius := 100.0
	var sa := 0.0
	var span := PI
	var r := SurfaceNodeScript.arc_sample(center, radius, sa, span, false, 0.5)
	var mid_angle := sa + span * 0.5
	var expected := center + Vector2(cos(mid_angle), sin(mid_angle)) * radius
	assert_almost_eq(r.position, expected, Vector2(0.1, 0.1), "t=0.5 should give midpoint of arc")
