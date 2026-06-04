extends Node

const MOVEMENT_ACTIONS := ["move_up", "move_down", "move_left", "move_right"]

var _player: CharacterBody2D
var _cursor: Node2D
var _arrow_animator: Node2D
var _path_renderer: Node2D
var _level_settings: Node2D
var _plan_hud: Control

var plan := PlanManager.new()
var click_detector := ClickDetector.new()
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
	if _arrow_animator:
		_arrow_animator.flight_completed.connect(_on_flight_completed)

func _process(_delta: float) -> void:
	_update_hover()

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

	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_C:
		plan.clear()
		_update_hud()
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_plan_click()
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

func _try_fire() -> void:
	if not _player or not _cursor:
		return

	var player_pos := _player.global_position
	var cursor_pos := _cursor.global_position
	if player_pos == cursor_pos:
		return

	var surfaces := _get_surfaces()
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
