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
	var h_w_re: float = b / 2.0
	var h_w_im: float = -c / 2.0

	var ax: float = mobius.a_re; var ay: float = mobius.a_im
	var bx: float = mobius.b_re; var by: float = mobius.b_im
	var cx: float = mobius.c_re; var cy: float = mobius.c_im
	var dx: float = mobius.d_re; var dy: float = mobius.d_im

	var n00_x: float; var n00_y: float
	var n01_x: float; var n01_y: float
	var n10_x: float; var n10_y: float
	var n11_x: float; var n11_y: float
	var h01_x: float; var h01_y: float
	var h10_x: float; var h10_y: float

	if mobius.conjugating:
		n00_x = dx; n00_y = -dy
		n01_x = -bx; n01_y = by
		n10_x = -cx; n10_y = cy
		n11_x = ax; n11_y = -ay
		h01_x = h_w_re; h01_y = -h_w_im
		h10_x = h_w_re; h10_y = h_w_im
	else:
		n00_x = dx; n00_y = dy
		n01_x = -bx; n01_y = -by
		n10_x = -cx; n10_y = -cy
		n11_x = ax; n11_y = ay
		h01_x = h_w_re; h01_y = h_w_im
		h10_x = h_w_re; h10_y = -h_w_im

	var nh00_x := n00_x; var nh00_y := -n00_y
	var nh01_x := n10_x; var nh01_y := -n10_y
	var nh10_x := n01_x; var nh10_y := -n01_y
	var nh11_x := n11_x; var nh11_y := -n11_y

	var h_a: float = a
	var h_d: float = d

	var t00_x := nh00_x * h_a + (nh01_x * h10_x - nh01_y * h10_y)
	var t00_y := nh00_y * h_a + (nh01_x * h10_y + nh01_y * h10_x)
	var t01_x := (nh00_x * h01_x - nh00_y * h01_y) + nh01_x * h_d
	var t01_y := (nh00_x * h01_y + nh00_y * h01_x) + nh01_y * h_d
	var t10_x := nh10_x * h_a + (nh11_x * h10_x - nh11_y * h10_y)
	var t10_y := nh10_y * h_a + (nh11_x * h10_y + nh11_y * h10_x)
	var t11_x := (nh10_x * h01_x - nh10_y * h01_y) + nh11_x * h_d
	var t11_y := (nh10_x * h01_y + nh10_y * h01_x) + nh11_y * h_d

	var r00 := (t00_x * n00_x - t00_y * n00_y) + (t01_x * n10_x - t01_y * n10_y)
	var r01_x := (t00_x * n01_x - t00_y * n01_y) + (t01_x * n11_x - t01_y * n11_y)
	var r01_y := (t00_x * n01_y + t00_y * n01_x) + (t01_x * n11_y + t01_y * n11_x)
	var r11 := (t10_x * n01_x - t10_y * n01_y) + (t11_x * n11_x - t11_y * n11_y)

	return GeneralizedCircle.new(r00, 2.0 * r01_x, -2.0 * r01_y, r11)
