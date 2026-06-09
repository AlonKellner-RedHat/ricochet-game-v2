extends Node

const MOVEMENT_ACTIONS := ["move_up", "move_down", "move_left", "move_right"]

var _player: CharacterBody2D
var _cursor: Node2D
var _arrow_animator: Node2D
var _path_renderer: Node2D
var _level_settings: Node2D
var _plan_hud: Control
var _camera: Camera2D

var plan := PlanManager.new()
var click_detector := ClickDetector.new()
var game_state := GameState.new()
var targets_hit: Dictionary = {}
var _checkpoints := CheckpointStack.new()
var _hovered_node: Node2D = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var parent := get_parent()
	_player = parent.get_node_or_null("Player")
	_cursor = parent.get_node_or_null("Cursor")
	_arrow_animator = parent.get_node_or_null("ArrowAnimator")
	_path_renderer = parent.get_node_or_null("PathRenderer")
	_level_settings = parent
	_plan_hud = parent.get_node_or_null("PlanHUD")
	_camera = parent.get_node_or_null("Camera")
	if _arrow_animator:
		_arrow_animator.flight_completed.connect(_on_flight_completed)
	if _camera and _level_settings and "level_bounds" in _level_settings:
		var bounds: Rect2 = _level_settings.level_bounds
		_camera.limit_left = int(bounds.position.x)
		_camera.limit_top = int(bounds.position.y)
		_camera.limit_right = int(bounds.end.x)
		_camera.limit_bottom = int(bounds.end.y)
	_checkpoints.set_initial(_capture_checkpoint())

func _process(_delta: float) -> void:
	_update_camera()
	_update_hover()

func _update_camera() -> void:
	if not _camera:
		return
	if _arrow_animator and _arrow_animator.is_flying():
		_camera.global_position = _arrow_animator.get_arrow_position()
	elif _player:
		_camera.global_position = _player.global_position

func _update_hover() -> void:
	if not _cursor or not _level_settings:
		return
	if _arrow_animator and _arrow_animator.is_flying():
		_clear_all_hover()
		return

	var surfaces := _get_surfaces()
	var result := click_detector.detect_hover(_cursor.global_position, surfaces)

	_clear_all_hover()

	if not result.is_empty():
		var surf: Surface = result.surface
		var side: Side.Value = result.side
		for child in _level_settings.get_children():
			if child.has_method("set_hover_side") and "surface" in child and child.surface == surf:
				child.set_hover_side(side)
				_hovered_node = child
				break

func _clear_all_hover() -> void:
	if _hovered_node and is_instance_valid(_hovered_node):
		_hovered_node.clear_hover()
	_hovered_node = null

func _input(event: InputEvent) -> void:
	if _arrow_animator and _arrow_animator.is_flying():
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

	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_G:
		if _level_settings:
			if _level_settings.gravity.length_squared() > 0.0:
				_level_settings.gravity = Vector2.ZERO
			else:
				_level_settings.gravity = Vector2(0, 980)
		return

	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_Z:
		_try_undo()
		return

	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_R:
		_try_reset()
		return

	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_C:
		plan.clear()
		_update_hud()
		_update_surface_overlays()
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_plan_click()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_try_plan_right_click()
			return

	if event.is_action_pressed("fire"):
		_try_fire()

func _try_plan_click() -> void:
	if not _cursor:
		return
	var surfaces := _get_surfaces()
	var result := click_detector.detect_click(_cursor.global_position, surfaces)
	if result.is_empty():
		return
	var surf: Surface = result.surface
	var side: Side.Value = result.side
	plan.add_entry(surf.id, side)
	_update_hud()
	_update_surface_overlays()

func _try_plan_right_click() -> void:
	if not _cursor:
		return
	var surfaces := _get_surfaces()
	var result := click_detector.detect_click(_cursor.global_position, surfaces)

	if result.is_empty():
		plan.clear()
	else:
		var surf: Surface = result.surface
		if plan.has_surface(surf.id):
			plan.remove_last_of(surf.id)
		else:
			plan.clear()

	_update_hud()
	_update_surface_overlays()

