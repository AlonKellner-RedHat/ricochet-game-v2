extends GutTest

const H := preload("res://tests/test_helpers.gd")

func before_each() -> void:
	H.reset_counters()

func _full_circle_mirror(center: Vector2, r: float) -> Surface:
	var carrier := GeneralizedCircle.from_circle(center, r)
	var seg := Segment.full_from_carrier(carrier)
	var refl := ReflectionEffect.new(carrier)
	var config := SideConfig.new(refl, true)
	return Surface.new(seg, config, config, false, false)

func _count_frame_transitions(path: Tracer.TracedPath) -> Array:
	var transitions: Array = []
	var prev_conj := false
	for step in path.steps:
		var s: Tracer.Step = step
		if s.frame.conjugating != prev_conj:
			transitions.append(s.frame.conjugating)
			prev_conj = s.frame.conjugating
	return transitions

func _mirror_and_wall_surfaces() -> Array:
	var top := H.wall_between(Vector2(560, 240), Vector2(1360, 240))
	var bottom := H.wall_between(Vector2(1360, 840), Vector2(560, 840))
	var left := H.wall_between(Vector2(560, 840), Vector2(560, 240))
	var interior := H.wall_between(Vector2(600, 300), Vector2(600, 780))
	var mirror_seg := Segment.from_coords(Vector2(800, 300), Vector2(800, 780), Vector2(800, 540))
	var mirror_carrier := mirror_seg.get_carrier()
	var mirror_refl := ReflectionEffect.new(mirror_carrier)
	var mirror := Surface.new(mirror_seg, SideConfig.new(mirror_refl, true), SideConfig.new(null, false), false, false)
	var sb_top := Surface.new(Segment.from_coords(Vector2(0, 0), Vector2(1920, 0), Vector2(960, 0)),
		SideConfig.new(null, false), SideConfig.new(null, false), false, false)
	var sb_right := Surface.new(Segment.from_coords(Vector2(1920, 0), Vector2(1920, 1080), Vector2(1920, 540)),
		SideConfig.new(null, false), SideConfig.new(null, false), false, false)
	var sb_bottom := Surface.new(Segment.from_coords(Vector2(1920, 1080), Vector2(0, 1080), Vector2(960, 1080)),
		SideConfig.new(null, false), SideConfig.new(null, false), false, false)
	var sb_left := Surface.new(Segment.from_coords(Vector2(0, 1080), Vector2(0, 0), Vector2(0, 540)),
		SideConfig.new(null, false), SideConfig.new(null, false), false, false)
	return [top, bottom, left, interior, mirror, sb_top, sb_right, sb_bottom, sb_left]


# ============================================================
# GROUP 1: Stage 45 Circle Re-hit — Wrap Via Point Bug
# ============================================================

