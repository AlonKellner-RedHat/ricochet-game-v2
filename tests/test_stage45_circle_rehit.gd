extends GutTest

const H := preload("res://tests/test_helpers.gd")

func before_each() -> void:
	H.reset_counters()

func _full_circle_mirror(center: Vector2, r: float) -> Surface:
	# Gap at top of circle, away from horizontal ray intersections at left/right
	var seg := Segment.from_coords(
		Vector2(center.x + 0.01, center.y - r),
		Vector2(center.x - 0.01, center.y - r),
		Vector2(center.x, center.y + r))
	var refl := ReflectionEffect.new(seg.get_carrier())
	var config := SideConfig.new(refl, true)
	return Surface.new(seg, config, config, false, false)

func test_ray_hits_full_circle_twice() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	# No room walls — under circle inversion, walls map through the center
	# and their terminal effects would absorb the ray before the re-hit.
	var surfaces: Array = [surf]
	var player := Vector2(600, 540)
	var cursor := Vector2(1300, 540)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	var transitions: Array = []
	var prev_conj := false
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame.conjugating != prev_conj:
			transitions.append(s.frame.conjugating)
			prev_conj = s.frame.conjugating

	assert_true(transitions.size() >= 2,
		"Should transition identity→reflected→identity. Got transitions=%s" % [transitions])
	assert_true(transitions[0], "First transition should enter reflected frame")
	if transitions.size() >= 2:
		assert_false(transitions[1], "Second transition should return to identity")

	var reflected_steps := 0
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame.conjugating and s.hit != null:
			reflected_steps += 1
	assert_gt(reflected_steps, 0,
		"Should have at least one surface hit inside the reflected frame (the re-hit)")

func test_no_infinite_loop_from_same_point() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var surfaces: Array = [surf]
	var player := Vector2(600, 540)
	var cursor := Vector2(1300, 540)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	assert_lt(path.steps.size(), Tracer.MAX_HITS * 4,
		"Should be bounded by MAX_HITS. Got %d steps" % path.steps.size())


func _build_below_scene() -> Dictionary:
	var center := Vector2(960, 540)
	var r := 200.0
	var seg := Segment.from_coords(
		Vector2(center.x + r, center.y + 0.01),
		Vector2(center.x + r, center.y - 0.01),
		Vector2(center.x - r, center.y))
	var refl := ReflectionEffect.new(seg.get_carrier())
	var config := SideConfig.new(refl, true)
	var surf := Surface.new(seg, config, config, false, false)
	var walls := RoomBuilder.create_room_surfaces(Rect2(160, 90, 1600, 900))
	var surfaces: Array = [surf]
	surfaces.append_array(walls)
	return {"surfaces": surfaces, "bounds": Rect2(0, 0, 1920, 1080),
			"player": Vector2(960, 950), "center": center, "radius": r,
			"carrier": seg.get_carrier()}

func _aim_at_offset(player: Vector2, center: Vector2, offset_deg: float) -> Direction:
	var base_angle := (center - player).angle()
	var aim_angle := base_angle + deg_to_rad(offset_deg)
	var cursor := player + Vector2(cos(aim_angle), sin(aim_angle)) * 500.0
	return Direction.from_coords(player, cursor)


func test_grazing_angle_produces_reflected_arc() -> void:
	var scene := _build_below_scene()
	var surfaces: Array = scene["surfaces"]
	var player: Vector2 = scene["player"]
	var center: Vector2 = scene["center"]

	var aim := _aim_at_offset(player, center, 29.0)
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	assert_gte(path.steps.size(), 2,
		"Near-tangent ray at 29° should reflect and produce ≥2 steps, got %d" % path.steps.size())

	var aim_neg := _aim_at_offset(player, center, -29.0)
	var path_neg := Tracer.trace(player, aim_neg, surfaces, GameState.new())

	assert_gte(path_neg.steps.size(), 2,
		"Near-tangent ray at -29° should reflect and produce ≥2 steps, got %d" % path_neg.steps.size())

