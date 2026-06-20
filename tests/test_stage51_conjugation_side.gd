extends GutTest

const H := preload("res://tests/test_helpers.gd")

func before_each() -> void:
	H.reset_counters()

# --- Scene setup (same as test_inversion_normalization._build_debug_scene) ---

func _build_scene() -> Dictionary:
	var room_walls := RoomBuilder.create_room_surfaces(Rect2(160, 90, 1600, 900))
	var mirror_left := _mirror_line(Vector2(500, 200), Vector2(500, 700))
	var mirror_right := _mirror_line(Vector2(1400, 300), Vector2(1400, 800))
	var mirror_bottom := _mirror_line(Vector2(700, 800), Vector2(1200, 800))
	var mirror_mid := _mirror_right_line(Vector2(960, 200), Vector2(960, 500))
	var inv_seg := Segment.from_coords(Vector2(1100, 400), Vector2(1100, 700), Vector2(1230, 550))
	var inv_effect := CircleInversionEffect.new(inv_seg.get_carrier())
	var inv_surf := Surface.new(inv_seg, SideConfig.new(inv_effect, true), SideConfig.new(null, false), false, true)
	var screen_bounds := _screen_bounds()
	var surfaces: Array = []
	surfaces.append_array(room_walls)
	surfaces.append(mirror_left)
	surfaces.append(mirror_right)
	surfaces.append(mirror_bottom)
	surfaces.append(mirror_mid)
	surfaces.append(inv_surf)
	surfaces.append_array(screen_bounds)
	return {
		"surfaces": surfaces,
		"inversion": inv_surf,
		"mirror_bottom": mirror_bottom,
	}

func _mirror_line(start: Vector2, end_v: Vector2) -> Surface:
	var mid := (start + end_v) / 2.0
	var seg := Segment.from_coords(start, end_v, mid)
	var refl := ReflectionEffect.new(seg.get_carrier())
	return Surface.new(seg, SideConfig.new(refl, true), SideConfig.new(null, false), false, false)

func _mirror_right_line(start: Vector2, end_v: Vector2) -> Surface:
	var mid := (start + end_v) / 2.0
	var seg := Segment.from_coords(start, end_v, mid)
	var refl := ReflectionEffect.new(seg.get_carrier())
	return Surface.new(seg, SideConfig.new(null, false), SideConfig.new(refl, true), false, false)

func _screen_bounds() -> Array:
	var result: Array = []
	var bounds_defs := [
		[Vector2(0, 0), Vector2(1920, 0)],
		[Vector2(1920, 0), Vector2(1920, 1080)],
		[Vector2(1920, 1080), Vector2(0, 1080)],
		[Vector2(0, 1080), Vector2(0, 0)],
	]
	for bd in bounds_defs:
		var s: Vector2 = bd[0]
		var e: Vector2 = bd[1]
		var config := SideConfig.new(null, false)
		result.append(Surface.new(Segment.from_coords(s, e, (s + e) / 2.0), config, config, false, false))
	return result

# ==========================================================================
# Regression tests — these must FAIL before the fix, PASS after
# ==========================================================================

func test_no_spurious_inversion_after_reflection() -> void:
	var scene := _build_scene()
	var player := Vector2(844.6, 551.4)
	var aim := Direction.from_coords(player, Vector2(979.0, 767.4))
	var path := Tracer.trace(player, aim, scene.surfaces, GameState.new())

	var found_conjugating := false
	var entered_arc_mode := false
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame != null and s.frame.conjugating:
			found_conjugating = true
		if s.frame != null and s.frame.maps_lines_to_arcs():
			entered_arc_mode = true

	assert_true(found_conjugating,
		"After reflecting off mirror, frame should be conjugating")
	assert_false(entered_arc_mode,
		"Should NOT enter arc mode — ray hit pass-through side of inversion arc")

