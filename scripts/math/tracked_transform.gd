class_name TrackedTransform
extends RefCounted

var mobius: MobiusTransform
var inverse: TrackedTransform
var carrier: GeneralizedCircle = null

static func from_self_inverse(m: MobiusTransform, p_carrier: GeneralizedCircle = null) -> TrackedTransform:
	var t := TrackedTransform.new()
	t.mobius = m
	t.inverse = t
	t.carrier = p_carrier
	return t

static func from_pair(forward: MobiusTransform, backward: MobiusTransform) -> TrackedTransform:
	var f := TrackedTransform.new()
	var b := TrackedTransform.new()
	f.mobius = forward
	f.inverse = b
	b.mobius = backward
	b.inverse = f
	return f

func is_inverse_of(other: TrackedTransform) -> bool:
	if inverse == other:
		return true
	if carrier == null or other.carrier == null:
		return false
	if carrier.is_line() != other.carrier.is_line():
		return false
	if carrier.is_line():
		var mag1 := sqrt(carrier.b * carrier.b + carrier.c * carrier.c)
		var mag2 := sqrt(other.carrier.b * other.carrier.b + other.carrier.c * other.carrier.c)
		if mag1 < 1e-10 or mag2 < 1e-10:
			return false
		return absf(carrier.b / mag1 - other.carrier.b / mag2) < 1e-6 and absf(carrier.c / mag1 - other.carrier.c / mag2) < 1e-6 and absf(carrier.d / mag1 - other.carrier.d / mag2) < 1e-6
	return carrier.center().distance_to(other.carrier.center()) < 1e-6 and absf(carrier.radius() - other.carrier.radius()) < 1e-6

static func identity() -> TrackedTransform:
	var t := TrackedTransform.new()
	t.mobius = MobiusTransform.identity()
	t.inverse = t
	return t
