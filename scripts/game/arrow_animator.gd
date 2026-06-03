extends Node2D

const ARROW_SPEED := 800.0
const ARROW_LENGTH := 40.0
const ARROW_HEAD_ANGLE := deg_to_rad(30.0)
const ARROW_HEAD_LENGTH := 16.0

signal flight_completed

var _path: Tracer.TracedPath = null
var _current_step_index := 0
var _progress_along_step := 0.0
var _flying := false
var _arrow_position := Vector2.ZERO
var _arrow_direction := Vector2.RIGHT

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func start_flight(path: Tracer.TracedPath) -> void:
	_path = path
	_current_step_index = 0
	_progress_along_step = 0.0
	_flying = true
	visible = true
	if _path.steps.size() > 0:
		var step: Tracer.Step = _path.steps[0]
		_arrow_position = step.start
		_arrow_direction = (step.end - step.start).normalized()
	queue_redraw()

func skip_animation() -> void:
	if _flying:
		_finish_flight()

func is_flying() -> bool:
	return _flying

func _process(delta: float) -> void:
	if not _flying or _path == null:
		return

	var distance := ARROW_SPEED * delta
	while distance > 0.0 and _current_step_index < _path.steps.size():
		var step: Tracer.Step = _path.steps[_current_step_index]
		var step_length: float = step.start.distance_to(step.end)
		var remaining_in_step: float = step_length - _progress_along_step

		if distance < remaining_in_step:
			_progress_along_step += distance
			var t: float = _progress_along_step / step_length if step_length > 0.0 else 1.0
			_arrow_position = step.start.lerp(step.end, t)
			_arrow_direction = (step.end - step.start).normalized()
			distance = 0.0
		else:
			distance -= remaining_in_step
			_arrow_position = step.end
			_current_step_index += 1
			_progress_along_step = 0.0
			if _current_step_index < _path.steps.size():
				var next_step: Tracer.Step = _path.steps[_current_step_index]
				_arrow_direction = (next_step.end - next_step.start).normalized()

	queue_redraw()

	if _current_step_index >= _path.steps.size():
		_finish_flight()

func _finish_flight() -> void:
	_flying = false
	visible = false
	_path = null
	flight_completed.emit()

func _draw() -> void:
	if not _flying:
		return

	var tip := _arrow_position
	var tail := tip - _arrow_direction * ARROW_LENGTH
	draw_line(tail - global_position, tip - global_position, Color.WHITE, 2.0)

	var head_left := tip - _arrow_direction.rotated(ARROW_HEAD_ANGLE) * ARROW_HEAD_LENGTH
	var head_right := tip - _arrow_direction.rotated(-ARROW_HEAD_ANGLE) * ARROW_HEAD_LENGTH
	var head_points := PackedVector2Array([
		tip - global_position,
		head_left - global_position,
		head_right - global_position,
	])
	draw_polygon(head_points, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]))