func test_pass_through_side_respected_after_reflection() -> void:
	var scene := _build_scene()
	var player := Vector2(844.6, 551.4)
	var aim := Direction.from_coords(player, Vector2(979.0, 767.4))
	var path := Tracer.trace(player, aim, scene.surfaces, GameState.new())

	var frame_count := 0
	var prev_frame_id := -1
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame_id != prev_frame_id:
			frame_count += 1
			prev_frame_id = s.frame_id

	assert_lte(frame_count, 2,
		"Should have at most 2 frames (identity + one reflection). Got %d — inversion was wrongly triggered" % frame_count)

func test_winding_stable_under_conjugation_circle() -> void:
	var mirror_seg := Segment.from_coords(Vector2(700, 800), Vector2(1200, 800), Vector2(950, 800))
	var refl := ReflectionEffect.new(mirror_seg.get_carrier())
	var tracked := refl.get_tracked_transform()

	var arc_seg := Segment.from_coords(Vector2(1100, 400), Vector2(1100, 700), Vector2(1230, 550))
	var w_orig := arc_seg._compute_winding()
	var norm_arc := arc_seg.transformed(tracked.inverse)
	var w_norm := norm_arc._compute_winding()

	var same_sign := (w_orig >= 0) == (w_norm >= 0)
	assert_true(same_sign,
		"Circle winding must be stable under conjugation (same sign). Got %.1f → %.1f" % [w_orig, w_norm])

# ==========================================================================
# Invariant tests — must PASS both before and after the fix
# ==========================================================================

func test_winding_stable_under_conjugation_line() -> void:
	var seg := Segment.from_coords(Vector2(700, 800), Vector2(1200, 800), Vector2(950, 800))
	var refl := ReflectionEffect.new(seg.get_carrier())
	var tracked := refl.get_tracked_transform()

	var w_orig := seg._compute_winding()
	var norm_seg := seg.transformed(tracked.inverse)
	var w_norm := norm_seg._compute_winding()

	var same_sign := (w_orig >= 0) == (w_norm >= 0)
	assert_true(same_sign,
		"Line winding must be stable under conjugation (same sign)")

func test_winding_identical_for_lines_after_unification() -> void:
	var seg := Segment.from_coords(Vector2(700, 800), Vector2(1200, 800), Vector2(950, 800))
	var refl := ReflectionEffect.new(seg.get_carrier())
	var tracked := refl.get_tracked_transform()
	var norm_seg := seg.transformed(tracked.inverse)

	var w_orig := seg._compute_winding()
	var w_norm := norm_seg._compute_winding()

	assert_almost_eq(w_orig, w_norm, 0.001,
		"Line winding should be numerically identical before and after conjugation")

# ==========================================================================
# Carrier identity tests — same_circle and is_inverse_of
# ==========================================================================

func test_same_circle_exact_equality() -> void:
	var c1 := GeneralizedCircle.new(1.0, -2200.0, -1100.0, 907475.0)
	var c2 := GeneralizedCircle.new(1.0, -2200.0, -1100.0, 907475.0)
	assert_true(c1.same_circle(c2),
		"Two GeneralizedCircles with identical coefficients should be same_circle")

	var c3 := GeneralizedCircle.new(1.0, -2200.0, -1100.0, 999999.0)
	assert_false(c1.same_circle(c3),
		"GeneralizedCircles with different coefficients should NOT be same_circle")

	assert_true(c1.same_circle(c1),
		"A circle should be same_circle with itself (reference equality fast path)")

func test_source_based_cancellation() -> void:
	var scene := _build_scene()
	var inv_surf: Surface = scene.inversion

	var inv_seg := inv_surf.segment
	var inv_carrier := inv_seg.get_carrier()
	var inv_effect := CircleInversionEffect.new(inv_carrier)
	var t1 := inv_effect.get_tracked_transform()

	var inv_carrier2 := GeneralizedCircle.new(inv_carrier.a, inv_carrier.b, inv_carrier.c, inv_carrier.d)
	var inv_effect2 := CircleInversionEffect.new(inv_carrier2)
	var t2 := inv_effect2.get_tracked_transform()

	assert_false(t1.is_inverse_of(t2),
		"is_inverse_of uses reference equality — different objects should not match")
	assert_true(inv_carrier.same_circle(inv_carrier2),
		"But same_circle recognizes them as the same mathematical circle")

	assert_true(t1.inverse == t1, "t1 is self-inverse")
	assert_true(t2.inverse == t2, "t2 is self-inverse")

