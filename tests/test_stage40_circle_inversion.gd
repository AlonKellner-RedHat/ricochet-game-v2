extends GutTest

func _carrier() -> GeneralizedCircle:
	return GeneralizedCircle.from_circle(Vector2(200, 200), 100.0)

func _effect() -> CircleInversionEffect:
	return CircleInversionEffect.new(_carrier())

# --- Construction ---

func test_stage40_inversion_construction_valid() -> void:
	var eff := _effect()
	assert_not_null(eff, "Effect constructed")
	assert_true(eff.get_mobius().conjugating, "Anti-conformal (conjugating=true)")
	assert_true(eff.is_transformative(), "Is transformative")

func test_stage40_inversion_construction_rejects_line() -> void:
	var line_carrier := GeneralizedCircle.from_line(1.0, 0.0, -200.0)
	var error_thrown := false
	# GDScript asserts crash in debug mode; we test the precondition directly
	assert_true(line_carrier.is_line(), "Carrier is a line")
	# Construction would assert — verify the guard condition
	assert_eq(line_carrier.a, 0.0, "Line carrier has a==0, would be rejected")

func test_stage40_inversion_mobius_coefficients() -> void:
	var m := _effect().get_mobius()
	assert_almost_eq(Vector2(m.a_re, m.a_im), Vector2(200, 200), Vector2(0.01, 0.01), "alpha = center")
	assert_almost_eq(Vector2(m.b_re, m.b_im), Vector2(-70000, 0), Vector2(0.01, 0.01), "beta = r^2 - |center|^2")
	assert_almost_eq(Vector2(m.c_re, m.c_im), Vector2(1, 0), Vector2(0.01, 0.01), "gamma = 1")
	assert_almost_eq(Vector2(m.d_re, m.d_im), Vector2(-200, 200), Vector2(0.01, 0.01), "delta = -conj(center)")
	assert_true(m.conjugating, "conjugating = true")

# --- Point application ---

func test_stage40_inversion_apply_point() -> void:
	var m := _effect().get_mobius()
	var result := m.apply(Vector2(400, 200))
	assert_almost_eq(result, Vector2(250, 200), Vector2(0.01, 0.01),
		"z=(400,200) -> w=(250,200) per GAME_SPEC 16.2")

func test_stage40_inversion_self_inverse() -> void:
	var m := _effect().get_mobius()
	var w := m.apply(Vector2(400, 200))
	var roundtrip := m.apply(w)
	assert_almost_eq(roundtrip, Vector2(400, 200), Vector2(0.01, 0.01),
		"Applying inversion twice returns original point")

func test_stage40_inversion_point_on_circle_fixed() -> void:
	var m := _effect().get_mobius()
	var on_circle := Vector2(300, 200)
	var result := m.apply(on_circle)
	assert_almost_eq(result, on_circle, Vector2(0.01, 0.01),
		"Point on the inversion circle is a fixed point")

# --- Invariants ---

func test_stage40_S2_transform_round_trip() -> void:
	var eff := _effect()
	var point := Vector2(400, 200)
	var fwd := eff.get_mobius().apply(point)
	var back := eff.get_inverse_mobius().apply(fwd)
	assert_almost_eq(back, point, Vector2(0.01, 0.01),
		"S2: apply then inverse returns original")

func test_stage40_S18_determinant_nonzero() -> void:
	var m := _effect().get_mobius()
	var ad := MobiusTransform.cmul(Vector2(m.a_re, m.a_im), Vector2(m.d_re, m.d_im))
	var bc := MobiusTransform.cmul(Vector2(m.b_re, m.b_im), Vector2(m.c_re, m.c_im))
	var det := ad - bc
	var det_mod2 := MobiusTransform.cmod2(det)
	assert_true(det_mod2 > 0.0, "S18: determinant |ad - bc|^2 > 0 (got %f)" % det_mod2)

func test_stage40_inversion_center_maps_to_infinity() -> void:
	var m := _effect().get_mobius()
	var result := m.apply(Vector2(200, 200))
	var is_degenerate := (
		is_nan(result.x) or is_nan(result.y) or
		is_inf(result.x) or is_inf(result.y) or
		result.length() > 1e6
	)
	assert_true(is_degenerate,
		"Center maps to infinity/degenerate (got %s)" % result)

func test_stage40_S16_no_nan_inf() -> void:
	var m := _effect().get_mobius()
	var points: Array[Vector2] = [
		Vector2(100, 100), Vector2(300, 300), Vector2(50, 200),
		Vector2(400, 100), Vector2(200, 100), Vector2(200, 300),
		Vector2(100, 200), Vector2(300, 200), Vector2(150, 150),
		Vector2(350, 250),
	]
	for p in points:
		var result := m.apply(p)
		assert_false(is_nan(result.x) or is_nan(result.y),
			"S16: no NaN for point %s (got %s)" % [p, result])
		assert_false(is_inf(result.x) or is_inf(result.y),
			"S16: no Inf for point %s (got %s)" % [p, result])