func test_arc_via_within_drawn_arc() -> void:
	var scene := _build_below_scene()
	var surfaces: Array = scene["surfaces"]
	var player: Vector2 = scene["player"]
	var center: Vector2 = scene["center"]

	var violations: Array[String] = []
	for angle_i in range(-28, 29):
		var angle := float(angle_i)
		var aim := _aim_at_offset(player, center, angle)
		var path := Tracer.trace(player, aim, surfaces, GameState.new())
		for i in path.steps.size():
			var step: Tracer.Step = path.steps[i]
			if not step.is_arc_step:
				continue
			if not VisualConverter.is_arc(step.start, step.via, step.end):
				continue
			var p := VisualConverter.arc_params(step.start, step.via, step.end)
			var ctr: Vector2 = p["center"]
			var sa: float = p["start_angle"]
			var span: float = p["span"]
			var cw: bool = p["clockwise"]
			var via_angle := (step.via - ctr).angle()
			var diff: float
			if cw:
				diff = fposmod(sa - via_angle, TAU)
			else:
				diff = fposmod(via_angle - sa, TAU)
			if diff > span + 0.01:
				violations.append("angle=%d step %d: diff=%.3f > span=%.3f" %
					[angle_i, i, diff, span])

	assert_eq(violations.size(), 0,
		"Via points must be on drawn arcs. Violations:\n%s" % "\n".join(violations))

func test_reflected_arc_symmetric_for_both_sides() -> void:
	# Rays hitting above vs below center must produce symmetric arcs —
	# same span, mirrored clockwise flags. Verifies the tracer logic is correct.
	var surf := _full_circle_mirror(Vector2(960, 540), 200.0)
	var walls := RoomBuilder.create_room_surfaces(Rect2(160, 90, 1600, 900))
	var surfaces: Array = [surf]
	surfaces.append_array(walls)
	var player := Vector2(600, 540)

	for dy in [20, 60, 100]:
		var aim_above := Direction.from_coords(player, Vector2(1300, 540 - dy))
		var aim_below := Direction.from_coords(player, Vector2(1300, 540 + dy))
		var path_above := Tracer.trace(player, aim_above, surfaces, GameState.new())
		var path_below := Tracer.trace(player, aim_below, surfaces, GameState.new())

		assert_eq(path_above.steps.size(), path_below.steps.size(),
			"dy=%d: both rays should produce same number of steps" % dy)

		for i in path_above.steps.size():
			var sa: Tracer.Step = path_above.steps[i]
			var sb: Tracer.Step = path_below.steps[i]
			if not sa.is_arc_step:
				continue
			if not VisualConverter.is_arc(sa.start, sa.via, sa.end):
				continue
			var pa := VisualConverter.arc_params(sa.start, sa.via, sa.end)
			var pb := VisualConverter.arc_params(sb.start, sb.via, sb.end)
			assert_almost_eq(pa["span"], pb["span"], 0.01,
				"dy=%d step %d: symmetric rays should have same arc span" % [dy, i])
			assert_ne(pa["clockwise"], pb["clockwise"],
				"dy=%d step %d: symmetric rays should have opposite clockwise flags" % [dy, i])

# --- Principle 1: Self-inverse carrier-fixed ---

func test_circle_segment_fixed_by_own_reflection() -> void:
	var scene := _build_below_scene()
	var surf: Surface = scene["surfaces"][0]
	var carrier := surf.segment.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var result := surf.segment.transformed(refl.get_tracked_transform())
	assert_eq(result, surf.segment,
		"Circle segment transformed by own reflection should return self")

func test_wall_segment_not_fixed_by_circle_reflection() -> void:
	var scene := _build_below_scene()
	var surf: Surface = scene["surfaces"][0]
	var wall: Surface = scene["surfaces"][1]
	var refl_tracked := surf.active_side_config(
		Side.Value.LEFT, GameState.new()).effect.get_tracked_transform()
	var result := wall.segment.transformed(refl_tracked)
	assert_ne(result, wall.segment,
		"Wall segment with different carrier should NOT return self")

# --- Principle 2: Round-trip cancellation ---

