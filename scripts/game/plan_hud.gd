extends Control

var _label: Label

func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(10, 10)
	_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(_label)

func update_plan(plan: PlanManager, surfaces: Array) -> void:
	if plan.is_empty():
		_label.text = ""
		return
	var lines: PackedStringArray = []
	lines.append("Plan:")
	for i in plan.size():
		var entry: PlanManager.PlanEntry = plan.get_entry(i)
		var name := _surface_name(entry.surface_id, surfaces)
		var side_str := "L" if entry.side == Side.Value.LEFT else "R"
		lines.append("  %d. %s (%s)" % [i + 1, name, side_str])
	_label.text = "\n".join(lines)

func _surface_name(surface_id: int, surfaces: Array) -> String:
	for surf in surfaces:
		if surf.id == surface_id:
			var config: SideConfig = surf.active_side_config(Side.Value.LEFT, GameState.new())
			if config.effect is ReflectionEffect:
				return "Mirror %d" % surface_id
			elif config.effect is TerminalEffect:
				return "Wall %d" % surface_id
			return "Surface %d" % surface_id
	return "Surface %d" % surface_id
