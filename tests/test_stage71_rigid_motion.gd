extends GutTest

const TOL := Vector2(0.01, 0.01)

func _effect(theta: float = PI / 2.0, d: Vector2 = Vector2(100, 50)) -> RigidMotionEffect:
	return RigidMotionEffect.new(theta, d)

func _line_seg() -> Segment:
	return Segment.from_coords(Vector2(100, 200), Vector2(200, 200), Vector2(150, 200))

func _arc_seg() -> Segment:
	return Segment.from_coords(Vector2(300, 200), Vector2(200, 300), Vector2(270.71, 270.71))

# --- Construction ---

func test_stage71_rigid_motion_construction() -> void:
	var eff := _effect()
	assert_not_null(eff, "Effect constructed")
	assert_false(eff.get_mobius().conjugating, "Conformal (conjugating=false)")
	assert_true(eff.is_transformative(), "Is transformative")

func test_stage71_rigid_motion_conformal() -> void:
	var eff := _effect()
	assert_false(eff.get_mobius().conjugating, "Rigid motion is conformal")
	var inv := eff.get_inverse_mobius()
	assert_false(inv.conjugating, "Inverse is also conformal")

func test_stage71_rigid_motion_coefficients() -> void:
	var m := _effect().get_mobius()
	assert_almost_eq(Vector2(m.a_re, m.a_im), Vector2(0, 1), TOL, "alpha = e^{i*PI/2} = (0,1)")
	assert_almost_eq(Vector2(m.b_re, m.b_im), Vector2(100, 50), TOL, "beta = d = (100,50)")
	assert_almost_eq(Vector2(m.c_re, m.c_im), Vector2(0, 0), TOL, "gamma = 0")
	assert_almost_eq(Vector2(m.d_re, m.d_im), Vector2(1, 0), TOL, "delta = 1")

# --- Application ---

func test_stage71_rigid_motion_apply() -> void:
	var eff := RigidMotionEffect.new(PI / 2.0, Vector2(100, 0))
	var result := eff.get_mobius().apply(Vector2(1, 0))
	assert_almost_eq(result, Vector2(100, 1), TOL,
		"e^{iPI/2}*(1,0) + (100,0) = (0,1) + (100,0) = (100,1)")

func test_stage71_rigid_motion_pure_translation() -> void:
	var eff := RigidMotionEffect.new(0.0, Vector2(50, 0))
	var result := eff.get_mobius().apply(Vector2(10, 20))
	assert_almost_eq(result, Vector2(60, 20), TOL, "Pure translation: (10,20) + (50,0) = (60,20)")

func test_stage71_rigid_motion_pure_rotation() -> void:
	var eff := RigidMotionEffect.new(PI, Vector2.ZERO)
	var result := eff.get_mobius().apply(Vector2(1, 0))
	assert_almost_eq(result, Vector2(-1, 0), TOL, "Rotation by PI: (1,0) -> (-1,0)")

func test_stage71_rigid_motion_identity_case() -> void:
	var eff := RigidMotionEffect.new(0.0, Vector2.ZERO)
	var result := eff.get_mobius().apply(Vector2(5, 7))
	assert_almost_eq(result, Vector2(5, 7), TOL, "Identity: (5,7) -> (5,7)")

# --- Inverse ---

func test_stage71_rigid_motion_inverse_coefficients() -> void:
	var inv := _effect().get_inverse_mobius()
	assert_almost_eq(Vector2(inv.a_re, inv.a_im), Vector2(0, -1), TOL, "inverse alpha = e^{-iPI/2} = (0,-1)")
	# inv_beta = -e^{-iPI/2} * (100,50) = -(0,-1)*(100,50) = -(50,-100) = (-50,100)
	assert_almost_eq(Vector2(inv.b_re, inv.b_im), Vector2(-50, 100), TOL, "inverse beta = -e^{-iPI/2}*d")
	assert_almost_eq(Vector2(inv.c_re, inv.c_im), Vector2(0, 0), TOL, "inverse gamma = 0")
	assert_almost_eq(Vector2(inv.d_re, inv.d_im), Vector2(1, 0), TOL, "inverse delta = 1")

