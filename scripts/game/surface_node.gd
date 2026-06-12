extends Node2D

const LINE_WIDTH := 3.0
const SIDE_OFFSET := 2.0
const BLOCK_COLOR := Color.RED
const REFLECTION_COLOR := Color.BLUE
const INVERSION_COLOR := Color.PURPLE
const PASSTHROUGH_COLOR := Color.GRAY

const HOVER_COLOR := Color(1.0, 1.0, 1.0, 0.3)
const HOVER_WIDTH := 8.0

var surface: Surface
var _plan_indices: Array[int] = []
var _hover_side: int = -1

func setup(p_surface: Surface) -> void:
	surface = p_surface
	if surface.player_solid and surface.segment.is_line():
		_add_collision_shape()
	queue_redraw()

func set_hover_side(side: int) -> void:
	if _hover_side != side:
		_hover_side = side
		queue_redraw()

func clear_hover() -> void:
	set_hover_side(-1)

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
	var is_arc := not surface.segment.is_line()

	if left_color == right_color:
		if is_arc:
			_draw_surface_arc(left_color, LINE_WIDTH)
		else:
			draw_line(surface.segment.start.coords, surface.segment.end.coords, left_color, LINE_WIDTH)
	else:
		var left_alpha := 1.0 if left_config.interactive else 0.5
		var right_alpha := 1.0 if right_config.interactive else 0.5
		var left_is_outer := _is_left_outer()
		if is_arc:
			var p := _arc_params()
			var outer_r: float = p["radius"] + SIDE_OFFSET
			var inner_r: float = p["radius"] - SIDE_OFFSET
			var outer_color := Color(left_color, left_alpha) if left_is_outer else Color(right_color, right_alpha)
			var inner_color := Color(right_color, right_alpha) if left_is_outer else Color(left_color, left_alpha)
			draw_arc(p["center"], outer_r, p["start_angle"], p["end_angle"], p["point_count"], outer_color, LINE_WIDTH * 0.5)
			draw_arc(p["center"], inner_r, p["start_angle"], p["end_angle"], p["point_count"], inner_color, LINE_WIDTH * 0.5)
		else:
			var seg_dir := (surface.segment.end.coords - surface.segment.start.coords).normalized()
			var normal := Vector2(-seg_dir.y, seg_dir.x)
			var offset := normal * SIDE_OFFSET
			var mid := (surface.segment.start.coords + surface.segment.end.coords) / 2.0
			var side_at_normal: Side.Value = surface.segment.determine_side(mid + normal * SIDE_OFFSET)
			if side_at_normal == Side.Value.LEFT:
				draw_line(surface.segment.start.coords + offset, surface.segment.end.coords + offset, Color(left_color, left_alpha), LINE_WIDTH * 0.5)
				draw_line(surface.segment.start.coords - offset, surface.segment.end.coords - offset, Color(right_color, right_alpha), LINE_WIDTH * 0.5)
			else:
				draw_line(surface.segment.start.coords + offset, surface.segment.end.coords + offset, Color(right_color, right_alpha), LINE_WIDTH * 0.5)
				draw_line(surface.segment.start.coords - offset, surface.segment.end.coords - offset, Color(left_color, left_alpha), LINE_WIDTH * 0.5)

	if _hover_side >= 0:
		if is_arc:
			var p := _arc_params()
			var is_outer := (_hover_side == Side.Value.LEFT) == _is_left_outer()
			var hover_r: float = p["radius"] + (SIDE_OFFSET + 2.0) * (1.0 if is_outer else -1.0)
			draw_arc(p["center"], hover_r, p["start_angle"], p["end_angle"], p["point_count"], HOVER_COLOR, HOVER_WIDTH)
		else:
			var seg_dir2 := (surface.segment.end.coords - surface.segment.start.coords).normalized()
			var normal2 := Vector2(-seg_dir2.y, seg_dir2.x)
			var mid2 := (surface.segment.start.coords + surface.segment.end.coords) / 2.0
			var side_at_n2: Side.Value = surface.segment.determine_side(mid2 + normal2 * SIDE_OFFSET)
			var sign2 := 1.0 if side_at_n2 == _hover_side else -1.0
			var hover_offset := normal2 * (SIDE_OFFSET + 2.0) * sign2
			draw_line(surface.segment.start.coords + hover_offset, surface.segment.end.coords + hover_offset, HOVER_COLOR, HOVER_WIDTH)

	if _plan_indices.size() > 0:
		var mid := surface.segment.via.coords
		var label_text := ""
		for idx in _plan_indices:
			if label_text != "":
				label_text += ","
			label_text += str(idx)
		draw_string(ThemeDB.fallback_font, mid + Vector2(-5, -10), label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.WHITE)

func _draw_surface_arc(color: Color, width: float) -> void:
	var p := _arc_params()
	draw_arc(p["center"], p["radius"], p["start_angle"], p["end_angle"], p["point_count"], color, width)

func _arc_params() -> Dictionary:
	return VisualConverter.arc_params(surface.segment.start.coords, surface.segment.via.coords, surface.segment.end.coords)

func _is_left_outer() -> bool:
	var carrier := surface.segment.get_carrier()
	if carrier.is_line():
		return true
	var ctr := carrier.center()
	var test_point := ctr + (surface.segment.start.coords - ctr).normalized() * (carrier.radius() + SIDE_OFFSET)
	return surface.segment.determine_side(test_point) == Side.Value.LEFT

func _effect_color(config: SideConfig) -> Color:
	if config == null or config.effect == null:
		return PASSTHROUGH_COLOR
	if config.effect is TerminalEffect:
		return BLOCK_COLOR
	if config.effect is ReflectionEffect:
		return REFLECTION_COLOR
	if config.effect is CircleInversionEffect:
		return INVERSION_COLOR
	return PASSTHROUGH_COLOR

func _add_collision_shape() -> void:
	var body := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := SegmentShape2D.new()
	shape.a = surface.segment.start.coords
	shape.b = surface.segment.end.coords
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
