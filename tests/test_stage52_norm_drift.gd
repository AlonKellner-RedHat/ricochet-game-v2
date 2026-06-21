extends GutTest

const H := preload("res://tests/test_helpers.gd")

func before_each() -> void:
	H.reset_counters()

# ==========================================================================
# Stage A: GeneralizedCircle.transformed_by — Hermitian carrier transform
# ==========================================================================

func test_line_reflected_through_line_stays_line() -> void:
	var line_x0 := GeneralizedCircle.from_line(1.0, 0.0, 0.0)  # x = 0
	var mirror := GeneralizedCircle.from_line(1.0, 0.0, -500.0)  # x = 500
	var refl := ReflectionEffect.new(mirror)

	var result := line_x0.transformed_by(refl.get_tracked_transform().mobius)

	assert_true(result.is_line(), "Line reflected through line must stay a line")
	# x=0 reflected through x=500 → x=1000
	var test_point := Vector2(1000.0, 42.0)
	assert_almost_eq(result.evaluate(test_point), 0.0, 0.01,
		"Reflected line should pass through (1000, y)")

func test_circle_reflected_through_line_preserves_radius() -> void:
	var circle := GeneralizedCircle.from_circle(Vector2(300.0, 400.0), 100.0)
	var mirror := GeneralizedCircle.from_line(1.0, 0.0, -500.0)  # x = 500
	var refl := ReflectionEffect.new(mirror)

	var result := circle.transformed_by(refl.get_tracked_transform().mobius)

	assert_false(result.is_line(), "Circle reflected through line should stay a circle")
	assert_almost_eq(result.radius(), 100.0, 0.01,
		"Line reflection is isometry — radius must be preserved")
	# center (300,400) reflected through x=500 → (700,400)
	var ctr := result.center()
	assert_almost_eq(ctr.x, 700.0, 0.01, "Center x reflected through x=500")
	assert_almost_eq(ctr.y, 400.0, 0.01, "Center y unchanged by vertical reflection")

func test_line_reflected_through_circle_becomes_circle() -> void:
	var line_x0 := GeneralizedCircle.from_line(1.0, 0.0, 0.0)  # x = 0
	var circle := GeneralizedCircle.from_circle(Vector2(500.0, 500.0), 200.0)
	var refl := ReflectionEffect.new(circle)

	var result := line_x0.transformed_by(refl.get_tracked_transform().mobius)

	assert_false(result.is_line(),
		"Line reflected through circle should become a circle (a != 0)")

func test_transformed_by_identity_is_unchanged() -> void:
	var line := GeneralizedCircle.from_line(3.0, 4.0, -5.0)
	var identity := MobiusTransform.identity()

	var result := line.transformed_by(identity)

	# Coefficients should be proportional (same carrier up to scale)
	assert_true(result.is_line(), "Line through identity stays line")
	# Check that the carrier represents the same geometric object
	assert_almost_eq(result.evaluate(Vector2(5.0 / 3.0, 0.0)), 0.0, 0.01,
		"Same line after identity transform")

func test_conformal_compose_equals_sequential() -> void:
	var carrier := GeneralizedCircle.from_line(1.0, 0.0, 0.0)  # x = 0
	var mirror_a := GeneralizedCircle.from_line(1.0, 0.0, -300.0)  # x = 300
	var mirror_b := GeneralizedCircle.from_line(1.0, 0.0, -700.0)  # x = 700
	var R_a := ReflectionEffect.new(mirror_a).get_tracked_transform().mobius
	var R_b := ReflectionEffect.new(mirror_b).get_tracked_transform().mobius

	# Sequential: transform by R_a, then by R_b
	var seq := carrier.transformed_by(R_a).transformed_by(R_b)
	# Composed: compose R_a ∘ R_b, then transform once
	var composed := R_a.compose(R_b)
	var comp := carrier.transformed_by(composed)

	# Both should represent the same line (x = 0 → x = 600 → x = 800)
	assert_true(seq.is_line(), "Sequential result should be a line")
	assert_true(comp.is_line(), "Composed result should be a line")
	# Test at the expected position
	var test_pt := Vector2(800.0, 123.0)
	assert_almost_eq(seq.evaluate(test_pt), 0.0, 0.1, "Sequential: line at x=800")
	assert_almost_eq(comp.evaluate(test_pt), 0.0, 0.1, "Composed: line at x=800")

# --- Gradient-based carrier distance (numerically stable for all carrier types) ---

static func _carrier_dist(point: Vector2, carrier: GeneralizedCircle) -> float:
	var f := carrier.evaluate(point)
	var gx := 2.0 * carrier.a * point.x + carrier.b
	var gy := 2.0 * carrier.a * point.y + carrier.c
	var grad := sqrt(gx * gx + gy * gy)
	if grad < 1e-10:
		return INF
	return absf(f) / grad

