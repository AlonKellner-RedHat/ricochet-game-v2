class_name Direction
extends RefCounted

var start: Point
var end: Point

func _init(p_start: Point, p_end: Point) -> void:
	start = p_start
	end = p_end

static func from_coords(p_start: Vector2, p_end: Vector2) -> Direction:
	return Direction.new(Point.at(p_start), Point.at(p_end))

func is_zero_length() -> bool:
	return start.coords == end.coords

func to_vector() -> Vector2:
	return end.coords - start.coords

func to_normalized() -> Vector2:
	var v := to_vector()
	if v.length_squared() == 0.0:
		return Vector2.ZERO
	return v.normalized()
