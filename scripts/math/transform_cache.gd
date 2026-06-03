class_name TransformCache
extends RefCounted

var _carrier_cache: Dictionary = {}
var _via_cache: Dictionary = {}

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

func clear() -> void:
	_carrier_cache.clear()
	_via_cache.clear()
