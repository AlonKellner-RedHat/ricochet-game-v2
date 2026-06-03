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
	var carrier := segment.get_carrier()
	if carrier.is_line():
		return _intersect_line_line(ray, segment, carrier)
	return []

static func _intersect_line_line(ray: Ray, segment: Segment, carrier: GeneralizedCircle) -> Array:
	var origin := ray.origin
	var dir := ray.direction.to_vector()

	if dir.length_squared() == 0.0:
		return []

	var rb := carrier.b
	var rc := carrier.c
	var rd := carrier.d

	var denom := rb * dir.x + rc * dir.y
	if denom == 0.0:
		return []

	var t := -(rb * origin.x + rc * origin.y + rd) / denom
	var point := origin + t * dir

	if not _is_on_line_segment(point, segment):
		return []

	return [HitCandidate.new(t, point, segment)]

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
