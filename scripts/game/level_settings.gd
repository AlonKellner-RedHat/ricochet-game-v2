extends Node2D

@export var gravity := Vector2(0, 0)
@export var room_rect := Rect2(560, 240, 800, 600)
@export var level_bounds := Rect2(0, 0, 1920, 1080)
@export var build_room := true

@export var passthrough_lines: Array[Vector4] = []
@export var block_lines: Array[Vector4] = []
@export var mirror_lines: Array[Vector4] = []
@export var mirror_right_lines: Array[Vector4] = []
@export var mirror_both_lines: Array[Vector4] = []
@export var inversion_left_arcs: PackedFloat64Array = PackedFloat64Array()
@export var reflective_arcs: PackedFloat64Array = PackedFloat64Array()

var surfaces: Array[Surface] = []

func _ready() -> void:
	if build_room:
		surfaces = RoomBuilder.add_room_to_scene(self, room_rect)
	for line_def in block_lines:
		var surf := RoomBuilder.create_block_surface(
			Vector2(line_def.x, line_def.y),
			Vector2(line_def.z, line_def.w),
			Vector2((line_def.x + line_def.z) / 2.0, (line_def.y + line_def.w) / 2.0))
		_add_surface(surf, "Block")
	for line_def in mirror_lines:
		var seg := _seg_from_v4(line_def)
		var reflection := ReflectionEffect.new(seg.get_carrier())
		var surf := Surface.new(seg, SideConfig.new(reflection, true), SideConfig.new(null, false), false, false)
		_add_surface(surf, "Mirror")
	for line_def in mirror_right_lines:
		var seg := _seg_from_v4(line_def)
		var reflection := ReflectionEffect.new(seg.get_carrier())
		var surf := Surface.new(seg, SideConfig.new(null, false), SideConfig.new(reflection, true), false, false)
		_add_surface(surf, "MirrorR")
	for line_def in mirror_both_lines:
		var seg := _seg_from_v4(line_def)
		var reflection := ReflectionEffect.new(seg.get_carrier())
		var surf := Surface.new(seg, SideConfig.new(reflection, true), SideConfig.new(reflection, true), false, false)
		_add_surface(surf, "MirrorB")
	for i in range(0, inversion_left_arcs.size(), 6):
		var seg := Segment.from_coords(
			Vector2(inversion_left_arcs[i], inversion_left_arcs[i + 1]),
			Vector2(inversion_left_arcs[i + 2], inversion_left_arcs[i + 3]),
			Vector2(inversion_left_arcs[i + 4], inversion_left_arcs[i + 5]))
		var inversion := CircleInversionEffect.new(seg.get_carrier())
		var surf := Surface.new(seg, SideConfig.new(inversion, true), SideConfig.new(null, false), false, true)
		_add_surface(surf, "Inversion")
	for i in range(0, reflective_arcs.size(), 6):
		var seg := Segment.from_coords(
			Vector2(reflective_arcs[i], reflective_arcs[i + 1]),
			Vector2(reflective_arcs[i + 2], reflective_arcs[i + 3]),
			Vector2(reflective_arcs[i + 4], reflective_arcs[i + 5]))
		var reflection := ReflectionEffect.new(seg.get_carrier())
		var surf := Surface.new(seg, SideConfig.new(reflection, true), SideConfig.new(reflection, true), false, false)
		_add_surface(surf, "ReflArc")
	var screen_bounds: Array[Vector4] = [
		Vector4(0, 0, 1920, 0),
		Vector4(1920, 0, 1920, 1080),
		Vector4(1920, 1080, 0, 1080),
		Vector4(0, 1080, 0, 0),
	]
	for line_def in screen_bounds:
		var config := SideConfig.new(null, false)
		var surf := Surface.new(_seg_from_v4(line_def), config, config, false, false)
		surfaces.append(surf)
	for line_def in passthrough_lines:
		var config := SideConfig.new(null, false)
		var surf := Surface.new(_seg_from_v4(line_def), config, config, false, false)
		_add_surface(surf, "PassThrough")

func _add_surface(surf: Surface, prefix: String) -> void:
	surfaces.append(surf)
	var node := Node2D.new()
	node.set_script(load("res://scripts/game/surface_node.gd"))
	node.name = "%s_%d" % [prefix, surf.id]
	add_child(node)
	node.setup(surf)

static func _seg_from_v4(v: Vector4) -> Segment:
	return Segment.from_coords(
		Vector2(v.x, v.y), Vector2(v.z, v.w),
		Vector2((v.x + v.z) / 2.0, (v.y + v.w) / 2.0))
