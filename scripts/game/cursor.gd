extends Node2D

const CROSSHAIR_SIZE := 10.0
const CROSSHAIR_COLOR := Color.WHITE
const CROSSHAIR_WIDTH := 1.5

func _process(_delta: float) -> void:
	global_position = get_global_mouse_position()
	queue_redraw()

func _draw() -> void:
	draw_line(Vector2(-CROSSHAIR_SIZE, 0), Vector2(CROSSHAIR_SIZE, 0), CROSSHAIR_COLOR, CROSSHAIR_WIDTH)
	draw_line(Vector2(0, -CROSSHAIR_SIZE), Vector2(0, CROSSHAIR_SIZE), CROSSHAIR_COLOR, CROSSHAIR_WIDTH)