# Step 1a — Diagnostic: dump wrap via values
func test_diag_G1_wrap_via_point_values() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var surface_carrier := surf.segment.get_carrier()
	var sc := surface_carrier.center()
	var sr := surface_carrier.radius()

	print("\n=== GROUP 1: Wrap via point values ===")

	# Inner case: player inside circle
	var inner_player := Vector2(960, 600)
	var inner_aim := Direction.from_coords(inner_player, Vector2(700, 540))
	var inner_path := Tracer.trace(inner_player, inner_aim, [surf], GameState.new())

	print("\n--- Inner case (player inside circle) ---")
	print("Player: %s, Aim toward: (700, 540)" % inner_player)
	print("Steps: %d" % inner_path.steps.size())
	for i in mini(inner_path.steps.size(), 20):
		var s: Tracer.Step = inner_path.steps[i]
		var via_is_inf := is_inf(s.via.x) or is_inf(s.via.y)
		var carrier_info := "N/A"
		if s.is_arc_step and VisualConverter.is_arc(s.start, s.via, s.end):
			var step_carrier := Segment.derive_carrier(s.start, s.end, s.via)
			if not step_carrier.is_line():
				var c := step_carrier.center()
				var cr := step_carrier.radius()
				var match_str := "MATCH" if c.distance_to(sc) < 1.0 and absf(cr - sr) < 1.0 else "MISMATCH"
				carrier_info = "center=(%.1f,%.1f) r=%.1f [%s]" % [c.x, c.y, cr, match_str]
		print("  step %2d: arc=%s frame_id=%d via_inf=%s | start=%s end=%s via=%s | carrier: %s" % [
			i, s.is_arc_step, s.frame_id, via_is_inf, s.start, s.end, s.via, carrier_info])

	# Outer case: player outside circle
	var outer_player := Vector2(600, 540)
	var outer_aim := Direction.from_coords(outer_player, Vector2(1300, 540))
	var outer_path := Tracer.trace(outer_player, outer_aim, [surf], GameState.new())

	print("\n--- Outer case (player outside circle) ---")
	print("Player: %s, Aim toward: (1300, 540)" % outer_player)
	print("Steps: %d" % outer_path.steps.size())
	for i in mini(outer_path.steps.size(), 20):
		var s: Tracer.Step = outer_path.steps[i]
		var via_is_inf := is_inf(s.via.x) or is_inf(s.via.y)
		var carrier_info := "N/A"
		if s.is_arc_step and VisualConverter.is_arc(s.start, s.via, s.end):
			var step_carrier := Segment.derive_carrier(s.start, s.end, s.via)
			if not step_carrier.is_line():
				var c := step_carrier.center()
				var cr := step_carrier.radius()
				var match_str := "MATCH" if c.distance_to(sc) < 1.0 and absf(cr - sr) < 1.0 else "MISMATCH"
				carrier_info = "center=(%.1f,%.1f) r=%.1f [%s]" % [c.x, c.y, cr, match_str]
		print("  step %2d: arc=%s frame_id=%d via_inf=%s | start=%s end=%s via=%s | carrier: %s" % [
			i, s.is_arc_step, s.frame_id, via_is_inf, s.start, s.end, s.via, carrier_info])

	print("\nSurface carrier: center=(%.1f,%.1f) r=%.1f" % [sc.x, sc.y, sr])
	assert_true(true, "Diagnostic — check output above")


# Step 1b — Diagnostic: outer case frame tracking
func test_diag_G1_outer_frame_tracking() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var player := Vector2(600, 540)
	var aim := Direction.from_coords(player, Vector2(1300, 540))
	var path := Tracer.trace(player, aim, [surf], GameState.new())

	print("\n=== GROUP 1: Outer case frame tracking ===")
	print("Total steps: %d" % path.steps.size())

	var frame_ids: Array = []
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if not frame_ids.has(s.frame_id):
			frame_ids.append(s.frame_id)
		print("  step %2d: frame_id=%d conj=%s arc=%s" % [
			i, s.frame_id, s.frame.conjugating, s.is_arc_step])

	var last: Tracer.Step = path.steps[path.steps.size() - 1]
	print("\nDistinct frame_ids: %s" % [frame_ids])
	print("Last step frame_id=%d (identity=%d), is_arc=%s" % [
		last.frame_id, MobiusTransform.IDENTITY_ID, last.is_arc_step])
	print("Returns to identity: %s" % (last.frame_id == MobiusTransform.IDENTITY_ID))

	assert_true(true, "Diagnostic — check output above")


