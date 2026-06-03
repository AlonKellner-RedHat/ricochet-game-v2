class_name Ray
extends RefCounted

var origin: Vector2
var direction: Direction

func _init(p_origin: Vector2, p_direction: Direction) -> void:
	origin = p_origin
	direction = p_direction
