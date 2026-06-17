extends GutTest

const H := preload("res://tests/test_helpers.gd")

func before_each() -> void:
	H.reset_counters()

func _arc_surface(player_solid: bool, start: Vector2 = Vector2(200, 100), end_v: Vector2 = Vector2(200, 300), via: Vector2 = Vector2(300, 200)) -> Surface:
	var seg := Segment.from_coords(start, end_v, via)
	var carrier := seg.get_carrier()
	var inv := CircleInversionEffect.new(carrier)
	var left := SideConfig.new(inv, true)
	var right := SideConfig.new(null, false)
	return Surface.new(seg, left, right, false, player_solid)

func _make_node(surf: Surface) -> Node2D:
	var node := Node2D.new()
	node.set_script(load("res://scripts/game/surface_node.gd"))
	add_child_autofree(node)
	node.setup(surf)
	return node

func _find_static_body(node: Node2D) -> StaticBody2D:
	for child in node.get_children():
		if child is StaticBody2D:
			return child
	return null

func _count_segment_shapes(body: StaticBody2D) -> int:
	var count := 0
	for child in body.get_children():
		if child is CollisionShape2D and child.shape is SegmentShape2D:
			count += 1
	return count

# --- Tests ---

func test_stage42_5_arc_collision_shape_type() -> void:
	var surf := _arc_surface(true)
	var node := _make_node(surf)
	var body := _find_static_body(node)
	assert_not_null(body, "Arc surface with player_solid=true should have StaticBody2D")
	var seg_count := _count_segment_shapes(body)
	assert_gt(seg_count, 1, "Arc collision should have multiple SegmentShape2D children, got %d" % seg_count)

func test_stage42_5_arc_segment_count_full_circle() -> void:
	var surf := _arc_surface(true, Vector2(300.0, 200.001), Vector2(300.0, 199.999), Vector2(100, 200))
	var node := _make_node(surf)
	var body := _find_static_body(node)
	assert_not_null(body, "Should have StaticBody2D")
	var seg_count := _count_segment_shapes(body)
	assert_gte(seg_count, 15, "Near-full-circle should have 15-16 segments, got %d" % seg_count)
	assert_lte(seg_count, 16, "Near-full-circle should have 15-16 segments, got %d" % seg_count)

func test_stage42_5_arc_segment_count_quarter() -> void:
	var center := Vector2(200, 200)
	var r := 100.0
	var start := center + Vector2(r, 0)
	var end_v := center + Vector2(0, r)
	var via := center + Vector2(r, r).normalized() * r
	var surf := _arc_surface(true, start, end_v, via)
	var node := _make_node(surf)
	var body := _find_static_body(node)
	assert_not_null(body, "Should have StaticBody2D")
	var seg_count := _count_segment_shapes(body)
	assert_eq(seg_count, 4, "Quarter circle should have max(3, floor(16*90/360))=4 segments, got %d" % seg_count)

func test_stage42_5_arc_segment_count_minimum() -> void:
	var center := Vector2(200, 200)
	var r := 100.0
	var angle_span := deg_to_rad(10.0)
	var start := center + Vector2(cos(0.0), sin(0.0)) * r
	var end_v := center + Vector2(cos(angle_span), sin(angle_span)) * r
	var via := center + Vector2(cos(angle_span / 2.0), sin(angle_span / 2.0)) * r
	var surf := _arc_surface(true, start, end_v, via)
	var node := _make_node(surf)
	var body := _find_static_body(node)
	assert_not_null(body, "Should have StaticBody2D")
	var seg_count := _count_segment_shapes(body)
	assert_eq(seg_count, 3, "Tiny arc should have minimum 3 segments, got %d" % seg_count)

func test_stage42_5_arc_points_on_circle() -> void:
	var surf := _arc_surface(true)
	var carrier := surf.segment.get_carrier()
	var ctr := carrier.center()
	var r := carrier.radius()
	var node := _make_node(surf)
	var body := _find_static_body(node)
	assert_not_null(body, "Should have StaticBody2D")
	for child in body.get_children():
		if child is CollisionShape2D and child.shape is SegmentShape2D:
			var shape: SegmentShape2D = child.shape
			var dist_a := (shape.a - ctr).length()
			var dist_b := (shape.b - ctr).length()
			assert_almost_eq(dist_a, r, 0.5, "Point A should be on circle (dist=%f, r=%f)" % [dist_a, r])
			assert_almost_eq(dist_b, r, 0.5, "Point B should be on circle (dist=%f, r=%f)" % [dist_b, r])

func test_stage42_5_line_collision_unchanged() -> void:
	var seg := Segment.from_coords(Vector2(100, 0), Vector2(100, 600), Vector2(100, 300))
	var refl := ReflectionEffect.new(seg.get_carrier())
	var left := SideConfig.new(refl, true)
	var right := SideConfig.new(null, false)
	var surf := Surface.new(seg, left, right, false, true)
	var node := _make_node(surf)
	var body := _find_static_body(node)
	assert_not_null(body, "Line surface should still have StaticBody2D")
	var seg_count := _count_segment_shapes(body)
	assert_eq(seg_count, 1, "Line surface should have exactly 1 SegmentShape2D, got %d" % seg_count)

func test_stage42_5_player_solid_false_no_collision() -> void:
	var surf := _arc_surface(false)
	var node := _make_node(surf)
	var body := _find_static_body(node)
	assert_null(body, "Arc surface with player_solid=false should have no StaticBody2D")
