class_name Intersection
extends RefCounted

class HitCandidate extends RefCounted:
	var t: float
	var point: Vector2
	var segment: Segment

	func _init(p_t: float, p_point: Vector2, p_segment: Segment) -> void:
		t = p_t
		point = p_point
		segment = p_segment

class HitRecord extends RefCounted:
	var t: float
	var point: Vector2
	var segment: Segment
	var side: Side.Value

	func _init(p_t: float, p_point: Vector2, p_segment: Segment, p_side: Side.Value) -> void:
		t = p_t
		point = p_point
		segment = p_segment
		side = p_side

static func find_earliest_hit(ray: Ray, segments: Array, excluded_segments: Array = []) -> RefCounted:
	var excluded_set: Dictionary = {}
	for seg in excluded_segments:
		excluded_set[seg] = true

	var forward: Array = []
	var beyond: Array = []

	for seg in segments:
		if excluded_set.has(seg):
			continue
		var candidates := intersect_line_with_gcircle(ray, seg)
		for candidate in candidates:
			if candidate.point == ray.origin:
				continue
			var side := _determine_side_at_hit(ray, candidate)
			var record := HitRecord.new(candidate.t, candidate.point, candidate.segment, side)
			if candidate.t > 0.0:
				forward.append(record)
			else:
				beyond.append(record)

	if forward.size() > 0:
		return _select_winner(forward, true)
	elif beyond.size() > 0:
		return _select_winner(beyond, false)
	return null

static func _select_winner(hits: Array, pick_smallest: bool) -> RefCounted:
	var winner = hits[0]
	for i in range(1, hits.size()):
		var hit = hits[i]
		if pick_smallest:
			if hit.t < winner.t:
				winner = hit
			elif hit.t == winner.t and hit.segment.get_instance_id() < winner.segment.get_instance_id():
				winner = hit
		else:
			if hit.t < winner.t:
				winner = hit
			elif hit.t == winner.t and hit.segment.get_instance_id() < winner.segment.get_instance_id():
				winner = hit
	return winner

static func _determine_side_at_hit(ray: Ray, candidate: HitCandidate) -> Side.Value:
	var dir := ray.direction.to_vector().normalized()
	var approach_point := candidate.point - dir * 0.001
	return candidate.segment.determine_side(approach_point)

static func intersect_line_with_gcircle(ray: Ray, segment: Segment) -> Array:
	var origin := ray.origin
	var dir := ray.direction.to_vector()

	if dir.length_squared() == 0.0:
		return []

	var carrier := segment.get_carrier()
	var ox := origin.x
	var oy := origin.y
	var dx := dir.x
	var dy := dir.y

	var qa := carrier.a * (dx * dx + dy * dy)
	var qb := 2.0 * carrier.a * (ox * dx + oy * dy) + carrier.b * dx + carrier.c * dy
	var qc := carrier.a * (ox * ox + oy * oy) + carrier.b * ox + carrier.c * oy + carrier.d

	var t_values: Array[float] = []

	if qa == 0.0:
		if qb == 0.0:
			return []
		t_values.append(-qc / qb)
	else:
		var discriminant := qb * qb - 4.0 * qa * qc
		if discriminant < 0.0:
			return []
		elif discriminant == 0.0:
			t_values.append(-qb / (2.0 * qa))
		else:
			var sqrt_d := sqrt(discriminant)
			t_values.append((-qb - sqrt_d) / (2.0 * qa))
			t_values.append((-qb + sqrt_d) / (2.0 * qa))

	var results: Array = []
	for t in t_values:
		var point := origin + t * dir
		if _is_on_segment(point, segment):
			results.append(HitCandidate.new(t, point, segment))
	return results

static func _is_on_segment(point: Vector2, segment: Segment) -> bool:
	var zP := Vector2(point.x, point.y)
	var wP := 1.0
	var zS := Vector2(segment.start.x, segment.start.y)
	var wS := 1.0
	var zE := Vector2(segment.end.x, segment.end.y)
	var wE := 1.0
	var zV: Vector2
	var wV: float
	if is_inf(segment.via.x) or is_inf(segment.via.y):
		zV = Vector2(1.0, 0.0)
		wV = 0.0
	else:
		zV = Vector2(segment.via.x, segment.via.y)
		wV = 1.0

	var sv := _hdet(zS, wS, zV, wV)
	var ep := _hdet(zE, wE, zP, wP)
	var sp := _hdet(zS, wS, zP, wP)
	var ev := _hdet(zE, wE, zV, wV)

	var num := MobiusTransform.cmul(sv, ep)
	var den := MobiusTransform.cmul(sp, ev)

	var den_conj := MobiusTransform.cconj(den)
	var product := MobiusTransform.cmul(num, den_conj)
	return product.x >= 0.0

static func _hdet(zA: Vector2, wA: float, zB: Vector2, wB: float) -> Vector2:
	return Vector2(zA.x * wB - zB.x * wA, zA.y * wB - zB.y * wA)

static func _same_sign(a: float, b: float) -> bool:
	return (a >= 0.0 and b >= 0.0) or (a <= 0.0 and b <= 0.0)
