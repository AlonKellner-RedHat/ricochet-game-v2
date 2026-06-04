extends Node2D

const LINE_WIDTH := 2.0
const DASH_ON := 10.0
const DASH_OFF := 5.0

var _player: CharacterBody2D
var _cursor: Node2D
var _traced_path: Tracer.TracedPath = null
var _typed_steps: Array = []
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
		_typed_steps = []
		return
	_cursor_pos = _cursor.global_position
	var player_pos := _player.global_position
	if player_pos == _cursor_pos:
		_traced_path = null
		_typed_steps = []
		return

	var surfaces := _get_surfaces()
	var dir := Direction.new(player_pos, _cursor_pos)
	var bounds := _get_bounds()
	_traced_path = Tracer.trace(player_pos, dir, surfaces, GameState.new(), bounds)
	_typed_steps = PreviewBuilder.build(_traced_path, player_pos, _cursor_pos, surfaces, bounds)

func _get_surfaces() -> Array:
	var parent := get_parent()
	if parent and "surfaces" in parent:
		return parent.surfaces
	return []

func _get_bounds() -> Rect2:
	return Tracer.DEFAULT_BOUNDS

func _draw() -> void:
	if _typed_steps.size() == 0:
		return

	for i in _typed_steps.size():
		var step: PreviewBuilder.TypedStep = _typed_steps[i]
		var from: Vector2 = step.start - global_position
		var to: Vector2 = step.end - global_position
		if from == to:
			continue
		var col: Color = StepTypes.color(step.type)
		if StepTypes.is_solid(step.type):
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
	return _typed_steps.size() > 0

func get_line_from() -> Vector2:
	if _typed_steps.size() > 0:
		return _typed_steps[0].start
	return Vector2.ZERO

func get_line_direction() -> Vector2:
	if _typed_steps.size() > 0:
		var step: PreviewBuilder.TypedStep = _typed_steps[0]
		return (step.end - step.start).normalized()
	return Vector2.ZERO

func get_traced_path() -> Tracer.TracedPath:
	return _traced_path

func get_typed_steps() -> Array:
	return _typed_steps
