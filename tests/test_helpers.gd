extends RefCounted

static func wall(x: float) -> Surface:
	return RoomBuilder.create_block_surface(Vector2(x, 0), Vector2(x, 600), Vector2(x, 300))

static func wall_between(start: Vector2, end_v: Vector2) -> Surface:
	var via := (start + end_v) / 2.0
	return RoomBuilder.create_block_surface(start, end_v, via)

static func mirror(x: float, y_start: float = 0.0, y_end: float = 600.0) -> Surface:
	var mid := (y_start + y_end) / 2.0
	var seg := Segment.from_coords(Vector2(x, y_start), Vector2(x, y_end), Vector2(x, mid))
	var refl := ReflectionEffect.new(seg.get_carrier())
	var config := SideConfig.new(refl, true)
	return Surface.new(seg, config, config, false, false)

static func find_nearest(ray: Ray, segments: Array, skip_segment: Segment = null) -> Intersection.HitRecord:
	var hits := Intersection.find_all_hits(ray, segments, skip_segment)
	if hits.is_empty():
		return null
	var forward: Array = []
	var beyond: Array = []
	for h in hits:
		if h.t > 0.0:
			forward.append(h)
		else:
			beyond.append(h)
	var pool := forward if not forward.is_empty() else beyond
	var best: Intersection.HitRecord = pool[0]
	for i in range(1, pool.size()):
		if pool[i].t < best.t or (pool[i].t == best.t and pool[i].segment.get_instance_id() < best.segment.get_instance_id()):
			best = pool[i]
	return best

static func reset_counters() -> void:
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()