# Step 1c — Evidence: correct vs wrong via
func test_diag_G1_correct_vs_wrong_via() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var surface_carrier := surf.segment.get_carrier()
	var sc := surface_carrier.center()
	var sr := surface_carrier.radius()

	var player := Vector2(960, 600)
	var aim := Direction.from_coords(player, Vector2(700, 540))
	var path := Tracer.trace(player, aim, [surf], GameState.new())

	print("\n=== GROUP 1: Correct vs wrong via point ===")

	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if not s.is_arc_step:
			continue
		if not VisualConverter.is_arc(s.start, s.via, s.end):
			continue

		var wrong_via := s.via
		var wrong_carrier := Segment.derive_carrier(s.start, s.end, wrong_via)

		# Compute correct via: back-transform visual endpoints, take midpoint, re-apply frame
		var frame_inv := s.frame.invert()
		var back_start := frame_inv.apply(s.start)
		var back_end := frame_inv.apply(s.end)
		var back_mid := (back_start + back_end) / 2.0
		var correct_via := s.frame.apply(back_mid)

		var correct_carrier_info := "N/A"
		if not (is_inf(correct_via.x) or is_inf(correct_via.y)):
			var correct_carrier := Segment.derive_carrier(s.start, s.end, correct_via)
			if not correct_carrier.is_line():
				var cc := correct_carrier.center()
				var cr := correct_carrier.radius()
				correct_carrier_info = "center=(%.1f,%.1f) r=%.1f dist_from_surface=%.2f" % [
					cc.x, cc.y, cr, cc.distance_to(sc)]

		var wrong_info := "N/A"
		if not wrong_carrier.is_line():
			var wc := wrong_carrier.center()
			var wr := wrong_carrier.radius()
			wrong_info = "center=(%.1f,%.1f) r=%.1f dist_from_surface=%.2f" % [
				wc.x, wc.y, wr, wc.distance_to(sc)]

		print("  step %d:" % i)
		print("    WRONG via (current):  %s → carrier: %s" % [wrong_via, wrong_info])
		print("    CORRECT via (midpoint): %s → carrier: %s" % [correct_via, correct_carrier_info])
		print("    Surface carrier: center=(%.1f,%.1f) r=%.1f" % [sc.x, sc.y, sr])
		# Only show first arc step as evidence
		break

	assert_true(true, "Diagnostic — check output above [G1c]")


# ============================================================
# GROUP 2: Player Blocking Through Infinity
# ============================================================

# Step 2a — Diagnostic: hitpoint walkthrough
func test_diag_G2_hitpoint_walkthrough() -> void:
	var surfaces := _mirror_and_wall_surfaces()
	var player := Vector2(1350, 250)
	var cursor := Vector2(560, 840)
	var aim := Planner.compute_aim_direction(player, cursor, [], surfaces, GameState.new())
	var path := Tracer.trace(player, aim, surfaces, GameState.new(),
		null, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [], null, cursor)

	print("\n=== GROUP 2: Hitpoint walkthrough ===")
	print("Player: %s, Cursor: %s" % [player, cursor])
	print("Aim direction: %s" % aim)
	print("Total steps: %d, cursor_index: %d" % [path.steps.size(), path.cursor_index])

	var show_count := mini(path.steps.size(), 35)
	for i in show_count:
		var s: Tracer.Step = path.steps[i]
		var hit_info := "null"
		if s.hit != null:
			hit_info = "t=%.4f pt=%s on_seg=%s ep=%d bl=%s br=%s" % [
				s.hit.t, s.hit.point.coords, s.hit.on_segment, s.hit.at_endpoint,
				s.hit.blocked_left, s.hit.blocked_right]
		var cursor_mark := " <<< CURSOR" if i == path.cursor_index else ""
		print("  step %2d: frame_id=%d conj=%s | start=%s end=%s | hit: %s%s" % [
			i, s.frame_id, s.frame.conjugating, s.start, s.end, hit_info, cursor_mark])

	if path.steps.size() > show_count:
		print("  ... (%d more steps) ..." % (path.steps.size() - show_count))
		for i in range(maxi(show_count, path.steps.size() - 3), path.steps.size()):
			var s: Tracer.Step = path.steps[i]
			var hit_info := "null"
			if s.hit != null:
				hit_info = "t=%.4f pt=%s" % [s.hit.t, s.hit.point.coords]
			print("  step %2d: frame_id=%d conj=%s | start=%s end=%s | hit: %s" % [
				i, s.frame_id, s.frame.conjugating, s.start, s.end, hit_info])

	var last: Tracer.Step = path.steps[path.steps.size() - 1]
	print("\nLast step ends at: %s (player at %s, dist=%.2f)" % [
		last.end, player, last.end.distance_to(player)])

	assert_true(true, "Diagnostic — check output above")