func _try_fire() -> void:
	if not _player or not _cursor:
		return

	var player_pos := _player.global_position
	var cursor_pos := _cursor.global_position
	if player_pos == cursor_pos:
		return

	_checkpoints.push(_capture_checkpoint())

	var surfaces := _get_surfaces()
	var dir := _compute_aim_direction(player_pos, cursor_pos, surfaces)
	var path := Tracer.trace(player_pos, dir, surfaces, game_state)

	if _path_renderer:
		_path_renderer.modulate.a = 0.25

	get_tree().paused = true

	if _arrow_animator:
		_arrow_animator.start_flight(path)

func _on_flight_completed() -> void:
	get_tree().paused = false
	if _path_renderer:
		_path_renderer.modulate.a = 1.0

func _try_undo() -> void:
	var data := _checkpoints.pop()
	if data == null:
		return
	_restore_checkpoint(data)

func _try_reset() -> void:
	var data := _checkpoints.reset()
	if data == null:
		return
	_restore_checkpoint(data)

func _capture_checkpoint() -> CheckpointData:
	var pos := _player.global_position if _player else Vector2.ZERO
	var vel := _player.velocity if _player else Vector2.ZERO
	return CheckpointData.new(pos, vel, game_state, plan.entries, targets_hit)

func _restore_checkpoint(data: CheckpointData) -> void:
	if _player:
		_player.global_position = data.player_position
		_player.velocity = data.player_velocity
	game_state = data.game_state.copy()
	plan.restore_from(data.plan_entries)
	targets_hit = data.targets_hit.duplicate()
	_update_hud()
	_update_surface_overlays()

func _compute_aim_direction(player_pos: Vector2, cursor_pos: Vector2, surfaces: Array) -> Direction:
	var entries: Array = plan.entries if not plan.is_empty() else []
	return Planner.compute_aim_direction(player_pos, cursor_pos, entries, surfaces, game_state)

func _get_surfaces() -> Array:
	if _level_settings and "surfaces" in _level_settings:
		return _level_settings.surfaces
	return []

func _update_hud() -> void:
	if not _plan_hud:
		return
	_plan_hud.update_plan(plan, _get_surfaces())

func _update_surface_overlays() -> void:
	if not _level_settings:
		return
	for child in _level_settings.get_children():
		if child.has_method("update_plan_overlay"):
			child.update_plan_overlay(plan)

func _dump_debug_state() -> void:
	var lines: PackedStringArray = []
	lines.append("=== DEBUG STATE (F12) ===")
	if _player:
		lines.append("Player: %s" % _player.global_position)
	if _cursor:
		lines.append("Cursor: %s" % _cursor.global_position)

	var surfaces := _get_surfaces()
	lines.append("Surfaces: %d" % surfaces.size())
	for surf in surfaces:
		var state := GameState.new()
		var left: SideConfig = surf.active_side_config(Side.Value.LEFT, state)
		var right: SideConfig = surf.active_side_config(Side.Value.RIGHT, state)
		var left_type := _effect_name(left.effect)
		var right_type := _effect_name(right.effect)
		lines.append("  Surface %d: (%s → %s) L=%s R=%s" % [
			surf.id, surf.segment.start, surf.segment.end, left_type, right_type])

	lines.append("Plan: %d entries" % plan.size())
	for i in plan.size():
		var entry: PlanManager.PlanEntry = plan.get_entry(i)
		lines.append("  [%d] surface_id=%d side=%d" % [i, entry.surface_id, entry.side])

	if _path_renderer and _path_renderer.get_traced_path():
		var path: Tracer.TracedPath = _path_renderer.get_traced_path()
		lines.append("Traced path: %d steps" % path.steps.size())
		for i in path.steps.size():
			var step: Tracer.Step = path.steps[i]
			var hit_info := "escape" if step.hit == null else "hit"
			lines.append("  Step %d: %s → %s [%s]" % [i, step.start, step.end, hit_info])

	var output := "\n".join(lines)
	print(output)

static func _effect_name(effect: RefCounted) -> String:
	if effect == null:
		return "pass"
	if effect is TerminalEffect:
		return "block"
	if effect is ReflectionEffect:
		return "reflect"
	return "unknown"
