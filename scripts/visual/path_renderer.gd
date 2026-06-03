extends Node2D

const LINE_COLOR := Color.GREEN
const LINE_WIDTH := 2.0
const DASH_ON := 10.0
const DASH_OFF := 5.0
const VIEWPORT_MARGIN := 2000.0

var _player: CharacterBody2D
var _cursor: Node2D
var _traced_path: Tracer.TracedPath = null
var _cursor_pos := Vector2.ZERO

func _ready() -> void:
	_player = get_node_or_null("../Player")
	_cursor = get_node_or_null("../Cursor")
	z_index = 20

func _process(_delta: float) -> void:
	if not _player or not _cursor:
		return
	_cursor_pos = _cursor.global_position
	_compute_trace()
	queue_redraw()

func _compute_trace() -> void:
	if not _player or not _cursor:
		_traced_path = null
		return
	_cursor_pos = _cursor.global_position
	var player_pos := _player.global_position
	if player_pos == _cursor_pos:
		_traced_path = null
		return

	var surfaces := _get_surfaces()
	var dir := Direction.new(player_pos, _cursor_pos)
	_traced_path = Tracer.trace(player_pos, dir, surfaces, GameState.new())

func _get_surfaces() -> Array:
	var parent := get_parent()
	if parent and "surfaces" in parent:
		return parent.surfaces
	return []

func _draw() -> void:
	if _traced_path == null or _traced_path.steps.size() == 0:
		return

	var player_pos := _player.global_position
	var cursor_dist := player_pos.distance_to(_cursor_pos)

	for i in _traced_path.steps.size():
		var step: Tracer.Step = _traced_path.steps[i]
		var from: Vector2 = step.start - global_position
		var to: Vector2 = _clamp_to_viewport(step.start, step.end) - global_position
		var step_start_dist: float = player_pos.distance_to(step.start)

		if step_start_dist < cursor_dist and step.hit != null:
			var hit_dist: float = player_pos.distance_to(step.end)
			if hit_dist <= cursor_dist:
				_draw_solid_line(from, to)
			else:
				var split: Vector2 = _cursor_pos - global_position
				_draw_solid_line(from, split)
				_draw_dashed_line(split, to)
		elif step_start_dist < cursor_dist:
			var split: Vector2 = _cursor_pos - global_position
			_draw_solid_line(from, split)
			_draw_dashed_line(split, to)
		else:
			_draw_dashed_line(from, to)

func _draw_solid_line(from: Vector2, to: Vector2) -> void:
	if from == to:
		return
	draw_line(from, to, LINE_COLOR, LINE_WIDTH)

func _draw_dashed_line(from: Vector2, to: Vector2) -> void:
	if from == to:
		return
	var dir := (to - from)
	var total_len := dir.length()
	var unit := dir / total_len
	var drawn := 0.0
	var on := true
	while drawn < total_len:
		var segment_len := DASH_ON if on else DASH_OFF
		segment_len = minf(segment_len, total_len - drawn)
		if on:
			draw_line(from + unit * drawn, from + unit * (drawn + segment_len), LINE_COLOR, LINE_WIDTH)
		drawn += segment_len
		on = not on

func _clamp_to_viewport(start: Vector2, end: Vector2) -> Vector2:
	if is_inf(end.x) or is_inf(end.y) or is_nan(end.x) or is_nan(end.y):
		var dir := (end - start)
		if dir.length_squared() == 0.0:
			return start
		return start + dir.normalized() * VIEWPORT_MARGIN
	return end

func has_line() -> bool:
	return _traced_path != null and _traced_path.steps.size() > 0

func get_line_from() -> Vector2:
	if _traced_path and _traced_path.steps.size() > 0:
		return _traced_path.steps[0].start
	return Vector2.ZERO

func get_line_direction() -> Vector2:
	if _traced_path and _traced_path.steps.size() > 0:
		var step = _traced_path.steps[0]
		return (step.end - step.start).normalized()
	return Vector2.ZERO

func get_traced_path() -> Tracer.TracedPath:
	return _traced_path
