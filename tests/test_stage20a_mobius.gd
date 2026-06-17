extends GutTest

func before_each() -> void:
	MobiusTransform.reset_id_counter()

func test_stage20a_cmul() -> void:
	var result := MobiusTransform.cmul(Vector2(3, 4), Vector2(1, 2))
	assert_almost_eq(result.x, -5.0, 0.001, "(3+4i)(1+2i) real = -5")
	assert_almost_eq(result.y, 10.0, 0.001, "(3+4i)(1+2i) imag = 10")

func test_stage20a_cconj() -> void:
	var result := MobiusTransform.cconj(Vector2(3, 4))
	assert_eq(result, Vector2(3, -4), "conj(3+4i) = 3-4i")

func test_stage20a_cdiv() -> void:
	var result := MobiusTransform.cdiv(Vector2(3, 4), Vector2(1, 2))
	assert_almost_eq(result.x, 2.2, 0.001, "(3+4i)/(1+2i) real = 2.2")
	assert_almost_eq(result.y, -0.4, 0.001, "(3+4i)/(1+2i) imag = -0.4")

func test_stage20a_cmod2() -> void:
	var result := MobiusTransform.cmod2(Vector2(3, 4))
	assert_almost_eq(result, 25.0, 0.001, "|3+4i|² = 25")

func test_stage20a_apply_conformal_identity() -> void:
	var m := MobiusTransform.identity()
	var result := m.apply(Vector2(5, 3))
	assert_almost_eq(result.x, 5.0, 0.001, "Identity maps (5,3) to (5,3)")
	assert_almost_eq(result.y, 3.0, 0.001, "Identity y preserved")

func test_stage20a_apply_conformal_rotation() -> void:
	var m := MobiusTransform.new(Vector2(0, 1), Vector2(0, 0), Vector2(0, 0), Vector2(1, 0), false)
	var result := m.apply(Vector2(1, 0))
	assert_almost_eq(result.x, 0.0, 0.001, "90° rotation of (1,0) x = 0")
	assert_almost_eq(result.y, 1.0, 0.001, "90° rotation of (1,0) y = 1")

func test_stage20a_apply_anticonformal() -> void:
	var m := MobiusTransform.new(Vector2(1, 0), Vector2(0, 0), Vector2(0, 0), Vector2(1, 0), true)
	var result := m.apply(Vector2(3, 4))
	assert_almost_eq(result.x, 3.0, 0.001, "x-axis reflection preserves x")
	assert_almost_eq(result.y, -4.0, 0.001, "x-axis reflection negates y")

func test_stage20a_compose_conformal_conformal() -> void:
	var r1 := MobiusTransform.new(Vector2(0, 1), Vector2(0, 0), Vector2(0, 0), Vector2(1, 0), false)
	var r2 := MobiusTransform.new(Vector2(0, 1), Vector2(0, 0), Vector2(0, 0), Vector2(1, 0), false)
	var composed := r1.compose(r2)
	assert_false(composed.conjugating, "Conformal × conformal = conformal")
	var result := composed.apply(Vector2(1, 0))
	assert_almost_eq(result.x, -1.0, 0.001, "Two 90° rotations = 180°")
	assert_almost_eq(result.y, 0.0, 0.001, "180° rotation y")

func test_stage20a_compose_conformal_anticonformal() -> void:
	var rot := MobiusTransform.new(Vector2(0, 1), Vector2(0, 0), Vector2(0, 0), Vector2(1, 0), false)
	var refl := MobiusTransform.new(Vector2(1, 0), Vector2(0, 0), Vector2(0, 0), Vector2(1, 0), true)
	var composed := rot.compose(refl)
	assert_true(composed.conjugating, "Conformal × anti-conformal = anti-conformal")

func test_stage20a_compose_anticonformal_anticonformal() -> void:
	var refl := MobiusTransform.new(Vector2(1, 0), Vector2(0, 0), Vector2(0, 0), Vector2(1, 0), true)
	var composed := refl.compose(refl)
	assert_false(composed.conjugating, "Anti-conformal × anti-conformal = conformal")

func test_stage20a_invert_identity() -> void:
	var m := MobiusTransform.identity()
	var inv := m.invert()
	var result := inv.apply(Vector2(7, 3))
	assert_almost_eq(result.x, 7.0, 0.001, "Identity inverse maps (7,3) to (7,3)")
	assert_almost_eq(result.y, 3.0, 0.001, "Identity inverse y")

func test_stage20a_compose_with_inverse() -> void:
	var m := MobiusTransform.new(Vector2(0, 1), Vector2(3, 2), Vector2(0, 0), Vector2(1, 0), false)
	var inv := m.invert()
	var composed := m.compose(inv)
	var result := composed.apply(Vector2(5, 7))
	assert_almost_eq(result.x, 5.0, 0.01, "M∘M⁻¹ should be identity")
	assert_almost_eq(result.y, 7.0, 0.01, "M∘M⁻¹ y")

func test_stage20a_S18_determinant_nonzero() -> void:
	var carrier := GeneralizedCircle.from_line(1, 0, -200)
	var refl := ReflectionEffect.new(carrier)
	var m := refl.get_mobius()
	var det := MobiusTransform.cmul(m.a, m.d) - MobiusTransform.cmul(m.b, m.c)
	assert_gt(MobiusTransform.cmod2(det), 0.0, "S18: Reflection determinant must be non-zero")

func test_stage20a_transform_id_unique() -> void:
	var ids: Dictionary = {}
	for i in 100:
		var m := MobiusTransform.new(Vector2(1, 0), Vector2(i, 0), Vector2(0, 0), Vector2(1, 0), false)
		assert_false(ids.has(m.id), "Transform ID %d should be unique" % m.id)
		ids[m.id] = true

