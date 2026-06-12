class_name CircleInversionEffect
extends TransformativeEffect

var _mobius: MobiusTransform
var _tracked: TrackedTransform

func _init(carrier: GeneralizedCircle) -> void:
	assert(not carrier.is_line(), "CircleInversionEffect requires a circle carrier (a != 0)")
	var ctr := carrier.center()
	var r2 := carrier.radius() * carrier.radius()
	var ctr_mod2 := ctr.x * ctr.x + ctr.y * ctr.y

	var alpha := ctr
	var beta := Vector2(r2 - ctr_mod2, 0.0)
	var gamma := Vector2(1.0, 0.0)
	var delta := Vector2(-ctr.x, ctr.y)

	_mobius = MobiusTransform.new(alpha, beta, gamma, delta, true)
	_tracked = TrackedTransform.from_self_inverse(_mobius)

func get_mobius() -> MobiusTransform:
	return _mobius

func get_inverse_mobius() -> MobiusTransform:
	return _mobius

func get_tracked_transform() -> TrackedTransform:
	return _tracked

func normalized(carrier: GeneralizedCircle) -> Effect:
	return CircleInversionEffect.new(carrier)
