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

	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_TAB:
		if _path_renderer:
			_path_renderer.cycle_display_mode()
		get_viewport().set_input_as_handled()
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

	var player_pos := Vector2.ZERO
	var cursor_pos := Vector2.ZERO
	if _player:
		player_pos = _player.global_position
		lines.append("Player: %s" % player_pos)
	if _cursor:
		cursor_pos = _cursor.global_position
		lines.append("Cursor: %s" % cursor_pos)
	if _player and _cursor:
		var aim_vec := (cursor_pos - player_pos)
		lines.append("Aim vector: %s (len=%.2f)" % [aim_vec.normalized(), aim_vec.length()])

	var surfaces := _get_surfaces()
	lines.append("Surfaces: %d" % surfaces.size())
	for surf in surfaces:
		var state := GameState.new()
		var left: SideConfig = surf.active_side_config(Side.Value.LEFT, state)
		var right: SideConfig = surf.active_side_config(Side.Value.RIGHT, state)
		var left_type := _effect_name(left.effect if left else null)
		var right_type := _effect_name(right.effect if right else null)
		var seg_len: float = surf.segment.start.coords.distance_to(surf.segment.end.coords)
		var solid_str := " SOLID" if surf.player_solid else ""
		var target_str := " TARGET" if surf.is_target else ""
		lines.append("  Surface %d: (%s → %s) len=%.1f L=%s R=%s%s%s" % [
			surf.id, surf.segment.start.coords, surf.segment.end.coords,
			seg_len, left_type, right_type, solid_str, target_str])

	lines.append("Plan: %d entries" % plan.size())
	for i in plan.size():
		var entry: PlanManager.PlanEntry = plan.get_entry(i)
		var side_name := "LEFT" if entry.side == Side.Value.LEFT else "RIGHT"
		lines.append("  [%d] surface_id=%d side=%s" % [i, entry.surface_id, side_name])

	if _path_renderer:
		lines.append("Display mode: %s (F11 to cycle)" % _path_renderer.DISPLAY_MODE_NAMES[_path_renderer.display_mode])

	# Aim direction from planner
	if _player and _cursor and _path_renderer:
		var plan_entries: Array = []
		var p: PlanManager = _path_renderer._get_plan()
		if p and not p.is_empty():
			plan_entries = p.entries
		var aim_dir: Direction = Planner.compute_aim_direction(
			player_pos, cursor_pos, plan_entries, surfaces, GameState.new())
		lines.append("Planner aim: direction=%s end=%s" % [aim_dir.to_normalized(), aim_dir.end.coords])
		if plan_entries.size() > 0:
			var image = aim_dir.end.coords
			lines.append("  Image (aim target): %s" % image)
			lines.append("  Cursor→Image dist: %.2f" % cursor_pos.distance_to(image))

	_dump_trace(lines, "Physical", "P", _path_renderer.get_traced_path() if _path_renderer else null, surfaces)
	_dump_trace(lines, "Planned", "L", _path_renderer.get_planned_path() if _path_renderer else null, surfaces)
	_dump_merged(lines)

	lines.append("=== END DEBUG STATE ===")
	var output := "\n".join(lines)
	print(output)

func _dump_trace(lines: PackedStringArray, trace_name: String, prefix: String, path: Tracer.TracedPath, surfaces: Array) -> void:
	if path == null:
		lines.append("%s trace: (null)" % trace_name)
		return
	lines.append("%s trace: %d steps, cursor_index=%d, targets_hit=%s" % [
		trace_name, path.steps.size(), path.cursor_index, path.targets_hit])
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		var parts: PackedStringArray = []
		parts.append("  %s%d: %s → %s" % [prefix, i, step.start, step.end])
		var seg_len := step.start.distance_to(step.end)
		parts.append("len=%.1f" % seg_len)
		parts.append("fid=%d" % step.frame_id)
		if step.is_arc_step:
			parts.append("ARC")
		if step.frame and step.frame.conjugating:
			parts.append("CONJ")
		if step.hit == null:
			parts.append("[virt]")
		else:
			var hit: Intersection.HitRecord = step.hit
			var side_name := "L" if hit.side == Side.Value.LEFT else "R"
			var on_seg_str := "on" if hit.on_segment else "off"
			var surf_id := _find_surface_id_for_segment(hit.segment, surfaces)
			parts.append("[hit t=%.4f side=%s %s-seg surf=%s]" % [hit.t, side_name, on_seg_str, surf_id])
		if i == path.cursor_index:
			parts.append("<-- CURSOR")
		lines.append(" ".join(parts))

func _dump_merged(lines: PackedStringArray) -> void:
	if not _path_renderer:
		return
	var typed: Array = _path_renderer.get_typed_steps()
	if typed.size() == 0:
		lines.append("Merged: (empty)")
		return
	var type_names := {
		StepTypes.Type.ALIGNED: "ALIGNED",
		StepTypes.Type.ALIGNED_POST_PLANNED: "ALIGNED_POST",
		StepTypes.Type.DIVERGED_PHYSICAL: "DIV_PHYS",
		StepTypes.Type.DIVERGED_PLANNED: "DIV_PLAN",
		StepTypes.Type.DIVERGED_POST_PLANNED: "DIV_POST",
	}
	lines.append("Merged: %d steps" % typed.size())
	for i in typed.size():
		var ms: StepTreeMerge.MergedStep = typed[i]
		var tname: String = type_names.get(ms.type, "?%d" % ms.type)
		var solid_str := "solid" if StepTypes.is_solid(ms.type) else "dash"
		lines.append("  M%d: %s → %s [%s %s] fid=%d" % [
			i, ms.start, ms.end, tname, solid_str, ms.frame_id])

func _find_surface_id_for_segment(seg: Segment, surfaces: Array) -> String:
	for surf in surfaces:
		if surf.segment == seg:
			return str(surf.id)
	return "?"

static func _effect_name(effect: RefCounted) -> String:
	if effect == null:
		return "pass"
	if effect is TerminalEffect:
		return "block"
	if effect is ReflectionEffect:
		return "reflect"
	if effect is CircleInversionEffect:
		return "inversion"
	return "unknown"
