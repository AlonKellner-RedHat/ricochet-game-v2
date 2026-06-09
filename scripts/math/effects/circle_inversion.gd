class_name CircleInversionEffect
extends TransformativeEffect

var _mobius: MobiusTransform

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

func get_mobius() -> MobiusTransform:
	return _mobius

func get_inverse_mobius() -> MobiusTransform:
	return _mobius

func normalized(carrier: GeneralizedCircle) -> Effect:
	return CircleInversionEffect.new(carrier)
