extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()

func test_side_visual_matches_behavior_vertical_mirror() -> void:
	var seg := Segment.new(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var left_config := SideConfig.new(refl, true)
	var right_config := SideConfig.new(null, false)
	var surf := Surface.new(seg, left_config, right_config, false, false)

	var point_x400 := Vector2(400, 300)
	var point_x600 := Vector2(600, 300)

	var side_at_400: Side.Value = seg.determine_side(point_x400)
	var side_at_600: Side.Value = seg.determine_side(point_x600)

	var config_at_400: SideConfig = surf.active_side_config(side_at_400, GameState.new())
	var config_at_600: SideConfig = surf.active_side_config(side_at_600, GameState.new())

	var reflects_at_400 := config_at_400.effect is ReflectionEffect
	var reflects_at_600 := config_at_600.effect is ReflectionEffect

	gut.p("Point x=400 is on side %d, reflects=%s" % [side_at_400, reflects_at_400])
	gut.p("Point x=600 is on side %d, reflects=%s" % [side_at_600, reflects_at_600])

	assert_ne(reflects_at_400, reflects_at_600, "One side should reflect, the other should not")

func test_side_left_is_which_geometric_side() -> void:
	var seg := Segment.new(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var side_at_400: Side.Value = seg.determine_side(Vector2(400, 300))
	var side_at_600: Side.Value = seg.determine_side(Vector2(600, 300))

	gut.p("x=400 (left of line) maps to Side.Value=%d" % side_at_400)
	gut.p("x=600 (right of line) maps to Side.Value=%d" % side_at_600)
	gut.p("Side.Value.LEFT=%d, Side.Value.RIGHT=%d" % [Side.Value.LEFT, Side.Value.RIGHT])

	assert_ne(side_at_400, side_at_600, "Opposite geometric sides should map to different Side values")

func test_trace_reflects_on_correct_side() -> void:
	var seg := Segment.new(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var left_config := SideConfig.new(refl, true)
	var right_config := SideConfig.new(null, false)
	var surf := Surface.new(seg, left_config, right_config, false, false)

	var wall := RoomBuilder.create_block_surface(Vector2(200, 0), Vector2(200, 600), Vector2(200, 300))
	var surfaces: Array[Surface] = [surf, wall]

	var side_at_300: Side.Value = seg.determine_side(Vector2(300, 300))
	var config_at_300: SideConfig = surf.active_side_config(side_at_300, GameState.new())
	var from_left_reflects: bool = config_at_300.effect is ReflectionEffect

	var dir_from_left := Direction.new(Vector2(300, 300), Vector2(600, 300))
	var path_from_left := Tracer.trace(Vector2(300, 300), dir_from_left, surfaces, GameState.new())

	var dir_from_right := Direction.new(Vector2(700, 300), Vector2(400, 300))
	var path_from_right := Tracer.trace(Vector2(700, 300), dir_from_right, surfaces, GameState.new())

	var bounced_from_left: bool = path_from_left.steps.size() >= 2 and path_from_left.steps[1].end.x < 500.0
	var bounced_from_right: bool = path_from_right.steps.size() >= 2 and path_from_right.steps[1].end.x > 500.0

	gut.p("From x=300 (left): reflects=%s, bounced=%s" % [from_left_reflects, bounced_from_left])
	gut.p("From x=700 (right): bounced=%s" % bounced_from_right)

	if from_left_reflects:
		assert_true(bounced_from_left, "LEFT=reflection: approaching from left should bounce")
		assert_false(bounced_from_right, "LEFT=reflection: approaching from right should pass through")
	else:
		assert_false(bounced_from_left, "RIGHT=reflection: approaching from left should pass through")
		assert_true(bounced_from_right, "RIGHT=reflection: approaching from right should bounce")

func test_surface_node_color_matches_behavior() -> void:
	var seg := Segment.new(Vector2(500, 0), Vector2(500, 600), Vector2(500, 300))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var left_config := SideConfig.new(refl, true)
	var right_config := SideConfig.new(null, false)
	var surf := Surface.new(seg, left_config, right_config, false, false)

	var node := Node2D.new()
	node.set_script(load("res://scripts/game/surface_node.gd"))
	add_child_autofree(node)
	node.setup(surf)

	var left_color: Color = node._effect_color(left_config)
	var right_color: Color = node._effect_color(right_config)

	assert_eq(left_color, Color.BLUE, "LEFT config (reflection) should render blue")
	assert_eq(right_color, Color.GRAY, "RIGHT config (pass-through) should render gray")

	var side_at_400: Side.Value = seg.determine_side(Vector2(400, 300))
	var rendered_color_at_400: Color = node._effect_color(surf.active_side_config(side_at_400, GameState.new()))

	gut.p("Visual side at x=400: color=%s (blue=reflection, gray=passthrough)" % rendered_color_at_400)

	var bounces_at_400: bool = surf.active_side_config(side_at_400, GameState.new()).effect is ReflectionEffect
	if bounces_at_400:
		assert_eq(rendered_color_at_400, Color.BLUE, "Side that bounces should be blue")
	else:
		assert_eq(rendered_color_at_400, Color.GRAY, "Side that passes through should be gray")
