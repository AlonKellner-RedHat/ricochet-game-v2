class_name Segment
extends RefCounted

var start: Vector2
var end: Vector2
var via: Vector2

var _carrier: GeneralizedCircle = null

func _init(p_start: Vector2, p_end: Vector2, p_via: Vector2) -> void:
	start = p_start
	end = p_end
	via = p_via

func get_carrier() -> GeneralizedCircle:
	if _carrier == null:
		_carrier = derive_carrier(start, end, via)
	return _carrier

func is_line() -> bool:
	return get_carrier().is_line()

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
	if get_carrier().is_line():
		var carrier := get_carrier()
		var traversal := end - start
		var normal := Vector2(carrier.b, carrier.c)
		w = -traversal.cross(normal)
	return w

static func _to_homogeneous_row(p: Vector2) -> Array[float]:
	if is_inf(p.x) or is_inf(p.y):
		return [1.0, 0.0, 0.0, 0.0]
	return [p.x * p.x + p.y * p.y, p.x, p.y, 1.0]

static func derive_carrier(p_start: Vector2, p_end: Vector2, p_via: Vector2) -> GeneralizedCircle:
	var r1 := _to_homogeneous_row(p_start)
	var r2 := _to_homogeneous_row(p_via)
	var r3 := _to_homogeneous_row(p_end)

	var a := _det3x3(r1[1], r1[2], r1[3], r2[1], r2[2], r2[3], r3[1], r3[2], r3[3])
	var b := -_det3x3(r1[0], r1[2], r1[3], r2[0], r2[2], r2[3], r3[0], r3[2], r3[3])
	var c := _det3x3(r1[0], r1[1], r1[3], r2[0], r2[1], r2[3], r3[0], r3[1], r3[3])
	var d := -_det3x3(r1[0], r1[1], r1[2], r2[0], r2[1], r2[2], r3[0], r3[1], r3[2])

	return GeneralizedCircle.new(a, b, c, d)

static func _det3x3(
	a11: float, a12: float, a13: float,
	a21: float, a22: float, a23: float,
	a31: float, a32: float, a33: float,
) -> float:
	return (a11 * (a22 * a33 - a23 * a32)
		- a12 * (a21 * a33 - a23 * a31)
		+ a13 * (a21 * a32 - a22 * a31))