# ==========================================================================
# Arc rehit tests — second hit on same arc after inversion (grazing)
# ==========================================================================

func test_arc_rehit_after_mirror_reflection() -> void:
	var scene := _build_scene()
	var player := Vector2(992.7743, 577.3065)
	var aim := Direction.from_coords(player, Vector2(1068.113, 737.3656))
	var path := Tracer.trace(player, aim, scene.surfaces, GameState.new())

	var has_arc_frame := false
	var arc_frame_exits := false
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		var arc := s.frame != null and s.frame.maps_lines_to_arcs()
		var conj := s.frame != null and s.frame.conjugating
		gut.p("step %d: %s→%s fid=%d arc=%s conj=%s hit=%s" % [
			i, s.start, s.end, s.frame_id, arc, conj,
			"t=%.4f side=%d on=%s" % [s.hit.t, s.hit.side, s.hit.on_segment] if s.hit else "none"])
		if arc:
			has_arc_frame = true
		elif has_arc_frame:
			arc_frame_exits = true

	assert_true(has_arc_frame,
		"Ray should enter arc mode after hitting inversion surface")
	assert_true(arc_frame_exits,
		"Ray should EXIT arc mode — second hit on arc should cancel inversion (grazing)")

func test_diag_shortcut_triggers_single_transform() -> void:
	# In the SIMPLE case (single transform), the shortcut in segment.transformed()
	# DOES trigger because the tracked transform's carrier is the SAME OBJECT as the
	# segment's carrier. This makes the arc map to itself → second hit guaranteed.
	var inv_seg := Segment.from_coords(Vector2(1100, 400), Vector2(1100, 700), Vector2(1230, 550))
	var inv_effect := CircleInversionEffect.new(inv_seg.get_carrier())
	var inv_tracked := inv_effect.get_tracked_transform()

	# The tracked transform's carrier should be the SAME OBJECT as the segment's carrier
	var same_ref := (inv_tracked.carrier == inv_seg.get_carrier())
	gut.p("Single transform: tracked.carrier == seg.carrier → %s (reference equality)" % same_ref)
	assert_true(same_ref, "Single transform: tracked carrier should be same object as segment carrier")

	# The self-inverse shortcut should trigger
	var is_self_inv := (inv_tracked.inverse == inv_tracked)
	gut.p("  is self-inverse: %s" % is_self_inv)
	assert_true(is_self_inv, "Inversion should be self-inverse")

	# The segment.transformed should return SELF (shortcut)
	var result := inv_seg.transformed(inv_tracked)
	var is_self := (result == inv_seg)
	gut.p("  segment.transformed returns self: %s" % is_self)
	assert_true(is_self, "Self-inverse shortcut should return the same segment")

