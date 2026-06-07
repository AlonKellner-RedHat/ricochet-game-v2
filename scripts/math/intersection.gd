class_name Intersection
extends RefCounted

class HitRecord extends RefCounted:
	var t: float
	var point: Vector2
	var segment: Segment
	var side: Side.Value
	var on_segment: bool

	func _init(p_t: float, p_point: Vector2, p_segment: Segment, p_side: Side.Value, p_on_segment: bool) -> void:
		t = p_t
		point = p_point
		segment = p_segment
		side = p_side
		on_segment = p_on_segment

static func find_nearest_hit(ray: Ray, segments: Array, skip_segment: Segment = null) -> HitRecord:
	var forward: Array = []
	var beyond: Array = []

	for seg in segments:
		if seg == skip_segment:
			continue
		var carrier: GeneralizedCircle = seg.get_carrier()
		var hits := _intersect_ray_carrier(ray, carrier)
		for hit_dict in hits:
			var point: Vector2 = hit_dict["point"]
			if point == ray.origin:
				continue
			var on_seg := is_on_segment(point, seg)
			var side := _determine_side(ray, point, seg)
			var record := HitRecord.new(hit_dict["t"], point, seg, side, on_seg)
			if hit_dict["t"] > 0.0:
				forward.append(record)
			else:
				beyond.append(record)

	if forward.size() > 0:
		return _pick_nearest(forward)
	elif beyond.size() > 0:
		return _pick_nearest(beyond)
	return null

static func intersect_line_with_carrier(ray: Ray, carrier: GeneralizedCircle) -> Array:
	return _intersect_ray_carrier(ray, carrier)

static func is_on_segment(point: Vector2, segment: Segment) -> bool:
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

static func _intersect_ray_carrier(ray: Ray, carrier: GeneralizedCircle) -> Array:
	var dir := ray.direction.to_vector()
	if dir.length_squared() == 0.0:
		return []

	var ox := ray.origin.x
	var oy := ray.origin.y
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
		var point := ray.origin + t * dir
		if point == ray.origin:
			continue
		results.append({"t": t, "point": point})
	return results

static func project_point_on_ray(ray: Ray, point: Vector2) -> float:
	var dir := ray.direction.to_vector()
	var dir_len_sq := dir.length_squared()
	if dir_len_sq == 0.0:
		return 0.0
	return (point - ray.origin).dot(dir) / dir_len_sq

static func _determine_side(ray: Ray, point: Vector2, seg: Segment) -> Side.Value:
	var carrier: GeneralizedCircle = seg.get_carrier()
	var dir := ray.direction.to_vector().normalized()
	var grad := Vector2(2.0 * carrier.a * point.x + carrier.b,
						2.0 * carrier.a * point.y + carrier.c)
	var approach_f_sign := -dir.dot(grad)
	var winding := seg._compute_winding()
	if winding >= 0.0:
		return Side.Value.LEFT if approach_f_sign > 0.0 else Side.Value.RIGHT
	else:
		return Side.Value.RIGHT if approach_f_sign > 0.0 else Side.Value.LEFT

static func _pick_nearest(hits: Array) -> HitRecord:
	var winner: HitRecord = hits[0]
	for i in range(1, hits.size()):
		var hit: HitRecord = hits[i]
		if hit.t < winner.t:
			winner = hit
		elif hit.t == winner.t and hit.segment.get_instance_id() < winner.segment.get_instance_id():
			winner = hit
	return winner

static func _hdet(zA: Vector2, wA: float, zB: Vector2, wB: float) -> Vector2:
	return Vector2(zA.x * wB - zB.x * wA, zA.y * wB - zB.y * wA)
