class_name TransformativeEffect
extends RefCounted

func get_mobius() -> MobiusTransform:
	return MobiusTransform.identity()

func get_inverse_mobius() -> MobiusTransform:
	return get_mobius().invert()
