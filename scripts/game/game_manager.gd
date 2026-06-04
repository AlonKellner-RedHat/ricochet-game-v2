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
				_arrow_animator.speed_up()
		return

	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_F12:
		_dump_debug_state()
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

func _dump_debug_state() -> void:
	var lines: PackedStringArray = []
	lines.append("=== DEBUG STATE (F12) ===")
	if _player:
		lines.append("Player: %s" % _player.global_position)
	if _cursor:
		lines.append("Cursor: %s" % _cursor.global_position)

	var surfaces: Array = []
	if _level_settings and "surfaces" in _level_settings:
		surfaces = _level_settings.surfaces
	lines.append("Surfaces: %d" % surfaces.size())
	for surf in surfaces:
		var state := GameState.new()
		var left: SideConfig = surf.active_side_config(Side.Value.LEFT, state)
		var right: SideConfig = surf.active_side_config(Side.Value.RIGHT, state)
		var left_type := _effect_name(left.effect)
		var right_type := _effect_name(right.effect)
		lines.append("  Surface %d: (%s → %s) L=%s R=%s" % [
			surf.id, surf.segment.start, surf.segment.end, left_type, right_type])

	if _path_renderer and _path_renderer.get_traced_path():
		var path: Tracer.TracedPath = _path_renderer.get_traced_path()
		lines.append("Traced path: %d steps" % path.steps.size())
		for i in path.steps.size():
			var step: Tracer.Step = path.steps[i]
			var hit_info := "escape" if step.hit == null else "hit"
			lines.append("  Step %d: %s → %s [%s]" % [i, step.start, step.end, hit_info])

	var output := "\n".join(lines)
	print(output)
	lines.append("========================")

static func _effect_name(effect: RefCounted) -> String:
	if effect == null:
		return "pass"
	if effect is TerminalEffect:
		return "block"
	if effect is ReflectionEffect:
		return "reflect"
	return "unknown"
