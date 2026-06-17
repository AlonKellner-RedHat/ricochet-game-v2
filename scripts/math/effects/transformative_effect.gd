class_name TransformativeEffect
extends Effect

func kind() -> int:
	return Kind.TRANSFORMATIVE

var _mobius: MobiusTransform
var _tracked: TrackedTransform
var _carrier: GeneralizedCircle

func get_mobius() -> MobiusTransform:
	return _mobius

func get_inverse_mobius() -> MobiusTransform:
	return _mobius

func get_tracked_transform() -> TrackedTransform:
	return _tracked