func test_stage20a_identity_id_preserved() -> void:
	var m := MobiusTransform.identity()
	assert_eq(m.id, MobiusTransform.IDENTITY_ID, "Identity ID should be 0")
	assert_eq(MobiusTransform.IDENTITY_ID, 0, "IDENTITY_ID constant should be 0")

func test_stage20a_S16_no_nan() -> void:
	var m := MobiusTransform.new(Vector2(0, 1), Vector2(3, 2), Vector2(0, 0), Vector2(1, 0), false)
	var result := m.apply(Vector2(100, 200))
	assert_false(is_nan(result.x), "S16: apply x not NaN")
	assert_false(is_nan(result.y), "S16: apply y not NaN")

# ==========================================================================
# Riemann sphere: infinity handling
# ==========================================================================

func test_apply_infinity_with_nonzero_c() -> void:
	# Unit circle inversion: center=(0,0), r²=1
	# T(∞) = a/c = (0,0)/(1,0) = (0,0) — infinity maps to center
	var m := MobiusTransform.new(Vector2(0, 0), Vector2(1, 0), Vector2(1, 0), Vector2(0, 0), true)
	var result := m.apply(Vector2(INF, INF))
	assert_almost_eq(result.x, 0.0, 0.001, "T(∞) x = center x = 0")
	assert_almost_eq(result.y, 0.0, 0.001, "T(∞) y = center y = 0")

func test_apply_infinity_with_nonzero_c_offset_center() -> void:
	# Inversion centered at (200,200)
	# T(∞) = a/c = (200,200)/(1,0) = (200,200)
	var m := MobiusTransform.new(Vector2(200, 200), Vector2(-80000, 0), Vector2(1, 0), Vector2(-200, 200), true)
	var result := m.apply(Vector2(INF, INF))
	assert_almost_eq(result.x, 200.0, 0.001, "T(∞) x = center x = 200")
	assert_almost_eq(result.y, 200.0, 0.001, "T(∞) y = center y = 200")

func test_apply_infinity_with_zero_c() -> void:
	# Reflection: c=(0,0) — T(∞) = ∞
	var m := MobiusTransform.new(Vector2(1, 0), Vector2(0, 0), Vector2(0, 0), Vector2(1, 0), true)
	var result := m.apply(Vector2(INF, INF))
	assert_true(is_inf(result.x), "Reflection T(∞) x = INF")
	assert_true(is_inf(result.y), "Reflection T(∞) y = INF")

func test_apply_to_infinity() -> void:
	# Unit circle inversion: center maps to ∞
	# T(0,0): conj(0)=(0,0), num=(1,0), den=(0,0) → ∞
	var m := MobiusTransform.new(Vector2(0, 0), Vector2(1, 0), Vector2(1, 0), Vector2(0, 0), true)
	var result := m.apply(Vector2(0, 0))
	assert_true(is_inf(result.x), "Center maps to infinity x")
	assert_true(is_inf(result.y), "Center maps to infinity y")

func test_cdiv_zero_denominator() -> void:
	var result := MobiusTransform.cdiv(Vector2(3, 4), Vector2(0, 0))
	assert_true(is_inf(result.x), "cdiv by zero x = INF")
	assert_true(is_inf(result.y), "cdiv by zero y = INF")

func test_invert_anticonformal_self_inverse() -> void:
	# Circle inversion is self-inverse: T(T(z)) = z, so T⁻¹ = T
	var m := MobiusTransform.new(Vector2(3, 4), Vector2(5, 0), Vector2(1, 0), Vector2(-3, 4), true)
	var inv := m.invert()
	# T⁻¹(T(z)) should equal z for any z
	var z := Vector2(1, 0)
	var tz := m.apply(z)
	var roundtrip := inv.apply(tz)
	assert_almost_eq(roundtrip.x, z.x, 0.01, "T⁻¹(T(z)) x roundtrip")
	assert_almost_eq(roundtrip.y, z.y, 0.01, "T⁻¹(T(z)) y roundtrip")

func test_invert_anticonformal_compose_identity() -> void:
	var m := MobiusTransform.new(Vector2(3, 4), Vector2(5, 0), Vector2(1, 0), Vector2(-3, 4), true)
	var inv := m.invert()
	var composed := m.compose(inv)
	var z := Vector2(7, -2)
	var result := composed.apply(z)
	assert_almost_eq(result.x, z.x, 0.01, "M∘M⁻¹ should be identity x (anticonformal)")
	assert_almost_eq(result.y, z.y, 0.01, "M∘M⁻¹ should be identity y (anticonformal)")

func test_apply_infinity_no_nan() -> void:
	var transforms: Array[MobiusTransform] = [
		MobiusTransform.identity(),
		MobiusTransform.new(Vector2(0, 1), Vector2(3, 2), Vector2(0, 0), Vector2(1, 0), false),
		MobiusTransform.new(Vector2(0, 0), Vector2(1, 0), Vector2(1, 0), Vector2(0, 0), true),
		MobiusTransform.new(Vector2(200, 200), Vector2(-80000, 0), Vector2(1, 0), Vector2(-200, 200), true),
	]
	for m in transforms:
		var result := m.apply(Vector2(INF, INF))
		assert_false(is_nan(result.x), "apply(INF) must not produce NaN x (id=%d)" % m.id)
		assert_false(is_nan(result.y), "apply(INF) must not produce NaN y (id=%d)" % m.id)
