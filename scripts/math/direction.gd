class_name Direction
extends RefCounted

var start: Vector2
var end: Vector2

func _init(p_start: Vector2, p_end: Vector2) -> void:
	start = p_start
	end = p_end

func is_zero_length() -> bool:
	return start == end

func to_vector() -> Vector2:
	return end - start

func to_normalized() -> Vector2:
	var v := to_vector()
	if v.length_squared() == 0.0:
		return Vector2.ZERO
	return v.normalized()