# Step 2b — Diagnostic: cursor corner blockage
func test_diag_G2_corner_blockage() -> void:
	var surfaces := _mirror_and_wall_surfaces()
	var player := Vector2(1350, 250)
	var cursor := Vector2(560, 840)
	var aim := Direction.from_coords(player, cursor)
	var ray := Ray.from_coords(player, aim)

	print("\n=== GROUP 2: Corner blockage at cursor position ===")
	print("Cursor: %s" % cursor)
	print("Ray: origin=%s dir=%s" % [ray.origin.coords, ray.direction.to_vector()])

	# Check each surface for hits near cursor
	for surf in surfaces:
		var s: Surface = surf
		var seg := s.segment
		var ep := Intersection.at_which_endpoint(cursor, seg)
		if ep > 0:
			var sides := Intersection.endpoint_blocked_sides(cursor, seg, ray, ep)
			print("  Surface id=%d seg=(%s→%s): cursor at endpoint %d, blocked_left=%s blocked_right=%s" % [
				s.id, seg.start.coords, seg.end.coords, ep, sides[0], sides[1]])
		elif cursor.distance_to(seg.start.coords) < 1.0 or cursor.distance_to(seg.end.coords) < 1.0:
			print("  Surface id=%d seg=(%s→%s): cursor near endpoint but at_which_endpoint returned 0" % [
				s.id, seg.start.coords, seg.end.coords])

	# Also check what t-value cursor has on the ray
	var cursor_t := Intersection.project_point_on_ray(ray, cursor)
	print("\nCursor t-value on ray: %.6f" % cursor_t)

	assert_true(true, "Diagnostic — check output above")


# Step 2c — Evidence: origin_hp after reflection
func test_diag_G2_origin_after_reflection() -> void:
	var surfaces := _mirror_and_wall_surfaces()
	var player := Vector2(1350, 250)
	var cursor := Vector2(560, 840)
	var aim := Planner.compute_aim_direction(player, cursor, [], surfaces, GameState.new())
	var path := Tracer.trace(player, aim, surfaces, GameState.new(),
		null, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [], null, cursor)

	print("\n=== GROUP 2: Origin position after reflection ===")
	print("Player (shared_ray origin): %s" % player)

	# Track frame changes to identify stages
	var prev_frame_id := -1
	var stage := 0
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if s.frame_id != prev_frame_id:
			stage += 1
			prev_frame_id = s.frame_id
			print("  Stage %d starts at step %d: frame_id=%d conj=%s start=%s" % [
				stage, i, s.frame_id, s.frame.conjugating, s.start])
			if stage > 8:
				print("  ... (too many stages, stopping)")
				break

	print("\nTotal stages: %d" % stage)

	assert_true(true, "Diagnostic — check output above")


