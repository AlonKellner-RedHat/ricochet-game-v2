extends GutTest

var _player: CharacterBody2D
var _cursor: Node2D
var _renderer: Node2D
var _main_scene: Node

func before_each() -> void:
	Surface.reset_id_counter()
	_main_scene = load("res://scenes/test_levels/room_boundaries.tscn").instantiate()
	_main_scene.gravity = Vector2.ZERO
	add_child_autofree(_main_scene)
	await get_tree().process_frame
	_player = _main_scene.get_node("Player")
	_cursor = _main_scene.get_node("Cursor")
	_renderer = _main_scene.get_node("PathRenderer")

func test_stage15_preview_has_trace() -> void:
	_cursor.global_position = Vector2(800, 400)
	_renderer._compute_trace()
	var path: Tracer.TracedPath = _renderer.get_traced_path()
	assert_not_null(path, "Should have a traced path")
	assert_gte(path.steps.size(), 1, "Should have at least 1 step")

func test_stage15_solid_line_starts_at_player() -> void:
	_cursor.global_position = Vector2(800, 400)
	_renderer._compute_trace()
	assert_eq(_renderer.get_line_from(), _player.global_position, "Solid line should start at player")

func test_stage15_direction_toward_cursor() -> void:
	_cursor.global_position = Vector2(800, 400)
	_renderer._compute_trace()
	var expected: Vector2 = (_cursor.global_position - _player.global_position).normalized()
	var actual: Vector2 = _renderer.get_line_direction()
	assert_almost_eq(expected.dot(actual), 1.0, 0.01, "Should point toward cursor")

func test_stage15_UX11_empty_plan_fires_straight() -> void:
	_cursor.global_position = Vector2(1200, 540)
	_renderer._compute_trace()
	var path: Tracer.TracedPath = _renderer.get_traced_path()
	assert_eq(path.steps.size(), 1, "Empty plan should produce 1 step (straight to wall)")
	var step: Tracer.Step = path.steps[0]
	var dir: Vector2 = (step.end - step.start).normalized()
	var expected: Vector2 = (_cursor.global_position - _player.global_position).normalized()
	assert_almost_eq(dir.dot(expected), 1.0, 0.01, "UX11: should fire straight toward cursor")

func test_stage15_trace_hits_wall() -> void:
	_cursor.global_position = Vector2(1200, 540)
	_renderer._compute_trace()
	var path: Tracer.TracedPath = _renderer.get_traced_path()
	assert_not_null(path.steps[0].hit, "Should hit a wall")

func test_stage15_preview_absent_when_zero_length() -> void:
	_cursor.global_position = _player.global_position
	_renderer._compute_trace()
	assert_false(_renderer.has_line(), "No preview when cursor == player")

func test_stage15_preview_no_nan_in_steps() -> void:
	_cursor.global_position = Vector2(800, 300)
	_renderer._compute_trace()
	var path: Tracer.TracedPath = _renderer.get_traced_path()
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		assert_false(is_nan(step.start.x), "S16: start.x not NaN")
		assert_false(is_nan(step.start.y), "S16: start.y not NaN")
		assert_false(is_nan(step.end.x), "S16: end.x not NaN")
		assert_false(is_nan(step.end.y), "S16: end.y not NaN")
