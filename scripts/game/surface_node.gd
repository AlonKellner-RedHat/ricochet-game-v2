extends Node2D

const LINE_WIDTH := 3.0
const BLOCK_COLOR := Color.RED

var surface: Surface

func setup(p_surface: Surface) -> void:
	surface = p_surface
	if surface.player_solid and surface.segment.is_line():
		_add_collision_shape()
	queue_redraw()

func _draw() -> void:
	if not surface:
		return
	var color := _get_color()
	draw_line(surface.segment.start, surface.segment.end, color, LINE_WIDTH)

func _get_color() -> Color:
	var left_config := surface.active_side_config(Side.Value.LEFT, GameState.new())
	if left_config and left_config.effect is TerminalEffect:
		return BLOCK_COLOR
	return Color.GRAY

func _add_collision_shape() -> void:
	var body := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := SegmentShape2D.new()
	shape.a = surface.segment.start
	shape.b = surface.segment.end
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