func test_wall_roundtrip_through_circle_reflection_preserves_carrier() -> void:
	var scene := _build_below_scene()
	var surf: Surface = scene["surfaces"][0]
	var wall: Surface = scene["surfaces"][1]
	var wall_carrier := wall.segment.get_carrier()
	var T := surf.active_side_config(
		Side.Value.LEFT, GameState.new()).effect.get_tracked_transform()
	var roundtrip := wall.segment.transformed(T).transformed(T)
	assert_eq(roundtrip.get_carrier(), wall_carrier,
		"Wall carrier should be same object after self-inverse roundtrip")

# --- Step 5a: Tracer double reflection identity ---

func test_double_reflection_frame_is_identity() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var surfaces: Array = [surf]
	var player := Vector2(600, 540)
	var cursor := Vector2(1300, 540)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	var post_double_found := false
	var in_reflected := false
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame.conjugating:
			in_reflected = true
		elif in_reflected and not s.frame.conjugating:
			post_double_found = true
			assert_eq(s.frame.id, MobiusTransform.IDENTITY_ID,
				"Post-double-reflection frame should be identity")
			assert_false(s.frame.maps_lines_to_arcs(),
				"Post-double-reflection should not map lines to arcs")
			assert_false(s.is_arc_step,
				"Post-double-reflection step should not be arc")
			break
	assert_true(post_double_found, "Should find post-double-reflection step")

# --- Step 6: End-to-end circle grazing scene verification ---

func test_circle_grazing_double_bounce_is_straight_line() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var surfaces: Array = [surf]
	var player := Vector2(600, 540)
	var violations: Array[String] = []
	for angle_i in range(-25, 26):
		var cursor := Vector2(1300, 540 + angle_i * 4)
		var aim := Direction.from_coords(player, cursor)
		var path := Tracer.trace(player, aim, surfaces, GameState.new())
		var in_reflected := false
		for i in path.steps.size():
			var s: Tracer.Step = path.steps[i]
			if s.frame.conjugating:
				in_reflected = true
			elif in_reflected:
				if s.frame_id != MobiusTransform.IDENTITY_ID:
					violations.append(
						"angle=%d step %d: post-double frame_id=%d, expected identity" %
						[angle_i, i, s.frame_id])
				if s.is_arc_step:
					violations.append(
						"angle=%d step %d: post-double step is arc, expected straight line" %
						[angle_i, i])
				break
	assert_eq(violations.size(), 0,
		"Circle grazing: post-double-reflection must be straight line.\n%s" %
		"\n".join(violations))

# --- Inner-side reflection investigation ---

func _semicircle_mirror(center: Vector2, r: float) -> Surface:
	var seg := Segment.from_coords(
		Vector2(center.x + r, center.y),
		Vector2(center.x - r, center.y),
		Vector2(center.x, center.y - r))
	var refl := ReflectionEffect.new(seg.get_carrier())
	var config := SideConfig.new(refl, true)
	return Surface.new(seg, config, config, false, false)

func _circle_center_from_frame(frame: MobiusTransform) -> Vector2:
	return frame.apply(Vector2(INF, INF))

func test_full_circle_inner_hit_produces_no_escape() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var surfaces: Array = [surf]
	# Player inside circle, aim left to hit left side (away from gap at top)
	var player := Vector2(960, 600)
	var aim := Direction.from_coords(player, Vector2(700, 540))
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	var circle_center := center
	var has_escape_to_center := false
	for step in path.steps:
		var s: Tracer.Step = step
		if s.start.distance_to(circle_center) < 5.0 or s.end.distance_to(circle_center) < 5.0:
			has_escape_to_center = true
			break

	assert_false(has_escape_to_center,
		"Inner-side hit should NOT produce escape arcs to circle center")

func test_semicircle_inner_hit_produces_no_escape() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _semicircle_mirror(center, r)
	var surfaces: Array = [surf]
	var player := Vector2(960, 640)
	var aim := Direction.from_coords(player, Vector2(860, 340))
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	var circle_center := center
	var has_escape_to_center := false
	for step in path.steps:
		var s: Tracer.Step = step
		if s.start.distance_to(circle_center) < 5.0 or s.end.distance_to(circle_center) < 5.0:
			has_escape_to_center = true
			break

	assert_false(has_escape_to_center,
		"Semicircle inner-side hit should NOT produce escape arcs to circle center")

