extends GutTest

const TOL := Vector2(0.01, 0.01)
const STOL := 0.01

var _test_points: Array[Vector2] = [
	Vector2(1, 0), Vector2(0, 1), Vector2(3, 4),
	Vector2(-2, 5), Vector2(100, 200)
]

func before_each() -> void:
	MobiusTransform.reset_id_counter()

func _rotation(angle: float) -> MobiusTransform:
	return MobiusTransform.new(
		Vector2(cos(angle), sin(angle)), Vector2(0, 0),
		Vector2(0, 0), Vector2(1, 0), false)

func _translation(dx: float, dy: float) -> MobiusTransform:
	return MobiusTransform.new(
		Vector2(1, 0), Vector2(dx, dy),
		Vector2(0, 0), Vector2(1, 0), false)

func _scaling(s: float) -> MobiusTransform:
	return MobiusTransform.new(
		Vector2(s, 0), Vector2(0, 0),
		Vector2(0, 0), Vector2(1, 0), false)

func _reflection_x() -> MobiusTransform:
	return MobiusTransform.new(
		Vector2(1, 0), Vector2(0, 0),
		Vector2(0, 0), Vector2(1, 0), true)

func _projective_mobius() -> MobiusTransform:
	return MobiusTransform.new(
		Vector2(1, 0), Vector2(2, 1),
		Vector2(0, 0.1), Vector2(1, 0), false)

func _det(m: MobiusTransform) -> Vector2:
	return MobiusTransform.cmul(m.a, m.d) - MobiusTransform.cmul(m.b, m.c)

# --- Composition associativity ---

func test_composition_associativity() -> void:
	var A := _rotation(PI / 3.0).compose(_translation(10, 20))
	var B := _reflection_x()
	var C := _scaling(2.5)
	var AB_C := A.compose(B).compose(C)
	var A_BC := A.compose(B.compose(C))
	for p in _test_points:
		assert_almost_eq(AB_C.apply(p), A_BC.apply(p), TOL,
			"(A∘B)∘C != A∘(B∘C) at %s" % p)

func test_composition_associativity_with_projective() -> void:
	var A := _projective_mobius()
	var B := _rotation(PI / 4.0)
	var C := _translation(5, -3)
	var AB_C := A.compose(B).compose(C)
	var A_BC := A.compose(B.compose(C))
	for p in _test_points:
		if MobiusTransform.cmod2(MobiusTransform.cmul(A.c, p) + A.d) < 0.01:
			continue
		assert_almost_eq(AB_C.apply(p), A_BC.apply(p), TOL,
			"(A∘B)∘C != A∘(B∘C) at %s (projective)" % p)

# --- Identity composition ---

func test_identity_composition_left() -> void:
	var I := MobiusTransform.identity()
	var M := _rotation(PI / 6.0).compose(_translation(3, 7))
	var IM := I.compose(M)
	for p in _test_points:
		assert_almost_eq(IM.apply(p), M.apply(p), TOL,
			"I∘M != M at %s" % p)

func test_identity_composition_right() -> void:
	var I := MobiusTransform.identity()
	var M := _rotation(PI / 6.0).compose(_translation(3, 7))
	var MI := M.compose(I)
	for p in _test_points:
		assert_almost_eq(MI.apply(p), M.apply(p), TOL,
			"M∘I != M at %s" % p)

# --- Inverse composition ---

func test_inverse_composition_is_identity() -> void:
	var M := _rotation(PI / 5.0).compose(_translation(4, -2))
	var M_inv := M.invert()
	var result := M.compose(M_inv)
	for p in _test_points:
		assert_almost_eq(result.apply(p), p, TOL,
			"M∘M⁻¹ != I at %s" % p)

func test_inverse_composition_reverse() -> void:
	var M := _reflection_x().compose(_scaling(3.0))
	var M_inv := M.invert()
	var result := M_inv.compose(M)
	for p in _test_points:
		assert_almost_eq(result.apply(p), p, TOL,
			"M⁻¹∘M != I at %s" % p)

# --- Double inversion ---

func test_double_inversion() -> void:
	var M := _projective_mobius()
	var M_inv_inv := M.invert().invert()
	for p in _test_points:
		if MobiusTransform.cmod2(MobiusTransform.cmul(M.c, p) + M.d) < 0.01:
			continue
		assert_almost_eq(M_inv_inv.apply(p), M.apply(p), TOL,
			"(M⁻¹)⁻¹ != M at %s" % p)

# --- Determinant product rule ---

func test_determinant_product_conformal() -> void:
	var A := _rotation(PI / 4.0).compose(_translation(1, 2))
	var B := _scaling(2.0).compose(_translation(-3, 5))
	var AB := A.compose(B)
	var det_AB := _det(AB)
	var det_A := _det(A)
	var det_B := _det(B)
	var expected := MobiusTransform.cmul(det_A, det_B)
	assert_almost_eq(det_AB, expected, TOL,
		"det(A∘B) != det(A)·det(B) for conformal pair")

func test_determinant_product_mixed() -> void:
	var A := _rotation(PI / 3.0)
	var B := _reflection_x()
	var AB := A.compose(B)
	var det_AB := _det(AB)
	var det_A := _det(A)
	var det_B_conj := MobiusTransform.cconj(_det(B))
	var expected := MobiusTransform.cmul(det_A, det_B_conj)
	assert_almost_eq(det_AB, expected, TOL,
		"det(A∘B) != det(A)·conj(det(B)) for conformal×anti-conformal")

# --- Conjugation table ---

func test_conjugation_composition_table() -> void:
	var conf := _rotation(PI / 4.0)
	var anti := _reflection_x()
	assert_false(conf.conjugating, "rotation should be conformal")
	assert_true(anti.conjugating, "reflection should be anti-conformal")
	assert_false(conf.compose(conf).conjugating, "conformal∘conformal = conformal")
	assert_true(conf.compose(anti).conjugating, "conformal∘anti = anti")
	assert_true(anti.compose(conf).conjugating, "anti∘conformal = anti")
	assert_false(anti.compose(anti).conjugating, "anti∘anti = conformal")

func test_inversion_preserves_conjugation() -> void:
	var conf := _rotation(PI / 3.0).compose(_translation(5, 5))
	var anti := _reflection_x().compose(_scaling(2.0))
	assert_eq(conf.invert().conjugating, conf.conjugating,
		"invert should preserve conjugation (conformal)")
	assert_eq(anti.invert().conjugating, anti.conjugating,
		"invert should preserve conjugation (anti-conformal)")
