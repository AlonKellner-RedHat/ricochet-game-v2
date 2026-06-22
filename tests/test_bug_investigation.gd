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
# PROOF TESTS
# ============================================================

func test_proof_G1_wrap_via_not_on_carrier() -> void:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var surface_carrier := surf.segment.get_carrier()

	var player := Vector2(960, 600)
	var aim := Direction.from_coords(player, Vector2(700, 540))
	var path := Tracer.trace(player, aim, [surf], GameState.new())

	var on_carrier := 0
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if not s.is_arc_step:
			continue
		var eval_via := surface_carrier.evaluate(s.via)
		if absf(eval_via) < 1.0:
			on_carrier += 1

	assert_eq(on_carrier, 0,
		"No reflected arc via should sit on the surface carrier (arc must curve outward)")


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
	assert_gte(transitions.size(), 1,
		"Collinear ray with walls should enter reflected frame. Got transitions=%s" % [transitions])
	assert_lt(path.steps.size(), 20,
		"With walls visible, collinear ray should terminate quickly (not bounce 32 times). Got %d steps" % path.steps.size())


func _circle_and_walls() -> Dictionary:
	var center := Vector2(960, 540)
	var r := 200.0
	var surf := _full_circle_mirror(center, r)
	var walls := RoomBuilder.create_room_surfaces(Rect2(160, 90, 1600, 900))
	var surfaces: Array = [surf]
	surfaces.append_array(walls)
	return {"surf": surf, "walls": walls, "surfaces": surfaces, "center": center, "r": r, "carrier": surf.segment.get_carrier()}


func test_inner_full_circle_ray_stays_trapped() -> void:
	var d := _circle_and_walls()
	var surfaces: Array = d["surfaces"]
	var carrier: GeneralizedCircle = d["carrier"]

	var player := Vector2(960, 600)
	var aim := Direction.from_coords(player, Vector2(700, 540))
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if s.hit != null:
			var hit_eval := absf(carrier.evaluate(s.hit.point.coords))
			assert_lt(hit_eval, 1.0,
				"Full-circle inner ray should only hit the circle carrier, not walls. step %d eval=%.2f" % [i, hit_eval])


func test_outer_circle_with_walls_hits_walls() -> void:
	var d := _circle_and_walls()
	var surfaces: Array = d["surfaces"]
	var carrier: GeneralizedCircle = d["carrier"]

	var player := Vector2(600, 540)
	var aim := Direction.from_coords(player, Vector2(1300, 540))
	var path := Tracer.trace(player, aim, surfaces, GameState.new())

	var reflected_wall_hits := 0
	for i in path.steps.size():
		var s: Tracer.Step = path.steps[i]
		if s.frame.conjugating and s.hit != null:
			var hit_eval := carrier.evaluate(s.hit.point.coords)
			if absf(hit_eval) > 10.0:
				reflected_wall_hits += 1

	assert_gt(reflected_wall_hits, 0,
		"Outer reflected ray should hit walls inside the circle")
