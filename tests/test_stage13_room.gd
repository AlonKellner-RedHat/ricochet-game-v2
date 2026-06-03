extends GutTest

func before_each() -> void:
	Surface.reset_id_counter()

func test_stage13_terminal_effect_exists() -> void:
	var effect := TerminalEffect.new()
	assert_not_null(effect, "TerminalEffect should be instantiable")
	assert_true(effect is RefCounted, "TerminalEffect should extend RefCounted")

func test_stage13_room_has_four_surfaces() -> void:
	var surfaces := RoomBuilder.create_room_surfaces(Rect2(560, 240, 800, 600))
	assert_eq(surfaces.size(), 4, "Room should have 4 surfaces")

func test_stage13_all_room_surfaces_are_block() -> void:
	var surfaces := RoomBuilder.create_room_surfaces(Rect2(560, 240, 800, 600))
	var state := GameState.new()
	for surf in surfaces:
		var left := surf.active_side_config(Side.Value.LEFT, state)
		var right := surf.active_side_config(Side.Value.RIGHT, state)
		assert_true(left.effect is TerminalEffect, "Left side should be terminal")
		assert_true(right.effect is TerminalEffect, "Right side should be terminal")

func test_stage13_room_surfaces_player_solid() -> void:
	var surfaces := RoomBuilder.create_room_surfaces(Rect2(560, 240, 800, 600))
	for surf in surfaces:
		assert_true(surf.player_solid, "Room surfaces should be player_solid")

func test_stage13_room_forms_closed_rectangle() -> void:
	var surfaces := RoomBuilder.create_room_surfaces(Rect2(560, 240, 800, 600))
	for i in surfaces.size():
		var current := surfaces[i]
		var next := surfaces[(i + 1) % surfaces.size()]
		assert_eq(current.segment.end, next.segment.start,
			"Surface %d end should connect to surface %d start" % [i, (i + 1) % surfaces.size()])

func test_stage13_surface_rendered_red() -> void:
	var node := Node2D.new()
	node.set_script(load("res://scripts/game/surface_node.gd"))
	add_child_autofree(node)
	var surf := RoomBuilder.create_block_surface(Vector2(0, 0), Vector2(100, 0), Vector2(50, 0))
	node.setup(surf)
	assert_eq(node.BLOCK_COLOR, Color.RED, "Block color should be red")

func test_stage13_surface_line_width() -> void:
	var node := Node2D.new()
	node.set_script(load("res://scripts/game/surface_node.gd"))
	add_child_autofree(node)
	assert_eq(node.LINE_WIDTH, 3.0, "Line width should be 3px")

func test_stage13_UX9_block_stops_ray() -> void:
	var surfaces := RoomBuilder.create_room_surfaces(Rect2(100, 100, 400, 400))
	var segments: Array = []
	for surf in surfaces:
		segments.append(surf.segment)
	var ray := Ray.new(Vector2(300, 300), Direction.new(Vector2(300, 300), Vector2(300, 0)))
	var hit = Intersection.find_earliest_hit(ray, segments)
	assert_not_null(hit, "Ray should hit a wall")
	assert_almost_eq(hit.point.y, 100.0, 0.1, "Ray should hit top wall")

func test_stage13_player_solid_false() -> void:
	var seg := Segment.new(Vector2(0, 0), Vector2(100, 0), Vector2(50, 0))
	var config := SideConfig.new(TerminalEffect.new())
	var surf := Surface.new(seg, config, config, false, false)
	assert_false(surf.player_solid, "player_solid=false should be respected")
