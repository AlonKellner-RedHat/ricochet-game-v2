extends Node

var _player: CharacterBody2D
var _cursor: Node2D
var _arrow_animator: Node2D
var _path_renderer: Node2D
var _level_settings: Node2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var parent := get_parent()
	_player = parent.get_node_or_null("Player")
	_cursor = parent.get_node_or_null("Cursor")
	_arrow_animator = parent.get_node_or_null("ArrowAnimator")
	_path_renderer = parent.get_node_or_null("PathRenderer")
	_level_settings = parent
	if _arrow_animator:
		_arrow_animator.flight_completed.connect(_on_flight_completed)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fire"):
		_try_fire()

func _try_fire() -> void:
	if _arrow_animator and _arrow_animator.is_flying():
		return
	if not _player or not _cursor:
		return

	var player_pos := _player.global_position
	var cursor_pos := _cursor.global_position
	if player_pos == cursor_pos:
		return

	var surfaces: Array = []
	if _level_settings and "surfaces" in _level_settings:
		surfaces = _level_settings.surfaces

	var bounds: Rect2 = Tracer.DEFAULT_BOUNDS
	if _level_settings and "room_rect" in _level_settings:
		bounds = _level_settings.room_rect

	var dir := Direction.new(player_pos, cursor_pos)
	var path := Tracer.trace(player_pos, dir, surfaces, GameState.new(), bounds)

	if _path_renderer:
		_path_renderer.modulate.a = 0.25

	get_tree().paused = true

	if _arrow_animator:
		_arrow_animator.start_flight(path)

func _on_flight_completed() -> void:
	get_tree().paused = false
	if _path_renderer:
		_path_renderer.modulate.a = 1.0
