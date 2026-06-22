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

# --- Diagnostic 1: check raw trace for zero-length steps ---

func test_diag_raw_trace_zero_length() -> void:
	var surfaces := _circle_no_walls_surfaces()
	var player := Vector2(1920, 0)
	var cursor := Vector2(1440, 270)
	var aim := Direction.from_coords(player, cursor)
	var raw := Tracer.trace(player, aim, surfaces, GameState.new())

	print("DIAG [RAW] steps=%d" % raw.steps.size())
	var zl_count := 0
	for i in raw.steps.size():
		var s: Tracer.Step = raw.steps[i]
		var hit_info := "null"
		if s.hit != null:
			hit_info = "t=%.4f on_seg=%s at_ep=%d" % [s.hit.t, s.hit.on_segment, s.hit.at_endpoint]
		var is_zl := s.start == s.end
		var flags := ""
		if is_zl: flags += " ZERO-LENGTH"
		if is_zl and s.hit != null and s.hit.t > 0.0: flags += " ***VIOLATION***"
		print("DIAG [RAW] step %d: start=%s end=%s frame_id=%d hit=%s%s" % [
			i, s.start, s.end, s.frame_id, hit_info, flags])
		if is_zl and s.hit != null and s.hit.t > 0.0:
			zl_count += 1

	print("DIAG [RAW] zero-length hit steps: %d" % zl_count)
	pending("Diagnostic — check raw trace for zero-length steps")

# --- Diagnostic 2: check display trace for zero-length steps ---

func test_diag_display_trace_zero_length() -> void:
	var surfaces := _circle_no_walls_surfaces()
	var player := Vector2(1920, 0)
	var cursor := Vector2(1440, 270)
	var aim := Direction.from_coords(player, cursor)
	var raw := Tracer.trace(player, aim, surfaces, GameState.new())
	var display := VisualConverter.prepare_for_display(raw, VisualConverter.DEFAULT_BOUNDS)

	print("DIAG [DISPLAY] steps=%d (raw had %d)" % [display.steps.size(), raw.steps.size()])
	var zl_count := 0
	for i in display.steps.size():
		var s: Tracer.Step = display.steps[i]
		var hit_info := "null"
		if s.hit != null:
			hit_info = "t=%.4f on_seg=%s at_ep=%d" % [s.hit.t, s.hit.on_segment, s.hit.at_endpoint]
		var is_zl := s.start == s.end
		var flags := ""
		if is_zl: flags += " ZERO-LENGTH"
		if is_zl and s.hit != null and s.hit.t > 0.0: flags += " ***VIOLATION***"
		var at_bounds := (absf(s.start.x) < 2.0 or absf(s.start.x - 1920.0) < 2.0 or
			absf(s.start.y) < 2.0 or absf(s.start.y - 1080.0) < 2.0)
		if at_bounds and is_zl: flags += " AT-BOUNDS"
		print("DIAG [DISPLAY] step %d: start=%s end=%s frame_id=%d hit=%s%s" % [
			i, s.start, s.end, s.frame_id, hit_info, flags])
		if is_zl and s.hit != null and s.hit.t > 0.0:
			zl_count += 1
			if i > 0:
				var prev: Tracer.Step = display.steps[i - 1]
				print("DIAG [DISPLAY]   prev step %d: start=%s end=%s hit=%s" % [
					i - 1, prev.start, prev.end, "null" if prev.hit == null else "t=%.4f" % prev.hit.t])

	print("DIAG [DISPLAY] zero-length hit steps: %d" % zl_count)
	pending("Diagnostic — check display trace for zero-length steps")

# --- Diagnostic 3: detailed info about zero-length steps ---

