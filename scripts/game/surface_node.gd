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
var _cached_left_outer: bool = true

func setup(p_surface: Surface) -> void:
	surface = p_surface
	_cached_left_outer = _is_left_outer()
	if surface.player_solid:
		if surface.segment.is_line():
			_add_collision_shape()
		else:
			_add_arc_collision_shape()
	queue_redraw()

func set_hover_side(side: int) -> void:
	if _hover_side != side:
		_hover_side = side
		queue_redraw()

func clear_hover() -> void:
	set_hover_side(-1)

func update_plan_overlay(plan: PlanManager) -> void:
	_plan_indices.clear()
	for i in plan.entries.size():
		var entry: PlanManager.PlanEntry = plan.entries[i]
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
		if is_arc:
			var ctr: Vector2
			var r: float
			var sa: float
			var ea: float
			var pc: int
			if surface.segment.full:
				var carrier := surface.segment.get_carrier()
				ctr = carrier.center()
				r = carrier.radius()
				sa = 0.0
				ea = TAU
				pc = VisualConverter.POINTS_PER_FULL_CIRCLE
			else:
				var p := _arc_params()
				ctr = p["center"]
				r = p["radius"]
				sa = p["start_angle"]
				ea = p["end_angle"]
				pc = p["point_count"]
			var outer_color := Color(left_color, left_alpha) if _cached_left_outer else Color(right_color, right_alpha)
			var inner_color := Color(right_color, right_alpha) if _cached_left_outer else Color(left_color, left_alpha)
			draw_arc(ctr, r + SIDE_OFFSET, sa, ea, pc, outer_color, LINE_WIDTH * 0.5)
			draw_arc(ctr, r - SIDE_OFFSET, sa, ea, pc, inner_color, LINE_WIDTH * 0.5)
		else:
			var left_offset := _line_side_offset(Side.Value.LEFT, SIDE_OFFSET)
			var right_offset := _line_side_offset(Side.Value.RIGHT, SIDE_OFFSET)
			draw_line(surface.segment.start.coords + left_offset, surface.segment.end.coords + left_offset, Color(left_color, left_alpha), LINE_WIDTH * 0.5)
			draw_line(surface.segment.start.coords + right_offset, surface.segment.end.coords + right_offset, Color(right_color, right_alpha), LINE_WIDTH * 0.5)

	if _hover_side >= 0:
		if is_arc:
			var h_ctr: Vector2
			var h_r: float
			var h_sa: float
			var h_ea: float
			var h_pc: int
			if surface.segment.full:
				var carrier := surface.segment.get_carrier()
				h_ctr = carrier.center()
				h_r = carrier.radius()
				h_sa = 0.0
				h_ea = TAU
				h_pc = VisualConverter.POINTS_PER_FULL_CIRCLE
			else:
				var p := _arc_params()
				h_ctr = p["center"]
				h_r = p["radius"]
				h_sa = p["start_angle"]
				h_ea = p["end_angle"]
				h_pc = p["point_count"]
			var is_outer := (_hover_side == Side.Value.LEFT) == _cached_left_outer
			var hover_r: float = h_r + (SIDE_OFFSET + 2.0) * (1.0 if is_outer else -1.0)
			draw_arc(h_ctr, hover_r, h_sa, h_ea, h_pc, HOVER_COLOR, HOVER_WIDTH)
		else:
			var hover_offset := _line_side_offset(_hover_side, SIDE_OFFSET + 2.0)
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
	if surface.segment.full:
		var carrier := surface.segment.get_carrier()
		draw_arc(carrier.center(), carrier.radius(), 0, TAU, VisualConverter.POINTS_PER_FULL_CIRCLE, color, width)
		return
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

func _line_side_offset(side: Side.Value, dist: float) -> Vector2:
	var seg_dir := (surface.segment.end.coords - surface.segment.start.coords).normalized()
	var normal := Vector2(-seg_dir.y, seg_dir.x)
	var mid := (surface.segment.start.coords + surface.segment.end.coords) / 2.0
	var side_at_normal: Side.Value = surface.segment.determine_side(mid + normal * SIDE_OFFSET)
	var sign_val := 1.0 if side_at_normal == side else -1.0
	return normal * dist * sign_val

func _effect_color(config: SideConfig) -> Color:
	if config == null or config.effect == null:
		return PASSTHROUGH_COLOR
	return config.effect.get_display_color()

func _add_arc_collision_shape() -> void:
	var ctr: Vector2
	var r: float
	var span: float
	var seg_count: int
	var sa: float
	var ccw: bool
	if surface.segment.full:
		var carrier := surface.segment.get_carrier()
		ctr = carrier.center()
		r = carrier.radius()
		span = TAU
		seg_count = 16
		sa = 0.0
		ccw = true
	else:
		var p := _arc_params()
		ctr = p["center"]
		r = p["radius"]
		span = p["span"]
		seg_count = maxi(3, int(16.0 * span / TAU))
		sa = (surface.segment.start.coords - ctr).angle()
		ccw = not p["clockwise"]
	var body := StaticBody2D.new()
	for i in seg_count:
		var t0 := float(i) / seg_count
		var t1 := float(i + 1) / seg_count
		var a0 := sa + (t0 * span * (1.0 if ccw else -1.0))
		var a1 := sa + (t1 * span * (1.0 if ccw else -1.0))
		var p0 := ctr + Vector2(cos(a0), sin(a0)) * r
		var p1 := ctr + Vector2(cos(a1), sin(a1)) * r
		var collision := CollisionShape2D.new()
		var shape := SegmentShape2D.new()
		shape.a = p0
		shape.b = p1
		collision.shape = shape
		body.add_child(collision)
	add_child(body)

func _add_collision_shape() -> void:
	var body := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := SegmentShape2D.new()
	shape.a = surface.segment.start.coords
	shape.b = surface.segment.end.coords
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
