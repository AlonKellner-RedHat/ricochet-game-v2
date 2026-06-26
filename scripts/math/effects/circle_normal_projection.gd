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

func back_propagate(target: Vector2, segment: Segment) -> Variant:
	var carrier := segment.get_carrier()
	var center := carrier.center()
	var dir_to_target := target - center
	if dir_to_target.length_squared() == 0.0:
		return null
	var dir_normalized := dir_to_target.normalized()
	var r := carrier.radius()
	var candidate_near := center + dir_normalized * r
	var candidate_far := center - dir_normalized * r
	if Intersection.is_on_segment(candidate_near, segment):
		return candidate_near
	if Intersection.is_on_segment(candidate_far, segment):
		return candidate_far
	return null

func get_display_name() -> String:
	return "circle_normal_back" if _project_back else "circle_normal"

func get_display_color() -> Color:
	return Color(1.0, 0.4, 0.1) if _project_back else Color(1.0, 0.8, 0.2)
