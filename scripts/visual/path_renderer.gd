extends Node2D

const LINE_WIDTH := 2.0
const DASH_ON := 10.0
const DASH_OFF := 5.0

enum DisplayMode { MERGED, PHYSICAL, PLANNED }
const DISPLAY_MODE_NAMES := ["MERGED", "PHYSICAL", "PLANNED"]

var display_mode: int = DisplayMode.MERGED
var _player: CharacterBody2D
var _cursor: Node2D
var _traced_path: Tracer.TracedPath = null
var _planned_path: Tracer.TracedPath = null
var _merged_steps: Array = []

func _ready() -> void:
	_player = get_node_or_null("../Player")
	_cursor = get_node_or_null("../Cursor")
	z_index = 20

func _process(_delta: float) -> void:
	if not _player or not _cursor:
		return
	_compute_trace()
	queue_redraw()

func _compute_trace() -> void:
	if not _player or not _cursor:
		_traced_path = null
		_planned_path = null
		_merged_steps = []
		return

	var player_pos := _player.global_position
	var cursor_pos := _cursor.global_position
	if player_pos == cursor_pos:
		_traced_path = null
		_planned_path = null
		_merged_steps = []
		return

	var surfaces := _get_surfaces()
	var plan := _get_plan()
	var plan_entries: Array = []
	if plan and not plan.is_empty():
		plan_entries = plan.entries

	var cache := TransformCache.new()
	var aim_dir: Direction = Planner.compute_aim_direction(
		player_pos, cursor_pos, plan_entries, surfaces, GameState.new(), cache)
	var aim_ray := Ray.from_coords(player_pos, aim_dir)
	var bounds := VisualConverter.DEFAULT_BOUNDS
	_traced_path = Tracer.trace(player_pos, aim_dir, surfaces, GameState.new(),
		aim_ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, plan_entries, cache, cursor_pos)
	_traced_path = VisualConverter.prepare_for_display(_traced_path, bounds)
	_planned_path = Tracer.trace(player_pos, aim_dir, surfaces, GameState.new(),
		aim_ray, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan_entries, cache, cursor_pos)
	_planned_path = VisualConverter.prepare_for_display(_planned_path, bounds)

	var ci: int = _planned_path.cursor_index
	if ci < 0:
		ci = _planned_path.steps.size()
	_merged_steps = StepTreeMerge.merge(_planned_path.steps, _traced_path.steps, ci)

func _get_plan() -> PlanManager:
	var game_mgr := get_node_or_null("../GameManager")
	if game_mgr and "plan" in game_mgr:
		return game_mgr.plan
	return null

func _get_surfaces() -> Array:
	var parent := get_parent()
	if parent and "surfaces" in parent:
		return parent.surfaces
	return []

func cycle_display_mode() -> void:
	display_mode = (display_mode + 1) % 3
	print("[PathRenderer] Display mode: %s" % DISPLAY_MODE_NAMES[display_mode])
	queue_redraw()

func _draw() -> void:
	if display_mode == DisplayMode.MERGED:
		_draw_merged()
	elif display_mode == DisplayMode.PHYSICAL:
		_draw_raw_trace(_traced_path, Color.CYAN, "P")
	elif display_mode == DisplayMode.PLANNED:
		_draw_raw_trace(_planned_path, Color.MAGENTA, "L")

func _draw_merged() -> void:
	if _merged_steps.size() == 0:
		return
	for i in _merged_steps.size():
		var ms: Tracer.Step = _merged_steps[i]
		if ms.start == ms.end:
			continue
		_draw_step(ms, StepTypes.color(ms.type), not StepTypes.is_solid(ms.type))

	for i in _merged_steps.size():
		var ms: Tracer.Step = _merged_steps[i]
		var col := StepTypes.color(ms.type)
		col.a = 0.4
		draw_circle(ms.start - global_position, 4.0, col)
		draw_circle(ms.end - global_position, 4.0, col)

func _draw_raw_trace(path: Tracer.TracedPath, base_color: Color, label_prefix: String) -> void:
	if path == null or path.steps.size() == 0:
		return
	var cursor_idx := path.cursor_index if path.cursor_index >= 0 else path.steps.size()
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		if step.start == step.end:
			continue
		var col := base_color
		if i >= cursor_idx:
			col = Color(base_color, 0.35)
		_draw_step(step, col, step.hit == null)

	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		var col := base_color
		col.a = 0.4
		draw_circle(step.start - global_position, 4.0, col)
		draw_circle(step.end - global_position, 4.0, col)
		# Step index label
		var mid := ((step.start + step.end) / 2.0) - global_position + Vector2(0, -10)
		var font := ThemeDB.fallback_font
		var lbl := "%s%d" % [label_prefix, i]
		if step.hit == null:
			lbl += "*"
		draw_string(font, mid, lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, col)

func _draw_step(step: Tracer.Step, col: Color, dashed: bool) -> void:
	if step.is_arc_step and VisualConverter.is_arc(step.start, step.via, step.end):
		var p := VisualConverter.arc_params(step.start, step.via, step.end)
		var arc_center: Vector2 = p["center"] - global_position
		if dashed:
			_draw_dashed_arc(arc_center, p["radius"], p["start_angle"], p["end_angle"], p["point_count"], col)
		else:
			draw_arc(arc_center, p["radius"], p["start_angle"], p["end_angle"], p["point_count"], col, LINE_WIDTH)
	else:
		var from := step.start - global_position
		var to := step.end - global_position
		if dashed:
			_draw_dashed(from, to, col)
		else:
			draw_line(from, to, col, LINE_WIDTH)

func _draw_dashed_arc(center: Vector2, radius: float, start_angle: float, end_angle: float, point_count: int, col: Color) -> void:
	var span := end_angle - start_angle
	var total_len := minf(radius * absf(span), 4000.0)
	if total_len == 0.0:
		return
	var drawn := 0.0
	var on := true
	while drawn < total_len:
		var seg_len := DASH_ON if on else DASH_OFF
		seg_len = minf(seg_len, total_len - drawn)
		if on:
			var a0 := start_angle + (drawn / total_len) * span
			var a1 := start_angle + ((drawn + seg_len) / total_len) * span
			var seg_points := maxi(2, int(point_count * seg_len / total_len))
			draw_arc(center, radius, a0, a1, seg_points, col, LINE_WIDTH)
		drawn += seg_len
		on = not on

func _draw_dashed(from: Vector2, to: Vector2, col: Color) -> void:
	var dir := to - from
	var total_len := dir.length()
	if total_len == 0.0:
		return
	var unit := dir / total_len
	var drawn := 0.0
	var on := true
	while drawn < total_len:
		var seg_len := DASH_ON if on else DASH_OFF
		seg_len = minf(seg_len, total_len - drawn)
		if on:
			draw_line(from + unit * drawn, from + unit * (drawn + seg_len), col, LINE_WIDTH)
		drawn += seg_len
		on = not on

func has_line() -> bool:
	return _merged_steps.size() > 0

func get_line_from() -> Vector2:
	if _merged_steps.size() > 0:
		var ms: Tracer.Step = _merged_steps[0]
		return ms.start
	return Vector2.ZERO

func get_line_direction() -> Vector2:
	if _merged_steps.size() > 0:
		var ms: Tracer.Step = _merged_steps[0]
		return (ms.end - ms.start).normalized()
	return Vector2.ZERO

func get_traced_path() -> Tracer.TracedPath:
	return _traced_path

func get_planned_path():
	return _planned_path

func get_typed_steps() -> Array:
	return _merged_steps
