extends GutTest

var _player: CharacterBody2D
var _cursor: Node2D
var _renderer: Node2D
var _main_scene: Node

func before_each() -> void:
	_main_scene = load("res://scenes/main.tscn").instantiate()
	_main_scene.gravity = Vector2.ZERO
	add_child_autofree(_main_scene)
	_player = _main_scene.get_node("Player")
	_cursor = _main_scene.get_node("Cursor")
	_renderer = _main_scene.get_node("PathRenderer")

func test_stage5_preview_exists_when_cursor_differs() -> void:
	_cursor.global_position = Vector2(500, 300)
	assert_true(_renderer.has_line(), "Renderer should have a line when cursor differs from player")

func test_stage5_preview_absent_when_cursor_equals_player() -> void:
	_cursor.global_position = _player.global_position
	assert_false(_renderer.has_line(), "Renderer should have no line when cursor equals player")

func test_stage5_preview_color_green() -> void:
	assert_eq(_renderer.LINE_COLOR, Color.GREEN, "Preview line color should be green")

func test_stage5_preview_endpoints() -> void:
	_cursor.global_position = Vector2(500, 300)
	assert_eq(_renderer.get_line_from(), _player.global_position, "Line should start at player position")
	assert_eq(_renderer.get_line_to(), _cursor.global_position, "Line should end at cursor position")
