class_name TrackedTransform
extends RefCounted

var mobius: MobiusTransform
var inverse: TrackedTransform

static func from_self_inverse(m: MobiusTransform) -> TrackedTransform:
	var t := TrackedTransform.new()
	t.mobius = m
	t.inverse = t
	return t

static func from_pair(forward: MobiusTransform, backward: MobiusTransform) -> TrackedTransform:
	var f := TrackedTransform.new()
	var b := TrackedTransform.new()
	f.mobius = forward
	f.inverse = b
	b.mobius = backward
	b.inverse = f
	return f

static func identity() -> TrackedTransform:
	var t := TrackedTransform.new()
	t.mobius = MobiusTransform.identity()
	t.inverse = t
	return t
