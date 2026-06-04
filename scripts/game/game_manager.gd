extends Node

const MOVEMENT_ACTIONS := ["move_up", "move_down", "move_left", "move_right"]

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
	if not _arrow_animator:
		return

	if _arrow_animator.is_flying():
		if event is InputEventKey and event.pressed and not event.echo:
			var is_movement := false
			for action in MOVEMENT_ACTIONS:
				if event.is_action(action):
					is_movement = true
					break
			if not is_movement:
				_arrow_animator.skip_animation()
		return

	if event.is_action_pressed("fire"):
		_try_fire()

func _try_fire() -> void:
	if not _player or not _cursor:
		return

	var player_pos := _player.global_position
	var cursor_pos := _cursor.global_position
	if player_pos == cursor_pos:
		return

	var surfaces: Array = []
	if _level_settings and "surfaces" in _level_settings:
		surfaces = _level_settings.surfaces

	var dir := Direction.new(player_pos, cursor_pos)
	var path := Tracer.trace(player_pos, dir, surfaces, GameState.new())

	if _path_renderer:
		_path_renderer.modulate.a = 0.25

	get_tree().paused = true

	if _arrow_animator:
		_arrow_animator.start_flight(path)

func _on_flight_completed() -> void:
	get_tree().paused = false
	if _path_renderer:
		_path_renderer.modulate.a = 1.0
