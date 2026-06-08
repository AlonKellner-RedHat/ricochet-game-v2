class_name Effect
extends RefCounted

func is_terminal() -> bool:
	return false

func is_transformative() -> bool:
	return false

func get_mobius() -> MobiusTransform:
	return MobiusTransform.identity()

func get_inverse_mobius() -> MobiusTransform:
	return get_mobius().invert()

func normalized(_carrier: GeneralizedCircle) -> Effect:
	return self
