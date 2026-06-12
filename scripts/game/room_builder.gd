class_name RoomBuilder
extends RefCounted

static func create_block_surface(start: Vector2, end_v: Vector2, via: Vector2) -> Surface:
	var seg := Segment.from_coords(start, end_v, via)
	var terminal := TerminalEffect.new()
	var left_config := SideConfig.new(terminal)
	var right_config := SideConfig.new(terminal)
	return Surface.new(seg, left_config, right_config)

static func create_room_surfaces(rect: Rect2) -> Array[Surface]:
	var left := rect.position.x
	var right := rect.position.x + rect.size.x
	var top := rect.position.y
	var bottom := rect.position.y + rect.size.y

	return [
		create_block_surface(Vector2(left, top), Vector2(right, top), Vector2((left + right) / 2.0, top)),
		create_block_surface(Vector2(right, top), Vector2(right, bottom), Vector2(right, (top + bottom) / 2.0)),
		create_block_surface(Vector2(right, bottom), Vector2(left, bottom), Vector2((left + right) / 2.0, bottom)),
		create_block_surface(Vector2(left, bottom), Vector2(left, top), Vector2(left, (top + bottom) / 2.0)),
	]

static func add_room_to_scene(parent: Node, rect: Rect2) -> Array[Surface]:
	var surfaces := create_room_surfaces(rect)
	for surface in surfaces:
		var node := Node2D.new()
		node.set_script(load("res://scripts/game/surface_node.gd"))
		node.name = "Surface_%d" % surface.id
		parent.add_child(node)
		node.setup(surface)
	return surfaces
