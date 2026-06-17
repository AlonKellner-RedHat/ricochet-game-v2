extends GutTest

# Diagnostic tests for circle reflection grazing case.
# Goal: reproduce and prove the exact cause of transform stack non-cancellation.

func test_carrier_identity_through_reflection() -> void:
	var start := Vector2(1160, 540)   # rightmost point
	var end_v := Vector2(760, 540)    # leftmost point
	var via := Vector2(960, 340)      # top of circle
	var seg := Segment.from_coords(start, end_v, via)
	var seg_carrier := seg.get_carrier()

	print("DIAGNOSTIC [test1] Original carrier: a=%f b=%f c=%f d=%f" % [seg_carrier.a, seg_carrier.b, seg_carrier.c, seg_carrier.d])
	print("DIAGNOSTIC [test1] Original center=%s radius=%f" % [seg_carrier.center(), seg_carrier.radius()])

	# Create reflection and get its Möbius
	var effect := ReflectionEffect.new(seg_carrier)
	var mobius: MobiusTransform = effect.get_mobius()

	# Apply Möbius to the 3 points on the carrier
	var t_start := mobius.apply(start)
	var t_end := mobius.apply(end_v)
	var t_via := mobius.apply(via)

	print("DIAGNOSTIC [test1] Transformed points: start=%s end=%s via=%s" % [t_start, t_end, t_via])

	# Re-derive carrier from transformed points
	var t_seg := Segment.from_coords(t_start, t_end, t_via)
	var t_carrier := t_seg.get_carrier()

	print("DIAGNOSTIC [test1] Re-derived carrier: a=%f b=%f c=%f d=%f" % [t_carrier.a, t_carrier.b, t_carrier.c, t_carrier.d])
	print("DIAGNOSTIC [test1] Re-derived center=%s radius=%f" % [t_carrier.center(), t_carrier.radius()])

	var center_dist := seg_carrier.center().distance_to(t_carrier.center())
	var radius_diff := absf(seg_carrier.radius() - t_carrier.radius())
	print("DIAGNOSTIC [test1] center_dist=%.10f  radius_diff=%.10f  (threshold=1e-6)" % [center_dist, radius_diff])
	print("DIAGNOSTIC [test1] Exceeds 1e-6 tolerance? center=%s radius=%s" % [center_dist > 1e-6, radius_diff > 1e-6])

	# Also check raw (a,b,c,d) differences after normalization by 'a'
	if seg_carrier.a != 0.0 and t_carrier.a != 0.0:
		var scale1 := 1.0 / seg_carrier.a
		var scale2 := 1.0 / t_carrier.a
		print("DIAGNOSTIC [test1] Normalized orig: (1, %f, %f, %f)" % [seg_carrier.b * scale1, seg_carrier.c * scale1, seg_carrier.d * scale1])
		print("DIAGNOSTIC [test1] Normalized rederived: (1, %f, %f, %f)" % [t_carrier.b * scale2, t_carrier.c * scale2, t_carrier.d * scale2])

	assert_lt(center_dist, 1.0, "Center drift should be small (actual=%.10f)" % center_dist)
	assert_lt(radius_diff, 1.0, "Radius drift should be small (actual=%.10f)" % radius_diff)


func test_normalized_effect_identity() -> void:
	var carrier := GeneralizedCircle.from_circle(Vector2(960, 540), 200.0)
	var start := Vector2(1160, 540)
	var end_v := Vector2(760, 540)
	var via := Vector2(960, 340)
	var seg := Segment.from_coords(start, end_v, via)
	var seg_carrier := seg.get_carrier()

	var effect := ReflectionEffect.new(seg_carrier)
	var original_tracked := effect.get_tracked_transform()

	# Re-derive carrier through Möbius (same as test 1)
	var mobius: MobiusTransform = effect.get_mobius()
	var t_seg := Segment.from_coords(
		mobius.apply(start), mobius.apply(end_v), mobius.apply(via))
	var re_derived_carrier := t_seg.get_carrier()

	# Test object identity
	var same_carrier_ref := (re_derived_carrier == seg_carrier)
	print("DIAGNOSTIC [test2] Same carrier reference? %s" % same_carrier_ref)

	# Test normalized() behavior
	var norm_effect := effect.normalized(re_derived_carrier)
	var same_effect := (norm_effect == effect)
	print("DIAGNOSTIC [test2] normalized() returned same effect? %s" % same_effect)

	if not same_effect:
		var new_tracked := norm_effect.get_tracked_transform()
		var same_tracked := (new_tracked == original_tracked)
		print("DIAGNOSTIC [test2] Same TrackedTransform? %s" % same_tracked)

		var inverse_check := original_tracked.is_inverse_of(new_tracked)
		print("DIAGNOSTIC [test2] is_inverse_of() result: %s" % inverse_check)

		if not inverse_check and new_tracked.carrier != null and original_tracked.carrier != null:
			var c1 := original_tracked.carrier
			var c2 := new_tracked.carrier
			var cd := c1.center().distance_to(c2.center())
			var rd := absf(c1.radius() - c2.radius())
			print("DIAGNOSTIC [test2] Carrier center_dist=%.10f  radius_diff=%.10f" % [cd, rd])
			print("DIAGNOSTIC [test2] C1 center=%s radius=%f" % [c1.center(), c1.radius()])
			print("DIAGNOSTIC [test2] C2 center=%s radius=%f" % [c2.center(), c2.radius()])

	assert_true(true, "Diagnostic test — check DIAGNOSTIC output above")