static func _min_carrier_dist(point: Vector2, surfaces: Array) -> float:
	var min_d := INF
	for surf in surfaces:
		var s: Surface = surf
		var d := _carrier_dist(point, s.segment.get_carrier())
		if d < min_d:
			min_d = d
	return min_d

static func _is_at_bounds(p: Vector2) -> bool:
	var bounds := Rect2(0, 0, 1920, 1080)
	return (p.x <= bounds.position.x + 2.0 or p.x >= bounds.end.x - 2.0 or
		p.y <= bounds.position.y + 2.0 or p.y >= bounds.end.y - 2.0)

# ==========================================================================
# Stage B: Provenance-enforced normalization in _build_normalized
# ==========================================================================

func test_normalized_carrier_is_line_after_line_reflections() -> void:
	var room_walls := RoomBuilder.create_room_surfaces(Rect2(0, 0, 1920, 1080))
	var mirror_a := _mirror_line(Vector2(800.0, 0.0), Vector2(800.0, 1080.0))
	var mirror_b := _mirror_line(Vector2(1200.0, 0.0), Vector2(1200.0, 1080.0))

	var surfaces: Array = []
	surfaces.append_array(room_walls)
	surfaces.append(mirror_a)
	surfaces.append(mirror_b)

	# Build a deep stack of alternating line reflections
	var stack: Array = []
	for i in 12:
		var refl: TransformativeEffect = mirror_a.active_side_config(
			Side.Value.LEFT, GameState.new()).effect if i % 2 == 0 else mirror_b.active_side_config(
			Side.Value.LEFT, GameState.new()).effect
		stack.append(refl.get_tracked_transform())

	var frame := MobiusTransform.identity()
	for t in stack:
		frame = frame.compose(t.mobius)

	var n2s := {}
	var norms := Tracer._build_normalized(surfaces, frame, n2s, null, stack)

	# Every original line carrier should remain a line after normalization
	for ns in norms:
		var norm_surf: Surface = ns
		var orig_surf: Surface = n2s.get(norm_surf.segment)
		if orig_surf == null or norm_surf.segment == orig_surf.segment:
			continue
		if orig_surf.segment.get_carrier().is_line():
			assert_true(norm_surf.segment.get_carrier().is_line(),
				"Surface %d: line carrier must stay a line after 12 line reflections" % orig_surf.id)

func test_normalized_carrier_preserves_circle_radius() -> void:
	var mirror := _mirror_line(Vector2(500.0, 0.0), Vector2(500.0, 1080.0))
	var circle_seg := Segment.from_coords(
		Vector2(300.0, 300.0), Vector2(300.0, 500.0), Vector2(200.0, 400.0))
	var circle_carrier := circle_seg.get_carrier()
	assert_false(circle_carrier.is_line(), "Precondition: test surface is a circle")
	var orig_radius := circle_carrier.radius()

	var circle_surf := Surface.new(circle_seg,
		SideConfig.new(null, false), SideConfig.new(null, false), false, false)

	var surfaces: Array = [mirror, circle_surf]

	# Stack: 6 reflections in the same line mirror
	var refl_effect: TransformativeEffect = mirror.active_side_config(
		Side.Value.LEFT, GameState.new()).effect
	var stack: Array = []
	for i in 6:
		stack.append(refl_effect.get_tracked_transform())
	# After 6 self-inverse reflections, net is identity — but let's test with odd too
	stack.resize(5)  # 5 reflections: net = one reflection

	var frame := MobiusTransform.identity()
	for t in stack:
		frame = frame.compose(t.mobius)

	var n2s := {}
	var norms := Tracer._build_normalized(surfaces, frame, n2s, null, stack)

	for ns in norms:
		var norm_surf: Surface = ns
		var orig_surf: Surface = n2s.get(norm_surf.segment)
		if orig_surf != circle_surf or norm_surf.segment == orig_surf.segment:
			continue
		var norm_carrier := norm_surf.segment.get_carrier()
		assert_false(norm_carrier.is_line(),
			"Circle should stay a circle after line reflections")
		assert_almost_eq(norm_carrier.radius(), orig_radius, 0.01,
			"Circle radius must be preserved by isometric (line) reflections")

func test_normalized_carrier_through_circle_reflection_may_change_type() -> void:
	var circle_mirror_carrier := GeneralizedCircle.from_circle(Vector2(500.0, 500.0), 200.0)
	var circle_mirror_seg := Segment.full_from_carrier(circle_mirror_carrier)
	var circle_refl := ReflectionEffect.new(circle_mirror_carrier)
	var circle_mirror_surf := Surface.new(circle_mirror_seg,
		SideConfig.new(circle_refl, true), SideConfig.new(null, false), false, false)

	var line_seg := Segment.from_coords(Vector2(0.0, 0.0), Vector2(0.0, 1080.0), Vector2(0.0, 540.0))
	var line_surf := Surface.new(line_seg,
		SideConfig.new(null, false), SideConfig.new(null, false), false, false)

	var surfaces: Array = [circle_mirror_surf, line_surf]

	var stack: Array = [circle_refl.get_tracked_transform()]
	var frame := circle_refl.get_tracked_transform().mobius

	var n2s := {}
	var norms := Tracer._build_normalized(surfaces, frame, n2s, null, stack)

	for ns in norms:
		var norm_surf: Surface = ns
		var orig_surf: Surface = n2s.get(norm_surf.segment)
		if orig_surf != line_surf or norm_surf.segment == orig_surf.segment:
			continue
		# A line reflected through a circle should NOT be forced to stay a line
		assert_false(norm_surf.segment.get_carrier().is_line(),
			"Line reflected through circle should become a circle (no provenance enforcement)")

