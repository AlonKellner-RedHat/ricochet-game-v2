class_name InvariantChecker
extends RefCounted

var _scene: Node
var _player: CharacterBody2D
var _cursor: Node2D
var _renderer: Node2D
var _game_mgr: Node

func setup(scene: Node) -> void:
	_scene = scene
	_player = scene.get_node_or_null("Player")
	_cursor = scene.get_node_or_null("Cursor")
	_renderer = scene.get_node_or_null("PathRenderer")
	_game_mgr = scene.get_node_or_null("GameManager")

func check_all(player_pos: Vector2, cursor_pos: Vector2, plan_entries: Array = []) -> Array[String]:
	var violations: Array[String] = []
	_position_nodes(player_pos, cursor_pos)
	var plan_applied := false
	if _game_mgr and "plan" in _game_mgr:
		_game_mgr.plan.clear()
		for entry in plan_entries:
			_game_mgr.plan.add_entry(entry.surface_id, entry.side)
		plan_applied = plan_entries.size() > 0
	if _renderer:
		_renderer._compute_trace()
	violations.append_array(check_UX7(player_pos, cursor_pos))
	violations.append_array(check_PREVIEW_NOGAPS(player_pos, cursor_pos))
	violations.append_array(check_S9(player_pos, cursor_pos))
	violations.append_array(check_S16(player_pos, cursor_pos))
	violations.append_array(check_GREEN_FROM_PLAYER(player_pos, cursor_pos))
	violations.append_array(check_ORIGIN_NOT_REHIT(player_pos, cursor_pos))
	violations.append_array(check_SINGLE_DIVERGENCE(player_pos, cursor_pos))
	violations.append_array(check_PHYSICAL_PREVIEW_MATCH(player_pos, cursor_pos))
	violations.append_array(check_PHYSICAL_CONTINUITY(player_pos, cursor_pos))
	violations.append_array(check_SOLID_PATH_TO_CURSOR(player_pos, cursor_pos))
	violations.append_array(check_TRACE_ENDS_AT_SURFACE_OR_BOUNDS(player_pos, cursor_pos))
	if plan_applied:
		violations.append_array(check_PLAN_EFFECTS_APPLIED(player_pos, cursor_pos, plan_entries))
	violations.append_array(check_BACK_TRANSFORM_ALIGNMENT(player_pos, cursor_pos))
	violations.append_array(check_PHYSICS_COMPLIANCE(player_pos, cursor_pos))
	return violations

func check_UX7(player_pos: Vector2, cursor_pos: Vector2) -> Array[String]:
	var violations: Array[String] = []
	if not _renderer:
		return violations
	if player_pos != cursor_pos:
		if not _renderer.has_line():
			violations.append("UX7: No line when cursor != player")
		else:
			if _renderer.get_line_from() != player_pos:
				violations.append("UX7: Line start %s != player %s" % [_renderer.get_line_from(), player_pos])
			# Direction check only valid for empty plan — with a plan, aim is back-propagated
			var has_plan: bool = _game_mgr != null and "plan" in _game_mgr and not _game_mgr.plan.is_empty()
			if not has_plan:
				var expected_dir := (cursor_pos - player_pos).normalized()
				var actual_dir: Vector2 = _renderer.get_line_direction()
				if expected_dir.dot(actual_dir) < 0.99:
					violations.append("UX7: Direction %s not toward cursor %s" % [actual_dir, expected_dir])
	else:
		if _renderer.has_line():
			violations.append("UX7: Line present when cursor == player")
	return violations

func check_PREVIEW_NOGAPS(player_pos: Vector2, cursor_pos: Vector2) -> Array[String]:
	var violations: Array[String] = []
	if not _renderer or player_pos == cursor_pos:
		return violations
	var path: Tracer.TracedPath = _renderer.get_traced_path()
	if path == null:
		return violations
	for i in range(1, path.steps.size()):
		var prev: Tracer.Step = path.steps[i - 1]
		var curr: Tracer.Step = path.steps[i]
		# Skip gaps at escape/return boundaries (ray wraps through infinity)
		if prev.hit == null or curr.hit == null:
			continue
		if prev.end.distance_to(curr.start) > 0.01:
			violations.append("NOGAPS: Gap between step %d end=%s and step %d start=%s" % [i - 1, prev.end, i, curr.start])
	return violations

