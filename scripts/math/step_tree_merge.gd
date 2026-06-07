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
		result.append(MergedStep.new(s.start, s.end, step_type, s.frame_id))
	return result
