extends Node2D

const LINE_WIDTH := 2.0
const DASH_ON := 10.0
const DASH_OFF := 5.0

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

	var aim_dir: Direction = Planner.compute_aim_direction(
		player_pos, cursor_pos, plan_entries, surfaces, GameState.new())
	var aim_ray := Ray.new(player_pos, aim_dir)
	var cache := TransformCache.new()
	_traced_path = Tracer.trace(player_pos, aim_dir, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, aim_ray, -1.0,
		Tracer.TraceMode.PHYSICAL, Tracer.TraceMode.PHYSICAL, plan_entries, cache)
	_planned_path = Tracer.trace(player_pos, aim_dir, surfaces, GameState.new(),
		Tracer.DEFAULT_BOUNDS, aim_ray, -1.0,
		Tracer.TraceMode.PLANNED, Tracer.TraceMode.PHYSICAL, plan_entries, cache)

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

func _draw() -> void:
	if _merged_steps.size() == 0:
		return
	for i in _merged_steps.size():
		var ms: StepTreeMerge.MergedStep = _merged_steps[i]
		var from := ms.start - global_position
		var to := ms.end - global_position
		if from == to:
			continue
		var col := StepTypes.color(ms.type)
		if StepTypes.is_solid(ms.type):
			draw_line(from, to, col, LINE_WIDTH)
		else:
			_draw_dashed(from, to, col)

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
		var ms: StepTreeMerge.MergedStep = _merged_steps[0]
		return ms.start
	return Vector2.ZERO

func get_line_direction() -> Vector2:
	if _merged_steps.size() > 0:
		var ms: StepTreeMerge.MergedStep = _merged_steps[0]
		return (ms.end - ms.start).normalized()
	return Vector2.ZERO

func get_traced_path() -> Tracer.TracedPath:
	return _traced_path

func get_planned_path():
	return null

func get_typed_steps() -> Array:
	return _merged_steps
