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

func test_stage18_skip_completes_animation() -> void:
	_fire_at(Vector2(1200, 540))
	assert_true(_arrow.is_flying(), "Arrow should be flying")
	_arrow.skip_animation()
	assert_false(_arrow.is_flying(), "Arrow should stop after skip")
	assert_false(_arrow.visible, "Arrow should be hidden after skip")

func test_stage18_skip_unfreezes_game() -> void:
	_fire_at(Vector2(1200, 540))
	_arrow.skip_animation()
	assert_false(get_tree().paused, "Game should be unpaused after skip")

func test_stage18_preview_reappears_after_skip() -> void:
	_fire_at(Vector2(1200, 540))
	_arrow.skip_animation()
	assert_almost_eq(_renderer.modulate.a, 1.0, 0.01, "Preview should be fully opaque after skip")

func test_stage18_wasd_does_not_skip() -> void:
	_fire_at(Vector2(1200, 540))
	assert_true(_arrow.is_flying(), "Arrow should be flying")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_W
	event.pressed = true
	_game_mgr._unhandled_input(event)
	assert_true(_arrow.is_flying(), "WASD should not skip animation")

func test_stage18_non_movement_key_skips() -> void:
	_fire_at(Vector2(1200, 540))
	assert_true(_arrow.is_flying(), "Arrow should be flying")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ENTER
	event.pressed = true
	_game_mgr._unhandled_input(event)
	assert_false(_arrow.is_flying(), "Non-movement key should skip animation")

func test_stage18_fire_during_flight_skips() -> void:
	_fire_at(Vector2(1200, 540))
	assert_true(_arrow.is_flying(), "Arrow should be flying")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = true
	_game_mgr._unhandled_input(event)
	assert_false(_arrow.is_flying(), "Spacebar during flight should skip")

func test_stage18_fire_during_flight_no_new_shot() -> void:
	_fire_at(Vector2(1200, 540))
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = true
	_game_mgr._unhandled_input(event)
	assert_false(_arrow.is_flying(), "Should have skipped")
	assert_false(get_tree().paused, "Should be unpaused")
	# Arrow should NOT be flying again — skip doesn't queue a new shot
	assert_false(_arrow.is_flying(), "No new shot should be queued from skip")

func test_stage18_echo_keys_ignored() -> void:
	_fire_at(Vector2(1200, 540))
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ENTER
	event.pressed = true
	event.echo = true
	_game_mgr._unhandled_input(event)
	assert_true(_arrow.is_flying(), "Echo key events should not skip")
