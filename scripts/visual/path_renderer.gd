extends Node2D

func _ready() -> void:
	z_index = 20

func _compute_trace() -> void:
	pass

func has_line() -> bool:
	return false

func get_line_from() -> Vector2:
	return Vector2.ZERO

func get_line_direction() -> Vector2:
	return Vector2.ZERO

func get_traced_path():
	return null

func get_planned_path():
	return null

func get_typed_steps() -> Array:
	return []