func test_diag_shortcut_fails_after_normalization() -> void:
	# In the COMPLEX case (mirror + inversion), _normalize_config creates a NEW effect
	# with the REFLECTED carrier. This new effect's tracked transform has a DIFFERENT
	# carrier object, so the shortcut in segment.transformed() DOES NOT trigger.
	var scene := _build_scene()
	var inv_surf: Surface = scene.inversion
	var mirror_bottom: Surface = scene.mirror_bottom

	# Step 1: Get the mirror's tracked transform
	var mirror_tracked := (mirror_bottom.active_side_config(
		Side.Value.LEFT, GameState.new()).effect as TransformativeEffect).get_tracked_transform()

	# Step 2: Normalize the inversion surface in the mirror frame
	# (this is what _build_normalized does)
	var norm_inv_seg := inv_surf.segment.transformed(mirror_tracked.inverse)
	var norm_inv_carrier := norm_inv_seg.get_carrier()

	# Step 3: _normalize_config creates a new effect with the normalized carrier
	var orig_inv_effect := inv_surf.active_side_config(
		Side.Value.LEFT, GameState.new()).effect as CircleInversionEffect
	var norm_inv_effect := orig_inv_effect.normalized(norm_inv_carrier)

	# The normalized effect should be a DIFFERENT object (new carrier)
	var same_effect := (norm_inv_effect == orig_inv_effect)
	gut.p("Normalized effect is same object: %s" % same_effect)
	assert_false(same_effect,
		"Normalized effect should be a NEW object (reflected carrier differs from original)")

	# Step 4: The normalized effect's tracked transform has the REFLECTED carrier
	var norm_inv_tracked := (norm_inv_effect as TransformativeEffect).get_tracked_transform()
	var carrier_match := (norm_inv_tracked.carrier == inv_surf.segment.get_carrier())
	gut.p("norm_tracked.carrier == original segment carrier: %s (reference eq)" % carrier_match)
	assert_false(carrier_match,
		"Normalized tracked carrier should NOT match original segment carrier")

	# Step 5: When this tracked transform is used to normalize the arc in the NEXT frame,
	# the shortcut FAILS because carriers don't match
	var shortcut_would_trigger := (
		norm_inv_tracked.carrier != null
		and norm_inv_tracked.inverse == norm_inv_tracked
		and inv_surf.segment.get_carrier() != null
		and norm_inv_tracked.carrier == inv_surf.segment.get_carrier()
	)
	gut.p("Shortcut would trigger for original arc: %s" % shortcut_would_trigger)
	assert_false(shortcut_would_trigger,
		"Shortcut FAILS: norm tracked carrier != original segment carrier → arc gets doubly-transformed")

	# Step 6: Without the shortcut, the arc is transformed to a DIFFERENT position.
	# The ray origin can't reach this position → no second intersection → no grazing.
	var doubly_transformed := inv_surf.segment.transformed(norm_inv_tracked)
	var dt_carrier := doubly_transformed.get_carrier()
	var orig_carrier := inv_surf.segment.get_carrier()
	gut.p("Original arc carrier: center=%s r=%.2f" % [orig_carrier.center(), orig_carrier.radius()])
	gut.p("Doubly-transformed carrier: center=%s r=%.2f" % [dt_carrier.center(), dt_carrier.radius()])

	# The doubly-transformed carrier should be at a DIFFERENT position
	var center_dist := orig_carrier.center().distance_to(dt_carrier.center())
	gut.p("Center distance: %.4f" % center_dist)
	assert_gt(center_dist, 1.0,
		"Doubly-transformed arc is at a different position — ray can't reach it for second hit")

func test_origin_carrier_matches_normalized_segment() -> void:
	var scene := _build_scene()
	var inv_surf: Surface = scene.inversion
	var mirror_bottom: Surface = scene.mirror_bottom

	var mirror_tracked := (mirror_bottom.active_side_config(
		Side.Value.LEFT, GameState.new()).effect as TransformativeEffect).get_tracked_transform()
	var inv_tracked := (inv_surf.active_side_config(
		Side.Value.LEFT, GameState.new()).effect as TransformativeEffect).get_tracked_transform()

	var transform_stack := [mirror_tracked, inv_tracked]
	var frame := MobiusTransform.identity()
	frame = frame.compose(mirror_tracked.mobius)
	frame = frame.compose(inv_tracked.mobius)

	var norm_to_surface := {}
	var norm_surfaces := Tracer._build_normalized(
		scene.surfaces, frame, norm_to_surface, null, transform_stack)

	var norm_inv_seg: Segment = null
	for ns in norm_surfaces:
		if norm_to_surface.get(ns.segment) == inv_surf:
			norm_inv_seg = ns.segment
			break

	assert_not_null(norm_inv_seg, "Should find normalized inversion segment")

	var orig_carrier := inv_surf.segment.get_carrier()
	var norm_carrier := norm_inv_seg.get_carrier()

	gut.p("Original carrier: a=%.6f b=%.6f c=%.6f d=%.6f" % [
		orig_carrier.a, orig_carrier.b, orig_carrier.c, orig_carrier.d])
	gut.p("Normalized carrier: a=%.6f b=%.6f c=%.6f d=%.6f" % [
		norm_carrier.a, norm_carrier.b, norm_carrier.c, norm_carrier.d])

	var carriers_differ := (
		absf(orig_carrier.a - norm_carrier.a) > 0.01 or
		absf(orig_carrier.b - norm_carrier.b) > 0.01 or
		absf(orig_carrier.c - norm_carrier.c) > 0.01 or
		absf(orig_carrier.d - norm_carrier.d) > 0.01)

	assert_true(carriers_differ,
		"Under mirror+inversion, normalized carrier must differ from original — using original is wrong")

