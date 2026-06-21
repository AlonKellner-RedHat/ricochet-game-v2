extends GutTest

const H := preload("res://tests/test_helpers.gd")

var _scene: Node
var _renderer: Node
var _player: Node
var _cursor: Node
var _game_mgr: Node

func before_each() -> void:
	H.reset_counters()
	_scene = load("res://scenes/test_levels/three_mirrors.tscn").instantiate()
	_scene.gravity = Vector2.ZERO
	add_child_autofree(_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	_renderer = _scene.get_node("PathRenderer")
	_player = _scene.get_node("Player")
	_cursor = _scene.get_node("Cursor")
	_game_mgr = _scene.get_node_or_null("GameManager")

func _setup_and_trace(player_pos: Vector2, cursor_pos: Vector2, plan_data: Array) -> void:
	_player.position = player_pos
	_cursor.position = cursor_pos
	if _game_mgr and "plan" in _game_mgr:
		_game_mgr.plan.clear()
		for pe in plan_data:
			_game_mgr.plan.add_entry(pe[0], pe[1])
	_renderer._compute_trace()

func _dump_trace(path: Tracer.TracedPath, trace_name: String, surfaces: Array) -> void:
	if path == null:
		gut.p("  %s: NULL path" % trace_name)
		return
	gut.p("  %s: %d steps, cursor_index=%d" % [trace_name, path.steps.size(), path.cursor_index])
	var start_idx := maxi(0, path.steps.size() - 8)
	for i in range(start_idx, path.steps.size()):
		var step: Tracer.Step = path.steps[i]
		var is_arc := step.frame != null and step.frame.maps_lines_to_arcs()
		var hit_desc := "null"
		if step.hit != null:
			if step.hit.segment != null:
				hit_desc = "seg(on=%s, side=%d)" % [str(step.hit.on_segment), step.hit.side]
			else:
				hit_desc = "null-seg"
		var t_inf_desc := ""
		if step.frame != null and is_arc:
			var t_inf := step.frame.apply(Vector2(INF, INF))
			t_inf_desc = " t_inf=%s" % t_inf
		gut.p("    step[%d]: start=%s end=%s fid=%d arc=%s hit=%s%s" % [
			i, step.start, step.end, step.frame_id, is_arc, hit_desc, t_inf_desc])

	var last: Tracer.Step = path.steps[path.steps.size() - 1]
	var end_pos := last.end
	gut.p("  --- Last endpoint analysis ---")
	gut.p("  end_pos=%s" % end_pos)

	var bounds := Rect2(0, 0, 1920, 1080)
	var at_bounds := (end_pos.x <= bounds.position.x + 2.0 or end_pos.x >= bounds.end.x - 2.0 or
		end_pos.y <= bounds.position.y + 2.0 or end_pos.y >= bounds.end.y - 2.0)
	gut.p("  at_bounds(2px)=%s" % at_bounds)

	var min_surf_dist := INF
	var nearest_surf := -1
	for si in surfaces.size():
		var s: Surface = surfaces[si]
		var d := _point_to_segment_dist(end_pos, s.segment.start.coords, s.segment.end.coords)
		if d < min_surf_dist:
			min_surf_dist = d
			nearest_surf = si
	gut.p("  min_segment_dist=%.4f (surface %d)" % [min_surf_dist, nearest_surf])

	var min_carrier_dist := INF
	var nearest_carrier := -1
	for si in surfaces.size():
		var s: Surface = surfaces[si]
		var carrier := s.segment.get_carrier()
		var f := carrier.evaluate(end_pos)
		var gx := 2.0 * carrier.a * end_pos.x + carrier.b
		var gy := 2.0 * carrier.a * end_pos.y + carrier.c
		var grad := sqrt(gx * gx + gy * gy)
		var d := absf(f) / maxf(grad, 1e-10)
		if d < min_carrier_dist:
			min_carrier_dist = d
			nearest_carrier = si
	gut.p("  min_carrier_dist=%.4f (surface %d)" % [min_carrier_dist, nearest_carrier])

	if last.frame != null and last.frame.maps_lines_to_arcs():
		var t_inf := last.frame.apply(Vector2(INF, INF))
		gut.p("  frame t_inf=%s, dist_to_t_inf=%.4f" % [t_inf, end_pos.distance_to(t_inf)])

	gut.p("  last.hit is null: %s" % (last.hit == null))
	if last.hit != null:
		gut.p("  last.hit.segment is null: %s" % (last.hit.segment == null))
		if last.hit.segment != null:
			gut.p("  last.hit.segment: start=%s end=%s" % [last.hit.segment.start.coords, last.hit.segment.end.coords])
			gut.p("  last.hit.point.coords=%s (normalized-space hitpoint)" % last.hit.point.coords)
			gut.p("  last.hit.on_segment=%s" % last.hit.on_segment)
			if last.frame != null:
				var reconstructed: Vector2 = last.frame.apply(last.hit.point.coords)
				gut.p("  frame.apply(hitpoint)=%s (should match end_pos)" % reconstructed)
				gut.p("  reconstruction_err=%.6f" % end_pos.distance_to(reconstructed))

static func _point_to_segment_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ap := p - a
	var t := clampf(ap.dot(ab) / maxf(ab.dot(ab), 1e-10), 0.0, 1.0)
	return p.distance_to(a + ab * t)

# --- Carrier precision diagnostics ---

func _analyze_carrier_precision(path: Tracer.TracedPath, surfaces: Array, label: String) -> void:
	if path == null or path.steps.size() == 0:
		gut.p("  %s: no path to analyze" % label)
		return

	var last: Tracer.Step = path.steps[path.steps.size() - 1]
	if last.hit == null or last.hit.segment == null or last.frame == null:
		gut.p("  %s: last step has no hit/segment/frame" % label)
		return

	gut.p("")
	gut.p("  === %s: Carrier Precision Analysis ===" % label)

	var frame := last.frame
	var frame_inv := frame.invert()

	gut.p("  frame.a=%s b=%s c=%s d=%s conj=%s" % [frame.a, frame.b, frame.c, frame.d, frame.conjugating])
	gut.p("  frame.c magnitude=%.15f" % frame.c.length())
	gut.p("  frame.maps_lines_to_arcs()=%s" % frame.maps_lines_to_arcs())

	# Find which original surface the hit segment maps to
	var hit_seg := last.hit.segment
	gut.p("  hit segment: start=%s end=%s via=%s" % [hit_seg.start.coords, hit_seg.end.coords, hit_seg.via.coords])

	var hit_carrier := hit_seg.get_carrier()
	gut.p("  hit carrier: a=%s b=%s c=%s d=%s" % [hit_carrier.a, hit_carrier.b, hit_carrier.c, hit_carrier.d])
	gut.p("  hit carrier is_line=%s" % hit_carrier.is_line())

	# Find the original surface nearest to the visual endpoint
	var end_pos := last.end
	var best_surf_idx := -1
	var best_dist := INF
	for si in surfaces.size():
		var s: Surface = surfaces[si]
		var carrier := s.segment.get_carrier()
		var f := carrier.evaluate(end_pos)
		var gx := 2.0 * carrier.a * end_pos.x + carrier.b
		var gy := 2.0 * carrier.a * end_pos.y + carrier.c
		var grad := sqrt(gx * gx + gy * gy)
		var d := absf(f) / maxf(grad, 1e-10)
		if d < best_dist:
			best_dist = d
			best_surf_idx = si
	gut.p("")
	gut.p("  nearest original surface: index=%d dist=%.4f" % [best_surf_idx, best_dist])

	if best_surf_idx < 0:
		return

	var orig_surf: Surface = surfaces[best_surf_idx]
	var orig_seg := orig_surf.segment
	var orig_carrier := orig_seg.get_carrier()
	gut.p("  original surface: id=%d start=%s end=%s via=%s" % [orig_surf.id, orig_seg.start.coords, orig_seg.end.coords, orig_seg.via.coords])
	gut.p("  original carrier: a=%s b=%s c=%s d=%s  is_line=%s" % [
		orig_carrier.a, orig_carrier.b, orig_carrier.c, orig_carrier.d, orig_carrier.is_line()])

	# Transform original surface points via frame_inv
	var t_start := frame_inv.apply(orig_seg.start.coords)
	var t_end := frame_inv.apply(orig_seg.end.coords)
	var t_via := frame_inv.apply(orig_seg.via.coords)
	gut.p("")
	gut.p("  frame_inv.apply(orig_start) = %s" % t_start)
	gut.p("  frame_inv.apply(orig_end)   = %s" % t_end)
	gut.p("  frame_inv.apply(orig_via)   = %s" % t_via)
	gut.p("  t_start.x precise = %.15f" % t_start.x)
	gut.p("  t_end.x   precise = %.15f" % t_end.x)
	gut.p("  t_via.x   precise = %.15f" % t_via.x)
	gut.p("  x spread (max-min) = %.15f" % (maxf(maxf(t_start.x, t_end.x), t_via.x) - minf(minf(t_start.x, t_end.x), t_via.x)))
	gut.p("  t_start is inf: %s" % (is_inf(t_start.x) or is_inf(t_start.y)))
	gut.p("  t_end is inf: %s" % (is_inf(t_end.x) or is_inf(t_end.y)))
	gut.p("  t_via is inf: %s" % (is_inf(t_via.x) or is_inf(t_via.y)))

	# Derive carrier from the 3 transformed points (what the tracer does)
	var carrier_3pt := Segment.derive_carrier(t_start, t_end, t_via)
	gut.p("")
	gut.p("  carrier_3pt: a=%.15f b=%.15f c=%.15f d=%.15f" % [
		carrier_3pt.a, carrier_3pt.b, carrier_3pt.c, carrier_3pt.d])
	gut.p("  carrier_3pt is_line=%s" % carrier_3pt.is_line())

	if not carrier_3pt.is_line() and carrier_3pt.a != 0.0:
		var ctr := carrier_3pt.center()
		var rad := carrier_3pt.radius()
		gut.p("  carrier_3pt is a CIRCLE: center=%s radius=%.2f" % [ctr, rad])

	# Evaluate hit point on the 3pt carrier
	var hp_coords := last.hit.point.coords
	var eval_3pt := carrier_3pt.evaluate(hp_coords)
	gut.p("  carrier_3pt.evaluate(hitpoint)=%.15f" % eval_3pt)

	# Also check: what would the carrier be if we computed it from the original carrier directly?
	# For a vertical line x=k: carrier is a=0, b=1, c=0, d=-k
	# For an anti-conformal transform (conjugating), the image of a line is a generalized circle
	# We can compute it by transforming more points and using least-squares, or by the Hermitian formula
	gut.p("")
	gut.p("  === Direct carrier transform (Hermitian action) ===")
	var direct_carrier := _transform_carrier_direct(orig_carrier, frame_inv)
	gut.p("  direct carrier: a=%.15f b=%.15f c=%.15f d=%.15f" % [
		direct_carrier.a, direct_carrier.b, direct_carrier.c, direct_carrier.d])
	gut.p("  direct carrier is_line=%s" % direct_carrier.is_line())
	var eval_direct := direct_carrier.evaluate(hp_coords)
	gut.p("  direct_carrier.evaluate(hitpoint)=%.15f" % eval_direct)

	# Compare the two carriers
	# Normalize both to make comparison meaningful
	var n3 := _normalize_carrier(carrier_3pt)
	var nd := _normalize_carrier(direct_carrier)
	gut.p("")
	gut.p("  normalized 3pt:    a=%.15f b=%.15f c=%.15f d=%.15f" % [n3.a, n3.b, n3.c, n3.d])
	gut.p("  normalized direct: a=%.15f b=%.15f c=%.15f d=%.15f" % [nd.a, nd.b, nd.c, nd.d])
	gut.p("  diff: da=%.15f db=%.15f dc=%.15f dd=%.15f" % [
		n3.a - nd.a, n3.b - nd.b, n3.c - nd.c, n3.d - nd.d])

	# Find ray intersection with direct carrier and compare visual position
	gut.p("")
	gut.p("  === Intersection comparison ===")
	# Reconstruct the ray in normalized space from the step
	# The ray direction in normalized space: frame_inv maps the physical ray direction
	# We can approximate: the ray passes through the hitpoint in normalized space
	# Use the step's ray and direction
	var phys_ray := last.ray
	var norm_origin := frame_inv.apply(phys_ray.origin.coords)
	var norm_dir_end := frame_inv.apply(phys_ray.origin.coords + phys_ray.direction.to_vector())
	if not (is_inf(norm_origin.x) or is_inf(norm_origin.y) or is_inf(norm_dir_end.x) or is_inf(norm_dir_end.y)):
		var norm_dir_vec := norm_dir_end - norm_origin
		var norm_ray := Ray.from_coords(norm_origin, Direction.from_coords(norm_origin, norm_origin + norm_dir_vec))

		var hits_3pt := Intersection.intersect_line_with_carrier(norm_ray, carrier_3pt)
		var hits_direct := Intersection.intersect_line_with_carrier(norm_ray, direct_carrier)

		gut.p("  norm_ray origin=%s dir=%s" % [norm_origin, norm_dir_vec])
		gut.p("  hits on 3pt carrier: %d" % hits_3pt.size())
		for h in hits_3pt:
			var vis := frame.apply(h["point"])
			gut.p("    t=%.6f point=%s → visual=%s" % [h["t"], h["point"], vis])
		gut.p("  hits on direct carrier: %d" % hits_direct.size())
		for h in hits_direct:
			var vis := frame.apply(h["point"])
			gut.p("    t=%.6f point=%s → visual=%s" % [h["t"], h["point"], vis])
	else:
		gut.p("  (ray maps to infinity in normalized space, skipping intersection comparison)")

# Transform a GeneralizedCircle by a Möbius transform using the Hermitian matrix action.
# For a conformal T(z) = (az+b)/(cz+d), the image of circle C under T⁻¹ is:
#   H' = N† H N  where N = adj(M) = [[d,-b],[-c,a]] and † = conjugate transpose
# For anti-conformal T(z̄) = (az̄+b)/(cz̄+d), the action involves conjugation.
static func _transform_carrier_direct(carrier: GeneralizedCircle, transform: MobiusTransform) -> GeneralizedCircle:
	# The carrier is represented as a(x²+y²) + bx + cy + d = 0
	# In Hermitian form: H = [[a_c, w], [w*, d_c]]
	# where w = (b_c - i*c_c)/2 and a_c, d_c are the circle coefficients
	var a_c := carrier.a
	var b_c := carrier.b
	var c_c := carrier.c
	var d_c := carrier.d

	# The Hermitian matrix H has entries:
	# H[0][0] = a_c (real)
	# H[0][1] = w = (b_c, -c_c) / 2  (as complex: (b_c - i*c_c)/2)
	# H[1][0] = w* = (b_c, c_c) / 2
	# H[1][1] = d_c (real)
	var w := Vector2(b_c / 2.0, -c_c / 2.0)
	var wc := Vector2(w.x, -w.y)

	# We need to compute H' = image of circle C under the transform.
	# For a conformal Möbius f(z) = (αz + β)/(γz + δ) with matrix M = [[α,β],[γ,δ]]:
	#   The preimage of a point z' is z = (δz' - β)/(-γz' + α)
	#   So the image circle satisfies: H' = N† H N where N = [[δ, -β], [-γ, α]]
	#
	# For anti-conformal f(z) = (αz̄ + β)/(γz̄ + δ):
	#   The preimage: z̄ = (δz' - β)/(-γz' + α), so z = conj((δz' - β)/(-γz' + α))
	#   The image circle: H' = N̄† H̄ N̄ = conj(N)† conj(H) conj(N)
	#   where N = [[δ, -β], [-γ, α]] (same as conformal case)
	#   Since H is Hermitian (H = H†), conj(H) swaps off-diag: [[a_c, wc], [w, d_c]]
	#   And conj(N) = [[conj(δ), conj(-β)], [conj(-γ), conj(α)]]

	var alpha := transform.a
	var beta := transform.b
	var gamma := transform.c
	var delta := transform.d

	# N = [[δ, -β], [-γ, α]]
	# For the anti-conformal case, use conj(N) and conj(H)
	var N00: Vector2
	var N01: Vector2
	var N10: Vector2
	var N11: Vector2
	var H00: float
	var H01: Vector2
	var H10: Vector2
	var H11: float

	if transform.conjugating:
		# Use conjugated N and conjugated H
		N00 = MobiusTransform.cconj(delta)
		N01 = MobiusTransform.cconj(-beta)
		N10 = MobiusTransform.cconj(-gamma)
		N11 = MobiusTransform.cconj(alpha)
		H00 = a_c
		H01 = wc  # swapped from w
		H10 = w   # swapped from wc
		H11 = d_c
	else:
		N00 = delta
		N01 = -beta
		N10 = -gamma
		N11 = alpha
		H00 = a_c
		H01 = w
		H10 = wc
		H11 = d_c

	# Compute N† H N
	# N† = [[conj(N00), conj(N10)], [conj(N01), conj(N11)]]
	var Nh00 := MobiusTransform.cconj(N00)
	var Nh01 := MobiusTransform.cconj(N10)
	var Nh10 := MobiusTransform.cconj(N01)
	var Nh11 := MobiusTransform.cconj(N11)

	# Temp = N† H (2x2 complex multiply)
	# H entries: H00 is real (treat as Vector2(H00, 0)), same for H11
	var rH00 := Vector2(H00, 0)
	var rH11 := Vector2(H11, 0)

	var T00 := MobiusTransform.cmul(Nh00, rH00) + MobiusTransform.cmul(Nh01, H10)
	var T01 := MobiusTransform.cmul(Nh00, H01) + MobiusTransform.cmul(Nh01, rH11)
	var T10 := MobiusTransform.cmul(Nh10, rH00) + MobiusTransform.cmul(Nh11, H10)
	var T11 := MobiusTransform.cmul(Nh10, H01) + MobiusTransform.cmul(Nh11, rH11)

	# Result = Temp * N
	var R00 := MobiusTransform.cmul(T00, N00) + MobiusTransform.cmul(T01, N10)
	var R01 := MobiusTransform.cmul(T00, N01) + MobiusTransform.cmul(T01, N11)
	var _R10 := MobiusTransform.cmul(T10, N00) + MobiusTransform.cmul(T11, N10)
	var R11 := MobiusTransform.cmul(T10, N01) + MobiusTransform.cmul(T11, N11)

	# R should be Hermitian: R[0][0] and R[1][1] are real, R[0][1] = conj(R[1][0])
	# Extract the generalized circle coefficients
	var new_a := R00.x  # real part of R[0][0]
	var new_w := R01    # complex: (new_b - i*new_c)/2
	var new_d := R11.x  # real part of R[1][1]
	var new_b := 2.0 * new_w.x
	var new_c := -2.0 * new_w.y

	return GeneralizedCircle.new(new_a, new_b, new_c, new_d)

static func _normalize_carrier(c: GeneralizedCircle) -> GeneralizedCircle:
	var max_val := maxf(maxf(absf(c.a), absf(c.b)), maxf(absf(c.c), absf(c.d)))
	if max_val == 0.0:
		return c
	return GeneralizedCircle.new(c.a / max_val, c.b / max_val, c.c / max_val, c.d / max_val)

# --- Main investigation test ---

func test_investigate_trace_ends():
	var surfaces: Array = _scene.surfaces
	gut.p("=== Scene surfaces (%d) ===" % surfaces.size())
	for i in surfaces.size():
		var s: Surface = surfaces[i]
		gut.p("  [%d] id=%d start=%s end=%s via=%s" % [i, s.id, s.segment.start.coords, s.segment.end.coords, s.segment.via.coords])
	gut.p("")

	var cases := [
		{
			"name": "V1: physical, player=(662.3, 632.2)",
			"player": Vector2(662.328735351562, 632.23876953125),
			"cursor": Vector2(0.0, 540.0),
			"plan": [[5, 0]],
			"trace": "physical",
			"expected_end": Vector2(10.21399, 433.294),
		},
		{
			"name": "V3: planned, player=(570, 250)",
			"player": Vector2(570.0, 250.0),
			"cursor": Vector2(960.0, 395.0),
			"plan": [[4, 0], [5, 0], [4, 0]],
			"trace": "planned",
			"expected_end": Vector2(109.0576, 543.7854),
		},
	]

	for c in cases:
		gut.p("=== %s ===" % c.name)
		_setup_and_trace(c.player, c.cursor, c.plan)

		var path: Tracer.TracedPath
		if c.trace == "physical":
			path = _renderer.get_traced_path()
		else:
			path = _renderer.get_planned_path()

		_dump_trace(path, c.trace, surfaces)

		if path != null and path.steps.size() > 0:
			var last_step: Tracer.Step = path.steps[path.steps.size() - 1]
			var last_end: Vector2 = last_step.end
			var expected: Vector2 = c.expected_end
			var dist_to_expected: float = last_end.distance_to(expected)
			gut.p("  dist_to_expected_violation_pos=%.4f" % dist_to_expected)
			if dist_to_expected < 2.0:
				gut.p("  >>> REPRODUCED <<<")
			else:
				gut.p("  >>> NOT REPRODUCED (endpoint moved) <<<")

			_analyze_carrier_precision(path, surfaces, c.name)
		gut.p("")

	pass_test("Investigation complete — see diagnostic output above")

# --- Standalone reproduction: carrier precision vs frame depth ---

func test_carrier_precision_vs_depth():
	gut.p("=== Carrier precision vs reflection depth ===")
	gut.p("Composing reflections in x=800 and x=1200 (parallel vertical mirrors)")
	gut.p("Measuring carrier drift for the line x=0 after normalization")
	gut.p("")

	# Original carrier: vertical line x=0 → a=0, b=1, c=0, d=0
	var orig_carrier := GeneralizedCircle.from_line(1.0, 0.0, 0.0)
	var orig_start := Vector2(0, 0)
	var orig_end := Vector2(0, 1080)
	var orig_via := Vector2(0, 540)

	# Build reflection transforms for x=800 and x=1200
	var carrier_800 := GeneralizedCircle.from_line(1.0, 0.0, -800.0)
	var carrier_1200 := GeneralizedCircle.from_line(1.0, 0.0, -1200.0)
	var refl_800 := ReflectionEffect.new(carrier_800)
	var refl_1200 := ReflectionEffect.new(carrier_1200)

	gut.p("  R(800) Möbius: a=%s b=%s c=%s d=%s conj=%s" % [
		refl_800.get_tracked_transform().mobius.a,
		refl_800.get_tracked_transform().mobius.b,
		refl_800.get_tracked_transform().mobius.c,
		refl_800.get_tracked_transform().mobius.d,
		refl_800.get_tracked_transform().mobius.conjugating])
	gut.p("  R(1200) Möbius: a=%s b=%s c=%s d=%s conj=%s" % [
		refl_1200.get_tracked_transform().mobius.a,
		refl_1200.get_tracked_transform().mobius.b,
		refl_1200.get_tracked_transform().mobius.c,
		refl_1200.get_tracked_transform().mobius.d,
		refl_1200.get_tracked_transform().mobius.conjugating])
	gut.p("")

	var depths := [2, 4, 6, 8, 10, 12, 14, 16, 20, 24, 30]
	for depth in depths:
		# Compose alternating reflections: R(800), R(1200), R(800), R(1200), ...
		var frame := MobiusTransform.identity()
		for i in depth:
			if i % 2 == 0:
				frame = frame.compose(refl_800.get_tracked_transform().mobius)
			else:
				frame = frame.compose(refl_1200.get_tracked_transform().mobius)
		var frame_inv := frame.invert()

		# Transform original line points via frame_inv
		var t_start := frame_inv.apply(orig_start)
		var t_end := frame_inv.apply(orig_end)
		var t_via := frame_inv.apply(orig_via)

		# Derive carrier from 3 points (what tracer does)
		var carrier_3pt := Segment.derive_carrier(t_start, t_end, t_via)

		# Direct carrier transform (Hermitian action)
		var carrier_direct := _transform_carrier_direct(orig_carrier, frame_inv)

		# Normalize for comparison
		var n3 := _normalize_carrier(carrier_3pt)
		var nd := _normalize_carrier(carrier_direct)

		# Expected x position of the transformed line
		# After N alternating reflections R(800), R(1200):
		# Even N: conformal, translation by -N/2 * 800
		# Odd N: anti-conformal
		var _expected_x: float
		if depth % 2 == 0:
			_expected_x = -float(depth / 2) * 800.0
		else:
			_expected_x = 1600.0 - float(depth / 2) * 800.0

		# Test: intersect a horizontal ray through the carrier at y=433
		var test_y := 433.0
		var test_ray := Ray.from_coords(Vector2(-10000, test_y), Direction.from_coords(Vector2(-10000, test_y), Vector2(-9999, test_y)))
		var hits_3pt := Intersection.intersect_line_with_carrier(test_ray, carrier_3pt)
		var hits_direct := Intersection.intersect_line_with_carrier(test_ray, carrier_direct)

		var vis_err_3pt := INF
		var vis_err_direct := INF
		if hits_3pt.size() > 0:
			for h in hits_3pt:
				var vis := frame.apply(h["point"])
				var err := absf(vis.x)  # distance from x=0
				if err < vis_err_3pt:
					vis_err_3pt = err
		if hits_direct.size() > 0:
			for h in hits_direct:
				var vis := frame.apply(h["point"])
				var err := absf(vis.x)
				if err < vis_err_direct:
					vis_err_direct = err

		gut.p("  depth=%d  conj=%s  c_mag=%s  3pt_a=%s  direct_a=%s  vis_err_3pt=%.4f  vis_err_direct=%.4f" % [
			depth, frame.conjugating, frame.c.length(),
			n3.a, nd.a,
			vis_err_3pt if vis_err_3pt != INF else -1.0,
			vis_err_direct if vis_err_direct != INF else -1.0])

	gut.p("")
	gut.p("Key: vis_err = distance from x=0 after frame.apply (should be 0)")
	pass_test("Standalone reproduction — see output above")

func test_derive_carrier_isolation():
	gut.p("=== derive_carrier isolation test ===")
	gut.p("Testing whether derive_carrier from exact collinear points gives a=0")
	gut.p("")

	# Case 1: hardcoded exact coordinates (no transform involved)
	var p1 := Vector2(-800, 1080)
	var p2 := Vector2(-800, 0)
	var p3 := Vector2(-800, 540)
	var c1 := Segment.derive_carrier(p1, p2, p3)
	gut.p("  Case 1: hardcoded V2(-800, 1080), V2(-800, 0), V2(-800, 540)")
	gut.p("    a=%.20f b=%.15f c=%.15f d=%.15f" % [c1.a, c1.b, c1.c, c1.d])
	gut.p("    is_line=%s" % c1.is_line())
	gut.p("")

	# Case 2: same but with 4400
	var q1 := Vector2(4400, 1080)
	var q2 := Vector2(4400, 0)
	var q3 := Vector2(4400, 540)
	var c2 := Segment.derive_carrier(q1, q2, q3)
	gut.p("  Case 2: hardcoded V2(4400, 1080), V2(4400, 0), V2(4400, 540)")
	gut.p("    a=%.20f b=%.15f c=%.15f d=%.15f" % [c2.a, c2.b, c2.c, c2.d])
	gut.p("    is_line=%s" % c2.is_line())
	gut.p("")

	# Case 3: get the actual frame_inv-applied coordinates from the real trace
	# and verify they're the same as the hardcoded ones
	var surfaces: Array = _scene.surfaces
	_setup_and_trace(Vector2(570.0, 250.0), Vector2(960.0, 395.0), [[4, 0], [5, 0], [4, 0]])
	var path: Tracer.TracedPath = _renderer.get_planned_path()
	if path != null and path.steps.size() > 0:
		var last: Tracer.Step = path.steps[path.steps.size() - 1]
		if last.hit != null and last.hit.segment != null and last.frame != null:
			var frame_inv := last.frame.invert()
			# Find left wall (id=10)
			var left_wall: Surface = null
			for s in surfaces:
				if s.id == 10:
					left_wall = s
					break
			if left_wall:
				var t_s := frame_inv.apply(left_wall.segment.start.coords)
				var t_e := frame_inv.apply(left_wall.segment.end.coords)
				var t_v := frame_inv.apply(left_wall.segment.via.coords)

				gut.p("  Case 3: frame_inv-applied left wall points")
				gut.p("    t_s = (%s, %s)" % [t_s.x, t_s.y])
				gut.p("    t_e = (%s, %s)" % [t_e.x, t_e.y])
				gut.p("    t_v = (%s, %s)" % [t_v.x, t_v.y])

				# Check if they equal the hardcoded values
				gut.p("    t_s == V2(-800, 1080): %s" % (t_s == Vector2(-800, 1080)))
				gut.p("    t_e == V2(-800, 0):    %s" % (t_e == Vector2(-800, 0)))
				gut.p("    t_v == V2(-800, 540):  %s" % (t_v == Vector2(-800, 540)))

				# Derive carrier from the actual transformed coordinates
				var c3 := Segment.derive_carrier(t_s, t_e, t_v)
				gut.p("    carrier a=%.20f b=%.15f c=%.15f d=%.15f" % [c3.a, c3.b, c3.c, c3.d])
				gut.p("    is_line=%s" % c3.is_line())

				# Also check: is the hit segment's carrier the same as what we'd get from derive_carrier?
				var hit_carrier := last.hit.segment.get_carrier()
				gut.p("    hit_carrier a=%.20f" % hit_carrier.a)

				# Check y precision too
				gut.p("")
				gut.p("    t_s.y precise = %.20f  (expect 1080)" % t_s.y)
				gut.p("    t_e.y precise = %.20f  (expect 0)" % t_e.y)
				gut.p("    t_v.y precise = %.20f  (expect 540)" % t_v.y)

				# Check bit-level: are the values EXACTLY what we think?
				gut.p("    t_s.x == -800.0: %s  (via float ==)" % (t_s.x == -800.0))
				gut.p("    t_s.y == 1080.0: %s" % (t_s.y == 1080.0))
				gut.p("    t_e.y == 0.0:    %s" % (t_e.y == 0.0))
				gut.p("    t_v.y == 540.0:  %s" % (t_v.y == 540.0))

	pass_test("Isolation test — see output above")
