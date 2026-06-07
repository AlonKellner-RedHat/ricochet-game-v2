class_name InvariantChecker
extends RefCounted

var _scene: Node
var _player: CharacterBody2D
var _cursor: Node2D
var _renderer: Node2D

func setup(scene: Node) -> void:
	_scene = scene
	_player = scene.get_node_or_null("Player")
	_cursor = scene.get_node_or_null("Cursor")
	_renderer = scene.get_node_or_null("PathRenderer")

func check_all(player_pos: Vector2, cursor_pos: Vector2) -> Array[String]:
	var violations: Array[String] = []
	_position_nodes(player_pos, cursor_pos)
	if _renderer:
		_renderer._compute_trace()
	violations.append_array(check_UX7(player_pos, cursor_pos))
	violations.append_array(check_PREVIEW_NOGAPS(player_pos, cursor_pos))
	violations.append_array(check_S9(player_pos, cursor_pos))
	violations.append_array(check_S16(player_pos, cursor_pos))
	violations.append_array(check_GREEN_FROM_PLAYER(player_pos, cursor_pos))
	violations.append_array(check_ORIGIN_NOT_REHIT(player_pos, cursor_pos))
	violations.append_array(check_SINGLE_DIVERGENCE(player_pos, cursor_pos))
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
	var first: StepTreeMerge.MergedStep = typed[0]
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
		var ms: StepTreeMerge.MergedStep = typed[i]
		var is_aligned := (ms.type == StepTypes.Type.ALIGNED or ms.type == StepTypes.Type.ALIGNED_POST_PLANNED)
		var is_diverged := not is_aligned
		if is_diverged:
			diverged = true
		elif diverged and is_aligned:
			violations.append("SINGLE-DIVERGENCE: Re-convergence at step %d after divergence" % i)
	return violations

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
	if absf(carrier.evaluate(segment.start)) > eps:
		violations.append("S11: start not on carrier")
	if absf(carrier.evaluate(segment.end)) > eps:
		violations.append("S11: end not on carrier")
	if segment.via != Vector2(INF, INF) and absf(carrier.evaluate(segment.via)) > eps:
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
		var traversal := segment.end - segment.start
		var to_point := point - segment.start
		var cross_val := traversal.cross(to_point)
		var expected_side: Side.Value
		if cross_val < 0.0:
			expected_side = Side.Value.LEFT
		else:
			expected_side = Side.Value.RIGHT
		if carrier.is_line() and side != expected_side:
			violations.append("S12: point %s side=%d expected=%d" % [point, side, expected_side])
	return violations

static func check_S1(cache: TransformCache, start: Point, end_pt: Point, via: Point) -> Array[String]:
	var violations: Array[String] = []
	var carrier := cache.derive_carrier_cached(start, end_pt, via)
	var recovered := cache.derive_via_cached(start, end_pt, carrier)
	if recovered == null:
		violations.append("S1: derive_via returned null")
	elif recovered.id != via.id:
		violations.append("S1: round-trip via ID %d != original %d" % [recovered.id, via.id])
	return violations

static func check_S17(points: Array[Point]) -> Array[String]:
	var violations: Array[String] = []
	var seen_ids: Dictionary = {}
	for p in points:
		if seen_ids.has(p.id):
			violations.append("S17: duplicate Point ID %d" % p.id)
		seen_ids[p.id] = true
	return violations
