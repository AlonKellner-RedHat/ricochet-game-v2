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
	if planned_steps.size() == 0:
		var result: Array = []
		for i in physical_steps.size():
			var step: Tracer.Step = physical_steps[i]
			result.append(MergedStep.new(step.start, step.end, StepTypes.Type.ALIGNED_POST_PLANNED, step.frame_id))
		return result

	var merged: Array = []
	var diverged := false
	var max_idx: int = maxi(planned_steps.size(), physical_steps.size())

	for idx in max_idx:
		var p: Tracer.Step = planned_steps[idx] if idx < planned_steps.size() else null
		var r: Tracer.Step = physical_steps[idx] if idx < physical_steps.size() else null
		var past_cursor: bool = idx >= cursor_index

		if not diverged:
			if p != null and r != null and p.frame_id == r.frame_id:
				if p.end.distance_to(r.end) < 1.0:
					var step_type: StepTypes.Type
					if past_cursor:
						step_type = StepTypes.Type.ALIGNED_POST_PLANNED
					else:
						step_type = StepTypes.Type.ALIGNED
					merged.append(MergedStep.new(p.start, p.end, step_type, p.frame_id))
				else:
					var p_len: float = p.start.distance_to(p.end)
					var r_len: float = r.start.distance_to(r.end)
					var shorter_end: Vector2 = r.end if r_len <= p_len else p.end
					var aligned_type: StepTypes.Type = StepTypes.Type.ALIGNED if not past_cursor else StepTypes.Type.ALIGNED_POST_PLANNED
					merged.append(MergedStep.new(p.start, shorter_end, aligned_type, p.frame_id))
					diverged = true
					if p_len > r_len:
						if not past_cursor:
							merged.append(MergedStep.new(r.end, p.end, StepTypes.Type.DIVERGED_PLANNED, p.frame_id))
						else:
							merged.append(MergedStep.new(r.end, p.end, StepTypes.Type.DIVERGED_POST_PLANNED, p.frame_id))
					elif r_len > p_len:
						merged.append(MergedStep.new(p.end, r.end, StepTypes.Type.DIVERGED_PHYSICAL, r.frame_id))
					for remaining_idx in range(idx + 1, physical_steps.size()):
						var rem: Tracer.Step = physical_steps[remaining_idx]
						merged.append(MergedStep.new(rem.start, rem.end, StepTypes.Type.DIVERGED_PHYSICAL, rem.frame_id))
					for remaining_idx in range(idx + 1, planned_steps.size()):
						var rem: Tracer.Step = planned_steps[remaining_idx]
						var rem_past: bool = remaining_idx >= cursor_index
						if not rem_past:
							merged.append(MergedStep.new(rem.start, rem.end, StepTypes.Type.DIVERGED_PLANNED, rem.frame_id))
						else:
							merged.append(MergedStep.new(rem.start, rem.end, StepTypes.Type.DIVERGED_POST_PLANNED, rem.frame_id))
					break
			else:
				diverged = true
				if p != null:
					if not past_cursor:
						merged.append(MergedStep.new(p.start, p.end, StepTypes.Type.DIVERGED_PLANNED, p.frame_id))
					else:
						merged.append(MergedStep.new(p.start, p.end, StepTypes.Type.DIVERGED_POST_PLANNED, p.frame_id))
				if r != null:
					merged.append(MergedStep.new(r.start, r.end, StepTypes.Type.DIVERGED_PHYSICAL, r.frame_id))
		else:
			if p != null:
				if not past_cursor:
					merged.append(MergedStep.new(p.start, p.end, StepTypes.Type.DIVERGED_PLANNED, p.frame_id))
				else:
					merged.append(MergedStep.new(p.start, p.end, StepTypes.Type.DIVERGED_POST_PLANNED, p.frame_id))
			if r != null:
				merged.append(MergedStep.new(r.start, r.end, StepTypes.Type.DIVERGED_PHYSICAL, r.frame_id))

	return merged