func test_diag_zero_length_step_details() -> void:
	var surfaces := _circle_no_walls_surfaces()
	var player := Vector2(1920, 0)
	var cursor := Vector2(1440, 270)
	var aim := Direction.from_coords(player, cursor)
	var raw := Tracer.trace(player, aim, surfaces, GameState.new())
	var display := VisualConverter.prepare_for_display(raw, VisualConverter.DEFAULT_BOUNDS)
	var bounds := VisualConverter.DEFAULT_BOUNDS

	print("DIAG [DETAILS] Analyzing zero-length steps:")
	for i in display.steps.size():
		var s: Tracer.Step = display.steps[i]
		if s.start != s.end or s.hit == null or s.hit.t <= 0.0:
			continue
		print("DIAG [DETAILS] === Step %d ===" % i)
		print("DIAG [DETAILS]   position: %s" % s.start)
		print("DIAG [DETAILS]   hit.t: %.6f" % s.hit.t)
		print("DIAG [DETAILS]   hit.on_segment: %s" % s.hit.on_segment)
		print("DIAG [DETAILS]   hit.at_endpoint: %d" % s.hit.at_endpoint)
		if s.hit.segment != null:
			print("DIAG [DETAILS]   hit.segment: %s -> %s" % [s.hit.segment.start.coords, s.hit.segment.end.coords])
		print("DIAG [DETAILS]   frame_id: %d" % s.frame_id)
		print("DIAG [DETAILS]   is_arc_step: %s" % s.is_arc_step)
		var on_bounds_edge := (absf(s.start.x - bounds.position.x) < 2.0 or
			absf(s.start.x - bounds.end.x) < 2.0 or
			absf(s.start.y - bounds.position.y) < 2.0 or
			absf(s.start.y - bounds.end.y) < 2.0)
		print("DIAG [DETAILS]   on_bounds_edge: %s" % on_bounds_edge)

		# Find the corresponding raw step by matching hit
		for j in raw.steps.size():
			var rs: Tracer.Step = raw.steps[j]
			if rs.hit == s.hit:
				print("DIAG [DETAILS]   raw step %d: start=%s end=%s (length=%.4f)" % [
					j, rs.start, rs.end, rs.start.distance_to(rs.end)])
				var rs_end_on_bounds := (absf(rs.end.x - bounds.position.x) < 2.0 or
					absf(rs.end.x - bounds.end.x) < 2.0 or
					absf(rs.end.y - bounds.position.y) < 2.0 or
					absf(rs.end.y - bounds.end.y) < 2.0)
				print("DIAG [DETAILS]   raw step end on bounds: %s" % rs_end_on_bounds)
				break

	pending("Diagnostic — zero-length step details")

# --- Diagnostic 4: all violation cases ---

func test_diag_all_violation_cases() -> void:
	var surfaces := _circle_no_walls_surfaces()
	var cases := [
		[Vector2(1920, 0), Vector2(1440, 270)],
		[Vector2(1920, 0), Vector2(960, 540)],
		[Vector2(1920, 0), Vector2(0, 1080)],
	]
	for case_data in cases:
		var player: Vector2 = case_data[0]
		var cursor: Vector2 = case_data[1]
		var aim := Direction.from_coords(player, cursor)
		var raw := Tracer.trace(player, aim, surfaces, GameState.new())
		var display := VisualConverter.prepare_for_display(raw, VisualConverter.DEFAULT_BOUNDS)

		var raw_zl := 0
		var display_zl := 0
		for i in raw.steps.size():
			var s: Tracer.Step = raw.steps[i]
			if s.start == s.end and s.hit != null and s.hit.t > 0.0:
				raw_zl += 1
		for i in display.steps.size():
			var s: Tracer.Step = display.steps[i]
			if s.start == s.end and s.hit != null and s.hit.t > 0.0:
				display_zl += 1
				print("DIAG [ALL-CASES] %s->%s: display step %d zero-length at %s" % [
					player, cursor, i, s.start])

		print("DIAG [ALL-CASES] %s->%s: raw_zl=%d display_zl=%d" % [
			player, cursor, raw_zl, display_zl])

	pending("Diagnostic — all violation cases")
