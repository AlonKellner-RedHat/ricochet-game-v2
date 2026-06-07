class_name Tracer
extends RefCounted

class Step extends RefCounted:
	var start: Vector2
	var end: Vector2
	var frame_id: int
	var hit: RefCounted
	var ray: Ray
	var frame: MobiusTransform

	func _init(p_start: Vector2 = Vector2.ZERO, p_end: Vector2 = Vector2.ZERO, p_frame_id: int = 0, p_hit: RefCounted = null, p_ray: Ray = null, p_frame: MobiusTransform = null) -> void:
		start = p_start
		end = p_end
		frame_id = p_frame_id
		hit = p_hit
		ray = p_ray
		frame = p_frame

class TracedPath extends RefCounted:
	var steps: Array = []
	var targets_hit: Dictionary = {}
	var cursor_index: int = -1

enum TraceMode { PHYSICAL = 0, PLANNED = 1 }

const MAX_HITS := 256
const DEFAULT_BOUNDS := Rect2(0, 0, 1920, 1080)

static func trace_ray(initial_ray: Ray, surfaces: Array, game_state: GameState, bounds: Rect2 = DEFAULT_BOUNDS) -> TracedPath:
	return trace(initial_ray.origin, initial_ray.direction, surfaces, game_state, bounds, initial_ray)

static func trace(origin: Vector2, direction: Direction, surfaces: Array, game_state: GameState, bounds: Rect2 = DEFAULT_BOUNDS, shared_ray: Ray = null, _target_dist: float = -1.0, mode: int = TraceMode.PHYSICAL, post_cursor_mode: int = TraceMode.PHYSICAL, plan_entries: Array = []) -> TracedPath:
	var path := TracedPath.new()
	if direction.is_zero_length():
		return path

	var state_copy := game_state.copy()
	var frame := MobiusTransform.identity()
	if shared_ray == null:
		shared_ray = Ray.new(origin, direction)
	var ray := Ray.new(origin, direction)
	var excluded: Array = []
	var cursor_injected := false
	var current_mode: int = mode
	var plan_index := 0
	var frame_dirty := true
	var norm_surfaces: Array = []
	var norm_to_surface: Dictionary = {}
	var cursor_image: Vector2 = direction.end

	for _i in MAX_HITS:
		if frame_dirty:
			norm_surfaces = _build_normalized(surfaces, frame, norm_to_surface)
			frame_dirty = false

		var norm_segments: Array = []
		for ns in norm_surfaces:
			norm_segments.append(ns.segment)

		var hit: Intersection.HitRecord = Intersection.find_nearest_hit(ray, norm_segments, excluded)
		var dir_vec := ray.direction.to_vector()
		var dir_len_sq := dir_vec.length_squared()

		if not cursor_injected and cursor_image != origin:
			var to_cursor := cursor_image - ray.origin
			var t_cursor := to_cursor.dot(dir_vec) / dir_len_sq if dir_len_sq > 0.0 else -1.0
			var cursor_wins := false
			if t_cursor > 0.0:
				cursor_wins = (hit == null or hit.t <= 0.0 or t_cursor < hit.t)
			elif t_cursor == 0.0:
				cursor_wins = (hit == null)
			if cursor_wins:
				path.steps.append(Step.new(
					frame.apply(ray.origin), frame.apply(cursor_image),
					frame.id, null, shared_ray, frame))
				path.cursor_index = path.steps.size()
				cursor_injected = true
				current_mode = post_cursor_mode
				ray = Ray.new(cursor_image, ray.direction)
				continue

		var to_player := origin - ray.origin
		var t_player := to_player.dot(dir_vec) / dir_len_sq if dir_len_sq > 0.0 else -1.0
		var player_wins := false
		if t_player > 0.0:
			player_wins = (hit == null or hit.t <= 0.0 or t_player < hit.t)
		elif t_player == 0.0:
			player_wins = (hit == null)
		if player_wins:
			path.steps.append(Step.new(
				frame.apply(ray.origin), frame.apply(origin),
				frame.id, null, shared_ray, frame))
			break

		if hit == null:
			var vis_origin := frame.apply(ray.origin)
			var vis_dir := (frame.apply(ray.origin + ray.direction.to_vector().normalized()) - vis_origin).normalized()
			var escape_end := _clip_to_bounds(vis_origin, vis_dir, bounds)
			var return_start := _clip_to_bounds(vis_origin, -vis_dir, bounds)
			if vis_origin != escape_end:
				path.steps.append(Step.new(vis_origin, escape_end, frame.id, null, shared_ray, frame))
			if return_start != vis_origin:
				path.steps.append(Step.new(return_start, vis_origin, frame.id, null, shared_ray, frame))
			break

		var vis_start := frame.apply(ray.origin)
		var vis_end := frame.apply(hit.point)
		if hit.t < 0.0:
			var vis_dir := (vis_end - vis_start).normalized()
			var esc := _clip_to_bounds(vis_start, -vis_dir, bounds)
			var ret := _clip_to_bounds(vis_end, vis_dir, bounds)
			path.steps.append(Step.new(vis_start, esc, frame.id, null, shared_ray, frame))
			path.steps.append(Step.new(ret, vis_end, frame.id, hit, shared_ray, frame))
		else:
			path.steps.append(Step.new(vis_start, vis_end, frame.id, hit, shared_ray, frame))

		var orig_surf: Surface = norm_to_surface.get(hit.segment)
		if orig_surf and orig_surf.is_target and hit.on_segment:
			path.targets_hit[orig_surf.id] = true

		var apply_effect := false
		var effect_config: SideConfig = null

		if current_mode == TraceMode.PHYSICAL:
			if orig_surf and hit.on_segment:
				effect_config = orig_surf.active_side_config(hit.side, state_copy)
				if effect_config != null:
					if effect_config.effect is TerminalEffect:
						break
					if effect_config.effect is TransformativeEffect:
						apply_effect = true
		elif current_mode == TraceMode.PLANNED:
			if orig_surf and plan_index < plan_entries.size():
				var entry: PlanManager.PlanEntry = plan_entries[plan_index]
				if orig_surf.id == entry.surface_id:
					effect_config = orig_surf.active_side_config(entry.side, state_copy)
					if effect_config != null and effect_config.effect is TransformativeEffect:
						apply_effect = true
					plan_index += 1

		if apply_effect:
			var mobius: MobiusTransform = effect_config.effect.get_mobius()
			var inv_mobius: MobiusTransform = effect_config.effect.get_inverse_mobius()
			frame = frame.compose(mobius)
			ray = Ray.new(inv_mobius.apply(hit.point), ray.direction)
			excluded = []
			frame_dirty = true
			continue

		excluded.append(hit.segment)
		ray = Ray.new(hit.point, ray.direction)

	return path