func check_S9(player_pos: Vector2, cursor_pos: Vector2) -> Array[String]:
	var violations: Array[String] = []
	if not _renderer or player_pos == cursor_pos:
		return violations
	var path: Tracer.TracedPath = _renderer.get_traced_path()
	if path == null or path.steps.size() < 2:
		return violations
	for i in range(1, path.steps.size()):
		var prev: Tracer.Step = path.steps[i - 1]
		var curr: Tracer.Step = path.steps[i]
		if prev.hit and curr.hit:
			if prev.hit.segment == curr.hit.segment:
				violations.append("S9: Same segment hit at steps %d and %d" % [i - 1, i])
	return violations

func check_S16(player_pos: Vector2, cursor_pos: Vector2) -> Array[String]:
	var violations: Array[String] = []
	if not _renderer or player_pos == cursor_pos:
		return violations
	var path: Tracer.TracedPath = _renderer.get_traced_path()
	if path == null:
		return violations
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		if is_nan(step.start.x) or is_nan(step.start.y):
			violations.append("S16: NaN in step %d start" % i)
		if is_nan(step.end.x) or is_nan(step.end.y):
			violations.append("S16: NaN in step %d end" % i)
	return violations

func check_GREEN_FROM_PLAYER(player_pos: Vector2, cursor_pos: Vector2) -> Array[String]:
	var violations: Array[String] = []
	if not _renderer or player_pos == cursor_pos:
		return violations
	var typed: Array = _renderer.get_typed_steps()
	if typed.size() == 0:
		return violations
	var first: Tracer.Step = typed[0]
	if first.type != StepTypes.Type.ALIGNED and first.type != StepTypes.Type.ALIGNED_POST_PLANNED:
		violations.append("GREEN-FROM-PLAYER: First step type=%d, expected green" % first.type)
	return violations

func check_ORIGIN_NOT_REHIT(player_pos: Vector2, cursor_pos: Vector2) -> Array[String]:
	var violations: Array[String] = []
	if not _renderer or player_pos == cursor_pos:
		return violations
	var path: Tracer.TracedPath = _renderer.get_traced_path()
	if path == null:
		return violations
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		if step.start == step.end:
			if step.hit != null and step.hit.t > 0.0:
				violations.append("ORIGIN-NOT-REHIT: Zero-length step %d at %s" % [i, step.start])
	return violations

func check_SINGLE_DIVERGENCE(player_pos: Vector2, cursor_pos: Vector2) -> Array[String]:
	var violations: Array[String] = []
	if not _renderer or player_pos == cursor_pos:
		return violations
	var typed: Array = _renderer.get_typed_steps()
	var diverged := false
	for i in typed.size():
		var ms: Tracer.Step = typed[i]
		var is_aligned := (ms.type == StepTypes.Type.ALIGNED or ms.type == StepTypes.Type.ALIGNED_POST_PLANNED)
		var is_diverged := not is_aligned
		if is_diverged:
			diverged = true
		elif diverged and is_aligned:
			violations.append("SINGLE-DIVERGENCE: Re-convergence at step %d after divergence" % i)
	return violations

func check_PHYSICAL_PREVIEW_MATCH(player_pos: Vector2, cursor_pos: Vector2) -> Array[String]:
	var violations: Array[String] = []
	if not _renderer or player_pos == cursor_pos:
		return violations
	var typed: Array = _renderer.get_typed_steps()
	if typed.size() == 0:
		return violations
	# The physical trace from the renderer IS the arrow path (both use the same trace)
	var physical: Tracer.TracedPath = _renderer.get_traced_path()
	if physical == null:
		return violations
	# Extract non-red preview steps
	var non_red: Array = []
	for i in typed.size():
		var ms: Tracer.Step = typed[i]
		if ms.type == StepTypes.Type.ALIGNED or ms.type == StepTypes.Type.ALIGNED_POST_PLANNED or ms.type == StepTypes.Type.DIVERGED_PHYSICAL:
			non_red.append(ms)
	if non_red.size() != physical.steps.size():
		violations.append("PHYSICAL-PREVIEW-MATCH: non-red count=%d != physical count=%d" % [non_red.size(), physical.steps.size()])
		return violations
	for i in non_red.size():
		var ms: Tracer.Step = non_red[i]
		var ps: Tracer.Step = physical.steps[i]
		if ms.start.distance_to(ps.start) > 0.01:
			violations.append("PHYSICAL-PREVIEW-MATCH: step %d start mismatch: preview=%s physical=%s" % [i, ms.start, ps.start])
		if ms.end.distance_to(ps.end) > 0.01:
			violations.append("PHYSICAL-PREVIEW-MATCH: step %d end mismatch: preview=%s physical=%s" % [i, ms.end, ps.end])
	return violations

