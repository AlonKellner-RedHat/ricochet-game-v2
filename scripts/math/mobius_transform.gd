class_name MobiusTransform
extends RefCounted

static var _next_id: int = 1
static var IDENTITY_ID := 0

var id: int
var a: Vector2
var b: Vector2
var c: Vector2
var d: Vector2
var conjugating: bool
var a_re: float
var a_im: float
var b_re: float
var b_im: float
var c_re: float
var c_im: float
var d_re: float
var d_im: float

func _init(p_a: Vector2, p_b: Vector2, p_c: Vector2, p_d: Vector2, p_conjugating: bool, p_id: int = -1) -> void:
	if p_id >= 0:
		id = p_id
	else:
		id = _next_id
		_next_id += 1
	a = p_a
	b = p_b
	c = p_c
	d = p_d
	conjugating = p_conjugating
	a_re = p_a.x; a_im = p_a.y
	b_re = p_b.x; b_im = p_b.y
	c_re = p_c.x; c_im = p_c.y
	d_re = p_d.x; d_im = p_d.y

static func identity() -> MobiusTransform:
	return MobiusTransform.new(
		Vector2(1, 0), Vector2(0, 0),
		Vector2(0, 0), Vector2(1, 0),
		false, IDENTITY_ID)

func apply(point: Vector2) -> Vector2:
	if is_inf(point.x) or is_inf(point.y):
		if c == Vector2.ZERO:
			return Vector2(INF, INF)
		return cdiv(a, c)
	var z := point
	if conjugating:
		z = cconj(z)
	var num := cmul(a, z) + b
	var den := cmul(c, z) + d
	if den == Vector2.ZERO:
		return Vector2(INF, INF)
	var result := cdiv(num, den)
	if is_nan(result.x) or is_nan(result.y):
		return Vector2(INF, INF)
	return result

func apply_f64(point: Vector2) -> Vector2:
	if is_inf(point.x) or is_inf(point.y):
		if c == Vector2.ZERO:
			return Vector2(INF, INF)
		return cdiv(a, c)
	var zx: float = point.x
	var zy: float = point.y
	if conjugating:
		zy = -zy
	var num_re: float = (a_re * zx - a_im * zy) + b_re
	var num_im: float = (a_re * zy + a_im * zx) + b_im
	var den_re: float = (c_re * zx - c_im * zy) + d_re
	var den_im: float = (c_re * zy + c_im * zx) + d_im
	var den_mag2: float = den_re * den_re + den_im * den_im
	if den_mag2 == 0.0:
		return Vector2(INF, INF)
	var res_re: float = (num_re * den_re + num_im * den_im) / den_mag2
	var res_im: float = (num_im * den_re - num_re * den_im) / den_mag2
	if is_nan(res_re) or is_nan(res_im):
		return Vector2(INF, INF)
	return Vector2(res_re, res_im)

