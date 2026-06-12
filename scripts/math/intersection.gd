class_name Intersection
extends RefCounted

class HitRecord extends RefCounted:
	var t: float
	var point: Point
	var segment: Segment
	var side: Side.Value
	var on_segment: bool
	var at_endpoint: int
	var blocked_left: bool
	var blocked_right: bool

	func _init(p_t: float, p_point: Vector2, p_segment: Segment, p_side: Side.Value, p_on_segment: bool, p_at_endpoint: int = 0, p_blocked_left: bool = false, p_blocked_right: bool = false) -> void:
		t = p_t
		point = Point.at(p_point)
		segment = p_segment
		side = p_side
		on_segment = p_on_segment
		at_endpoint = p_at_endpoint
		blocked_left = p_blocked_left
		blocked_right = p_blocked_right

	func is_fully_blocked() -> bool:
		return blocked_left and blocked_right

static func find_nearest_hit(ray: Ray, segments: Array, _skip_point: Vector2 = Vector2(NAN, NAN), skip_segment: Segment = null, t_offset: float = 0.0) -> HitRecord:
	var forward: Array = []
	var beyond: Array = []

	for seg in segments:
		if skip_segment != null and seg == skip_segment:
			continue
		var carrier: GeneralizedCircle = seg.get_carrier()
		var hits := _intersect_ray_carrier(ray, carrier)
		for hit_dict in hits:
			var point: Vector2 = hit_dict["point"]
			var on_seg := is_on_segment(point, seg)
			var side := _determine_side(ray, point, seg)
			var ep := at_which_endpoint(point, seg) if on_seg else 0
			var bl := false
			var br := false
			if on_seg:
				if ep == 0:
					bl = true
					br = true
				else:
					var sides := endpoint_blocked_sides(point, seg, ray, ep)
					bl = sides[0]
					br = sides[1]
			var record := HitRecord.new(hit_dict["t"], point, seg, side, on_seg, ep, bl, br)
			if hit_dict["t"] > t_offset:
				forward.append(record)
			else:
				beyond.append(record)

	if forward.size() > 0:
		return _pick_nearest(forward)
	elif beyond.size() > 0:
		return _pick_nearest(beyond)
	return null

static func find_all_hits(ray: Ray, segments: Array, skip_segment: Segment = null) -> Array:
	var results: Array = []
	for seg in segments:
		if skip_segment != null and seg == skip_segment:
			continue
		var carrier: GeneralizedCircle = seg.get_carrier()
		var hits := _intersect_ray_carrier(ray, carrier)
		for hit_dict in hits:
			var point: Vector2 = hit_dict["point"]
			var on_seg := is_on_segment(point, seg)
			var side := _determine_side(ray, point, seg)
			var ep := at_which_endpoint(point, seg) if on_seg else 0
			var bl := false
			var br := false
			if on_seg:
				if ep == 0:
					bl = true
					br = true
				else:
					var sides := endpoint_blocked_sides(point, seg, ray, ep)
					bl = sides[0]
					br = sides[1]
			results.append(HitRecord.new(hit_dict["t"], point, seg, side, on_seg, ep, bl, br))
	return results

static func projective_sort(hits: Array) -> Array:
	var sorted := hits.duplicate()
	sorted.sort_custom(func(a: HitRecord, b: HitRecord) -> bool:
		var a_zero := absf(a.t) < 1e-12
		var b_zero := absf(b.t) < 1e-12
		if a_zero and b_zero:
			return false
		if a_zero:
			return false
		if b_zero:
			return true
		var a_pos := a.t > 0.0
		var b_pos := b.t > 0.0
		if a_pos and not b_pos:
			return true
		if not a_pos and b_pos:
			return false
		if a.t == b.t:
			var a_id := a.segment.get_instance_id() if a.segment != null else -1
			var b_id := b.segment.get_instance_id() if b.segment != null else -1
			return a_id < b_id
		return a.t < b.t
	)
	return sorted

static func build_stage_hitpoints(ray: Ray, segments: Array, skip_segment: Segment = null) -> Array:
	var hits := find_all_hits(ray, segments, skip_segment)
	var origin_hit := HitRecord.new(0.0, ray.origin.coords, null, Side.Value.LEFT, false)
	hits.append(origin_hit)
	return projective_sort(hits)

static func intersect_line_with_carrier(ray: Ray, carrier: GeneralizedCircle) -> Array:
	return _intersect_ray_carrier(ray, carrier)

# Cross-ratio containment: P is on arc S→V→E iff Re(cross_ratio(S,P;E,V)) >= 0
static func is_on_segment(point: Vector2, segment: Segment) -> bool:
	var zP := Vector2(point.x, point.y)
	var wP := 1.0
	var zS := Vector2(segment.start.coords.x, segment.start.coords.y)
	var wS := 1.0
	var zE := Vector2(segment.end.coords.x, segment.end.coords.y)
	var wE := 1.0
	var zV: Vector2
	var wV: float
	if is_inf(segment.via.coords.x) or is_inf(segment.via.coords.y):
		zV = Vector2(1.0, 0.0)
		wV = 0.0
	else:
		zV = Vector2(segment.via.coords.x, segment.via.coords.y)
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

	var ox := ray.origin.coords.x
	var oy := ray.origin.coords.y
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
		var point := ray.origin.coords + t * dir
		results.append({"t": t, "point": point})
	return results

static func project_point_on_ray(ray: Ray, point: Vector2) -> float:
	var dir := ray.direction.to_vector()
	var dir_len_sq := dir.length_squared()
	if dir_len_sq == 0.0:
		return 0.0
	return (point - ray.origin.coords).dot(dir) / dir_len_sq

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

static func at_which_endpoint(point: Vector2, segment: Segment, eps: float = 0.01) -> int:
	if point.distance_to(segment.start.coords) < eps:
		return 1
	if point.distance_to(segment.end.coords) < eps:
		return 2
	return 0

static func tangent_into_segment(segment: Segment, which_endpoint: int) -> Vector2:
	var carrier := segment.get_carrier()
	if carrier.is_line():
		if which_endpoint == 1:
			return (segment.end.coords - segment.start.coords).normalized()
		else:
			return (segment.start.coords - segment.end.coords).normalized()
	var center := carrier.center()
	var ep := segment.start.coords if which_endpoint == 1 else segment.end.coords
	var radius_dir := ep - center
	var perp_ccw := Vector2(-radius_dir.y, radius_dir.x)
	var perp_cw := Vector2(radius_dir.y, -radius_dir.x)
	var ref := segment.via.coords - ep
	if perp_ccw.dot(ref) >= perp_cw.dot(ref):
		return perp_ccw.normalized()
	return perp_cw.normalized()

static func endpoint_blocked_sides(point: Vector2, segment: Segment, ray: Ray, which_endpoint: int) -> Array:
	if which_endpoint == 0:
		var on_seg := is_on_segment(point, segment)
		return [on_seg, on_seg]
	var tangent := tangent_into_segment(segment, which_endpoint)
	var ray_dir := ray.direction.to_vector().normalized()
	var cross := ray_dir.cross(tangent)
	if absf(cross) < 1e-9:
		return [true, true]
	if cross > 0:
		return [false, true]
	return [true, false]
