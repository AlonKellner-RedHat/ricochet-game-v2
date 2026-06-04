class_name PreviewBuilder
extends RefCounted

class TypedStep extends RefCounted:
	var start: Vector2
	var end: Vector2
	var type: StepTypes.Type

	func _init(p_start: Vector2, p_end: Vector2, p_type: StepTypes.Type) -> void:
		start = p_start
		end = p_end
		type = p_type

static func build(traced_path: Tracer.TracedPath, player_pos: Vector2, cursor_pos: Vector2, surfaces: Array, bounds: Rect2 = Tracer.DEFAULT_BOUNDS) -> Array:
	if traced_path == null or traced_path.steps.size() == 0:
		return []

	var cursor_dist: float = player_pos.distance_to(cursor_pos)
	var cursor_dir: Vector2 = (cursor_pos - player_pos).normalized()
	var typed_steps: Array = []

	var div := _find_divergence(traced_path, cursor_dist, surfaces)
	var div_index: int = div[0]
	var div_point: Vector2 = div[1]

	if div_index < 0:
		typed_steps.append_array(_build_aligned(traced_path, player_pos, cursor_pos, cursor_dist))
	else:
		typed_steps.append_array(_build_aligned_before_div(traced_path, div_index, div_point, cursor_dist))
		typed_steps.append_array(_build_diverged_planned(div_point, cursor_pos, cursor_dir))
		typed_steps.append_array(_build_diverged_post_planned(cursor_pos, cursor_dir, surfaces, bounds))
		typed_steps.append_array(_build_diverged_physical(traced_path, div_index))

	return typed_steps

static func _find_divergence(path: Tracer.TracedPath, cursor_dist: float, surfaces: Array) -> Array:
	var accumulated := 0.0
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		var step_len: float = step.start.distance_to(step.end)

		if step.hit != null and accumulated + step_len <= cursor_dist + 0.01:
			var config: SideConfig = _get_config_for_hit(step.hit, surfaces)
			if config != null and config.effect != null:
				return [i + 1, step.end]

		accumulated += step_len
		if accumulated >= cursor_dist:
			return [-1, Vector2.ZERO]

	return [-1, Vector2.ZERO]

static func _build_aligned(path: Tracer.TracedPath, _player_pos: Vector2, _cursor_pos: Vector2, cursor_dist: float) -> Array:
	var result: Array = []
	var accumulated := 0.0

	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		var step_len: float = step.start.distance_to(step.end)
		var dist_at_end: float = accumulated + step_len

		if accumulated < cursor_dist and dist_at_end >= cursor_dist:
			var t: float = (cursor_dist - accumulated) / step_len if step_len > 0.0 else 1.0
			var split: Vector2 = step.start.lerp(step.end, t)
			result.append(TypedStep.new(step.start, split, StepTypes.Type.ALIGNED))
			result.append(TypedStep.new(split, step.end, StepTypes.Type.ALIGNED_POST_PLANNED))
		elif accumulated < cursor_dist:
			result.append(TypedStep.new(step.start, step.end, StepTypes.Type.ALIGNED))
		else:
			result.append(TypedStep.new(step.start, step.end, StepTypes.Type.ALIGNED_POST_PLANNED))

		accumulated += step_len

	return result

static func _build_aligned_before_div(path: Tracer.TracedPath, div_index: int, _div_point: Vector2, cursor_dist: float) -> Array:
	var result: Array = []
	var accumulated := 0.0

	for i in range(0, div_index):
		var step: Tracer.Step = path.steps[i]
		var step_len: float = step.start.distance_to(step.end)

		if accumulated + step_len <= cursor_dist:
			result.append(TypedStep.new(step.start, step.end, StepTypes.Type.ALIGNED))
		else:
			var t: float = (cursor_dist - accumulated) / step_len if step_len > 0.0 else 1.0
			var split: Vector2 = step.start.lerp(step.end, t)
			result.append(TypedStep.new(step.start, split, StepTypes.Type.ALIGNED))

		accumulated += step_len

	return result

static func _build_diverged_planned(div_point: Vector2, cursor_pos: Vector2, _cursor_dir: Vector2) -> Array:
	return [TypedStep.new(div_point, cursor_pos, StepTypes.Type.DIVERGED_PLANNED)]

static func _build_diverged_post_planned(cursor_pos: Vector2, cursor_dir: Vector2, surfaces: Array, bounds: Rect2) -> Array:
	var dir := Direction.new(cursor_pos, cursor_pos + cursor_dir)
	var post_trace := Tracer.trace(cursor_pos, dir, surfaces, GameState.new(), bounds)
	var result: Array = []
	for i in post_trace.steps.size():
		var step: Tracer.Step = post_trace.steps[i]
		result.append(TypedStep.new(step.start, step.end, StepTypes.Type.DIVERGED_POST_PLANNED))
	return result

static func _build_diverged_physical(path: Tracer.TracedPath, div_index: int) -> Array:
	var result: Array = []
	for i in range(div_index, path.steps.size()):
		var step: Tracer.Step = path.steps[i]
		result.append(TypedStep.new(step.start, step.end, StepTypes.Type.DIVERGED_PHYSICAL))
	return result

static func _get_config_for_hit(hit: RefCounted, surfaces: Array) -> SideConfig:
	for surf in surfaces:
		if surf.segment == hit.segment:
			return surf.active_side_config(hit.side, GameState.new())
	return null
