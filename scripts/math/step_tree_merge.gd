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
	var min_len: int = mini(planned_steps.size(), physical_steps.size())

	for idx in min_len:
		var p: Tracer.Step = planned_steps[idx]
		var r: Tracer.Step = physical_steps[idx]
		var past_cursor: bool = idx >= cursor_index

		if not diverged:
			var aligned: bool
			if past_cursor:
				# Post-cursor: post-planned and physical are independent PHYSICAL traces
				# with different MobiusTransform ID counters. Compare geometry instead.
				aligned = (p.start == r.start and p.end == r.end)
			else:
				# Pre-cursor: planned and physical share the same ID counter origin.
				aligned = (p.frame_id == r.frame_id)

			if aligned:
				var step_type: StepTypes.Type
				if past_cursor:
					step_type = StepTypes.Type.ALIGNED_POST_PLANNED
				else:
					step_type = StepTypes.Type.ALIGNED
				merged.append(MergedStep.new(p.start, p.end, step_type, p.frame_id))
			else:
				diverged = true
				_append_diverged_pair(merged, p, r, past_cursor)
		else:
			_append_diverged_pair(merged, p, r, past_cursor)

	# Post-divergence: remaining steps from whichever array is longer
	for idx in range(min_len, planned_steps.size()):
		var p: Tracer.Step = planned_steps[idx]
		var past_cursor: bool = idx >= cursor_index
		var div_type: StepTypes.Type = StepTypes.Type.DIVERGED_PLANNED if not past_cursor else StepTypes.Type.DIVERGED_POST_PLANNED
		merged.append(MergedStep.new(p.start, p.end, div_type, p.frame_id))

	for idx in range(min_len, physical_steps.size()):
		var r: Tracer.Step = physical_steps[idx]
		merged.append(MergedStep.new(r.start, r.end, StepTypes.Type.DIVERGED_PHYSICAL, r.frame_id))

	return merged

static func _append_diverged_pair(merged: Array, p: Tracer.Step, r: Tracer.Step, past_cursor: bool) -> void:
	if p != null:
		var div_type: StepTypes.Type = StepTypes.Type.DIVERGED_PLANNED if not past_cursor else StepTypes.Type.DIVERGED_POST_PLANNED
		merged.append(MergedStep.new(p.start, p.end, div_type, p.frame_id))
	if r != null:
		merged.append(MergedStep.new(r.start, r.end, StepTypes.Type.DIVERGED_PHYSICAL, r.frame_id))
