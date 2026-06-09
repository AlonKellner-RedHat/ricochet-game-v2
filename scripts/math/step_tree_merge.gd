class_name StepTreeMerge
extends RefCounted

class MergedStep extends RefCounted:
	var start: Vector2
	var end: Vector2
	var via: Vector2
	var type: StepTypes.Type
	var frame_id: int

	func _init(p_start: Vector2, p_end: Vector2, p_type: StepTypes.Type, p_frame_id: int = 0, p_via: Vector2 = Vector2.ZERO) -> void:
		start = p_start
		end = p_end
		type = p_type
		frame_id = p_frame_id
		via = p_via if p_via != Vector2.ZERO else (p_start + p_end) / 2.0

static func classify_physical(path: Tracer.TracedPath) -> Array:
	var result: Array = []
	var ci: int = path.cursor_index
	if ci < 0:
		ci = path.steps.size()
	for idx in path.steps.size():
		var s: Tracer.Step = path.steps[idx]
		var step_type: StepTypes.Type
		if idx < ci:
			step_type = StepTypes.Type.ALIGNED
		else:
			step_type = StepTypes.Type.ALIGNED_POST_PLANNED
		result.append(MergedStep.new(s.start, s.end, step_type, s.frame_id, s.via))
	return result

static func merge(planned_steps: Array, physical_steps: Array, cursor_index: int) -> Array:
	var merged: Array = []
	var diverged := false
	var max_len: int = maxi(planned_steps.size(), physical_steps.size())

	for idx in max_len:
		var p: Tracer.Step = planned_steps[idx] if idx < planned_steps.size() else null
		var r: Tracer.Step = physical_steps[idx] if idx < physical_steps.size() else null
		var past_cursor: bool = idx >= cursor_index

		if not diverged and p != null and r != null and p.frame_id == r.frame_id:
			var step_type: StepTypes.Type
			if past_cursor:
				step_type = StepTypes.Type.ALIGNED_POST_PLANNED
			else:
				step_type = StepTypes.Type.ALIGNED
			merged.append(MergedStep.new(p.start, p.end, step_type, p.frame_id, p.via))
		else:
			diverged = true
			if p != null:
				var div_type: StepTypes.Type
				if past_cursor:
					div_type = StepTypes.Type.DIVERGED_POST_PLANNED
				else:
					div_type = StepTypes.Type.DIVERGED_PLANNED
				merged.append(MergedStep.new(p.start, p.end, div_type, p.frame_id, p.via))
			if r != null:
				merged.append(MergedStep.new(r.start, r.end, StepTypes.Type.DIVERGED_PHYSICAL, r.frame_id, r.via))

	return merged