func test_full_circle_inner_hit_returns_to_identity() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var surfaces: Array = [surf]
	# Player inside circle, aim left (away from gap at top)
	var player := Vector2(960, 600)
	var aim := Direction.from_coords(player, Vector2(700, 540))
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	var transitions: Array = []
	var prev_conj := false
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame.conjugating != prev_conj:
			transitions.append(s.frame.conjugating)
			prev_conj = s.frame.conjugating

	assert_true(transitions.size() >= 2,
		"Inner hit should transition identity->reflected->identity. Got transitions=%s" % [transitions])
	if transitions.size() >= 2:
		assert_true(transitions[0], "First transition should enter reflected frame")
		assert_false(transitions[1], "Second transition should return to identity")

func test_outer_hit_still_works() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var surfaces: Array = [surf]
	# Player outside circle, aim right to hit left side (away from gap at top)
	var player := Vector2(600, 540)
	var aim := Direction.from_coords(player, Vector2(1300, 540))
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	var transitions: Array = []
	var prev_conj := false
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame.conjugating != prev_conj:
			transitions.append(s.frame.conjugating)
			prev_conj = s.frame.conjugating

	assert_true(transitions.size() >= 2,
		"Outer hit should have at least one identity->reflected->identity cycle. Got transitions=%s" % [transitions])
	assert_true(transitions[0], "First transition should enter reflected frame")
	assert_false(transitions[1], "Second transition should return to identity")

func test_no_arcs_in_identity_frame_sweep() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var surfaces: Array = [surf]
	var player := Vector2(600, 540)
	var violations: Array[String] = []
	for angle_i in range(-25, 26):
		var cursor := Vector2(1300, 540 + angle_i * 4)
		var aim := Direction.from_coords(player, cursor)
		var path := Tracer.trace(player, aim, surfaces, GameState.new())
		for i in path.steps.size():
			var s: Tracer.Step = path.steps[i]
			if s.frame_id == MobiusTransform.IDENTITY_ID and s.is_arc_step:
				violations.append("angle=%d step %d: identity frame but is_arc_step" %
					[angle_i, i])
	assert_eq(violations.size(), 0,
		"No identity-frame step should be an arc.\n%s" % "\n".join(violations))

# --- Phase 2: Evidence collection ---

func test_diag_inner_hit_carrier_intersections_are_nonpositive() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var carrier := Segment.derive_carrier(
		Vector2(center.x + r, center.y),
		Vector2(center.x - r, center.y),
		Vector2(center.x, center.y - r))

	# Inner hit: from P going outward (away from circle)
	var P := Vector2(center.x - r, center.y)  # left side of circle
	var inner_dir := Direction.from_coords(P, P + Vector2(-1, 0))  # going left (outward)
	var inner_ray := Ray.from_coords(P, inner_dir)
	var inner_hits := Intersection.intersect_line_with_carrier(inner_ray, carrier)

	var all_nonpositive := true
	for hit in inner_hits:
		var t: float = hit["t"]
		if t > 0.0:
			all_nonpositive = false
	assert_true(all_nonpositive,
		"Inner direction: all carrier intersections should be t<=0. Got %s" %
		[inner_hits.map(func(h): return h["t"])])

func test_diag_outer_hit_carrier_intersections_have_positive() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var carrier := Segment.derive_carrier(
		Vector2(center.x + r, center.y),
		Vector2(center.x - r, center.y),
		Vector2(center.x, center.y - r))

	# Outer hit: from P going inward (toward circle center)
	var P := Vector2(center.x - r, center.y)  # left side of circle
	var outer_dir := Direction.from_coords(P, P + Vector2(1, 0))  # going right (inward)
	var outer_ray := Ray.from_coords(P, outer_dir)
	var outer_hits := Intersection.intersect_line_with_carrier(outer_ray, carrier)

	var has_positive := false
	for hit in outer_hits:
		var t: float = hit["t"]
		if t > 0.0:
			has_positive = true
	assert_true(has_positive,
		"Outer direction: should have at least one t>0. Got %s" %
		[outer_hits.map(func(h): return h["t"])])