# Step 2d — Evidence: post-cursor effects
func test_diag_G2_post_cursor_effects() -> void:
	var surfaces := _mirror_and_wall_surfaces()
	var player := Vector2(1350, 250)
	var cursor := Vector2(560, 840)
	var aim := Planner.compute_aim_direction(player, cursor, [], surfaces, GameState.new())
	var path := Tracer.trace(player, aim, surfaces, GameState.new(),
		null, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [], null, cursor)

	print("\n=== GROUP 2: Post-cursor step analysis ===")
	print("cursor_index: %d, total steps: %d" % [path.cursor_index, path.steps.size()])

	if path.cursor_index < 0:
		print("  Cursor was never injected!")
		assert_true(true, "Diagnostic — cursor not injected")
		return

	var post_start := path.cursor_index
	var post_end := mini(path.steps.size(), post_start + 15)
	for i in range(post_start, post_end):
		var s: Tracer.Step = path.steps[i]
		var hit_info := "no hit"
		if s.hit != null:
			hit_info = "t=%.4f pt=%s on_seg=%s ep=%d bl=%s br=%s" % [
				s.hit.t, s.hit.point.coords, s.hit.on_segment, s.hit.at_endpoint,
				s.hit.blocked_left, s.hit.blocked_right]
		print("  step %2d: frame_id=%d conj=%s arc=%s | %s" % [
			i, s.frame_id, s.frame.conjugating, s.is_arc_step, hit_info])

	assert_true(true, "Diagnostic — check output above")


# ============================================================
# GROUP 3: Collinear Ray + Walls
# ============================================================

# Step 3a — Diagnostic: step dump with walls
func test_diag_G3_step_dump() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var walls := RoomBuilder.create_room_surfaces(Rect2(160, 90, 1600, 900))
	var surfaces: Array = [surf]
	surfaces.append_array(walls)
	var player := Vector2(600, 540)
	var aim := Direction.from_coords(player, Vector2(960, 540))
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	print("\n=== GROUP 3: Collinear + walls step dump ===")
	print("Player: %s, Aim toward: (960, 540) — collinear through center" % player)
	print("Total steps: %d" % path.steps.size())

	var transitions := _count_frame_transitions(path)
	print("Frame transitions: %s (count=%d)" % [transitions, transitions.size()])

	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		var hit_info := "null"
		if s.hit != null:
			hit_info = "t=%.4f pt=%s on_seg=%s ep=%d bl=%s br=%s seg=(%s→%s)" % [
				s.hit.t, s.hit.point.coords, s.hit.on_segment, s.hit.at_endpoint,
				s.hit.blocked_left, s.hit.blocked_right,
				str(s.hit.segment.start.coords) if s.hit.segment else "null",
				str(s.hit.segment.end.coords) if s.hit.segment else "null"]
		print("  step %2d: frame_id=%d conj=%s arc=%s | start=%s end=%s | hit: %s" % [
			i, s.frame_id, s.frame.conjugating, s.is_arc_step, s.start, s.end, hit_info])

	assert_true(true, "Diagnostic — check output above")


# Step 3b — Diagnostic: normalized wall positions
func test_diag_G3_normalized_walls() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var carrier := surf.segment.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var tracked := refl.get_tracked_transform()
	var frame := tracked.mobius

	print("\n=== GROUP 3: Normalized wall positions under circle reflection ===")
	print("Circle mirror: center=%s r=%.1f" % [center, r])
	print("Reflection frame: %s" % frame)

	var frame_inv := frame.invert()
	var walls := RoomBuilder.create_room_surfaces(Rect2(160, 90, 1600, 900))

	var ray_origin := Vector2(600, 540)
	var ray_dir := Direction.from_coords(ray_origin, Vector2(960, 540))
	var ray := Ray.from_coords(ray_origin, ray_dir)
	# Normalize the ray through frame_inv
	var norm_origin := frame_inv.apply(ray_origin)
	var norm_dir_pt := frame_inv.apply(ray_origin + ray_dir.to_vector().normalized())
	print("Normalized ray origin: %s" % norm_origin)
	print("Normalized ray direction point: %s" % norm_dir_pt)
	if is_inf(norm_origin.x) or is_inf(norm_origin.y):
		print("WARNING: normalized ray origin is infinite!")
	if is_inf(norm_dir_pt.x) or is_inf(norm_dir_pt.y):
		print("WARNING: normalized ray direction point is infinite!")

	for wall_surf in walls:
		var ws: Surface = wall_surf
		var seg := ws.segment
		var orig_start := seg.start.coords
		var orig_end := seg.end.coords
		var orig_via := seg.via.coords

		var norm_start := frame_inv.apply(orig_start)
		var norm_end := frame_inv.apply(orig_end)
		var norm_via := frame_inv.apply(orig_via)

		var any_large := false
		for pt in [norm_start, norm_end, norm_via]:
			if is_inf(pt.x) or is_inf(pt.y) or absf(pt.x) > 1e6 or absf(pt.y) > 1e6:
				any_large = true

		var flag := " *** LARGE ***" if any_large else ""
		print("\n  Wall id=%d: (%s→%s via %s)%s" % [ws.id, orig_start, orig_end, orig_via, flag])
		print("    Normalized: (%s→%s via %s)" % [norm_start, norm_end, norm_via])

		if not any_large:
			# Find ray-carrier intersections for this normalized wall
			var norm_seg := Segment.from_coords(norm_start, norm_end, norm_via)
			var norm_ray := Ray.from_coords(norm_origin, Direction.from_coords(norm_origin, norm_dir_pt))
			var hits := Intersection.find_all_hits(norm_ray, [norm_seg])
			if hits.size() > 0:
				for h in hits:
					var hr: Intersection.HitRecord = h
					print("    Ray-carrier hit: t=%.6f pt=%s on_seg=%s" % [hr.t, hr.point.coords, hr.on_segment])
			else:
				print("    No ray-carrier intersections")

	assert_true(true, "Diagnostic — check output above")