func check_PHYSICAL_CONTINUITY(player_pos: Vector2, cursor_pos: Vector2) -> Array[String]:
	var violations: Array[String] = []
	if not _renderer or player_pos == cursor_pos:
		return violations
	var physical: Tracer.TracedPath = _renderer.get_traced_path()
	if physical == null or physical.steps.size() < 2:
		return violations
	for i in range(1, physical.steps.size()):
		var prev: Tracer.Step = physical.steps[i - 1]
		var curr: Tracer.Step = physical.steps[i]
		# Only skip gaps at escape/return boundaries (beyond-hit with t < 0)
		var prev_is_escape: bool = (prev.hit == null) or (prev.hit != null and prev.hit.t < 0.0)
		var curr_is_return: bool = (curr.hit != null and curr.hit.t < 0.0)
		if prev_is_escape or curr_is_return:
			continue
		if prev.end.distance_to(curr.start) > 0.01:
			violations.append("PHYSICAL-CONTINUITY: gap between step %d end=%s and step %d start=%s" % [i - 1, prev.end, i, curr.start])
	return violations

func check_SOLID_PATH_TO_CURSOR(player_pos: Vector2, cursor_pos: Vector2) -> Array[String]:
	var violations: Array[String] = []
	if not _renderer or player_pos == cursor_pos:
		return violations
	var typed: Array = _renderer.get_typed_steps()
	if typed.size() == 0:
		return violations
	var solid_steps: Array = []
	for i in typed.size():
		var ms: Tracer.Step = typed[i]
		if StepTypes.is_solid(ms.type):
			solid_steps.append(ms)
	if solid_steps.size() == 0:
		return violations
	var first: Tracer.Step = solid_steps[0]
	if first.start != player_pos:
		violations.append("SOLID-PATH-TO-CURSOR: first solid step starts at %s, not player %s" % [first.start, player_pos])
	var bounds := Tracer.DEFAULT_BOUNDS
	for i in range(1, solid_steps.size()):
		var prev: Tracer.Step = solid_steps[i - 1]
		var curr: Tracer.Step = solid_steps[i]
		if prev.end.distance_to(curr.start) > 0.01:
			# Skip gaps at escape/return boundaries (ray wraps through infinity)
			var at_bounds := (prev.end.x <= bounds.position.x + 1.0 or prev.end.x >= bounds.end.x - 1.0 or
				prev.end.y <= bounds.position.y + 1.0 or prev.end.y >= bounds.end.y - 1.0)
			if not at_bounds:
				violations.append("SOLID-PATH-TO-CURSOR: gap between solid step %d end=%s and step %d start=%s" % [i - 1, prev.end, i, curr.start])
	return violations

