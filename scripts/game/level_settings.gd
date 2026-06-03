extends Node2D

@export var gravity := Vector2(0, 0)
@export var room_rect := Rect2(560, 240, 800, 600)
@export var build_room := true

@export var passthrough_lines: Array[Vector4] = []

var surfaces: Array[Surface] = []

func _ready() -> void:
	if build_room:
		surfaces = RoomBuilder.add_room_to_scene(self, room_rect)
	for line_def in passthrough_lines:
		var seg := Segment.new(
			Vector2(line_def.x, line_def.y),
			Vector2(line_def.z, line_def.w),
			Vector2((line_def.x + line_def.z) / 2.0, (line_def.y + line_def.w) / 2.0))
		var config := SideConfig.new(null, false)
		var surf := Surface.new(seg, config, config, false, false)
		surfaces.append(surf)
		var node := Node2D.new()
		node.set_script(load("res://scripts/game/surface_node.gd"))
		node.name = "PassThrough_%d" % surf.id
		add_child(node)
		node.setup(surf)
