class_name StepTypes

enum Type {
	ALIGNED,
	ALIGNED_POST_PLANNED,
	DIVERGED_PHYSICAL,
	DIVERGED_PLANNED,
	DIVERGED_POST_PLANNED,
}

static func color(type: Type) -> Color:
	match type:
		Type.ALIGNED:
			return Color.GREEN
		Type.ALIGNED_POST_PLANNED:
			return Color.GREEN
		Type.DIVERGED_PHYSICAL:
			return Color.YELLOW
		Type.DIVERGED_PLANNED:
			return Color.RED
		Type.DIVERGED_POST_PLANNED:
			return Color.RED
	return Color.WHITE

static func is_solid(type: Type) -> bool:
	match type:
		Type.ALIGNED:
			return true
		Type.DIVERGED_PLANNED:
			return true
	return false
