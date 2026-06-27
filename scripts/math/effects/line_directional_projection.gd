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

func get_display_name() -> String:
	return "line_directional_back" if _project_back else "line_directional"

func get_display_color() -> Color:
	return Color(1.0, 0.4, 0.1) if _project_back else Color(1.0, 0.8, 0.2)