# ==========================================================================
# Investigation: Premature trace termination in arc mode
# ==========================================================================

func _kind_name(effect: Effect) -> String:
	if effect == null:
		return "null"
	return ["PASS", "TERMINAL", "TRANSFORMATIVE", "PROJECTIVE"][effect.kind()]

func test_trace_continues_past_arc_mode() -> void:
	var scene := _build_scene()
	var player := Vector2(960.0, 540.0)
	var aim := Direction.from_coords(player, Vector2(1051.095, 751.3915))
	var path := Tracer.trace(player, aim, scene.surfaces, GameState.new())

	var surfaces: Array = scene.surfaces
	gut.p("=== Surface catalog ===")
	for i in surfaces.size():
		var surf: Surface = surfaces[i]
		var c := surf.segment.get_carrier()
		var lc := surf.active_side_config(Side.Value.LEFT, GameState.new())
		var rc := surf.active_side_config(Side.Value.RIGHT, GameState.new())
		var ek_l := _kind_name(lc.effect if lc else null)
		var ek_r := _kind_name(rc.effect if rc else null)
		gut.p("  surf[%d] id=%d carrier=(a=%.2f b=%.2f c=%.2f d=%.2f) L=%s R=%s" % [
			i, surf.id, c.a, c.b, c.c, c.d, ek_l, ek_r])

	gut.p("=== Trace steps (%d total) ===" % path.steps.size())
	var has_arc_frame := false
	var arc_frame_exits := false
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		var arc := s.frame != null and s.frame.maps_lines_to_arcs()
		var conj := s.frame != null and s.frame.conjugating
		var hit_info := "no-hit"
		if s.hit:
			var hc := s.hit.segment.get_carrier()
			hit_info = "t=%.4f side=%d on=%s ep=%d bl=%s br=%s carrier=(a=%.4f b=%.4f c=%.4f d=%.4f)" % [
				s.hit.t, s.hit.side, s.hit.on_segment, s.hit.at_endpoint,
				s.hit.blocked_left, s.hit.blocked_right,
				hc.a, hc.b, hc.c, hc.d]
		gut.p("  step[%d]: %s → %s fid=%d arc=%s conj=%s %s" % [
			i, s.start, s.end, s.frame_id, arc, conj, hit_info])
		if arc:
			has_arc_frame = true
		elif has_arc_frame:
			arc_frame_exits = true

	# Build ARC frame normalization manually to identify P4's surface
	var inv_surf: Surface = scene.inversion
	var mirror_bottom: Surface = scene.mirror_bottom
	var mirror_tracked := (mirror_bottom.active_side_config(
		Side.Value.LEFT, GameState.new()).effect as TransformativeEffect).get_tracked_transform()
	var inv_tracked := (inv_surf.active_side_config(
		Side.Value.LEFT, GameState.new()).effect as TransformativeEffect).get_tracked_transform()
	var arc_stack := [mirror_tracked, inv_tracked]
	var arc_frame := MobiusTransform.identity()
	arc_frame = arc_frame.compose(mirror_tracked.mobius)
	arc_frame = arc_frame.compose(inv_tracked.mobius)
	var arc_n2s := {}
	var arc_norms := Tracer._build_normalized(surfaces, arc_frame, arc_n2s, null, arc_stack)
	gut.p("=== ARC frame normalized surfaces ===")
	for ns in arc_norms:
		var ns_surf: Surface = ns
		var orig: Surface = arc_n2s.get(ns_surf.segment)
		var nc: GeneralizedCircle = ns_surf.segment.get_carrier()
		var lc2: SideConfig = ns_surf.active_side_config(Side.Value.LEFT, GameState.new())
		var rc2: SideConfig = ns_surf.active_side_config(Side.Value.RIGHT, GameState.new())
		var ek_l := _kind_name(lc2.effect if lc2 else null)
		var ek_r := _kind_name(rc2.effect if rc2 else null)
		gut.p("  orig_id=%d carrier=(a=%.4f b=%.4f c=%.4f d=%.4f) L=%s R=%s" % [
			orig.id if orig else -1, nc.a, nc.b, nc.c, nc.d, ek_l, ek_r])

	assert_true(has_arc_frame,
		"Ray should enter arc mode")
	assert_true(arc_frame_exits,
		"Ray should EXIT arc mode — trace should not stop prematurely in arc mode")

