extends GutTest

var _main_scene: Node
var _player: CharacterBody2D
var _cursor: Node2D
var _arrow: Node2D
var _game_mgr: Node
var _renderer: Node2D

func before_each() -> void:
	Surface.reset_id_counter()
	_main_scene = load("res://scenes/main.tscn").instantiate()
	_main_scene.gravity = Vector2.ZERO
	add_child_autofree(_main_scene)
	await get_tree().process_frame
	_player = _main_scene.get_node("Player")
	_cursor = _main_scene.get_node("Cursor")
	_arrow = _main_scene.get_node("ArrowAnimator")
	_game_mgr = _main_scene.get_node("GameManager")
	_renderer = _main_scene.get_node("PathRenderer")

func after_each() -> void:
	get_tree().paused = false

func _fire_at(cursor_pos: Vector2) -> void:
	_cursor.global_position = cursor_pos
	_game_mgr._try_fire()

func test_stage17_fire_pauses_tree() -> void:
	_fire_at(Vector2(1200, 540))
	assert_true(get_tree().paused, "Tree should be paused during flight")

func test_stage17_fire_noop_zero_length() -> void:
	_fire_at(_player.global_position)
	assert_false(get_tree().paused, "Should not pause for zero-length direction")
	assert_false(_arrow.is_flying(), "Arrow should not fly")

func test_stage17_arrow_speed_constant() -> void:
	assert_eq(_arrow.ARROW_SPEED, 800.0, "Arrow speed should be 800 u/s")

func test_stage17_arrow_animator_process_mode() -> void:
	assert_eq(_arrow.process_mode, Node.PROCESS_MODE_ALWAYS, "Arrow should run during pause")

func test_stage17_game_manager_process_mode() -> void:
	assert_eq(_game_mgr.process_mode, Node.PROCESS_MODE_ALWAYS, "GameManager should run during pause")

func test_stage17_preview_hidden_during_flight() -> void:
	_fire_at(Vector2(1200, 540))
	assert_false(_renderer.visible, "Preview should be hidden during flight")

func test_stage17_fire_starts_flying() -> void:
	_fire_at(Vector2(1200, 540))
	assert_true(_arrow.is_flying(), "Arrow should be flying after fire")
	assert_true(_arrow.visible, "Arrow should be visible during flight")

func test_stage17_flight_completed_unpauses() -> void:
	_fire_at(Vector2(1200, 540))
	_arrow.skip_animation()
	assert_false(get_tree().paused, "Tree should be unpaused after flight completes")

func test_stage17_preview_reappears_after_flight() -> void:
	_fire_at(Vector2(1200, 540))
	_arrow.skip_animation()
	assert_true(_renderer.visible, "Preview should reappear after flight")

func test_stage17_arrow_disappears_after_flight() -> void:
	_fire_at(Vector2(1200, 540))
	_arrow.skip_animation()
	assert_false(_arrow.visible, "Arrow should be hidden after flight")
	assert_false(_arrow.is_flying(), "Arrow should not be flying after completion")

func test_stage17_UX4_same_shot_same_result() -> void:
	var surfaces: Array = _main_scene.surfaces
	var dir := Direction.new(Vector2(960, 540), Vector2(1200, 540))
	var path1 := Tracer.trace(Vector2(960, 540), dir, surfaces, GameState.new())
	var path2 := Tracer.trace(Vector2(960, 540), dir, surfaces, GameState.new())
	assert_eq(path1.steps.size(), path2.steps.size(), "UX4: Same step count")
	for i in path1.steps.size():
		var s1: Tracer.Step = path1.steps[i]
		var s2: Tracer.Step = path2.steps[i]
		assert_eq(s1.start, s2.start, "UX4: Same start at step %d" % i)
		assert_eq(s1.end, s2.end, "UX4: Same end at step %d" % i)

func test_stage17_arrow_origin_at_player() -> void:
	_fire_at(Vector2(1200, 540))
	assert_eq(_arrow._arrow_position, _player.global_position, "Arrow should start at player position")

func test_stage17_cannot_fire_during_flight() -> void:
	_fire_at(Vector2(1200, 540))
	assert_true(_arrow.is_flying(), "Arrow should be flying")
	_game_mgr._try_fire()
	assert_true(_arrow.is_flying(), "Should not restart flight during active flight")