func test_stage71_rigid_motion_not_self_inverse() -> void:
	var eff := _effect()
	var z := Vector2(10, 20)
	var fwd := eff.get_mobius().apply(z)
	assert_true(fwd.distance_to(z) > 1.0, "Forward != original (not self-inverse)")
	var back := eff.get_inverse_mobius().apply(fwd)
	assert_almost_eq(back, z, TOL, "inverse(forward(z)) == z")

func test_stage71_get_inverse_mobius_correct() -> void:
	var eff := _effect()
	var z := Vector2(42, 99)
	var fwd := eff.get_mobius().apply(z)
	var back := eff.get_inverse_mobius().apply(fwd)
	assert_almost_eq(back, z, TOL,
		"get_inverse_mobius() returns actual inverse, not _mobius")
	var m := eff.get_mobius()
	var inv := eff.get_inverse_mobius()
	assert_true(m.id != inv.id, "Forward and inverse have different IDs")

# --- Portal pair: line source ---

func test_stage71_portal_pair_translated() -> void:
	var seg := _line_seg()
	var result := RigidMotionEffect.create_portal_pair(seg, 0.0, Vector2(0, 200))
	var target: Segment = result.target_segment
	assert_almost_eq(target.start.coords, Vector2(100, 400), TOL, "start translated by (0,200)")
	assert_almost_eq(target.end.coords, Vector2(200, 400), TOL, "end translated by (0,200)")
	assert_almost_eq(target.via.coords, Vector2(150, 400), TOL, "via translated by (0,200)")

func test_stage71_portal_pair_rotated() -> void:
	var seg := _line_seg()
	var result := RigidMotionEffect.create_portal_pair(seg, PI / 2.0, Vector2(100, 0))
	var target: Segment = result.target_segment
	# T((100,200)) = e^{iPI/2}*(100,200) + (100,0) = (-200,100) + (100,0) = (-100,100)
	assert_almost_eq(target.start.coords, Vector2(-100, 100), TOL, "start rotated+translated")
	# T((200,200)) = e^{iPI/2}*(200,200) + (100,0) = (-200,200) + (100,0) = (-100,200)
	assert_almost_eq(target.end.coords, Vector2(-100, 200), TOL, "end rotated+translated")

func test_stage71_portal_pair_inverse_composition() -> void:
	var seg := _line_seg()
	var result := RigidMotionEffect.create_portal_pair(seg, PI / 3.0, Vector2(50, -75))
	var fwd = result.source_effect.get_mobius()
	var inv = result.target_effect.get_mobius()
	var points := [Vector2(0, 0), Vector2(100, 200), Vector2(-50, 300), Vector2(999, 1)]
	for p in points:
		var roundtrip = inv.apply(fwd.apply(p))
		assert_almost_eq(roundtrip, p, TOL,
			"T_BA(T_AB(%s)) == %s (identity composition)" % [p, p])

func test_stage71_portal_pair_tracked_linking() -> void:
	var seg := _line_seg()
	var result := RigidMotionEffect.create_portal_pair(seg, PI / 4.0, Vector2(100, 100))
	var tracked_a: TrackedTransform = result.source_effect.get_tracked_transform()
	var tracked_b: TrackedTransform = result.target_effect.get_tracked_transform()
	assert_true(tracked_a.is_inverse_of(tracked_b),
		"tracked_a is inverse of tracked_b")
	assert_true(tracked_b.is_inverse_of(tracked_a),
		"tracked_b is inverse of tracked_a")
	assert_false(tracked_a.inverse == tracked_a,
		"tracked_a is NOT self-inverse")

# --- Portal pair: arc source ---

func test_stage71_portal_pair_arc_translated() -> void:
	var seg := _arc_seg()
	var result := RigidMotionEffect.create_portal_pair(seg, 0.0, Vector2(300, 0))
	var target: Segment = result.target_segment
	assert_almost_eq(target.start.coords, Vector2(600, 200), TOL, "arc start translated")
	assert_almost_eq(target.end.coords, Vector2(500, 300), TOL, "arc end translated")
	var target_carrier := target.get_carrier()
	var source_carrier := seg.get_carrier()
	assert_false(target_carrier.is_line(), "Target carrier is a circle")
	assert_almost_eq(target_carrier.radius(), source_carrier.radius(), 0.01,
		"Same radius after translation")