func test_norm_round_trip_accuracy() -> void:
	var scene := _build_scene()
	var surfaces: Array = scene.surfaces
	var inv_surf: Surface = scene.inversion
	var mirror_bottom: Surface = scene.mirror_bottom

	var mirror_tracked := (mirror_bottom.active_side_config(
		Side.Value.LEFT, GameState.new()).effect as TransformativeEffect).get_tracked_transform()

	var conj_n2s := {}
	var conj_norms := Tracer._build_normalized(
		surfaces, mirror_tracked.mobius, conj_n2s, null, [mirror_tracked])

	var conj_inv_surf: Surface = null
	for ns in conj_norms:
		if conj_n2s.get(ns.segment) == inv_surf:
			conj_inv_surf = ns
			break
	assert_not_null(conj_inv_surf, "Should find inversion in CONJ norms")
	var norm_inv_tracked := (conj_inv_surf.active_side_config(
		Side.Value.LEFT, GameState.new()).effect as TransformativeEffect).get_tracked_transform()

	var arc_stack := [mirror_tracked, norm_inv_tracked]
	var arc_frame := MobiusTransform.identity()
	arc_frame = arc_frame.compose(mirror_tracked.mobius)
	arc_frame = arc_frame.compose(norm_inv_tracked.mobius)

	var ref_n2s := {}
	var ref_norms := Tracer._build_normalized(
		surfaces, arc_frame, ref_n2s, null, arc_stack)

	gut.p("=== Round-trip invariant check (Euclidean distance) ===")
	var ref_max_err := 0.0

	for i in ref_norms.size():
		var ref_surf: Surface = ref_norms[i]
		var orig_ref: Surface = ref_n2s.get(ref_surf.segment)
		if orig_ref == null:
			continue
		var vis_pt := arc_frame.apply(ref_surf.segment.start.coords)
		if is_inf(vis_pt.x) or is_inf(vis_pt.y):
			continue
		var err := vis_pt.distance_to(orig_ref.segment.start.coords)
		if err > ref_max_err:
			ref_max_err = err
			gut.p("  ref: orig_id=%d start=%s → norm_start=%s → vis=%s err=%.4f" % [
				orig_ref.id, orig_ref.segment.start.coords,
				ref_surf.segment.start.coords, vis_pt, err])

	gut.p("  SUMMARY: ref_max_err=%.4f" % ref_max_err)

	assert_lt(ref_max_err, 1.0,
		"_build_normalized round-trip error should be < 1 pixel (got %.2f)" % ref_max_err)
