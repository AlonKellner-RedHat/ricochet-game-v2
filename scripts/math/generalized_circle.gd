class_name GeneralizedCircle
extends RefCounted

var a: float
var b: float
var c: float
var d: float

func _init(p_a: float, p_b: float, p_c: float, p_d: float) -> void:
	a = p_a
	b = p_b
	c = p_c
	d = p_d

func is_line() -> bool:
	return a == 0.0

func center() -> Vector2:
	assert(a != 0.0, "center() called on a line (a == 0)")
	return Vector2(-b / (2.0 * a), -c / (2.0 * a))

func radius() -> float:
	assert(a != 0.0, "radius() called on a line (a == 0)")
	return sqrt((b * b + c * c - 4.0 * a * d) / (4.0 * a * a))

func same_circle(other: GeneralizedCircle) -> bool:
	return self == other or (a == other.a and b == other.b and c == other.c and d == other.d)

func evaluate(point: Vector2) -> float:
	return a * (point.x * point.x + point.y * point.y) + b * point.x + c * point.y + d

static func from_line(p_b: float, p_c: float, p_d: float) -> GeneralizedCircle:
	return GeneralizedCircle.new(0.0, p_b, p_c, p_d)

static func from_circle(p_center: Vector2, p_radius: float) -> GeneralizedCircle:
	var p_a := 1.0
	var p_b := -2.0 * p_center.x
	var p_c := -2.0 * p_center.y
	var p_d := p_center.x * p_center.x + p_center.y * p_center.y - p_radius * p_radius
	return GeneralizedCircle.new(p_a, p_b, p_c, p_d)

func transformed_by(mobius: MobiusTransform) -> GeneralizedCircle:
	var w := Vector2(b / 2.0, -c / 2.0)
	var wc := Vector2(w.x, -w.y)

	var alpha := mobius.a
	var beta := mobius.b
	var gamma := mobius.c
	var delta := mobius.d

	var N00: Vector2
	var N01: Vector2
	var N10: Vector2
	var N11: Vector2
	var H00: float
	var H01: Vector2
	var H10: Vector2
	var H11: float

	if mobius.conjugating:
		N00 = MobiusTransform.cconj(delta)
		N01 = MobiusTransform.cconj(-beta)
		N10 = MobiusTransform.cconj(-gamma)
		N11 = MobiusTransform.cconj(alpha)
		H00 = a
		H01 = wc
		H10 = w
		H11 = d
	else:
		N00 = delta
		N01 = -beta
		N10 = -gamma
		N11 = alpha
		H00 = a
		H01 = w
		H10 = wc
		H11 = d

	var Nh00 := MobiusTransform.cconj(N00)
	var Nh01 := MobiusTransform.cconj(N10)
	var Nh10 := MobiusTransform.cconj(N01)
	var Nh11 := MobiusTransform.cconj(N11)

	var rH00 := Vector2(H00, 0)
	var rH11 := Vector2(H11, 0)

	var T00 := MobiusTransform.cmul(Nh00, rH00) + MobiusTransform.cmul(Nh01, H10)
	var T01 := MobiusTransform.cmul(Nh00, H01) + MobiusTransform.cmul(Nh01, rH11)
	var T10 := MobiusTransform.cmul(Nh10, rH00) + MobiusTransform.cmul(Nh11, H10)
	var T11 := MobiusTransform.cmul(Nh10, H01) + MobiusTransform.cmul(Nh11, rH11)

	var R00 := MobiusTransform.cmul(T00, N00) + MobiusTransform.cmul(T01, N10)
	var R01 := MobiusTransform.cmul(T00, N01) + MobiusTransform.cmul(T01, N11)
	var R11 := MobiusTransform.cmul(T10, N01) + MobiusTransform.cmul(T11, N11)

	return GeneralizedCircle.new(R00.x, 2.0 * R01.x, -2.0 * R01.y, R11.x)
