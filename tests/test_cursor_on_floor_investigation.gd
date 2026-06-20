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

func _dump_path(path: Tracer.TracedPath, label: String) -> void:
	if path == null:
		gut.p("  %s: NULL path" % label)
		return
	gut.p("  %s: %d steps, cursor_index=%d" % [label, path.steps.size(), path.cursor_index])
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		var hit_desc := "null"
		if step.hit != null:
			if step.hit.segment != null:
				hit_desc = "seg(t=%.6f, on=%s, side=%d, bl=%s, br=%s)" % [
					step.hit.t, step.hit.on_segment, step.hit.side,
					step.hit.blocked_left, step.hit.blocked_right]
			else:
				hit_desc = "null-seg(t=%.6f)" % step.hit.t
		gut.p("    step[%d]: start=%s end=%s fid=%d hit=%s" % [
			i, step.start, step.end, step.frame_id, hit_desc])

func _carrier_dist(point: Vector2, carrier: GeneralizedCircle) -> float:
	var f := carrier.evaluate(point)
	var gx := 2.0 * carrier.a * point.x + carrier.b
	var gy := 2.0 * carrier.a * point.y + carrier.c
	var grad := sqrt(gx * gx + gy * gy)
	if grad < 1e-10:
		return INF
	return absf(f) / grad


# --- Test 1: Full scene reproduction ---

func test_reproduce_cursor_on_floor() -> void:
	var surfaces: Array = _scene.surfaces
	gut.p("=== Scene surfaces (%d) ===" % surfaces.size())
	for i in surfaces.size():
		var s: Surface = surfaces[i]
		gut.p("  [%d] id=%d start=%s end=%s" % [i, s.id, s.segment.start.coords, s.segment.end.coords])
	gut.p("")

	var player_pos := Vector2(960, 250)
	var cursor_pos := Vector2(960, 840)
	var plan := [[4, 0]]

	_setup_and_trace(player_pos, cursor_pos, plan)

	var planned: Tracer.TracedPath = _renderer.get_planned_path()
	var physical: Tracer.TracedPath = _renderer.get_traced_path()

	gut.p("=== Planned trace (PLANNED -> PHYSICAL) ===")
	_dump_path(planned, "planned")

	gut.p("")
	gut.p("=== Physical trace (PHYSICAL -> PHYSICAL) ===")
	_dump_path(physical, "physical")

	var floor_s: Surface = surfaces[1]
	var floor_carrier: GeneralizedCircle = floor_s.segment.get_carrier()
	gut.p("")
	gut.p("=== Floor analysis (surface ID 2) ===")
	gut.p("  Floor carrier: a=%.6f b=%.6f c=%.6f d=%.6f" % [
		floor_carrier.a, floor_carrier.b, floor_carrier.c, floor_carrier.d])

	if planned != null and planned.steps.size() > 0:
		var last: Tracer.Step = planned.steps[planned.steps.size() - 1]
		var dist := _carrier_dist(last.end, floor_carrier)
		gut.p("  Planned last endpoint: %s" % last.end)
		gut.p("  Planned last endpoint dist to floor: %.6f" % dist)
		var crosses_floor := false
		for i in planned.steps.size():
			var step: Tracer.Step = planned.steps[i]
			if step.start.y < 840.0 and step.end.y > 840.0:
				crosses_floor = true
				gut.p("  >>> Step %d crosses floor: start.y=%.2f end.y=%.2f <<<" % [i, step.start.y, step.end.y])
			elif step.end.y > 841.0:
				gut.p("  >>> Step %d ends past floor: end.y=%.2f <<<" % [i, step.end.y])
		if not crosses_floor:
			gut.p("  No step crosses the floor")

		if planned.cursor_index >= 0:
			gut.p("  Cursor injected at step index %d" % planned.cursor_index)
			var steps_after_cursor := planned.steps.size() - planned.cursor_index
			gut.p("  Steps after cursor: %d" % steps_after_cursor)
			var blocked_by_floor_after_cursor := false
			for i in range(planned.cursor_index, planned.steps.size()):
				var step: Tracer.Step = planned.steps[i]
				if step.hit != null and step.hit.segment != null:
					var hit_dist := _carrier_dist(step.hit.point.coords, floor_carrier)
					if hit_dist < 2.0 and step.hit.on_segment:
						blocked_by_floor_after_cursor = true
						gut.p("  Floor hit after cursor at step %d" % i)
			if not blocked_by_floor_after_cursor:
				gut.p("  >>> BUG: No floor hit after cursor — ray passed through <<<")

	pass_test("Investigation complete — see diagnostics above")


# --- Test 2: cursor_t vs floor_t numerical comparison ---