func test_diag_direction_dot_product_distinguishes_sides() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var P := Vector2(center.x - r, center.y)  # left side of circle

	var inner_dir := Vector2(-1, 0)  # going left (outward)
	var outer_dir := Vector2(1, 0)   # going right (inward)
	var outward_normal := (P - center)  # points left (outward)

	var inner_dot := inner_dir.dot(outward_normal)
	var outer_dot := outer_dir.dot(outward_normal)

	assert_gt(inner_dot, 0.0,
		"Inner hit: dir.dot(P - center) should be > 0 (going outward). Got %f" % inner_dot)
	assert_lt(outer_dot, 0.0,
		"Outer hit: dir.dot(P - center) should be < 0 (going inward). Got %f" % outer_dot)

# --- Phase 3: Prove root cause chain ---

func test_proof_inner_direction_causes_empty_carrier_hits() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var seg := surf.segment
	var carrier := seg.get_carrier()

	var P := Vector2(center.x - r, center.y)
	var inner_dir := Direction.from_coords(P, P + Vector2(-1, 0))
	var inner_ray := Ray.from_coords(P, inner_dir)

	var hits := Intersection.find_all_hits(inner_ray, [seg], seg, carrier)
	# Apply same filter as tracer.gd:284-285
	var filtered := hits.filter(func(h: Intersection.HitRecord) -> bool:
		return h.segment != seg or h.t > 0.0)

	assert_eq(filtered.size(), 0,
		"Inner direction: after wrap-around filter, no hits should remain. Got %d hits with t=%s" %
		[filtered.size(), filtered.map(func(h: Intersection.HitRecord): return h.t)])

func test_proof_negated_direction_would_produce_positive_t() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var seg := surf.segment
	var carrier := seg.get_carrier()

	var P := Vector2(center.x - r, center.y)
	# Negated inner direction: going inward instead of outward
	var negated_dir := Direction.from_coords(P, P + Vector2(1, 0))
	var negated_ray := Ray.from_coords(P, negated_dir)

	var hits := Intersection.find_all_hits(negated_ray, [seg], seg, carrier)
	var filtered := hits.filter(func(h: Intersection.HitRecord) -> bool:
		return h.segment != seg or h.t > 0.0)

	assert_gt(filtered.size(), 0,
		"Negated direction: should have at least one hit with t>0 after filter")
	if filtered.size() > 0:
		var best_t: float = filtered[0].t
		assert_gt(best_t, 0.0,
			"Negated direction: surviving hit should have positive t. Got %f" % best_t)

func test_proof_no_escape_to_center_after_fix() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var surfaces: Array = [surf]
	var player := Vector2(960, 600)
	var aim := Direction.from_coords(player, Vector2(700, 540))
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	var found_center_step := false
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame.conjugating:
			if s.start.distance_to(center) < 5.0 or s.end.distance_to(center) < 5.0:
				found_center_step = true
				break

	assert_false(found_center_step,
		"Inner hit should NOT produce escape arcs to circle center (bug was fixed)")

# --- Wrap carrier investigation ---

func _inner_trace() -> Dictionary:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var carrier := surf.segment.get_carrier()
	var surfaces: Array = [surf]
	var bounds := Rect2(0, 0, 1920, 1080)
	var player := Vector2(960, 600)
	var aim := Direction.from_coords(player, Vector2(700, 540))
	var path := Tracer.trace(player, aim, surfaces, GameState.new())
	return {"path": path, "carrier": carrier, "center": center, "r": r,
			"surf": surf, "bounds": bounds}

# Phase 1: Reproduction