func test_segment_transformed_shortcut() -> void:
	var carrier := GeneralizedCircle.from_circle(Vector2(960, 540), 200.0)
	var start := Vector2(1160, 540)
	var end_v := Vector2(760, 540)
	var via := Vector2(960, 340)
	var seg := Segment.from_coords(start, end_v, via)
	seg.get_carrier()  # force cache

	var effect := ReflectionEffect.new(seg.get_carrier())
	var tracked := effect.get_tracked_transform()

	# For self-inverse: tracked.inverse == tracked
	print("DIAGNOSTIC [test3] Is self-inverse? %s" % (tracked.inverse == tracked))
	print("DIAGNOSTIC [test3] tracked.carrier is seg carrier? %s" % (tracked.carrier == seg.get_carrier()))

	# Try the shortcut
	var transformed_seg := seg.transformed(tracked.inverse)
	var same_seg := (transformed_seg == seg)
	print("DIAGNOSTIC [test3] transformed() returned self? %s" % same_seg)

	if not same_seg:
		print("DIAGNOSTIC [test3] Shortcut failed. Checking conditions:")
		print("DIAGNOSTIC [test3]   t.carrier != null: %s" % (tracked.carrier != null))
		print("DIAGNOSTIC [test3]   t.inverse == t: %s" % (tracked.inverse == tracked))
		print("DIAGNOSTIC [test3]   seg._carrier != null: %s" % (seg._carrier != null))
		print("DIAGNOSTIC [test3]   t.carrier == seg._carrier: %s" % (tracked.carrier == seg._carrier))
		var t_carrier := transformed_seg.get_carrier()
		print("DIAGNOSTIC [test3] Transformed carrier center=%s radius=%f" % [t_carrier.center(), t_carrier.radius()])
	else:
		print("DIAGNOSTIC [test3] Shortcut worked — segment returned self (provenance preserved)")

	assert_true(true, "Diagnostic test — check DIAGNOSTIC output above")


func test_full_tracer_grazing() -> void:
	var arc_seg := Segment.from_coords(
		Vector2(1160, 540), Vector2(760, 540), Vector2(960, 340))
	var reflection := ReflectionEffect.new(arc_seg.get_carrier())
	var reflect_config := SideConfig.new(reflection, true)
	var pass_config := SideConfig.new(null, false)

	var surfaces: Array = []
	# The circular mirror (both sides reflective)
	var mirror_surf := Surface.new(arc_seg, reflect_config, reflect_config, false, false)
	surfaces.append(mirror_surf)

	# Room walls
	var walls := [
		Segment.from_coords(Vector2(160, 90), Vector2(1760, 90), Vector2(960, 90)),
		Segment.from_coords(Vector2(1760, 90), Vector2(1760, 990), Vector2(1760, 540)),
		Segment.from_coords(Vector2(1760, 990), Vector2(160, 990), Vector2(960, 990)),
		Segment.from_coords(Vector2(160, 990), Vector2(160, 90), Vector2(160, 540)),
	]
	for w in walls:
		var block := SideConfig.new(TerminalEffect.new(), true)
		surfaces.append(Surface.new(w, block, block, false, true))

	# Screen bounds (passthrough)
	for bound_seg in [
		Segment.from_coords(Vector2(0, 0), Vector2(1920, 0), Vector2(960, 0)),
		Segment.from_coords(Vector2(1920, 0), Vector2(1920, 1080), Vector2(1920, 540)),
		Segment.from_coords(Vector2(1920, 1080), Vector2(0, 1080), Vector2(960, 1080)),
		Segment.from_coords(Vector2(0, 1080), Vector2(0, 0), Vector2(0, 540)),
	]:
		surfaces.append(Surface.new(bound_seg, pass_config, pass_config, false, false))

	# Trace: player at (600, 540), aiming to graze the circle
	var player_pos := Vector2(600, 540)
	var cursor_pos := Vector2(960, 380)
	var aim_dir := Direction.from_coords(player_pos, cursor_pos)
	var path := Tracer.trace(player_pos, aim_dir, surfaces, GameState.new())

	print("DIAGNOSTIC [test4] Trace: %d steps, cursor_index=%d" % [path.steps.size(), path.cursor_index])

	var circle_hit_count := 0
	var prev_frame_id := 0
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		var is_arc := step.is_arc_step
		var frame_id := step.frame_id
		var frame_changed := (frame_id != prev_frame_id)

		if step.hit != null and step.hit.segment == arc_seg:
			circle_hit_count += 1
			print("DIAGNOSTIC [test4] Step %d: CIRCLE HIT #%d | frame_id=%d arc=%s on_seg=%s side=%s" % [
				i, circle_hit_count, frame_id, is_arc, step.hit.on_segment, step.hit.side])
		elif frame_changed or i < 5 or is_arc:
			print("DIAGNOSTIC [test4] Step %d: start=%s end=%s frame_id=%d arc=%s len=%.1f" % [
				i, step.start, step.end, frame_id, is_arc, step.start.distance_to(step.end)])

		prev_frame_id = frame_id

	# Check: did the frame return to identity after two circle hits?
	if circle_hit_count >= 2:
		# Find the step AFTER the second circle hit
		var second_hit_idx := -1
		var hits_seen := 0
		for i in path.steps.size():
			if path.steps[i].hit != null and path.steps[i].hit.segment == arc_seg:
				hits_seen += 1
				if hits_seen == 2:
					second_hit_idx = i
					break
		if second_hit_idx >= 0 and second_hit_idx + 1 < path.steps.size():
			var after: Tracer.Step = path.steps[second_hit_idx + 1]
			print("DIAGNOSTIC [test4] After 2nd circle hit: frame_id=%d is_arc=%s" % [after.frame_id, after.is_arc_step])
			var identity_frame: bool = (after.frame_id == MobiusTransform.IDENTITY_ID)
			print("DIAGNOSTIC [test4] Frame returned to identity? %s" % identity_frame)
			if not identity_frame:
				gut.p("FAILURE: Transform stack did not cancel after two circle reflections")
	else:
		print("DIAGNOSTIC [test4] Only %d circle hits found (need 2 for grazing)" % circle_hit_count)
		# Try different cursor positions
		for cursor in [Vector2(960, 350), Vector2(960, 400), Vector2(1100, 400), Vector2(1050, 380)]:
			aim_dir = Direction.from_coords(player_pos, cursor)
			path = Tracer.trace(player_pos, aim_dir, surfaces, GameState.new())
			var hits := 0
			for step: Tracer.Step in path.steps:
				if step.hit != null and step.hit.segment == arc_seg:
					hits += 1
			if hits >= 2:
				print("DIAGNOSTIC [test4] cursor=%s gives %d circle hits — use this!" % [cursor, hits])

	assert_true(true, "Diagnostic test — check DIAGNOSTIC output above")