# ==========================================================================
# TDD: These tests should FAIL before the fix, PASS after
# ==========================================================================

func test_visual_endpoints_on_original_carriers() -> void:
	var scene: Node = load("res://scenes/test_levels/three_mirrors.tscn").instantiate()
	scene.gravity = Vector2.ZERO
	add_child_autofree(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var surfaces: Array = scene.surfaces
	var renderer := scene.get_node("PathRenderer")
	var player := scene.get_node("Player")
	var cursor := scene.get_node("Cursor")

	player.position = Vector2(1229.4, 516.7)
	cursor.position = Vector2(1000.0, 550.0)

	renderer._compute_trace()

	var path: Tracer.TracedPath = renderer.get_planned_path()
	assert_not_null(path, "Should have a planned path")
	assert_gt(path.steps.size(), 4, "Should have enough steps to trigger deep frames")

	var max_dist := 0.0
	var worst_step := -1
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		if step.hit == null or step.hit.segment == null:
			continue
		var end_pos := step.end
		if is_inf(end_pos.x) or is_inf(end_pos.y):
			continue
		if _is_at_bounds(end_pos):
			continue
		var dist := _min_carrier_dist(end_pos, surfaces)
		if dist > max_dist:
			max_dist = dist
			worst_step = i
		assert_lt(dist, 5.0,
			"Step %d visual endpoint %s should be within 5px of an original carrier (got %.2f)" % [i, end_pos, dist])

	gut.p("Max carrier distance: %.4f at step %d" % [max_dist, worst_step])

func test_normalized_coords_from_aggregated_frame() -> void:
	var scene := _build_scene()
	var surfaces: Array = scene.surfaces

	var mirror_bottom: Surface = scene.mirror_bottom
	var mirror_tracked := (mirror_bottom.active_side_config(
		Side.Value.LEFT, GameState.new()).effect as TransformativeEffect).get_tracked_transform()

	var conj_n2s := {}
	var conj_norms := Tracer._build_normalized(
		surfaces, mirror_tracked.mobius, conj_n2s, null, [mirror_tracked])

	var conj_inv_surf: Surface = null
	for ns in conj_norms:
		if conj_n2s.get(ns.segment) == scene.inversion:
			conj_inv_surf = ns
			break
	assert_not_null(conj_inv_surf, "Should find inversion in CONJ norms")
	var norm_inv_tracked := (conj_inv_surf.active_side_config(
		Side.Value.LEFT, GameState.new()).effect as TransformativeEffect).get_tracked_transform()

	var arc_stack := [mirror_tracked, norm_inv_tracked]
	var arc_frame := MobiusTransform.identity()
	arc_frame = arc_frame.compose(mirror_tracked.mobius)
	arc_frame = arc_frame.compose(norm_inv_tracked.mobius)
	var arc_frame_inv := arc_frame.invert()

	var arc_n2s := {}
	var arc_norms := Tracer._build_normalized(
		surfaces, arc_frame, arc_n2s, null, arc_stack)

	for i in arc_norms.size():
		var norm_surf: Surface = arc_norms[i]
		var orig_surf: Surface = arc_n2s.get(norm_surf.segment)
		if orig_surf == null:
			continue
		if norm_surf.segment == orig_surf.segment:
			continue

		var expected_start := arc_frame_inv.apply(orig_surf.segment.start.coords)
		var expected_end := arc_frame_inv.apply(orig_surf.segment.end.coords)
		var _expected_via := arc_frame_inv.apply(orig_surf.segment.via.coords)

		if is_inf(expected_start.x) or is_inf(expected_start.y):
			continue
		if is_inf(norm_surf.segment.start.coords.x) or is_inf(norm_surf.segment.start.coords.y):
			continue

		var err_start := norm_surf.segment.start.coords.distance_to(expected_start)
		var err_end := norm_surf.segment.end.coords.distance_to(expected_end)

		assert_lt(err_start, 1e-6,
			"Surface %d start should match frame_inv.apply(original) (err=%.6f)" % [orig_surf.id, err_start])
		if not (is_inf(expected_end.x) or is_inf(expected_end.y) or is_inf(norm_surf.segment.end.coords.x)):
			assert_lt(err_end, 1e-6,
				"Surface %d end should match frame_inv.apply(original) (err=%.6f)" % [orig_surf.id, err_end])

# --- Scene builder (same as test_stage51) ---

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