# Step 3c — Evidence: which wall terminates
func test_diag_G3_which_wall_terminates() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var walls := RoomBuilder.create_room_surfaces(Rect2(160, 90, 1600, 900))
	var surfaces: Array = [surf]
	surfaces.append_array(walls)
	var player := Vector2(600, 540)
	var aim := Direction.from_coords(player, Vector2(960, 540))
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	print("\n=== GROUP 3: Which wall terminates the trace? ===")

	var in_reflected := false
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if s.frame.conjugating and not in_reflected:
			in_reflected = true
			print("  Entered reflected frame at step %d" % i)
		if in_reflected:
			var hit_info := "no surface hit"
			if s.hit != null and s.hit.segment != null:
				hit_info = "seg=(%s→%s) t=%.4f on_seg=%s ep=%d bl=%s br=%s" % [
					s.hit.segment.start.coords, s.hit.segment.end.coords,
					s.hit.t, s.hit.on_segment, s.hit.at_endpoint,
					s.hit.blocked_left, s.hit.blocked_right]
			print("  step %d [reflected]: frame_id=%d | %s" % [i, s.frame_id, hit_info])
		if not s.frame.conjugating and in_reflected:
			print("  Exited reflected frame at step %d" % i)
			in_reflected = false

	if in_reflected:
		print("  NEVER exited reflected frame!")

	# Check last step
	var last: Tracer.Step = path.steps[path.steps.size() - 1]
	print("\nLast step %d: frame_id=%d conj=%s start=%s end=%s" % [
		path.steps.size() - 1, last.frame_id, last.frame.conjugating, last.start, last.end])
	if last.hit != null and last.hit.segment != null:
		print("  Last hit: seg=(%s→%s) t=%.4f bl=%s br=%s" % [
			last.hit.segment.start.coords, last.hit.segment.end.coords,
			last.hit.t, last.hit.blocked_left, last.hit.blocked_right])

	assert_true(true, "Diagnostic — check output above")


