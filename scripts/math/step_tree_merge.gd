class_name StepTreeMerge
extends RefCounted

class MergedStep extends RefCounted:
	var start: Vector2
	var end: Vector2
	var type: StepTypes.Type
	var frame_id: int

	func _init(p_start: Vector2, p_end: Vector2, p_type: StepTypes.Type, p_frame_id: int = 0) -> void:
		start = p_start
		end = p_end
		type = p_type
		frame_id = p_frame_id

static func merge(planned_steps: Array, physical_steps: Array, cursor_index: int) -> Array:
	var merged: Array = []
	var diverged := false
	var max_idx: int = maxi(planned_steps.size(), physical_steps.size())

	for idx in max_idx:
		var p: Tracer.Step = planned_steps[idx] if idx < planned_steps.size() else null
		var r: Tracer.Step = physical_steps[idx] if idx < physical_steps.size() else null
		var past_cursor: bool = idx >= cursor_index

		if not diverged:
			if _is_aligned_start(p, r):
				if p.end == r.end:
					var step_type: StepTypes.Type
					if past_cursor:
						step_type = StepTypes.Type.ALIGNED_POST_PLANNED
					else:
						step_type = StepTypes.Type.ALIGNED
					merged.append(MergedStep.new(p.start, p.end, step_type, p.frame_id))
				else:
					var aligned_type: StepTypes.Type = StepTypes.Type.ALIGNED if not past_cursor else StepTypes.Type.ALIGNED_POST_PLANNED
					var p_len: float = p.start.distance_to(p.end)
					var r_len: float = r.start.distance_to(r.end)
					var shorter_end: Vector2 = r.end if r_len <= p_len else p.end
					merged.append(MergedStep.new(p.start, shorter_end, aligned_type, p.frame_id))
					diverged = true
					if p_len > r_len:
						var div_type: StepTypes.Type = StepTypes.Type.DIVERGED_PLANNED if not past_cursor else StepTypes.Type.DIVERGED_POST_PLANNED
						merged.append(MergedStep.new(r.end, p.end, div_type, p.frame_id))
					elif r_len > p_len:
						merged.append(MergedStep.new(p.end, r.end, StepTypes.Type.DIVERGED_PHYSICAL, r.frame_id))
					_append_remaining(merged, planned_steps, physical_steps, idx + 1, cursor_index)
					break
			else:
				diverged = true
				_append_diverged_pair(merged, p, r, past_cursor)
		else:
			_append_diverged_pair(merged, p, r, past_cursor)

	return merged

static func _is_aligned_start(p: Tracer.Step, r: Tracer.Step) -> bool:
	if p == null or r == null:
		return false
	if p.ray != null and r.ray != null and p.ray != r.ray:
		return false
	if p.frame_id != r.frame_id:
		return false
	if p.start != r.start:
		return false
	return true

static func _append_diverged_pair(merged: Array, p: Tracer.Step, r: Tracer.Step, past_cursor: bool) -> void:
	if p != null:
		var div_type: StepTypes.Type = StepTypes.Type.DIVERGED_PLANNED if not past_cursor else StepTypes.Type.DIVERGED_POST_PLANNED
		merged.append(MergedStep.new(p.start, p.end, div_type, p.frame_id))
	if r != null:
		merged.append(MergedStep.new(r.start, r.end, StepTypes.Type.DIVERGED_PHYSICAL, r.frame_id))

static func _append_remaining(merged: Array, planned_steps: Array, physical_steps: Array, from_idx: int, cursor_index: int) -> void:
	for i in range(from_idx, physical_steps.size()):
		var rem: Tracer.Step = physical_steps[i]
		merged.append(MergedStep.new(rem.start, rem.end, StepTypes.Type.DIVERGED_PHYSICAL, rem.frame_id))
	for i in range(from_idx, planned_steps.size()):
		var rem: Tracer.Step = planned_steps[i]
		var rem_past: bool = i >= cursor_index
		var div_type: StepTypes.Type = StepTypes.Type.DIVERGED_PLANNED if not rem_past else StepTypes.Type.DIVERGED_POST_PLANNED
		merged.append(MergedStep.new(rem.start, rem.end, div_type, rem.frame_id))