func check_TRACE_ENDS_AT_SURFACE_OR_BOUNDS(player_pos: Vector2, cursor_pos: Vector2) -> Array[String]:
	var violations: Array[String] = []
	if not _renderer or player_pos == cursor_pos:
		return violations
	var bounds := Tracer.DEFAULT_BOUNDS
	var surfaces: Array = []
	var parent := _renderer.get_parent()
	if parent and "surfaces" in parent:
		surfaces = parent.surfaces

	for trace_name in ["physical", "planned"]:
		var path: Tracer.TracedPath
		if trace_name == "physical":
			path = _renderer.get_traced_path()
		else:
			path = _renderer.get_planned_path()
		if path == null or path.steps.size() == 0:
			continue
		var last: Tracer.Step = path.steps[path.steps.size() - 1]
		var end_pos: Vector2 = last.end
		var valid := false
		if end_pos.distance_to(player_pos) < 2.0:
			valid = true
		if end_pos.x <= bounds.position.x + 2.0 or end_pos.x >= bounds.end.x - 2.0:
			valid = true
		if end_pos.y <= bounds.position.y + 2.0 or end_pos.y >= bounds.end.y - 2.0:
			valid = true
		for surf in surfaces:
			var s: Surface = surf
			var dist := _point_to_segment_dist(end_pos, s.segment.start.coords, s.segment.end.coords)
			if dist < 2.0:
				valid = true
				break
		# Also check if endpoint is on any surface's carrier (off-segment but on carrier line)
		if not valid:
			for surf in surfaces:
				var s: Surface = surf
				var carrier := s.segment.get_carrier()
				var eval_val := carrier.evaluate(end_pos)
				var grad_mag := sqrt(carrier.b * carrier.b + carrier.c * carrier.c + 4.0 * carrier.a * carrier.a * (end_pos.x * end_pos.x + end_pos.y * end_pos.y))
				var dist_to_carrier := absf(eval_val) / maxf(grad_mag, 1e-10)
				if dist_to_carrier < 2.0:
					valid = true
					break
		if not valid:
			violations.append("TRACE-ENDS: %s trace ends mid-air at %s" % [trace_name, end_pos])
	return violations

func check_PLAN_EFFECTS_APPLIED(player_pos: Vector2, cursor_pos: Vector2, plan_entries: Array) -> Array[String]:
	var violations: Array[String] = []
	if not _renderer or player_pos == cursor_pos or plan_entries.size() == 0:
		return violations
	var planned_path = _renderer.get_planned_path()
	if planned_path == null or planned_path.steps.size() < 2:
		return violations
	# cursor_index == -1 means the plan wasn't consumed (geometrically infeasible)
	if planned_path.cursor_index < 0:
		return violations
	var ci: int = planned_path.cursor_index
	var frame_changes := 0
	for i in range(1, mini(ci + 1, planned_path.steps.size())):
		var prev: Tracer.Step = planned_path.steps[i - 1]
		var curr: Tracer.Step = planned_path.steps[i]
		if prev.frame_id != curr.frame_id:
			frame_changes += 1
	if frame_changes < plan_entries.size():
		violations.append("PLAN-EFFECTS: expected %d frame changes for %d plan entries, got %d" % [plan_entries.size(), plan_entries.size(), frame_changes])
	return violations

func check_BACK_TRANSFORM_ALIGNMENT(player_pos: Vector2, cursor_pos: Vector2) -> Array[String]:
	var violations: Array[String] = []
	if not _renderer or player_pos == cursor_pos:
		return violations
	var path: Tracer.TracedPath = _renderer.get_traced_path()
	if path == null or path.steps.size() == 0:
		return violations
	var bounds := Tracer.DEFAULT_BOUNDS
	var check_limit: int = path.cursor_index if path.cursor_index >= 0 else path.steps.size()
	for i in check_limit:
		var step: Tracer.Step = path.steps[i]
		if step.hit == null:
			continue
		if step.start == step.end:
			continue
		if step.frame == null or step.ray == null:
			continue
		if step.frame.maps_lines_to_arcs():
			continue
		var frame_inv := step.frame.invert()
		var aim_dir := step.ray.direction.to_vector().normalized()
		var origin := step.ray.origin.coords
		var bt_start := frame_inv.apply(step.start)
		var bt_end := frame_inv.apply(step.end)
		var _at_bounds := func(p: Vector2) -> bool:
			return (p.x <= bounds.position.x + 2.0 or p.x >= bounds.end.x - 2.0 or
				p.y <= bounds.position.y + 2.0 or p.y >= bounds.end.y - 2.0)
		if not _at_bounds.call(step.start):
			var cross_s := (bt_start - origin).cross(aim_dir)
			if absf(cross_s) > 1.0:
				violations.append("BACK-TRANSFORM-ALIGNMENT: step %d start cross=%.2f (bt=%s)" % [i, cross_s, bt_start])
		if not _at_bounds.call(step.end):
			var cross_e := (bt_end - origin).cross(aim_dir)
			if absf(cross_e) > 1.0:
				violations.append("BACK-TRANSFORM-ALIGNMENT: step %d end cross=%.2f (bt=%s)" % [i, cross_e, bt_end])
	return violations

