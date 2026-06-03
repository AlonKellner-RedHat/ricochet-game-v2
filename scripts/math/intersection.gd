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

	if absf(qa) < 1e-30:
		if absf(qb) < 1e-30:
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
	if segment.is_line():
		return _is_on_line_segment(point, segment)
	return _is_on_arc_segment(point, segment)

static func _is_on_line_segment(point: Vector2, segment: Segment) -> bool:
	var is_inf_segment := is_inf(segment.via.x) or is_inf(segment.via.y)

	var seg_dir := segment.end - segment.start
	var to_point := point - segment.start
	var seg_len_sq := seg_dir.length_squared()

	if seg_len_sq == 0.0:
		return point == segment.start

	var param := seg_dir.dot(to_point) / seg_len_sq
	var is_between := param >= 0.0 and param <= 1.0

	if is_inf_segment:
		return not is_between
	return is_between

static func _is_on_arc_segment(point: Vector2, segment: Segment) -> bool:
	var carrier := segment.get_carrier()
	var center := carrier.center()

	if segment.start == segment.end:
		return true

	var cp := point - center
	var cs := segment.start - center
	if cp.cross(cs) == 0.0 and cp.dot(cs) > 0.0:
		return true
	var ce := segment.end - center
	if cp.cross(ce) == 0.0 and cp.dot(ce) > 0.0:
		return true

	var cv := segment.via - center

	var cross_sv := cs.cross(cv)
	var cross_sp := cs.cross(cp)
	var cross_ve := cv.cross(ce)
	var cross_vp := cv.cross(cp)

	return _same_sign(cross_sp, cross_sv) and _same_sign(cross_vp, cross_ve)

static func _same_sign(a: float, b: float) -> bool:
	return (a >= 0.0 and b >= 0.0) or (a <= 0.0 and b <= 0.0)
