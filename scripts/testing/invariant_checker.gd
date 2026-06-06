class_name InvariantChecker
extends RefCounted

func setup(_scene: Node) -> void:
	pass

func check_all(_player_pos: Vector2, _cursor_pos: Vector2) -> Array[String]:
	return []

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