func test_is_inverse_of_with_realistic_drift() -> void:
	var carrier := GeneralizedCircle.from_circle(Vector2(960, 540), 200.0)
	var start := Vector2(1160, 540)
	var end_v := Vector2(760, 540)
	var via := Vector2(960, 340)
	var seg := Segment.from_coords(start, end_v, via)
	var seg_carrier := seg.get_carrier()

	var effect := ReflectionEffect.new(seg_carrier)
	var mobius := effect.get_mobius()

	# Re-derive carrier (simulating incremental normalization)
	var t_seg := Segment.from_coords(
		mobius.apply(start), mobius.apply(end_v), mobius.apply(via))
	var re_derived := t_seg.get_carrier()

	# Create two TrackedTransforms
	var t1 := TrackedTransform.from_self_inverse(mobius, seg_carrier)
	var t2 := TrackedTransform.from_self_inverse(mobius, re_derived)

	var result := t1.is_inverse_of(t2)
	print("DIAGNOSTIC [test5] is_inverse_of result: %s" % result)

	if not result:
		print("DIAGNOSTIC [test5] Breaking down the comparison:")
		print("DIAGNOSTIC [test5]   t1.inverse == t2: %s" % (t1.inverse == t2))
		print("DIAGNOSTIC [test5]   t1.carrier null: %s  t2.carrier null: %s" % [t1.carrier == null, t2.carrier == null])
		if t1.carrier != null and t2.carrier != null:
			print("DIAGNOSTIC [test5]   is_line: t1=%s t2=%s" % [t1.carrier.is_line(), t2.carrier.is_line()])
			if not t1.carrier.is_line() and not t2.carrier.is_line():
				var cd := t1.carrier.center().distance_to(t2.carrier.center())
				var rd := absf(t1.carrier.radius() - t2.carrier.radius())
				print("DIAGNOSTIC [test5]   center_dist=%.10f (threshold 1e-6, exceeds=%s)" % [cd, cd > 1e-6])
				print("DIAGNOSTIC [test5]   radius_diff=%.10f (threshold 1e-6, exceeds=%s)" % [rd, rd > 1e-6])
				print("DIAGNOSTIC [test5]   C1: center=%s radius=%.10f" % [t1.carrier.center(), t1.carrier.radius()])
				print("DIAGNOSTIC [test5]   C2: center=%s radius=%.10f" % [t2.carrier.center(), t2.carrier.radius()])
	else:
		print("DIAGNOSTIC [test5] is_inverse_of PASSED — geometry tolerance is sufficient")

	assert_true(true, "Diagnostic test — check DIAGNOSTIC output above")