func test_repro_inner_arc_carrier_differs_from_surface_carrier() -> void:
	var d := _inner_trace()
	var path: Tracer.TracedPath = d["path"]
	var surface_carrier: GeneralizedCircle = d["carrier"]

	var mismatches: Array[String] = []
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if not s.is_arc_step:
			continue
		if not VisualConverter.is_arc(s.start, s.via, s.end):
			continue
		var step_carrier := Segment.derive_carrier(s.start, s.end, s.via)
		if step_carrier.is_line():
			continue
		var sc := surface_carrier.center()
		var sr := surface_carrier.radius()
		var c := step_carrier.center()
		var r := step_carrier.radius()
		if c.distance_to(sc) > 1.0 or absf(r - sr) > 1.0:
			mismatches.append("step %d: carrier center=(%.1f,%.1f) r=%.1f vs surface center=(%.1f,%.1f) r=%.1f" %
				[i, c.x, c.y, r, sc.x, sc.y, sr])

	assert_eq(mismatches.size(), 0,
		"All reflected arc steps should use the surface carrier.\n%s" % "\n".join(mismatches))

func test_repro_inner_arc_has_multiple_carriers() -> void:
	var d := _inner_trace()
	var path: Tracer.TracedPath = d["path"]

	var carriers: Array = []
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if not s.is_arc_step or not VisualConverter.is_arc(s.start, s.via, s.end):
			continue
		var step_carrier := Segment.derive_carrier(s.start, s.end, s.via)
		if step_carrier.is_line():
			continue
		var c := step_carrier.center()
		var r := step_carrier.radius()
		var is_new := true
		for existing in carriers:
			if c.distance_to(existing["center"]) < 1.0 and absf(r - existing["radius"]) < 1.0:
				is_new = false
				break
		if is_new:
			carriers.append({"center": c, "radius": r})

	assert_eq(carriers.size(), 1,
		"All reflected arcs should share one carrier. Found %d distinct carriers: %s" %
		[carriers.size(), carriers])

func test_repro_outer_case_step_count_explosion() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var surfaces: Array = [surf]
	var player := Vector2(600, 540)
	var aim := Direction.from_coords(player, Vector2(1300, 540))
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	assert_lt(path.steps.size(), 20,
		"Outer case should produce clean exit, not %d steps" % path.steps.size())

func test_repro_outer_case_still_has_identity_exit() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var surfaces: Array = [surf]
	var player := Vector2(600, 540)
	var aim := Direction.from_coords(player, Vector2(1300, 540))
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	var last_step: Tracer.Step = path.steps[path.steps.size() - 1]
	assert_eq(last_step.frame_id, MobiusTransform.IDENTITY_ID,
		"Outer case should end in identity frame, got frame_id=%d" % last_step.frame_id)
	assert_false(last_step.is_arc_step,
		"Outer case should end with a straight line, not an arc")

# Phase 2: Evidence collection

func test_evidence_inner_hit_produces_regular_arc_steps() -> void:
	var d := _inner_trace()
	var path: Tracer.TracedPath = d["path"]

	var reflected_arc_steps: Array = []
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if s.frame.conjugating and s.is_arc_step:
			reflected_arc_steps.append({"index": i, "start": s.start, "end": s.end, "via": s.via})

	assert_gt(reflected_arc_steps.size(), 0,
		"Should have arc steps in reflected frame")

	var bounds := Rect2(0, 0, 1920, 1080)
	var wrap_sub_steps := 0
	for arc in reflected_arc_steps:
		var s_pt: Vector2 = arc["start"]
		var e_pt: Vector2 = arc["end"]
		var on_bounds_start := (absf(s_pt.x - bounds.position.x) < 1.0 or
			absf(s_pt.x - bounds.end.x) < 1.0 or
			absf(s_pt.y - bounds.position.y) < 1.0 or
			absf(s_pt.y - bounds.end.y) < 1.0)
		var on_bounds_end := (absf(e_pt.x - bounds.position.x) < 1.0 or
			absf(e_pt.x - bounds.end.x) < 1.0 or
			absf(e_pt.y - bounds.position.y) < 1.0 or
			absf(e_pt.y - bounds.end.y) < 1.0)
		if on_bounds_start or on_bounds_end:
			wrap_sub_steps += 1

	gut.p("Reflected arc steps: %d, wrap sub-steps (bounds-clipped): %d" %
		[reflected_arc_steps.size(), wrap_sub_steps])
	assert_eq(wrap_sub_steps, 0,
		"Inner arcs should be regular steps, not bounds-clipped wrap sub-steps")

