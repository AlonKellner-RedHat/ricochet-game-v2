extends GutTest

const H := preload("res://tests/test_helpers.gd")

func before_each() -> void:
	H.reset_counters()

func _circle_no_walls_surfaces() -> Array:
	var center := Vector2(960, 540)
	var r := 200.0
	var carrier := GeneralizedCircle.from_circle(center, r)
	var seg := Segment.full_from_carrier(carrier)
	var reflection := ReflectionEffect.new(carrier)
	var config := SideConfig.new(reflection, true)
	var surf := Surface.new(seg, config, config, false, false)
	var surfaces: Array = [surf]
	var screen_defs := [
		[Vector2(0, 0), Vector2(1920, 0)],
		[Vector2(1920, 0), Vector2(1920, 1080)],
		[Vector2(1920, 1080), Vector2(0, 1080)],
		[Vector2(0, 1080), Vector2(0, 0)],
	]
	for bd in screen_defs:
		var s: Vector2 = bd[0]
		var e: Vector2 = bd[1]
		var bseg := Segment.from_coords(s, e, (s + e) / 2.0)
		var bconf := SideConfig.new(null, false)
		surfaces.append(Surface.new(bseg, bconf, bconf, false, false))
	return surfaces

static func _is_inf_vec(v: Vector2) -> bool:
	return is_inf(v.x) or is_inf(v.y)

static func _is_huge(v: Vector2, threshold: float = 10000.0) -> bool:
	return absf(v.x) > threshold or absf(v.y) > threshold

# --- Diagnostic 1: dump raw trace step sequence ---

func test_diag_raw_trace_gaps() -> void:
	var surfaces := _circle_no_walls_surfaces()
	var player := Vector2(0, 0)
	var cursor := Vector2(480, 270)
	var aim := Direction.from_coords(player, cursor)
	var raw := Tracer.trace(player, aim, surfaces, GameState.new())

	print("DIAG [RAW] steps=%d" % raw.steps.size())
	var raw_gap_count := 0
	for i in raw.steps.size():
		var s: Tracer.Step = raw.steps[i]
		var hit_info := "null"
		if s.hit != null:
			hit_info = "t=%.4f on_seg=%s" % [s.hit.t, s.hit.on_segment]
		var inf_s := _is_inf_vec(s.start)
		var inf_e := _is_inf_vec(s.end)
		var huge_s := _is_huge(s.start)
		var huge_e := _is_huge(s.end)
		var flags := ""
		if inf_s: flags += " INF_START"
		if inf_e: flags += " INF_END"
		if huge_s and not inf_s: flags += " HUGE_START"
		if huge_e and not inf_e: flags += " HUGE_END"
		print("DIAG [RAW] step %d: start=%s end=%s frame_id=%d hit=%s%s" % [
			i, s.start, s.end, s.frame_id, hit_info, flags])
		if i > 0:
			var prev: Tracer.Step = raw.steps[i - 1]
			if not _is_inf_vec(prev.end) and not _is_inf_vec(s.start):
				var gap := prev.end.distance_to(s.start)
				if gap > 1.0:
					print("DIAG [RAW] *** GAP between step %d end and step %d start: %.2f ***" % [i - 1, i, gap])
					raw_gap_count += 1

	print("DIAG [RAW] total gaps > 1.0: %d" % raw_gap_count)
	pending("Diagnostic — check raw trace output")

# --- Diagnostic 2: dump display trace (after prepare_for_display) ---

func test_diag_display_trace_gaps() -> void:
	var surfaces := _circle_no_walls_surfaces()
	var player := Vector2(0, 0)
	var cursor := Vector2(480, 270)
	var aim := Direction.from_coords(player, cursor)
	var raw := Tracer.trace(player, aim, surfaces, GameState.new())
	var display := VisualConverter.prepare_for_display(raw, VisualConverter.DEFAULT_BOUNDS)

	print("DIAG [DISPLAY] steps=%d (raw had %d)" % [display.steps.size(), raw.steps.size()])
	var display_gap_count := 0
	for i in display.steps.size():
		var s: Tracer.Step = display.steps[i]
		var hit_info := "null"
		if s.hit != null:
			hit_info = "t=%.4f on_seg=%s" % [s.hit.t, s.hit.on_segment]
		var flags := ""
		if _is_inf_vec(s.start): flags += " INF_START"
		if _is_inf_vec(s.end): flags += " INF_END"
		if _is_huge(s.start) and not _is_inf_vec(s.start): flags += " HUGE_START"
		if _is_huge(s.end) and not _is_inf_vec(s.end): flags += " HUGE_END"
		if is_nan(s.start.x) or is_nan(s.end.x): flags += " NaN"
		print("DIAG [DISPLAY] step %d: start=%s end=%s frame_id=%d hit=%s%s" % [
			i, s.start, s.end, s.frame_id, hit_info, flags])
		if i > 0:
			var prev: Tracer.Step = display.steps[i - 1]
			var gap := prev.end.distance_to(s.start)
			if gap > 1.0:
				var prev_hit := prev.hit != null
				var curr_hit := s.hit != null
				print("DIAG [DISPLAY] *** GAP %.2f between step %d and %d (prev_hit=%s curr_hit=%s) ***" % [
					gap, i - 1, i, prev_hit, curr_hit])
				# Would NOGAPS skip this? (skips when either hit is null)
				var nogaps_skip := not prev_hit or not curr_hit
				print("DIAG [DISPLAY]     NOGAPS would %s this gap" % ("SKIP" if nogaps_skip else "REPORT"))
				display_gap_count += 1

	print("DIAG [DISPLAY] total gaps > 1.0: %d" % display_gap_count)
	pending("Diagnostic — check display trace output")

