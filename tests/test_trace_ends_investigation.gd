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

func test_investigate_trace_ends():
	var surfaces: Array = _scene.surfaces
	gut.p("=== Scene surfaces (%d) ===" % surfaces.size())
	for i in surfaces.size():
		var s: Surface = surfaces[i]
		gut.p("  [%d] id=%d start=%s end=%s" % [i, s.id, s.segment.start.coords, s.segment.end.coords])
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
			"name": "V2: planned, player=(1155, 250)",
			"player": Vector2(1155.0, 250.0),
			"cursor": Vector2(765.0, 395.0),
			"plan": [[4, 0], [5, 0], [6, 1]],
			"trace": "planned",
			"expected_end": Vector2(100.2043, 583.3397),
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
		gut.p("")

	pass_test("Investigation complete — see diagnostic output above")