func test_evidence_arc_step_endpoints_are_on_consistent_carrier() -> void:
	var d := _inner_trace()
	var path: Tracer.TracedPath = d["path"]

	var ref_carrier: GeneralizedCircle = null
	var inconsistencies: Array[String] = []
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if not s.frame.conjugating or not s.is_arc_step:
			continue
		if not VisualConverter.is_arc(s.start, s.via, s.end):
			continue
		var step_carrier := Segment.derive_carrier(s.start, s.end, s.via)
		if step_carrier.is_line():
			continue
		if ref_carrier == null:
			ref_carrier = step_carrier
			continue
		var rc := ref_carrier.center()
		var c := step_carrier.center()
		var dist := c.distance_to(rc)
		if dist > 1.0:
			inconsistencies.append(
				"step %d: carrier center=(%.1f,%.1f) vs ref center=(%.1f,%.1f) dist=%.1f" %
				[i, c.x, c.y, rc.x, rc.y, dist])

	assert_not_null(ref_carrier, "Should have at least one reflected arc step")
	assert_eq(inconsistencies.size(), 0,
		"All reflected arc steps should share the same carrier.\n%s" %
		"\n".join(inconsistencies))

func test_evidence_arc_step_via_is_on_its_own_carrier() -> void:
	var d := _inner_trace()
	var path: Tracer.TracedPath = d["path"]

	var off_carrier_vias: Array[String] = []
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if not s.frame.conjugating or not s.is_arc_step:
			continue
		if not VisualConverter.is_arc(s.start, s.via, s.end):
			continue
		var step_carrier := Segment.derive_carrier(s.start, s.end, s.via)
		var eval_val := step_carrier.evaluate(s.via)
		var r := step_carrier.radius() if not step_carrier.is_line() else 1.0
		var normalized := absf(eval_val) / (r * r) if r > 0.0 else absf(eval_val)
		if normalized > 0.01:
			off_carrier_vias.append(
				"step %d: via=(%.1f,%.1f) eval=%.3f normalized=%.4f" %
				[i, s.via.x, s.via.y, eval_val, normalized])

	assert_eq(off_carrier_vias.size(), 0,
		"Arc step via points should lie on their own derived carrier.\n%s" %
		"\n".join(off_carrier_vias))

func test_evidence_all_arc_steps_share_single_carrier() -> void:
	var d := _inner_trace()
	var path: Tracer.TracedPath = d["path"]

	var distinct_carriers: Array = []
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if not s.frame.conjugating or not s.is_arc_step:
			continue
		if not VisualConverter.is_arc(s.start, s.via, s.end):
			continue
		var step_carrier := Segment.derive_carrier(s.start, s.end, s.via)
		if step_carrier.is_line():
			continue
		var c := step_carrier.center()
		var r := step_carrier.radius()
		var is_new := true
		for existing in distinct_carriers:
			if c.distance_to(existing["center"]) < 1.0 and absf(r - existing["radius"]) < 1.0:
				is_new = false
				break
		if is_new:
			distinct_carriers.append({"center": c, "radius": r})

	assert_eq(distinct_carriers.size(), 1,
		"All arc steps should share one carrier. Found %d: %s" %
		[distinct_carriers.size(), distinct_carriers])

# Phase 3: Proof of exact cause

func test_proof_is_wrap_true_because_negative_t() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var seg := surf.segment
	var carrier := seg.get_carrier()

	var P := Vector2(center.x - r, center.y)
	var inner_dir := Direction.from_coords(P, P + Vector2(-1, 0))
	var inner_ray := Ray.from_coords(P, inner_dir)

	var hits := Intersection.find_all_hits(inner_ray, [seg], seg, carrier)
	var filtered := hits.filter(func(h: Intersection.HitRecord) -> bool:
		return h.segment != seg or h.t != 0.0)

	var has_negative_t := false
	for h in filtered:
		if h.t < 0.0:
			has_negative_t = true
			gut.p("Negative t hit: t=%.3f point=(%.1f,%.1f)" % [h.t, h.point.coords.x, h.point.coords.y])

	assert_true(has_negative_t,
		"After self-hit filter, inner direction should have negative-t carrier hit (wrap trigger)")
	gut.p("walk_t starts at 0.0 → hp.t < walk_t → is_wrap = true → _add_wrap_steps fires")

