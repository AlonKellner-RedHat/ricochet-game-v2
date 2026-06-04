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

static func build(traced_path: Tracer.TracedPath, player_pos: Vector2, cursor_pos: Vector2, surfaces: Array, bounds: Rect2 = Tracer.DEFAULT_BOUNDS, planned_path: Planner.PlannedPath = null) -> Array:
	if traced_path == null or traced_path.steps.size() == 0:
		return []

	if planned_path != null and planned_path.steps.size() > 0:
		return _build_with_plan(traced_path, planned_path, player_pos, cursor_pos, surfaces, bounds)
	else:
		return _build_no_plan(traced_path, player_pos, cursor_pos, surfaces, bounds)

static func _build_no_plan(traced_path: Tracer.TracedPath, player_pos: Vector2, cursor_pos: Vector2, surfaces: Array, bounds: Rect2) -> Array:
	var cursor_dist: float = player_pos.distance_to(cursor_pos)
	var cursor_dir: Vector2 = (cursor_pos - player_pos).normalized()

	var div_index := _find_divergence_no_plan(traced_path, cursor_dist, surfaces)

	if div_index < 0:
		return _split_at_cursor_dist(traced_path, cursor_dist)
	else:
		var div_point: Vector2 = traced_path.steps[div_index - 1].end if div_index > 0 else player_pos
		var result: Array = []
		result.append_array(_build_aligned_before(traced_path, div_index, cursor_dist))
		result.append(TypedStep.new(div_point, cursor_pos, StepTypes.Type.DIVERGED_PLANNED))
		result.append_array(_build_post_planned_physical(cursor_pos, cursor_dir, surfaces, bounds))
		result.append_array(_build_physical_from(traced_path, div_index))
		return result

static func _build_with_plan(traced_path: Tracer.TracedPath, _planned_path: Planner.PlannedPath, _player_pos: Vector2, cursor_pos: Vector2, _surfaces: Array, _bounds: Rect2) -> Array:
	var result: Array = []

	for i in traced_path.steps.size():
		var step: Tracer.Step = traced_path.steps[i]
		result.append(TypedStep.new(step.start, step.end, StepTypes.Type.ALIGNED))

	var last_phys_point: Vector2 = traced_path.steps[traced_path.steps.size() - 1].end

	if last_phys_point.distance_to(cursor_pos) > 1.0:
		result.append(TypedStep.new(last_phys_point, cursor_pos, StepTypes.Type.DIVERGED_PLANNED))

	return result

static func _find_divergence_no_plan(phys_path: Tracer.TracedPath, cursor_dist: float, surfaces: Array) -> int:
	var accumulated := 0.0
	for i in phys_path.steps.size():
		var step: Tracer.Step = phys_path.steps[i]
		var step_len: float = step.start.distance_to(step.end)

		if step.hit != null and accumulated + step_len <= cursor_dist + 0.01:
			var config: SideConfig = _get_config_for_hit(step.hit, surfaces)
			if config != null and config.effect != null:
				return i + 1

		accumulated += step_len
		if accumulated >= cursor_dist:
			return -1

	return -1

static func _split_at_cursor_dist(path: Tracer.TracedPath, cursor_dist: float) -> Array:
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

static func _build_aligned_before(path: Tracer.TracedPath, div_index: int, cursor_dist: float) -> Array:
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

static func _build_post_planned_physical(cursor_pos: Vector2, cursor_dir: Vector2, surfaces: Array, bounds: Rect2) -> Array:
	var dir := Direction.new(cursor_pos, cursor_pos + cursor_dir)
	var post_trace := Tracer.trace(cursor_pos, dir, surfaces, GameState.new(), bounds)
	var result: Array = []
	for i in post_trace.steps.size():
		var step: Tracer.Step = post_trace.steps[i]
		result.append(TypedStep.new(step.start, step.end, StepTypes.Type.DIVERGED_POST_PLANNED))
	return result

static func _build_physical_from(path: Tracer.TracedPath, div_index: int) -> Array:
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
