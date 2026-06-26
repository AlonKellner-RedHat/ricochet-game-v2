class_name LineDirectionalProjection
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
	var carrier_normal := Vector2(carrier.b, carrier.c)
	var denom := carrier_normal.dot(_normal)
	if absf(denom) < 1e-12:
		return null
	var t := -carrier.evaluate(target) / denom
	var projected := target + t * _normal
	if Intersection.is_on_segment(projected, segment):
		return projected
	return null

func get_display_name() -> String:
	return "line_directional_back" if _project_back else "line_directional"

func get_display_color() -> Color:
	return Color(1.0, 0.4, 0.1) if _project_back else Color(1.0, 0.8, 0.2)
