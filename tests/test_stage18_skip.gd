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

func _fast_forward() -> void:
	_arrow.speed_up()
	_arrow.speed_up()
	_arrow._process(1.0)

func test_stage18_speed_up_accelerates() -> void:
	_fire_at(Vector2(1200, 540))
	assert_almost_eq(_arrow._speed_multiplier, 1.0, 0.01, "Should start at 1x")
	_arrow.speed_up()
	assert_almost_eq(_arrow._speed_multiplier, 10.0, 0.01, "First speed_up should be 10x")
	_arrow.speed_up()
	assert_almost_eq(_arrow._speed_multiplier, 100.0, 0.01, "Second speed_up should be 100x")

func test_stage18_speed_up_completes_flight() -> void:
	_fire_at(Vector2(1200, 540))
	assert_true(_arrow.is_flying(), "Arrow should be flying")
	_fast_forward()
	assert_false(_arrow.is_flying(), "Arrow should finish after fast-forward")

func test_stage18_speed_up_unfreezes_game() -> void:
	_fire_at(Vector2(1200, 540))
	_fast_forward()
	assert_false(get_tree().paused, "Game should be unpaused after completion")

func test_stage18_preview_reappears_after_speed_up() -> void:
	_fire_at(Vector2(1200, 540))
	_fast_forward()
	assert_almost_eq(_renderer.modulate.a, 1.0, 0.01, "Preview should be fully opaque after completion")

func test_stage18_wasd_does_not_speed_up() -> void:
	_fire_at(Vector2(1200, 540))
	assert_true(_arrow.is_flying(), "Arrow should be flying")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_W
	event.pressed = true
	_game_mgr._unhandled_input(event)
	assert_almost_eq(_arrow._speed_multiplier, 1.0, 0.01, "WASD should not speed up")

func test_stage18_non_movement_key_speeds_up() -> void:
	_fire_at(Vector2(1200, 540))
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ENTER
	event.pressed = true
	_game_mgr._unhandled_input(event)
	assert_almost_eq(_arrow._speed_multiplier, 10.0, 0.01, "Non-movement key should speed up 10x")

func test_stage18_fire_during_flight_speeds_up() -> void:
	_fire_at(Vector2(1200, 540))
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = true
	_game_mgr._unhandled_input(event)
	assert_almost_eq(_arrow._speed_multiplier, 10.0, 0.01, "Spacebar during flight should speed up")

func test_stage18_echo_keys_ignored() -> void:
	_fire_at(Vector2(1200, 540))
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ENTER
	event.pressed = true
	event.echo = true
	_game_mgr._unhandled_input(event)
	assert_almost_eq(_arrow._speed_multiplier, 1.0, 0.01, "Echo key events should not speed up")

func test_stage18_speed_resets_on_new_flight() -> void:
	_fire_at(Vector2(1200, 540))
	_arrow.speed_up()
	_fast_forward()
	_fire_at(Vector2(1200, 540))
	assert_almost_eq(_arrow._speed_multiplier, 1.0, 0.01, "Speed should reset on new flight")