static func _build_normalized(surfaces: Array, frame: MobiusTransform, out_mapping: Dictionary) -> Array:
	out_mapping.clear()
	if frame.id == MobiusTransform.IDENTITY_ID:
		for surf in surfaces:
			out_mapping[surf.segment] = surf
		return surfaces

	var inv := frame.invert()
	var result: Array = []
	for surf in surfaces:
		var s := inv.apply(surf.segment.start)
		var e := inv.apply(surf.segment.end)
		var v: Vector2
		if is_inf(surf.segment.via.x) or is_inf(surf.segment.via.y):
			v = Vector2(INF, INF)
		else:
			v = inv.apply(surf.segment.via)
		var new_seg := Segment.new(s, e, v)
		var state := GameState.new()
		var left: SideConfig = surf.active_side_config(Side.Value.LEFT, state)
		var right: SideConfig = surf.active_side_config(Side.Value.RIGHT, state)
		var new_surf := Surface.new(new_seg, left, right, surf.is_target, surf.player_solid)
		out_mapping[new_surf.segment] = surf
		result.append(new_surf)
	return result

static func _clip_to_bounds(origin: Vector2, dir: Vector2, bounds: Rect2) -> Vector2:
	var min_t := INF
	if dir.x > 0.0:
		min_t = minf(min_t, (bounds.end.x - origin.x) / dir.x)
	elif dir.x < 0.0:
		min_t = minf(min_t, (bounds.position.x - origin.x) / dir.x)
	if dir.y > 0.0:
		min_t = minf(min_t, (bounds.end.y - origin.y) / dir.y)
	elif dir.y < 0.0:
		min_t = minf(min_t, (bounds.position.y - origin.y) / dir.y)
	if is_inf(min_t) or min_t < 0.0:
		min_t = 100.0
	return origin + dir * min_t