func test_cursor_t_vs_floor_t() -> void:
	var surfaces: Array = _scene.surfaces

	var player_pos := Vector2(960, 250)
	var cursor_pos := Vector2(960, 840)
	var plan_entries: Array = []
	var plan_entry := PlanManager.PlanEntry.new(4, Side.Value.LEFT)
	plan_entries.append(plan_entry)

	var cache := TransformCache.new()
	var aim_dir := Planner.compute_aim_direction(
		player_pos, cursor_pos, plan_entries, surfaces, GameState.new(), cache)
	var aim_ray := Ray.from_coords(player_pos, aim_dir)

	gut.p("=== Aim direction ===")
	gut.p("  aim_dir vector: %s" % aim_dir.to_vector())
	gut.p("  aim_ray origin: %s" % aim_ray.origin.coords)

	var mirror: Surface = null
	for s in surfaces:
		if s.id == 4:
			mirror = s
			break
	var mirror_carrier := mirror.segment.get_carrier()

	var mirror_hits := Intersection.intersect_line_with_carrier(aim_ray, mirror_carrier)
	gut.p("  Mirror carrier hits: %d" % mirror_hits.size())
	var mirror_t: float = -1.0
	var mirror_point := Vector2.ZERO
	for h in mirror_hits:
		gut.p("    t=%.10f point=%s" % [h["t"], h["point"]])
		if h["t"] > 0.0 and (mirror_t < 0 or h["t"] < mirror_t):
			mirror_t = h["t"]
			mirror_point = h["point"]

	gut.p("  Selected mirror hit: t=%.10f point=%s" % [mirror_t, mirror_point])

	var config: SideConfig = mirror.active_side_config(Side.Value.LEFT, GameState.new())
	var tracked: TrackedTransform = config.effect.get_tracked_transform()
	var reflection_mobius: MobiusTransform = tracked.mobius
	var new_origin: Vector2 = tracked.inverse.mobius.apply(mirror_point)
	gut.p("  Post-reflection origin: %s" % new_origin)

	var frame := reflection_mobius
	var frame_inv := frame.invert()
	var aim_in_frame := frame_inv.apply(cursor_pos)
	gut.p("")
	gut.p("=== Post-mirror frame analysis ===")
	gut.p("  aim_in_frame (cursor in normalized space): %s" % aim_in_frame)

	var post_ray := Ray.from_coords(new_origin, aim_dir)

	var cursor_t := Intersection.project_point_on_ray(post_ray, aim_in_frame)
	gut.p("  cursor_t = %.15f" % cursor_t)

	var floor_surf: Surface = null
	for s in surfaces:
		if s.id == 2:
			floor_surf = s
			break
	var floor_carrier := floor_surf.segment.get_carrier()

	var floor_hits := Intersection.intersect_line_with_carrier(post_ray, floor_carrier)
	var floor_t: float = INF
	for h in floor_hits:
		if h["t"] > 0.0 and h["t"] < floor_t:
			floor_t = h["t"]
	gut.p("  floor_t = %.15f" % floor_t)

	var diff := cursor_t - floor_t
	gut.p("  diff (cursor_t - floor_t) = %.15f" % diff)
	gut.p("  cursor sorts first? %s" % (cursor_t < floor_t))

	var floor_eval := floor_carrier.evaluate(aim_in_frame)
	gut.p("")
	gut.p("=== aim_in_frame on floor carrier? ===")
	gut.p("  floor_carrier.evaluate(aim_in_frame) = %.15f" % floor_eval)
	gut.p("  aim_in_frame.y = %.15f (floor at y=840)" % aim_in_frame.y)
	gut.p("  aim_in_frame is exactly on floor? %s" % (floor_eval == 0.0))

	var cursor_hit_point := post_ray.origin.coords + cursor_t * aim_dir.to_vector()
	var floor_hit_point := post_ray.origin.coords + floor_t * aim_dir.to_vector()
	gut.p("")
	gut.p("=== Hit point positions ===")
	gut.p("  cursor hit point: %s" % cursor_hit_point)
	gut.p("  floor hit point:  %s" % floor_hit_point)
	gut.p("  distance between: %.10f" % cursor_hit_point.distance_to(floor_hit_point))

	pass_test("Investigation complete — see numerical analysis above")


# --- Test 3: Differential test — cursor on floor vs above floor ---

func test_differential_cursor_on_vs_above_floor() -> void:
	var cursor_positions := [
		{"label": "ON floor (y=840)", "pos": Vector2(960, 840)},
		{"label": "ABOVE floor (y=835)", "pos": Vector2(960, 835)},
	]

	var player_pos := Vector2(960, 250)
	var plan := [[4, 0]]

	for config in cursor_positions:
		gut.p("=== %s ===" % config.label)
		_setup_and_trace(player_pos, config.pos, plan)

		var planned: Tracer.TracedPath = _renderer.get_planned_path()
		_dump_path(planned, "planned")

		if planned == null or planned.steps.size() == 0:
			gut.p("  No planned trace!")
			continue

		var last: Tracer.Step = planned.steps[planned.steps.size() - 1]
		gut.p("  Last endpoint: %s" % last.end)
		gut.p("  cursor_index: %d" % planned.cursor_index)
		gut.p("  total steps: %d" % planned.steps.size())

		var floor_s2: Surface = _scene.surfaces[1]
		var floor_carrier: GeneralizedCircle = floor_s2.segment.get_carrier()
		var dist := _carrier_dist(last.end, floor_carrier)
		gut.p("  Last endpoint dist to floor carrier: %.6f" % dist)

		var post_cursor_blocked := false
		if planned.cursor_index >= 0:
			for i in range(planned.cursor_index, planned.steps.size()):
				var step: Tracer.Step = planned.steps[i]
				if step.hit != null and step.hit.segment != null and step.hit.on_segment:
					if step.hit.blocked_left and step.hit.blocked_right:
						post_cursor_blocked = true
						gut.p("  Blocked at step %d after cursor" % i)
		gut.p("  Post-cursor blocked by floor: %s" % post_cursor_blocked)
		gut.p("")

	pass_test("Investigation complete — compare ON vs ABOVE floor above")
