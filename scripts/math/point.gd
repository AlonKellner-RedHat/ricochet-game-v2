class_name Point
extends RefCounted

var original: Vector2
var coords: Vector2
var transforms: Array
var frame: MobiusTransform

static func at(position: Vector2) -> Point:
	var p := Point.new()
	p.original = position
	p.coords = position
	p.transforms = []
	p.frame = MobiusTransform.identity()
	return p

func transformed(t: TrackedTransform) -> Point:
	var p := Point.new()
	p.original = original
	p.transforms = _simplify(transforms + [t])
	p.frame = _aggregate(p.transforms)
	if p.transforms.is_empty():
		p.coords = original
	else:
		p.coords = p.frame.apply(original)
	return p

func same_origin(other: Point) -> bool:
	return original == other.original

func same_position(other: Point) -> bool:
	return coords == other.coords

static func _simplify(seq: Array) -> Array:
	var result: Array = []
	for t in seq:
		if result.size() > 0 and result.back().inverse == t:
			result.pop_back()
		else:
			result.append(t)
	return result

static func _aggregate(seq: Array) -> MobiusTransform:
	if seq.is_empty():
		return MobiusTransform.identity()
	var result: MobiusTransform = seq[0].mobius
	for i in range(1, seq.size()):
		result = result.compose(seq[i].mobius)
	return result
