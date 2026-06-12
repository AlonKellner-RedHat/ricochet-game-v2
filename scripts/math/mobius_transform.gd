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

static func identity() -> MobiusTransform:
	return MobiusTransform.new(
		Vector2(1, 0), Vector2(0, 0),
		Vector2(0, 0), Vector2(1, 0),
		false, IDENTITY_ID)

func apply(point: Vector2) -> Vector2:
	var z := Vector2(point.x, point.y)
	if conjugating:
		z = cconj(z)
	var num := cmul(a, z) + b
	var den := cmul(c, z) + d
	var w := cdiv(num, den)
	return Vector2(w.x, w.y)

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

	var new_conj: bool
	if conjugating:
		new_conj = not other.conjugating
	else:
		new_conj = other.conjugating

	return MobiusTransform.new(new_a, new_b, new_c, new_d, new_conj)

func invert() -> MobiusTransform:
	var det := cmul(a, d) - cmul(b, c)
	var inv_a := cdiv(d, det)
	var inv_b := cdiv(-b, det)
	var inv_c := cdiv(-c, det)
	var inv_d := cdiv(a, det)
	return MobiusTransform.new(inv_a, inv_b, inv_c, inv_d, conjugating)

func determinant_mod2() -> float:
	var det := cmul(a, d) - cmul(b, c)
	return cmod2(det)

static func cmul(v1: Vector2, v2: Vector2) -> Vector2:
	return Vector2(v1.x * v2.x - v1.y * v2.y, v1.x * v2.y + v1.y * v2.x)

static func cconj(v: Vector2) -> Vector2:
	return Vector2(v.x, -v.y)

static func cdiv(v1: Vector2, v2: Vector2) -> Vector2:
	var denom: float = v2.x * v2.x + v2.y * v2.y
	return Vector2((v1.x * v2.x + v1.y * v2.y) / denom, (v1.y * v2.x - v1.x * v2.y) / denom)

static func cmod2(v: Vector2) -> float:
	return v.x * v.x + v.y * v.y

func maps_lines_to_arcs() -> bool:
	return c != Vector2.ZERO

static func reset_id_counter() -> void:
	_next_id = 1
