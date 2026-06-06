class_name Intersection
extends RefCounted

static func intersect_line_with_carrier(ray: Ray, carrier: GeneralizedCircle) -> Array:
	var origin := ray.origin
	var dir := ray.direction.to_vector()
	if dir.length_squared() == 0.0:
		return []

	var ox := origin.x
	var oy := origin.y
	var dx := dir.x
	var dy := dir.y

	var qa := carrier.a * (dx * dx + dy * dy)
	var qb := 2.0 * carrier.a * (ox * dx + oy * dy) + carrier.b * dx + carrier.c * dy
	var qc := carrier.a * (ox * ox + oy * oy) + carrier.b * ox + carrier.c * oy + carrier.d

	var t_values: Array[float] = []
	if qa == 0.0:
		if qb == 0.0:
			return []
		t_values.append(-qc / qb)
	else:
		var discriminant := qb * qb - 4.0 * qa * qc
		if discriminant < 0.0:
			return []
		elif discriminant == 0.0:
			t_values.append(-qb / (2.0 * qa))
		else:
			var sqrt_d := sqrt(discriminant)
			t_values.append((-qb - sqrt_d) / (2.0 * qa))
			t_values.append((-qb + sqrt_d) / (2.0 * qa))

	var results: Array = []
	for t in t_values:
		var point := origin + t * dir
		if point == ray.origin:
			continue
		results.append({"t": t, "point": point})
	return results