func test_stage71_portal_pair_arc_rotated() -> void:
	var seg := _arc_seg()
	var result := RigidMotionEffect.create_portal_pair(seg, PI / 4.0, Vector2.ZERO)
	var target: Segment = result.target_segment
	var fwd = result.source_effect.get_mobius()
	assert_almost_eq(target.via.coords, fwd.apply(seg.via.coords), TOL,
		"via_B.coords == T(via_A.coords)")
	var target_carrier := target.get_carrier()
	var source_carrier := seg.get_carrier()
	assert_almost_eq(target_carrier.radius(), source_carrier.radius(), 0.01,
		"Same radius after rotation")

func test_stage71_portal_pair_arc_inverse_composition() -> void:
	var seg := _arc_seg()
	var result := RigidMotionEffect.create_portal_pair(seg, PI / 6.0, Vector2(100, -50))
	var fwd = result.source_effect.get_mobius()
	var inv = result.target_effect.get_mobius()
	var points := [Vector2(300, 200), Vector2(250, 250), Vector2(0, 0)]
	for p in points:
		var roundtrip = inv.apply(fwd.apply(p))
		assert_almost_eq(roundtrip, p, TOL,
			"Arc portal round-trip: T_BA(T_AB(%s)) == %s" % [p, p])

# --- Portal pair: provenance ---

func test_stage71_portal_pair_target_provenance() -> void:
	var seg := _line_seg()
	var result := RigidMotionEffect.create_portal_pair(seg, PI / 2.0, Vector2(50, 50))
	var target: Segment = result.target_segment
	assert_true(target.start.same_origin(seg.start),
		"Target start shares original coords with source start")
	assert_true(target.end.same_origin(seg.end),
		"Target end shares original coords with source end")
	assert_true(target.via.same_origin(seg.via),
		"Target via shares original coords with source via")

func test_stage71_portal_pair_provenance_round_trip() -> void:
	var seg := _line_seg()
	var result := RigidMotionEffect.create_portal_pair(seg, PI / 3.0, Vector2(200, 100))
	var target: Segment = result.target_segment
	var tracked_ba: TrackedTransform = result.target_effect.get_tracked_transform()
	var round_start := target.start.transformed(tracked_ba)
	assert_eq(round_start.coords, seg.start.coords,
		"Exact provenance round-trip: target.start -> source.start (not approximate)")
	var round_end := target.end.transformed(tracked_ba)
	assert_eq(round_end.coords, seg.end.coords,
		"Exact provenance round-trip: target.end -> source.end")

# --- Invariants ---

func test_stage71_S2_transform_round_trip() -> void:
	var eff := _effect()
	var z := Vector2(42, 99)
	var fwd := eff.get_mobius().apply(z)
	var back := eff.get_inverse_mobius().apply(fwd)
	assert_almost_eq(back, z, TOL, "S2: forward then inverse returns original")

func test_stage71_S18_determinant_nonzero() -> void:
	var m := _effect().get_mobius()
	var ad := MobiusTransform.cmul(Vector2(m.a_re, m.a_im), Vector2(m.d_re, m.d_im))
	var bc := MobiusTransform.cmul(Vector2(m.b_re, m.b_im), Vector2(m.c_re, m.c_im))
	var det := ad - bc
	var det_mod2 := MobiusTransform.cmod2(det)
	assert_true(det_mod2 > 0.0, "S18: |ad - bc|^2 > 0 (got %f)" % det_mod2)

func test_stage71_S16_no_nan_inf() -> void:
	var m := _effect().get_mobius()
	var points: Array[Vector2] = [
		Vector2(0, 0), Vector2(100, 200), Vector2(-50, -50),
		Vector2(300, 300), Vector2(1, 0), Vector2(0, 1),
		Vector2(9999, 9999), Vector2(-100, 50), Vector2(0.5, 0.5),
		Vector2(42, 99),
	]
	for p in points:
		var result := m.apply(p)
		assert_false(is_nan(result.x) or is_nan(result.y),
			"S16: no NaN for point %s (got %s)" % [p, result])
		assert_false(is_inf(result.x) or is_inf(result.y),
			"S16: no Inf for point %s (got %s)" % [p, result])

# --- Display ---

func test_stage71_display_name_and_color() -> void:
	var eff := _effect()
	assert_eq(eff.get_display_name(), "portal", "Display name is 'portal'")
	assert_eq(eff.get_display_color(), Color.CYAN, "Display color is CYAN")
