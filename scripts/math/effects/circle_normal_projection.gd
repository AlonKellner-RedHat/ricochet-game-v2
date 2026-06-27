class_name CircleNormalProjection
extends Effect

var _project_back: bool

func _init(project_back: bool = false) -> void:
	_project_back = project_back

func kind() -> int:
	return Kind.PROJECTIVE

func apply_forward(hit_point: Vector2, segment: Segment, side: int) -> Ray:
	var carrier := segment.get_carrier()
	var center := carrier.center()
	var radial := (hit_point - center).normalized()
	var radial_side := segment.determine_side(hit_point + radial)
	var radial_toward_entry := (radial_side == side)
	if _project_back:
		radial_toward_entry = not radial_toward_entry
	var exit_dir := -radial if radial_toward_entry else radial
	var direction := Direction.from_coords(hit_point, hit_point + exit_dir)
	return Ray.from_coords(hit_point, direction)

func get_display_name() -> String:
	return "circle_normal_back" if _project_back else "circle_normal"

func get_display_color() -> Color:
	return Color(1.0, 0.4, 0.1) if _project_back else Color(1.0, 0.8, 0.2)
