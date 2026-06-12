class_name ReflectionEffect
extends TransformativeEffect

var _mobius: MobiusTransform
var _tracked: TrackedTransform

func _init(carrier: GeneralizedCircle) -> void:
	var norm: float = sqrt(carrier.b * carrier.b + carrier.c * carrier.c)
	var b_n: float = carrier.b / norm
	var c_n: float = carrier.c / norm
	var d_n: float = carrier.d / norm

	var n := Vector2(b_n, c_n)
	var n_conj := MobiusTransform.cconj(n)

	var alpha := -n_conj
	var beta := Vector2(-2.0 * d_n * n_conj.x, -2.0 * d_n * n_conj.y)
	var gamma := Vector2(0, 0)
	var delta := n

	_mobius = MobiusTransform.new(alpha, beta, gamma, delta, true)
	_tracked = TrackedTransform.from_self_inverse(_mobius)

func get_mobius() -> MobiusTransform:
	return _mobius

func get_inverse_mobius() -> MobiusTransform:
	return _mobius

func get_tracked_transform() -> TrackedTransform:
	return _tracked

func normalized(carrier: GeneralizedCircle) -> Effect:
	return ReflectionEffect.new(carrier)
