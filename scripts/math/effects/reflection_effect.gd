class_name ReflectionEffect
extends TransformativeEffect

func _init(carrier: GeneralizedCircle) -> void:
	_carrier = carrier
	var alpha := Vector2(-carrier.b, -carrier.c)
	var beta := Vector2(-2.0 * carrier.d, 0.0)
	var gamma := Vector2(2.0 * carrier.a, 0.0)
	var delta := Vector2(carrier.b, -carrier.c)
	_mobius = MobiusTransform.new(alpha, beta, gamma, delta, true)
	_tracked = TrackedTransform.from_self_inverse(_mobius, carrier)

func normalized(carrier: GeneralizedCircle) -> Effect:
	if carrier == _carrier:
		return self
	return ReflectionEffect.new(carrier)

func get_display_name() -> String:
	return "reflect"

func get_display_color() -> Color:
	return Color.BLUE
