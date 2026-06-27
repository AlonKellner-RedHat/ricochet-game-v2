extends GutTest

const COMBO_BASE := "res://scenes/test_levels/combo_base.tscn"
const LINE1 := Vector4(600, 300, 600, 700)
const ARC1_START := Vector2(400, 250)
const ARC1_END := Vector2(300, 250)
const ARC1_VIA := Vector2(350, 200)
const ARC2_START := Vector2(1550, 750)
const ARC2_END := Vector2(1450, 750)
const ARC2_VIA := Vector2(1500, 700)

const PLAYER := Vector2(1334.662, 234.909)
const CURSOR := Vector2(400, 250)

func _build_scene() -> Node:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()
	var scene: Node = load(COMBO_BASE).instantiate()
	scene.gravity = Vector2.ZERO
	scene.portal_lines = PackedFloat64Array([
		LINE1.x, LINE1.y, LINE1.z, LINE1.w, 0, 1000, 0])
	scene.reflective_arcs = PackedFloat64Array([
		ARC1_START.x, ARC1_START.y, ARC1_END.x, ARC1_END.y, ARC1_VIA.x, ARC1_VIA.y,
		ARC2_START.x, ARC2_START.y, ARC2_END.x, ARC2_END.y, ARC2_VIA.x, ARC2_VIA.y])
	return scene

func _trace_raw(scene: Node) -> Tracer.TracedPath:
	var surfaces: Array[Surface] = scene.surfaces
	var cache := TransformCache.new()
	var aim_dir: Direction = Planner.compute_aim_direction(
		PLAYER, CURSOR, [], surfaces, GameState.new(), cache)
	var aim_ray := Ray.from_coords(PLAYER, aim_dir)
	return Tracer.trace(PLAYER, aim_dir, surfaces, GameState.new(),
		aim_ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, [], cache, CURSOR)

func _trace_via_renderer(scene: Node) -> Tracer.TracedPath:
	var player := scene.get_node("Player")
	var cursor := scene.get_node("Cursor")
	var renderer := scene.get_node("PathRenderer")
	player.global_position = PLAYER
	cursor.global_position = CURSOR
	renderer._compute_trace()
	return renderer.get_traced_path()

