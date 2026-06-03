extends GutTest

var _player: CharacterBody2D
var _main_scene: Node

func before_each() -> void:
	_main_scene = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(_main_scene)
	_player = _main_scene.get_node("Player")

func _set_gravity(g: Vector2) -> void:
	_main_scene.gravity = g

func test_stage2_5_gravity_horizontal_only() -> void:
	_set_gravity(Vector2(0, 980))
	var start_pos := _player.position
	Input.action_press("move_right")
	_simulate_physics(5)
	Input.action_release("move_right")
	assert_gt(_player.position.x, start_pos.x, "Player should move right with gravity")

func test_stage2_5_jump_velocity() -> void:
	_set_gravity(Vector2(0, 980))
	await _wait_for_floor()
	assert_true(_player.is_on_floor(), "Player should be on floor after falling")
	var floor_y := _player.position.y
	Input.action_press("move_up")
	await _await_physics_frames(2)
	Input.action_release("move_up")
	assert_lt(_player.position.y, floor_y, "Player should move upward after jump")
	assert_lt(_player.velocity.y, 0.0, "Velocity should be negative (upward) after jump")

func test_stage2_5_single_jump_no_double() -> void:
	_set_gravity(Vector2(0, 980))
	await _wait_for_floor()
	Input.action_press("move_up")
	await _await_physics_frames(2)
	Input.action_release("move_up")
	var peak_velocity := _player.velocity.y
	# Wait a few frames for gravity to slow the player
	await _await_physics_frames(5)
	# Try to jump again mid-air
	Input.action_press("move_up")
	await _await_physics_frames(2)
	Input.action_release("move_up")
	# Velocity should be increasing (less negative / more positive) due to gravity, not reset to jump velocity
	assert_gt(_player.velocity.y, peak_velocity, "Should not double jump — velocity should increase from gravity")

func test_stage2_5_horizontal_ad_only() -> void:
	_set_gravity(Vector2(0, 980))
	await _wait_for_floor()
	var floor_pos := _player.position
	Input.action_press("move_down")
	_simulate_physics(5)
	Input.action_release("move_down")
	assert_almost_eq(_player.position.y, floor_pos.y, 2.0, "S key should not move player down with gravity")

func test_stage2_5_zero_gravity_unchanged() -> void:
	_set_gravity(Vector2(0, 0))
	var start_pos := _player.position
	Input.action_press("move_up")
	_simulate_physics(5)
	Input.action_release("move_up")
	assert_lt(_player.position.y, start_pos.y, "W should move up in zero gravity")

func test_stage2_5_gravity_causes_falling() -> void:
	_set_gravity(Vector2(0, 980))
	var start_pos := _player.position
	_simulate_physics(10)
	assert_gt(_player.position.y, start_pos.y, "Player should fall with gravity")

func test_stage2_5_platform_landing() -> void:
	_set_gravity(Vector2(0, 980))
	await _wait_for_floor()
	assert_true(_player.is_on_floor(), "Player should land on floor collision body")
	var floor_y := _player.position.y
	await _await_physics_frames(10)
	assert_almost_eq(_player.position.y, floor_y, 2.0, "Player should stay on floor")

func test_stage2_5_no_coyote_time() -> void:
	_set_gravity(Vector2(0, 980))
	await _wait_for_floor()
	_player.position = Vector2(1920, _player.position.y)
	_simulate_physics(2)
	Input.action_press("move_up")
	_simulate_physics(1)
	Input.action_release("move_up")
	assert_ne(_player.velocity.y, -400.0, "Should not jump after walking off edge (no coyote time)")

func _simulate_physics(count: int) -> void:
	var dt := get_physics_process_delta_time()
	for i in count:
		_player._physics_process(dt)

func _await_physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _wait_for_floor() -> void:
	for i in 300:
		await get_tree().physics_frame
		if _player.is_on_floor():
			return
	push_warning("Player never reached floor after 300 physics frames")
