class_name TransformCache
extends RefCounted

var _carrier_cache: Dictionary = {}
var _via_cache: Dictionary = {}
var _compose_cache: Dictionary = {}
var _inverse_cache: Dictionary = {}
var _norm_cache: Dictionary = {}

func derive_carrier_cached(start: Point, end_pt: Point, via: Point) -> GeneralizedCircle:
	var key := Vector3i(start.id, end_pt.id, via.id)
	if _carrier_cache.has(key):
		return _carrier_cache[key]

	var seg := Segment.new(start.position, end_pt.position, via.position)
	var carrier := seg.get_carrier()

	_carrier_cache[key] = carrier
	var reverse_key := Vector3i(start.id, end_pt.id, -1)
	_via_cache[reverse_key] = via

	return carrier

func derive_via_cached(start: Point, end_pt: Point, _carrier: GeneralizedCircle) -> Point:
	var reverse_key := Vector3i(start.id, end_pt.id, -1)
	if _via_cache.has(reverse_key):
		return _via_cache[reverse_key]
	return null

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

func clear() -> void:
	_carrier_cache.clear()
	_via_cache.clear()
	_compose_cache.clear()
	_inverse_cache.clear()
	_norm_cache.clear()