func test_reproduce_gaps() -> void:
	var scene := _build_scene()
	add_child_autofree(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var raw_path := _trace_raw(scene)
	var rendered_path := _trace_via_renderer(scene)

	gut.p("=== RAW TRACE (before VisualConverter) ===")
	gut.p("Steps: %d" % raw_path.steps.size())
	_dump_steps(raw_path, "RAW")

	gut.p("")
	gut.p("=== RENDERED TRACE (after VisualConverter) ===")
	gut.p("Steps: %d" % rendered_path.steps.size())
	_dump_steps(rendered_path, "RENDERED")

	var raw_gaps := _find_large_gaps(raw_path, 100.0)
	var rendered_gaps := _find_large_gaps(rendered_path, 100.0)

	gut.p("")
	gut.p("=== LARGE GAPS (>100px) ===")
	gut.p("Raw: %d, Rendered: %d" % [raw_gaps.size(), rendered_gaps.size()])

	assert_gt(raw_gaps.size() + rendered_gaps.size(), 0,
		"Should reproduce at least one large gap")

func test_frame_transitions_at_gaps() -> void:
	var scene := _build_scene()
	add_child_autofree(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var raw_path := _trace_raw(scene)
	var rendered_path := _trace_via_renderer(scene)

	gut.p("=== FRAME TRANSITIONS (raw) ===")
	_analyze_frame_transitions(raw_path, "RAW")

	gut.p("")
	gut.p("=== FRAME TRANSITIONS (rendered) ===")
	_analyze_frame_transitions(rendered_path, "RENDERED")

	gut.p("")
	gut.p("=== STEP COUNT DIFFERENCE ===")
	gut.p("Raw steps: %d, Rendered steps: %d, Diff: %d" % [
		raw_path.steps.size(), rendered_path.steps.size(),
		rendered_path.steps.size() - raw_path.steps.size()])
	if raw_path.steps.size() != rendered_path.steps.size():
		gut.p("VisualConverter CHANGED step count — potential after_portal flag loss")

	pass_test("Frame transition analysis complete")

func test_hitpoint_on_carrier() -> void:
	var scene := _build_scene()
	add_child_autofree(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var raw_path := _trace_raw(scene)
	var surfaces: Array[Surface] = scene.surfaces

	gut.p("=== SURFACES ===")
	for surf in surfaces:
		var seg := surf.segment
		var carrier := seg.get_carrier()
		var kind := "line" if carrier.is_line() else "circle(r=%.1f)" % carrier.radius()
		gut.p("  Surface %d: %s start=%s end=%s" % [surf.id, kind, seg.start.coords, seg.end.coords])

	gut.p("")
	gut.p("=== HITPOINT-ON-CARRIER CHECK ===")
	for i in raw_path.steps.size():
		var step: Tracer.Step = raw_path.steps[i]
		if step.hit == null:
			continue
		var hp_coords := step.hit.point.coords
		var frame := step.frame
		var visual_end := step.end
		var recomputed_end := frame.apply(hp_coords)
		var end_diff := visual_end.distance_to(recomputed_end)

		var msg := "Step %d: hit=(%s) frame_id=%d visual_end=%s recomputed=%s diff=%.6f" % [
			i, hp_coords, frame.id, visual_end, recomputed_end, end_diff]
		if end_diff > 0.01:
			msg += " *** MISMATCH ***"
		gut.p("  " + msg)

	pass_test("Hitpoint-on-carrier analysis complete")

func _dump_steps(path: Tracer.TracedPath, label: String) -> void:
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		var gap := 0.0
		if i > 0:
			gap = path.steps[i - 1].end.distance_to(step.start)
		var via_inf := is_inf(step.via.x) or is_inf(step.via.y)
		var frame_info := "frame=%d conj=%s" % [step.frame.id, step.frame.conjugating]
		var portal_flag := " PORTAL" if step.after_portal else ""
		var hit_info := ""
		if step.hit:
			hit_info = " hit=(%s) surf=%d side=%d" % [step.hit.point.coords, step.surface_id, step.hit_side]
		var gap_marker := ""
		if gap > 100.0:
			gap_marker = " *** GAP=%.1f ***" % gap
		elif gap > 1.5:
			gap_marker = " * gap=%.2f *" % gap
		gut.p("  [%s %02d] start=%s end=%s via_inf=%s %s%s%s%s" % [
			label, i, step.start, step.end, via_inf, frame_info, portal_flag, hit_info, gap_marker])

func _find_large_gaps(path: Tracer.TracedPath, threshold: float) -> Array[Dictionary]:
	var gaps: Array[Dictionary] = []
	for i in range(1, path.steps.size()):
		var prev: Tracer.Step = path.steps[i - 1]
		var curr: Tracer.Step = path.steps[i]
		var gap := prev.end.distance_to(curr.start)
		if gap > threshold:
			gaps.append({
				"index": i,
				"gap": gap,
				"prev_end": prev.end,
				"curr_start": curr.start,
				"after_portal": curr.after_portal,
				"prev_frame": prev.frame.id,
				"curr_frame": curr.frame.id,
			})
	return gaps

func test_normalized_carrier_size() -> void:
	var scene := _build_scene()
	add_child_autofree(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var raw_path := _trace_raw(scene)
	var surfaces: Array[Surface] = scene.surfaces

	gut.p("=== NORMALIZED CARRIER SIZE ANALYSIS ===")
	gut.p("")

	for i in range(1, raw_path.steps.size()):
		var prev: Tracer.Step = raw_path.steps[i - 1]
		var curr: Tracer.Step = raw_path.steps[i]
		var gap := prev.end.distance_to(curr.start)
		if gap < 10.0:
			continue

		if prev.hit == null:
			continue

		var hp := prev.hit.point.coords
		var surf_id := prev.surface_id
		var orig_surf: Surface = null
		for s in surfaces:
			if s.id == surf_id:
				orig_surf = s
				break
		if orig_surf == null:
			continue

		var orig_carrier := orig_surf.segment.get_carrier()
		var orig_kind := "line" if orig_carrier.is_line() else "circle(r=%.4f)" % orig_carrier.radius()

		var frame := prev.frame
		var cache := TransformCache.new()
		var frame_inv := cache.invert_cached(frame)

		var norm_start := frame_inv.apply(orig_surf.segment.start.coords)
		var norm_end := frame_inv.apply(orig_surf.segment.end.coords)
		var norm_via := frame_inv.apply(orig_surf.segment.via.coords)

		var span_se := norm_start.distance_to(norm_end)
		var span_sv := norm_start.distance_to(norm_via)

		var norm_seg := Segment.from_coords(norm_start, norm_end, norm_via)
		var norm_carrier := norm_seg.get_carrier()
		var norm_kind := "line" if norm_carrier.is_line() else "circle(r=%.6f)" % norm_carrier.radius()

		var direct_carrier := orig_carrier.transformed_by(frame_inv)
		var direct_kind := "line" if direct_carrier.is_line() else "circle(r=%.6f)" % direct_carrier.radius()

		var hp_dist_from_norm_carrier := absf(norm_carrier.evaluate(hp))
		var hp_dist_from_direct_carrier := absf(direct_carrier.evaluate(hp))

		gut.p("Gap %d->%d (%.0fpx): hit surf=%d (%s)" % [i - 1, i, gap, surf_id, orig_kind])
		gut.p("  Norm points: start=%s end=%s via=%s" % [norm_start, norm_end, norm_via])
		gut.p("  Norm point spread: start-end=%.8f start-via=%.8f" % [span_se, span_sv])
		gut.p("  Carrier from 3 points: %s" % norm_kind)
		gut.p("  Carrier via transformed_by: %s" % direct_kind)
		gut.p("  hp=%s" % hp)
		gut.p("  hp distance from 3pt carrier: %.10f" % hp_dist_from_norm_carrier)
		gut.p("  hp distance from direct carrier: %.10f" % hp_dist_from_direct_carrier)

		if not norm_carrier.is_line() and not direct_carrier.is_line():
			gut.p("  3pt center=%s  direct center=%s" % [norm_carrier.center(), direct_carrier.center()])
			gut.p("  3pt radius=%.8f  direct radius=%.8f" % [norm_carrier.radius(), direct_carrier.radius()])
			gut.p("  Center offset=%.8f  Radius ratio=%.8f" % [
				norm_carrier.center().distance_to(direct_carrier.center()),
				norm_carrier.radius() / direct_carrier.radius() if direct_carrier.radius() > 0 else INF])
		gut.p("")

	pass_test("Normalized carrier analysis complete")

func test_root_cause_frame_discontinuity() -> void:
	var scene := _build_scene()
	add_child_autofree(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var raw_path := _trace_raw(scene)

	gut.p("=== ROOT CAUSE ANALYSIS: frame.apply(hp) across frame transitions ===")
	gut.p("")
	for i in range(1, raw_path.steps.size()):
		var prev: Tracer.Step = raw_path.steps[i - 1]
		var curr: Tracer.Step = raw_path.steps[i]
		var gap := prev.end.distance_to(curr.start)
		if gap < 1.5:
			continue

		var hp_coords := prev.hit.point.coords if prev.hit else Vector2.ZERO
		var prev_frame_at_hp := prev.frame.apply(hp_coords)
		var curr_frame_at_hp := curr.frame.apply(hp_coords)
		var frame_diff := prev_frame_at_hp.distance_to(curr_frame_at_hp)

		gut.p("Gap at step %d->%d: %.1f px" % [i - 1, i, gap])
		gut.p("  prev.end = %s (= prev_frame.apply(hp) where hp=%s)" % [prev.end, hp_coords])
		gut.p("  curr.start = %s (= curr_frame.apply(ray_origin))" % curr.start)
		gut.p("  prev_frame.apply(hp) = %s" % prev_frame_at_hp)
		gut.p("  curr_frame.apply(hp) = %s  (diff = %.3f)" % [curr_frame_at_hp, frame_diff])
		gut.p("  prev_frame: id=%d conj=%s" % [prev.frame.id, prev.frame.conjugating])
		gut.p("  curr_frame: id=%d conj=%s" % [curr.frame.id, curr.frame.conjugating])
		gut.p("  after_portal=%s" % curr.after_portal)

		if curr.after_portal:
			gut.p("  -> EXPECTED portal gap (~1000px), covered by after_portal flag")
		elif frame_diff > 1.0:
			gut.p("  -> BUG: reflection changed frame, old and new frame map SAME normalized point to DIFFERENT visual positions")
			gut.p("     The gap IS the frame discontinuity: new_frame(hp) != old_frame(hp)")
			gut.p("     Reflection on arc carrier is NOT fixing the visual point")
		gut.p("")

	pass_test("Root cause analysis complete")

func _analyze_frame_transitions(path: Tracer.TracedPath, label: String) -> void:
	for i in range(1, path.steps.size()):
		var prev: Tracer.Step = path.steps[i - 1]
		var curr: Tracer.Step = path.steps[i]
		var gap := prev.end.distance_to(curr.start)
		if prev.frame.id != curr.frame.id or gap > 1.5:
			var transition := "SAME_FRAME" if prev.frame.id == curr.frame.id else "FRAME_CHANGE(%d->%d)" % [prev.frame.id, curr.frame.id]
			var portal := "after_portal=true" if curr.after_portal else "after_portal=FALSE"
			gut.p("  [%s %d->%d] gap=%.3f %s %s conj:%s->%s" % [
				label, i - 1, i, gap, transition, portal,
				prev.frame.conjugating, curr.frame.conjugating])
			if prev.frame.id != curr.frame.id:
				gut.p("    prev_frame: a=%s b=%s c=%s d=%s" % [prev.frame.a, prev.frame.b, prev.frame.c, prev.frame.d])
				gut.p("    curr_frame: a=%s b=%s c=%s d=%s" % [curr.frame.a, curr.frame.b, curr.frame.c, curr.frame.d])
