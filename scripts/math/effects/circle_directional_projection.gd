class_name CircleDirectionalProjection
extends Effect

var _normal: Vector2
var _project_back: bool

func _init(normal_dir: Vector2, project_back: bool = false) -> void:
	_normal = normal_dir.normalized()
	_project_back = project_back

func kind() -> int:
	return Kind.PROJECTIVE

func apply_forward(hit_point: Vector2, segment: Segment, side: int) -> Ray:
	var normal_side := segment.determine_side(hit_point + _normal)
	var normal_toward_entry := (normal_side == side)
	if _project_back:
		normal_toward_entry = not normal_toward_entry
	var exit_dir := -_normal if normal_toward_entry else _normal
	var direction := Direction.from_coords(hit_point, hit_point + exit_dir)
	return Ray.from_coords(hit_point, direction)

func back_propagate(target: Vector2, segment: Segment) -> Variant:
	var carrier := segment.get_carrier()
	var center := carrier.center()
	var r := carrier.radius()
	var v := target - center
	var b_coeff := 2.0 * v.dot(_normal)
	var c_coeff := v.length_squared() - r * r
	var disc := b_coeff * b_coeff - 4.0 * c_coeff
	if disc < 0.0:
		return null
	var sqrt_disc := sqrt(disc)
	var t1 := (-b_coeff + sqrt_disc) / 2.0
	var t2 := (-b_coeff - sqrt_disc) / 2.0
	var p1 := target + t1 * _normal
	var p2 := target + t2 * _normal
	if Intersection.is_on_segment(p1, segment):
		return p1
	if Intersection.is_on_segment(p2, segment):
		return p2
	return null

func get_display_name() -> String:
	return "circle_directional_back" if _project_back else "circle_directional"

func get_display_color() -> Color:
	return Color(1.0, 0.4, 0.1) if _project_back else Color(1.0, 0.8, 0.2)
