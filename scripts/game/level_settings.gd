extends Node2D

@export var gravity := Vector2(0, 0)
@export var room_rect := Rect2(560, 240, 800, 600)
@export var level_bounds := Rect2(0, 0, 1920, 1080)
@export var build_room := true

@export var passthrough_lines: Array[Vector4] = []
@export var block_lines: Array[Vector4] = []
@export var mirror_lines: Array[Vector4] = []
@export var mirror_right_lines: Array[Vector4] = []
@export var inversion_left_arcs: PackedFloat64Array = PackedFloat64Array()

var surfaces: Array[Surface] = []

func _ready() -> void:
	if build_room:
		surfaces = RoomBuilder.add_room_to_scene(self, room_rect)
	for line_def in block_lines:
		var surf := RoomBuilder.create_block_surface(
			Vector2(line_def.x, line_def.y),
			Vector2(line_def.z, line_def.w),
			Vector2((line_def.x + line_def.z) / 2.0, (line_def.y + line_def.w) / 2.0))
		surfaces.append(surf)
		var node := Node2D.new()
		node.set_script(load("res://scripts/game/surface_node.gd"))
		node.name = "Block_%d" % surf.id
		add_child(node)
		node.setup(surf)
	for line_def in mirror_lines:
		var seg := Segment.from_coords(
			Vector2(line_def.x, line_def.y),
			Vector2(line_def.z, line_def.w),
			Vector2((line_def.x + line_def.z) / 2.0, (line_def.y + line_def.w) / 2.0))
		var carrier := seg.get_carrier()
		var reflection := ReflectionEffect.new(carrier)
		var left_config := SideConfig.new(reflection, true)
		var right_config := SideConfig.new(null, false)
		var surf := Surface.new(seg, left_config, right_config, false, false)
		surfaces.append(surf)
		var node := Node2D.new()
		node.set_script(load("res://scripts/game/surface_node.gd"))
		node.name = "Mirror_%d" % surf.id
		add_child(node)
		node.setup(surf)
	for line_def in mirror_right_lines:
		var seg := Segment.from_coords(
			Vector2(line_def.x, line_def.y),
			Vector2(line_def.z, line_def.w),
			Vector2((line_def.x + line_def.z) / 2.0, (line_def.y + line_def.w) / 2.0))
		var carrier := seg.get_carrier()
		var reflection := ReflectionEffect.new(carrier)
		var left_config := SideConfig.new(null, false)
		var right_config := SideConfig.new(reflection, true)
		var surf := Surface.new(seg, left_config, right_config, false, false)
		surfaces.append(surf)
		var node := Node2D.new()
		node.set_script(load("res://scripts/game/surface_node.gd"))
		node.name = "MirrorR_%d" % surf.id
		add_child(node)
		node.setup(surf)
	for i in range(0, inversion_left_arcs.size(), 6):
		var seg := Segment.from_coords(
			Vector2(inversion_left_arcs[i], inversion_left_arcs[i + 1]),
			Vector2(inversion_left_arcs[i + 2], inversion_left_arcs[i + 3]),
			Vector2(inversion_left_arcs[i + 4], inversion_left_arcs[i + 5]))
		var carrier := seg.get_carrier()
		var inversion := CircleInversionEffect.new(carrier)
		var left_config := SideConfig.new(inversion, true)
		var right_config := SideConfig.new(null, false)
		var surf := Surface.new(seg, left_config, right_config, false, false)
		surfaces.append(surf)
		var node := Node2D.new()
		node.set_script(load("res://scripts/game/surface_node.gd"))
		node.name = "Inversion_%d" % surf.id
		add_child(node)
		node.setup(surf)
	# Screen boundary pass-throughs — ensure off-screen steps split at screen edge
	var screen_bounds: Array[Vector4] = [
		Vector4(0, 0, 1920, 0),
		Vector4(1920, 0, 1920, 1080),
		Vector4(1920, 1080, 0, 1080),
		Vector4(0, 1080, 0, 0),
	]
	for line_def in screen_bounds:
		var seg := Segment.from_coords(
			Vector2(line_def.x, line_def.y),
			Vector2(line_def.z, line_def.w),
			Vector2((line_def.x + line_def.z) / 2.0, (line_def.y + line_def.w) / 2.0))
		var config := SideConfig.new(null, false)
		var surf := Surface.new(seg, config, config, false, false)
		surfaces.append(surf)

	for line_def in passthrough_lines:
		var seg := Segment.from_coords(
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
