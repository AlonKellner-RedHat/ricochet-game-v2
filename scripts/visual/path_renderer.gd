extends Node2D

const LINE_COLOR := Color.GREEN
const LINE_WIDTH := 2.0

var _player: CharacterBody2D
var _cursor: Node2D

func _ready() -> void:
	_player = get_node_or_null("../Player")
	_cursor = get_node_or_null("../Cursor")
	z_index = 20

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not _player or not _cursor:
		return
	var from := _player.global_position
	var to := _cursor.global_position
	if from == to:
		return
	draw_line(from - global_position, to - global_position, LINE_COLOR, LINE_WIDTH)

func has_line() -> bool:
	if not _player or not _cursor:
		return false
	return _player.global_position != _cursor.global_position

func get_line_from() -> Vector2:
	if _player:
		return _player.global_position
	return Vector2.ZERO

func get_line_to() -> Vector2:
	if _cursor:
		return _cursor.global_position
	return Vector2.ZERO