func check_PHYSICS_COMPLIANCE(player_pos: Vector2, cursor_pos: Vector2) -> Array[String]:
	var violations: Array[String] = []
	if not _renderer or player_pos == cursor_pos:
		return violations
	var path: Tracer.TracedPath = _renderer.get_traced_path()
	if path == null or path.steps.size() == 0:
		return violations
	var surfaces: Array = []
	var parent := _renderer.get_parent()
	if parent and "surfaces" in parent:
		surfaces = parent.surfaces
	if surfaces.size() == 0:
		return violations
	var check_limit: int = path.cursor_index if path.cursor_index >= 0 else path.steps.size()
	for i in check_limit:
		var step: Tracer.Step = path.steps[i]
		if step.is_arc_step:
			continue
		if step.start == step.end:
			continue
		for surf in surfaces:
			var s: Surface = surf
			var config_l := s.active_side_config(Side.Value.LEFT, GameState.new())
			var config_r := s.active_side_config(Side.Value.RIGHT, GameState.new())
			var has_effect := false
			if config_l != null and config_l.effect != null and config_l.effect.is_transformative():
				has_effect = true
			if config_r != null and config_r.effect != null and config_r.effect.is_transformative():
				has_effect = true
			if s.player_solid:
				has_effect = true
			if not has_effect:
				continue
			var sa := s.segment.start.coords
			var sb := s.segment.end.coords
			var ix := _segment_intersection(step.start, step.end, sa, sb)
			if ix.is_empty():
				continue
			var pt: Vector2 = ix["point"]
			if pt.distance_to(step.start) < 1.0 or pt.distance_to(step.end) < 1.0:
				continue
			if pt.distance_to(sa) < 1.0 or pt.distance_to(sb) < 1.0:
				continue
			violations.append("PHYSICS-COMPLIANCE: step %d crosses surface %d at %s" % [i, s.id, pt])
	return violations

func _segment_intersection(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> Dictionary:
	var d1 := a2 - a1
	var d2 := b2 - b1
	var cross := d1.cross(d2)
	if absf(cross) < 1e-10:
		return {}
	var d := b1 - a1
	var t := d.cross(d2) / cross
	var u := d.cross(d1) / cross
	if t > 0.01 and t < 0.99 and u > 0.01 and u < 0.99:
		return {"point": a1 + d1 * t}
	return {}

func _point_to_segment_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq == 0.0:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + t * ab)

func _position_nodes(player_pos: Vector2, cursor_pos: Vector2) -> void:
	if _player:
		_player.global_position = player_pos
	if _cursor:
		_cursor.global_position = cursor_pos

# --- Static checks (kept from original for stage compatibility) ---

static func check_S11(segment: Segment) -> Array[String]:
	var violations: Array[String] = []
	var carrier := segment.get_carrier()
	var eps := 0.01
	if absf(carrier.evaluate(segment.start.coords)) > eps:
		violations.append("S11: start not on carrier")
	if absf(carrier.evaluate(segment.end.coords)) > eps:
		violations.append("S11: end not on carrier")
	if segment.via.coords != Vector2(INF, INF) and absf(carrier.evaluate(segment.via.coords)) > eps:
		violations.append("S11: via not on carrier")
	return violations

static func check_S12(segment: Segment, test_points: Array[Vector2]) -> Array[String]:
	var violations: Array[String] = []
	for point in test_points:
		var carrier := segment.get_carrier()
		var f_val := carrier.evaluate(point)
		if f_val == 0.0:
			continue
		var side := segment.determine_side(point)
		var traversal := segment.end.coords - segment.start.coords
		var to_point := point - segment.start.coords
		var cross_val := traversal.cross(to_point)
		var expected_side: Side.Value
		if cross_val < 0.0:
			expected_side = Side.Value.LEFT
		else:
			expected_side = Side.Value.RIGHT
		if carrier.is_line() and side != expected_side:
			violations.append("S12: point %s side=%d expected=%d" % [point, side, expected_side])
	return violations

