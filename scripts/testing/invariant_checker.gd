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
	return violations

func check_UX7(player_pos: Vector2, cursor_pos: Vector2) -> Array[String]:
	var violations: Array[String] = []
	if not _renderer:
		violations.append("UX7: PathRenderer not found in scene")
		return violations

	if player_pos != cursor_pos:
		if not _renderer.has_line():
			violations.append("UX7: No line when cursor != player (player=%s, cursor=%s)" % [player_pos, cursor_pos])
		else:
			if _renderer.get_line_from() != player_pos:
				violations.append("UX7: Line start %s != player %s" % [_renderer.get_line_from(), player_pos])
			var expected_dir := (cursor_pos - player_pos).normalized()
			var actual_dir: Vector2 = _renderer.get_line_direction()
			if expected_dir.dot(actual_dir) < 0.99:
				violations.append("UX7: Line direction %s not toward cursor direction %s" % [actual_dir, expected_dir])
	else:
		if _renderer.has_line():
			violations.append("UX7: Line present when cursor == player at %s" % [player_pos])

	return violations

func check_PREVIEW_NOGAPS(player_pos: Vector2, cursor_pos: Vector2) -> Array[String]:
	var violations: Array[String] = []
	if not _renderer or player_pos == cursor_pos:
		return violations

	var path = _renderer.get_traced_path()
	if path == null:
		return violations

	for i in range(1, path.steps.size()):
		var prev_end: Vector2 = path.steps[i - 1].end
		var curr_start: Vector2 = path.steps[i].start
		if prev_end.distance_to(curr_start) > 0.01:
			violations.append("PREVIEW-NOGAPS: Gap between step %d end=%s and step %d start=%s" % [i - 1, prev_end, i, curr_start])

	return violations

static func check_S11(segment: Segment) -> Array[String]:
	var violations: Array[String] = []
	var carrier := segment.get_carrier()
	var eps := 0.01
	var f_start := carrier.evaluate(segment.start)
	var f_end := carrier.evaluate(segment.end)
	var f_via := carrier.evaluate(segment.via)
	if absf(f_start) > eps:
		violations.append("S11: start evaluates to %f (expected ~0) on carrier" % f_start)
	if absf(f_end) > eps:
		violations.append("S11: end evaluates to %f (expected ~0) on carrier" % f_end)
	if segment.via != Vector2(INF, INF) and absf(f_via) > eps:
		violations.append("S11: via evaluates to %f (expected ~0) on carrier" % f_via)
	return violations

static func check_S12(segment: Segment, test_points: Array[Vector2]) -> Array[String]:
	var violations: Array[String] = []
	for point in test_points:
		var carrier := segment.get_carrier()
		var f_val := carrier.evaluate(point)
		if absf(f_val) < 1e-10:
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
			violations.append("S12: point %s side=%d expected=%d (cross=%f)" % [point, side, expected_side, cross_val])
	return violations

static func check_S1(cache: TransformCache, start: Point, end_pt: Point, via: Point) -> Array[String]:
	var violations: Array[String] = []
	var carrier := cache.derive_carrier_cached(start, end_pt, via)
	var recovered := cache.derive_via_cached(start, end_pt, carrier)
	if recovered == null:
		violations.append("S1: derive_via returned null — cache miss")
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

func _position_nodes(player_pos: Vector2, cursor_pos: Vector2) -> void:
	if _player:
		_player.global_position = player_pos
	if _cursor:
		_cursor.global_position = cursor_pos