func compose(other: MobiusTransform) -> MobiusTransform:
	var m2_a := other.a
	var m2_b := other.b
	var m2_c := other.c
	var m2_d := other.d

	if conjugating:
		m2_a = cconj(m2_a)
		m2_b = cconj(m2_b)
		m2_c = cconj(m2_c)
		m2_d = cconj(m2_d)

	var new_a := cmul(a, m2_a) + cmul(b, m2_c)
	var new_b := cmul(a, m2_b) + cmul(b, m2_d)
	var new_c := cmul(c, m2_a) + cmul(d, m2_c)
	var new_d := cmul(c, m2_b) + cmul(d, m2_d)

	var max_mag := maxf(maxf(new_a.length(), new_b.length()), maxf(new_c.length(), new_d.length()))
	if max_mag > 0.0:
		var inv := 1.0 / max_mag
		new_a *= inv
		new_b *= inv
		new_c *= inv
		new_d *= inv

	var new_conj: bool
	if conjugating:
		new_conj = not other.conjugating
	else:
		new_conj = other.conjugating

	var result := MobiusTransform.new(new_a, new_b, new_c, new_d, new_conj)

	var o_ar: float = other.a_re; var o_ai: float = other.a_im
	var o_br: float = other.b_re; var o_bi: float = other.b_im
	var o_cr: float = other.c_re; var o_ci: float = other.c_im
	var o_dr: float = other.d_re; var o_di: float = other.d_im
	if conjugating:
		o_ai = -o_ai; o_bi = -o_bi; o_ci = -o_ci; o_di = -o_di

	var na_re := (a_re * o_ar - a_im * o_ai) + (b_re * o_cr - b_im * o_ci)
	var na_im := (a_re * o_ai + a_im * o_ar) + (b_re * o_ci + b_im * o_cr)
	var nb_re := (a_re * o_br - a_im * o_bi) + (b_re * o_dr - b_im * o_di)
	var nb_im := (a_re * o_bi + a_im * o_br) + (b_re * o_di + b_im * o_dr)
	var nc_re := (c_re * o_ar - c_im * o_ai) + (d_re * o_cr - d_im * o_ci)
	var nc_im := (c_re * o_ai + c_im * o_ar) + (d_re * o_ci + d_im * o_cr)
	var nd_re := (c_re * o_br - c_im * o_bi) + (d_re * o_dr - d_im * o_di)
	var nd_im := (c_re * o_bi + c_im * o_br) + (d_re * o_di + d_im * o_dr)

	var f64_max := maxf(maxf(sqrt(na_re*na_re + na_im*na_im), sqrt(nb_re*nb_re + nb_im*nb_im)),
						maxf(sqrt(nc_re*nc_re + nc_im*nc_im), sqrt(nd_re*nd_re + nd_im*nd_im)))
	if f64_max > 0.0:
		var f64_inv := 1.0 / f64_max
		na_re *= f64_inv; na_im *= f64_inv
		nb_re *= f64_inv; nb_im *= f64_inv
		nc_re *= f64_inv; nc_im *= f64_inv
		nd_re *= f64_inv; nd_im *= f64_inv

	result.a_re = na_re; result.a_im = na_im
	result.b_re = nb_re; result.b_im = nb_im
	result.c_re = nc_re; result.c_im = nc_im
	result.d_re = nd_re; result.d_im = nd_im
	return result

func invert() -> MobiusTransform:
	var result: MobiusTransform
	if conjugating:
		result = MobiusTransform.new(
			Vector2(-d.x, d.y), Vector2(b.x, -b.y),
			Vector2(c.x, -c.y), Vector2(-a.x, a.y),
			true)
		result.a_re = -d_re; result.a_im = d_im
		result.b_re = b_re; result.b_im = -b_im
		result.c_re = c_re; result.c_im = -c_im
		result.d_re = -a_re; result.d_im = a_im
	else:
		var det := cmul(a, d) - cmul(b, c)
		result = MobiusTransform.new(
			cdiv(d, det), cdiv(-b, det),
			cdiv(-c, det), cdiv(a, det),
			false)
		var det_re: float = (a_re * d_re - a_im * d_im) - (b_re * c_re - b_im * c_im)
		var det_im: float = (a_re * d_im + a_im * d_re) - (b_re * c_im + b_im * c_re)
		var det_mag2: float = det_re * det_re + det_im * det_im
		var inv_det_re: float = det_re / det_mag2
		var inv_det_im: float = -det_im / det_mag2
		result.a_re = d_re * inv_det_re - d_im * inv_det_im
		result.a_im = d_re * inv_det_im + d_im * inv_det_re
		result.b_re = -(b_re * inv_det_re - b_im * inv_det_im)
		result.b_im = -(b_re * inv_det_im + b_im * inv_det_re)
		result.c_re = -(c_re * inv_det_re - c_im * inv_det_im)
		result.c_im = -(c_re * inv_det_im + c_im * inv_det_re)
		result.d_re = a_re * inv_det_re - a_im * inv_det_im
		result.d_im = a_re * inv_det_im + a_im * inv_det_re
	return result

static func cmul(v1: Vector2, v2: Vector2) -> Vector2:
	return Vector2(v1.x * v2.x - v1.y * v2.y, v1.x * v2.y + v1.y * v2.x)

static func cconj(v: Vector2) -> Vector2:
	return Vector2(v.x, -v.y)

static func cdiv(v1: Vector2, v2: Vector2) -> Vector2:
	var denom: float = v2.x * v2.x + v2.y * v2.y
	if denom == 0.0:
		return Vector2(INF, INF)
	return Vector2((v1.x * v2.x + v1.y * v2.y) / denom, (v1.y * v2.x - v1.x * v2.y) / denom)

static func cmod2(v: Vector2) -> float:
	return v.x * v.x + v.y * v.y

func maps_lines_to_arcs() -> bool:
	return c != Vector2.ZERO

func pole() -> Vector2:
	var z := cdiv(-d, c)
	if conjugating:
		return cconj(z)
	return z

static func reset_id_counter() -> void:
	_next_id = 1