func _get_trace_hitpoints() -> Dictionary:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var carrier := surf.segment.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var frame := refl.get_tracked_transform().mobius

	var player := Vector2(960, 600)
	var aim := Direction.from_coords(player, Vector2(700, 540))
	var ray := Ray.from_coords(player, aim)
	var hits := Intersection.find_all_hits(ray, [surf.segment], null, null)
	var circle_hits: Array = []
	for h in hits:
		if h.segment == surf.segment:
			circle_hits.append(h)

	var phys_P: Vector2 = circle_hits[0].point.coords
	var phys_Q: Vector2 = circle_hits[1].point.coords
	return {"P": phys_P, "Q": phys_Q, "carrier": carrier, "frame": frame,
			"surf": surf, "center": center, "r": r}

func test_proof_chord_clip_diverges_from_arc_clip() -> void:
	var d := _get_trace_hitpoints()
	var carrier: GeneralizedCircle = d["carrier"]
	var frame: MobiusTransform = d["frame"]
	var vis_start := frame.apply(d["P"])
	var vis_end := frame.apply(d["Q"])

	var chord_dir := (vis_end - vis_start).normalized()
	var bounds := Rect2(0, 0, 1920, 1080)
	var chord_clip := VisualConverter._clip_to_bounds(vis_start, -chord_dir, bounds)

	var circle_radius := carrier.radius()
	var chord_clip_eval := carrier.evaluate(chord_clip)
	var normalized_eval := absf(chord_clip_eval) / (circle_radius * circle_radius)

	gut.p("vis_start=(%.1f,%.1f) vis_end=(%.1f,%.1f) chord_clip=(%.1f,%.1f)" %
		[vis_start.x, vis_start.y, vis_end.x, vis_end.y, chord_clip.x, chord_clip.y])
	gut.p("carrier.evaluate(chord_clip)=%.3f normalized=%.4f" % [chord_clip_eval, normalized_eval])
	assert_gt(normalized_eval, 0.01,
		"Chord clip point should NOT be on the carrier circle (chord ≠ arc)")

func test_proof_three_point_carrier_wrong_when_clip_point_off_circle() -> void:
	var d := _get_trace_hitpoints()
	var carrier: GeneralizedCircle = d["carrier"]
	var frame: MobiusTransform = d["frame"]
	var vis_start := frame.apply(d["P"])
	var vis_end := frame.apply(d["Q"])

	var chord_dir := (vis_end - vis_start).normalized()
	var bounds := Rect2(0, 0, 1920, 1080)
	var chord_clip := VisualConverter._clip_to_bounds(vis_start, -chord_dir, bounds)
	var via_center := frame.apply(Vector2(INF, INF))

	gut.p("vis_start=(%.1f,%.1f) chord_clip=(%.1f,%.1f) via_center=(%.1f,%.1f)" %
		[vis_start.x, vis_start.y, chord_clip.x, chord_clip.y, via_center.x, via_center.y])

	var wrong_carrier := Segment.derive_carrier(vis_start, chord_clip, via_center)

	if wrong_carrier.is_line():
		fail_test("Three-point carrier should be a circle for off-axis geometry, not a line")
	else:
		var wc := wrong_carrier.center()
		var wr := wrong_carrier.radius()
		var sc := carrier.center()
		var sr := carrier.radius()
		var center_diff := wc.distance_to(sc)
		var radius_diff := absf(wr - sr)
		gut.p("Wrong carrier: center=(%.1f,%.1f) r=%.1f | Surface: center=(%.1f,%.1f) r=%.1f" %
			[wc.x, wc.y, wr, sc.x, sc.y, sr])
		gut.p("Differences: center=%.1f radius=%.1f" % [center_diff, radius_diff])
		assert_true(center_diff > 1.0 or radius_diff > 1.0,
			"Three-point carrier from (vis_start, chord_clip, center) should differ from surface carrier")