# --- Diagnostic 3: trace all violation cases from violations.json ---

func test_diag_all_violation_cases() -> void:
	var surfaces := _circle_no_walls_surfaces()
	var cases := [
		[Vector2(0, 0), Vector2(480, 270)],
		[Vector2(0, 0), Vector2(960, 540)],
		[Vector2(0, 0), Vector2(1440, 810)],
		[Vector2(0, 0), Vector2(1920, 1080)],
		[Vector2(0, 0), Vector2(160, 90)],
	]
	for case_data in cases:
		var player: Vector2 = case_data[0]
		var cursor: Vector2 = case_data[1]
		var aim := Direction.from_coords(player, cursor)
		var raw := Tracer.trace(player, aim, surfaces, GameState.new())
		var display := VisualConverter.prepare_for_display(raw, VisualConverter.DEFAULT_BOUNDS)

		# Find gaps in display path (matching NOGAPS logic)
		var nogaps_violations := 0
		var continuity_violations := 0
		for i in range(1, display.steps.size()):
			var prev: Tracer.Step = display.steps[i - 1]
			var curr: Tracer.Step = display.steps[i]
			var gap := prev.end.distance_to(curr.start)
			var tol := 0.05 + 0.001 * i
			if gap > tol:
				# NOGAPS: skip if either hit is null
				if prev.hit != null and curr.hit != null:
					nogaps_violations += 1
					print("DIAG [CASE %s->%s] NOGAPS: step %d end=%s -> step %d start=%s gap=%.2f" % [
						player, cursor, i - 1, prev.end, i, curr.start, gap])
				# PHYSICAL-CONTINUITY: skip escape/return
				var prev_escape := prev.hit == null or (prev.hit != null and prev.hit.t < 0.0)
				var curr_return := curr.hit != null and curr.hit.t < 0.0
				if not prev_escape and not curr_return:
					continuity_violations += 1

		print("DIAG [CASE %s->%s] NOGAPS=%d CONTINUITY=%d" % [
			player, cursor, nogaps_violations, continuity_violations])

	pending("Diagnostic — check all violation cases")

# --- Diagnostic 4: identify infinity transitions ---

func test_diag_infinity_transitions() -> void:
	var surfaces := _circle_no_walls_surfaces()
	var player := Vector2(0, 0)
	var cursor := Vector2(480, 270)
	var aim := Direction.from_coords(player, cursor)
	var raw := Tracer.trace(player, aim, surfaces, GameState.new())

	print("DIAG [INFINITY] Scanning raw trace for infinity transitions:")
	for i in raw.steps.size():
		var s: Tracer.Step = raw.steps[i]
		if _is_inf_vec(s.end) or _is_inf_vec(s.start):
			print("DIAG [INFINITY] step %d: start=%s end=%s frame_id=%d" % [
				i, s.start, s.end, s.frame_id])
			if i > 0:
				var prev: Tracer.Step = raw.steps[i - 1]
				print("DIAG [INFINITY]   prev step %d end=%s (gap to curr start = %s)" % [
					i - 1, prev.end,
					"INF" if _is_inf_vec(prev.end) or _is_inf_vec(s.start) else "%.2f" % prev.end.distance_to(s.start)])
			if i < raw.steps.size() - 1:
				var next_step: Tracer.Step = raw.steps[i + 1]
				print("DIAG [INFINITY]   next step %d start=%s (gap from curr end = %s)" % [
					i + 1, next_step.start,
					"INF" if _is_inf_vec(s.end) or _is_inf_vec(next_step.start) else "%.2f" % s.end.distance_to(next_step.start)])

	# Check: do the gap endpoints match the violation coordinates?
	print("DIAG [INFINITY] Checking known violation coordinates:")
	var display := VisualConverter.prepare_for_display(raw, VisualConverter.DEFAULT_BOUNDS)
	for i in range(1, display.steps.size()):
		var prev: Tracer.Step = display.steps[i - 1]
		var curr: Tracer.Step = display.steps[i]
		if prev.hit == null or curr.hit == null:
			continue
		var gap := prev.end.distance_to(curr.start)
		if gap > 100.0:
			var prev_huge := _is_huge(prev.end)
			var curr_huge := _is_huge(curr.start)
			print("DIAG [INFINITY] Display gap at steps %d->%d: end=%s start=%s gap=%.0f huge_prev=%s huge_curr=%s" % [
				i - 1, i, prev.end, curr.start, gap, prev_huge, curr_huge])

	pending("Diagnostic — check infinity transitions")
