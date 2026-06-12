class_name Ray
extends RefCounted

var origin: Point
var direction: Direction

func _init(p_origin: Point, p_direction: Direction) -> void:
	origin = p_origin
	direction = p_direction

static func from_coords(p_origin: Vector2, p_direction: Direction) -> Ray:
	return Ray.new(Point.at(p_origin), p_direction)
