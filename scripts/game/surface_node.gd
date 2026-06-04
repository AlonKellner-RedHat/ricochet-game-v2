extends Node2D

const LINE_WIDTH := 3.0
const SIDE_OFFSET := 2.0
const BLOCK_COLOR := Color.RED
const REFLECTION_COLOR := Color.BLUE
const PASSTHROUGH_COLOR := Color.GRAY

var surface: Surface
var _plan_indices: Array[int] = []

func setup(p_surface: Surface) -> void:
	surface = p_surface
	if surface.player_solid and surface.segment.is_line():
		_add_collision_shape()
	queue_redraw()

func update_plan_overlay(plan: PlanManager) -> void:
	_plan_indices.clear()
	for i in plan.size():
		var entry: PlanManager.PlanEntry = plan.get_entry(i)
		if entry.surface_id == surface.id:
			_plan_indices.append(i + 1)
	queue_redraw()

func _draw() -> void:
	if not surface:
		return
	var state := GameState.new()
	var left_config := surface.active_side_config(Side.Value.LEFT, state)
	var right_config := surface.active_side_config(Side.Value.RIGHT, state)
	var left_color := _effect_color(left_config)
	var right_color := _effect_color(right_config)

	if left_color == right_color:
		draw_line(surface.segment.start, surface.segment.end, left_color, LINE_WIDTH)
	else:
		var seg_dir := (surface.segment.end - surface.segment.start).normalized()
		var normal := Vector2(-seg_dir.y, seg_dir.x)
		var offset := normal * SIDE_OFFSET
		var left_alpha := 1.0 if left_config.interactive else 0.5
		var right_alpha := 1.0 if right_config.interactive else 0.5
		draw_line(surface.segment.start + offset, surface.segment.end + offset, Color(left_color, left_alpha), LINE_WIDTH * 0.5)
		draw_line(surface.segment.start - offset, surface.segment.end - offset, Color(right_color, right_alpha), LINE_WIDTH * 0.5)

	if _plan_indices.size() > 0:
		var mid := (surface.segment.start + surface.segment.end) / 2.0
		var label_text := ""
		for idx in _plan_indices:
			if label_text != "":
				label_text += ","
			label_text += str(idx)
		draw_string(ThemeDB.fallback_font, mid + Vector2(-5, -10), label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.WHITE)

func _effect_color(config: SideConfig) -> Color:
	if config == null or config.effect == null:
		return PASSTHROUGH_COLOR
	if config.effect is TerminalEffect:
		return BLOCK_COLOR
	if config.effect is ReflectionEffect:
		return REFLECTION_COLOR
	return PASSTHROUGH_COLOR

func _add_collision_shape() -> void:
	var body := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := SegmentShape2D.new()
	shape.a = surface.segment.start
	shape.b = surface.segment.end
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
