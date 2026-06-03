class_name Segment
extends RefCounted

var start: Vector2
var end: Vector2
var via: Vector2
var is_line_by_construction: bool

var _carrier: GeneralizedCircle = null

func _init(p_start: Vector2, p_end: Vector2, p_via: Vector2, p_is_line: bool = false) -> void:
	start = p_start
	end = p_end
	via = p_via
	is_line_by_construction = p_is_line or p_via == Vector2(INF, INF)

func get_carrier() -> GeneralizedCircle:
	if _carrier == null:
		_carrier = _derive_carrier()
	return _carrier

func is_line() -> bool:
	return is_line_by_construction

func determine_side(point: Vector2) -> Side.Value:
	var carrier := get_carrier()
	var f_val := carrier.evaluate(point)
	var winding := _compute_winding()

	if winding >= 0.0:
		return Side.Value.LEFT if f_val > 0.0 else Side.Value.RIGHT
	else:
		return Side.Value.RIGHT if f_val > 0.0 else Side.Value.LEFT

func _compute_winding() -> float:
	var w := (via - start).cross(end - start)
	if is_line_by_construction:
		var carrier := get_carrier()
		var traversal := end - start
		var normal := Vector2(carrier.b, carrier.c)
		w = -traversal.cross(normal)
	return w

func _derive_carrier() -> GeneralizedCircle:
	if is_line_by_construction:
		return _line_carrier_from_two_points(start, end)
	return _circle_carrier_from_three_points(start, end, via)

static func _line_carrier_from_two_points(p1: Vector2, p2: Vector2) -> GeneralizedCircle:
	var dx := p2.x - p1.x
	var dy := p2.y - p1.y
	var b_val := -dy
	var c_val := dx
	var d_val := dy * p1.x - dx * p1.y
	return GeneralizedCircle.new(0.0, b_val, c_val, d_val)

static func _circle_carrier_from_three_points(p1: Vector2, p2: Vector2, p3: Vector2) -> GeneralizedCircle:
	var ax := p1.x
	var ay := p1.y
	var bx := p2.x
	var by := p2.y
	var cx := p3.x
	var cy := p3.y

	var d_val := 2.0 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))

	var ux := ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) + (cx * cx + cy * cy) * (ay - by)) / d_val
	var uy := ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) + (cx * cx + cy * cy) * (bx - ax)) / d_val

	var center := Vector2(ux, uy)
	var radius := center.distance_to(p1)

	return GeneralizedCircle.from_circle(center, radius)