# Step 3d — Evidence: comparison with/without walls
func test_diag_G3_with_vs_without_walls() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var walls := RoomBuilder.create_room_surfaces(Rect2(160, 90, 1600, 900))

	var player := Vector2(600, 540)
	var aim := Direction.from_coords(player, Vector2(960, 540))

	var path_no_walls := Tracer.trace(player, aim, [surf], GameState.new())
	var surfaces_with_walls: Array = [surf]
	surfaces_with_walls.append_array(walls)
	var path_with_walls := Tracer.trace(player, aim, surfaces_with_walls, GameState.new())

	var trans_no := _count_frame_transitions(path_no_walls)
	var trans_with := _count_frame_transitions(path_with_walls)

	print("\n=== GROUP 3: With vs without walls ===")
	print("Without walls: %d steps, transitions=%s" % [path_no_walls.steps.size(), trans_no])
	print("With walls:    %d steps, transitions=%s" % [path_with_walls.steps.size(), trans_with])

	print("\n--- Without walls (all steps) ---")
	for i in path_no_walls.steps.size():
		var s: Tracer.Step = path_no_walls.steps[i]
		print("  step %2d: frame_id=%d conj=%s arc=%s start=%s end=%s" % [
			i, s.frame_id, s.frame.conjugating, s.is_arc_step, s.start, s.end])

	print("\n--- With walls (all steps) ---")
	for i in path_with_walls.steps.size():
		var s: Tracer.Step = path_with_walls.steps[i]
		var hit_seg := "null"
		if s.hit != null and s.hit.segment != null:
			hit_seg = "(%s→%s)" % [s.hit.segment.start.coords, s.hit.segment.end.coords]
		print("  step %2d: frame_id=%d conj=%s arc=%s start=%s end=%s | hit_seg=%s" % [
			i, s.frame_id, s.frame.conjugating, s.is_arc_step, s.start, s.end, hit_seg])

	assert_true(true, "Diagnostic [G3d]")


# ============================================================
# PROOF TESTS — should FAIL before fix, PASS after
# ============================================================

func test_proof_G1_wrap_via_on_carrier() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var surface_carrier := surf.segment.get_carrier()
	var sc := surface_carrier.center()
	var sr := surface_carrier.radius()

	var player := Vector2(960, 600)
	var aim := Direction.from_coords(player, Vector2(700, 540))
	var path := Tracer.trace(player, aim, [surf], GameState.new())

	var mismatches := 0
	var details := ""
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if not s.is_arc_step:
			continue
		if not VisualConverter.is_arc(s.start, s.via, s.end):
			continue
		var step_carrier := Segment.derive_carrier(s.start, s.end, s.via)
		if step_carrier.is_line():
			continue
		var c := step_carrier.center()
		var cr := step_carrier.radius()
		if c.distance_to(sc) > 1.0 or absf(cr - sr) > 1.0:
			mismatches += 1
			if mismatches <= 3:
				details += "\n    step %d: center=(%.1f,%.1f) r=%.1f vs surface (%.1f,%.1f) r=%.1f" % [
					i, c.x, c.y, cr, sc.x, sc.y, sr]

	assert_eq(mismatches, 0,
		"All reflected arc steps should use the surface carrier.%s" % details)


func test_proof_G2_trace_reaches_player() -> void:
	var surfaces := _mirror_and_wall_surfaces()
	var player := Vector2(1350, 250)
	var cursor := Vector2(560, 840)
	var aim := Planner.compute_aim_direction(player, cursor, [], surfaces, GameState.new())
	var path := Tracer.trace(player, aim, surfaces, GameState.new(),
		null, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, [], null, cursor)

	assert_gt(path.steps.size(), 0, "Should have at least one step")
	var last: Tracer.Step = path.steps[path.steps.size() - 1]
	assert_almost_eq(last.end, player, Vector2(2, 2),
		"Trace should end at player %s, got %s" % [player, last.end])


func test_proof_G3_collinear_with_walls_reflects() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var walls := RoomBuilder.create_room_surfaces(Rect2(160, 90, 1600, 900))
	var surfaces: Array = [surf]
	surfaces.append_array(walls)
	var player := Vector2(600, 540)
	var aim := Direction.from_coords(player, Vector2(960, 540))
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	var transitions := _count_frame_transitions(path)
	assert_gte(transitions.size(), 2,
		"Collinear ray with walls should enter AND exit reflected frame. Got transitions=%s" % [transitions])
