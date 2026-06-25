class_name TransformCache
extends RefCounted

var _carrier_cache: Dictionary = {}
var _via_cache: Dictionary = {}
var _compose_cache: Dictionary = {}
var _inverse_cache: Dictionary = {}
var _norm_cache: Dictionary = {}
var _point_cache: Dictionary = {}

func derive_carrier_cached(start: Vector2, end_pt: Vector2, via: Vector2) -> GeneralizedCircle:
	var key := "%s|%s|%s" % [var_to_str(start), var_to_str(end_pt), var_to_str(via)]
	if _carrier_cache.has(key):
		return _carrier_cache[key]

	var seg := Segment.from_coords(start, end_pt, via)
	var carrier := seg.get_carrier()

	_carrier_cache[key] = carrier
	var reverse_key := "%s|%s" % [var_to_str(start), var_to_str(end_pt)]
	_via_cache[reverse_key] = via

	return carrier

func derive_via_cached(start: Vector2, end_pt: Vector2, _carrier: GeneralizedCircle) -> Vector2:
	var reverse_key := "%s|%s" % [var_to_str(start), var_to_str(end_pt)]
	if _via_cache.has(reverse_key):
		return _via_cache[reverse_key]
	return Vector2(NAN, NAN)

func compose_cached(a: MobiusTransform, b: MobiusTransform) -> MobiusTransform:
	var key := Vector2i(a.id, b.id)
	if _compose_cache.has(key):
		return _compose_cache[key]
	var result := a.compose(b)
	_compose_cache[key] = result
	return result

func invert_cached(t: MobiusTransform) -> MobiusTransform:
	if _inverse_cache.has(t.id):
		return _inverse_cache[t.id]
	var result := t.invert()
	_inverse_cache[t.id] = result
	_inverse_cache[result.id] = t
	return result

func get_normalized(frame_id: int) -> Variant:
	if _norm_cache.has(frame_id):
		return _norm_cache[frame_id]
	return null

func set_normalized(frame_id: int, surfaces: Array, mapping: Dictionary) -> void:
	_norm_cache[frame_id] = {"surfaces": surfaces, "mapping": mapping}

func apply_point(transform: MobiusTransform, point: Vector2, inverse: MobiusTransform = null) -> Vector2:
	var key := Vector3(transform.id, point.x, point.y)
	if _point_cache.has(key):
		return _point_cache[key]
	var result := transform.apply(point)
	_point_cache[key] = result
	if inverse:
		var rev_key := Vector3(inverse.id, result.x, result.y)
		if not _point_cache.has(rev_key):
			_point_cache[rev_key] = point
	return result

func clear() -> void:
	_carrier_cache.clear()
	_via_cache.clear()
	_compose_cache.clear()
	_inverse_cache.clear()
	_norm_cache.clear()
	_point_cache.clear()
