extends Node2D

const LINE_WIDTH := 2.0
const DASH_ON := 10.0
const DASH_OFF := 5.0

var _player: CharacterBody2D
var _cursor: Node2D
var _traced_path: Tracer.TracedPath = null
var _planned_path: Tracer.TracedPath = null
var _merged_steps: Array = []
var _cursor_pos := Vector2.ZERO

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
	_cursor_pos = _cursor.global_position
	var player_pos := _player.global_position
	if player_pos == _cursor_pos:
		_traced_path = null
		_planned_path = null
		_merged_steps = []
		return

	var surfaces := _get_surfaces()
	var plan := _get_plan()
	var bounds := _get_bounds()

	var plan_entries: Array = []
	if plan and not plan.is_empty():
		plan_entries = plan.entries

	var aim_dir: Direction = Planner.compute_aim_direction(
		player_pos, _cursor_pos, plan_entries, surfaces, GameState.new())

	var aim_ray := Ray.new(player_pos, aim_dir)
	var target_dist: float = player_pos.distance_to(_cursor_pos)

	# 1. Physical trace — full path
	_traced_path = Tracer.trace(player_pos, aim_dir, surfaces, GameState.new(), bounds, aim_ray, target_dist, Tracer.TraceMode.PHYSICAL)

	# 2. Planned trace — full path (sliced to cursor below)
	var planned_full := Tracer.trace(player_pos, aim_dir, surfaces, GameState.new(), bounds, aim_ray, target_dist, Tracer.TraceMode.PLANNED, plan_entries)

	# 3. Extract planned steps up to cursor
	var ci: int = planned_full.cursor_index
	var cursor_reached: bool = ci >= 0
	if not cursor_reached:
		ci = planned_full.steps.size()
	var combined_steps: Array = planned_full.steps.slice(0, ci)

	# 4. Post-planned trace — from cursor, PHYSICAL mode, in planned frame
	# Only if cursor was actually reached (not blocked by a wall before cursor)
	if cursor_reached and ci > 0 and ci <= planned_full.steps.size():
		var last_step: Tracer.Step = combined_steps[ci - 1]
		var post_trace := Tracer.trace(last_step.end, aim_dir, surfaces, GameState.new(), bounds, aim_ray, -1.0, Tracer.TraceMode.PHYSICAL, [], last_step.frame)
		for i in post_trace.steps.size():
			combined_steps.append(post_trace.steps[i])

	# 5. Store planned path for invariant checking
	_planned_path = Tracer.TracedPath.new()
	_planned_path.steps = combined_steps
	_planned_path.cursor_index = ci

	# 6. Merge (planned+post-planned) vs physical
	_merged_steps = StepTreeMerge.merge(combined_steps, _traced_path.steps, ci)

func _get_surfaces() -> Array:
	var parent := get_parent()
	if parent and "surfaces" in parent:
		return parent.surfaces
	return []

func _get_bounds() -> Rect2:
	return Tracer.DEFAULT_BOUNDS

func _get_plan() -> PlanManager:
	var game_mgr := get_node_or_null("../GameManager")
	if game_mgr and "plan" in game_mgr:
		return game_mgr.plan
	return null

func _draw() -> void:
	if _merged_steps.size() == 0:
		return

	for i in _merged_steps.size():
		var ms: StepTreeMerge.MergedStep = _merged_steps[i]
		var from: Vector2 = ms.start - global_position
		var to: Vector2 = ms.end - global_position
		if from.distance_to(to) < 0.01:
			continue
		var col: Color = StepTypes.color(ms.type)
		if StepTypes.is_solid(ms.type):
			draw_line(from, to, col, LINE_WIDTH)
		else:
			_draw_dashed(from, to, col)

	_draw_hit_points()

func _draw_dashed(from: Vector2, to: Vector2, col: Color) -> void:
	var dir := (to - from)
	var total_len := dir.length()
	if total_len == 0.0:
		return
	var unit := dir / total_len
	var drawn := 0.0
	var on := true
	while drawn < total_len:
		var segment_len := DASH_ON if on else DASH_OFF
		segment_len = minf(segment_len, total_len - drawn)
		if on:
			draw_line(from + unit * drawn, from + unit * (drawn + segment_len), col, LINE_WIDTH)
		drawn += segment_len
		on = not on

func _draw_hit_points() -> void:
	if _traced_path == null:
		return
	var hit_color := Color(1.0, 1.0, 0.0, 0.35)
	for i in _traced_path.steps.size():
		var step: Tracer.Step = _traced_path.steps[i]
		if step.hit != null:
			var pos: Vector2 = step.end - global_position
			draw_circle(pos, 5.0, hit_color)

func has_line() -> bool:
	return _merged_steps.size() > 0

func get_line_from() -> Vector2:
	if _merged_steps.size() > 0:
		return _merged_steps[0].start
	return Vector2.ZERO

func get_line_direction() -> Vector2:
	if _merged_steps.size() > 0:
		var ms: StepTreeMerge.MergedStep = _merged_steps[0]
		return (ms.end - ms.start).normalized()
	return Vector2.ZERO

func get_traced_path() -> Tracer.TracedPath:
	return _traced_path

func get_planned_path() -> Tracer.TracedPath:
	return _planned_path

func get_typed_steps() -> Array:
	return _merged_steps
