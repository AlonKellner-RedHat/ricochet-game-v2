class_name Tracer
extends RefCounted

class Step extends RefCounted:
	var start: Vector2
	var end: Vector2
	var via: Vector2
	var frame_id: int
	var hit: RefCounted
	var ray: Ray
	var frame: MobiusTransform
	var is_arc_step: bool

	func _init(p_start: Vector2 = Vector2.ZERO, p_end: Vector2 = Vector2.ZERO, p_frame_id: int = 0, p_hit: RefCounted = null, p_ray: Ray = null, p_frame: MobiusTransform = null, p_via: Vector2 = Vector2.ZERO, p_is_arc: bool = false) -> void:
		start = p_start
		end = p_end
		frame_id = p_frame_id
		hit = p_hit
		ray = p_ray
		frame = p_frame
		via = p_via if p_via != Vector2.ZERO else (p_start + p_end) / 2.0
		is_arc_step = p_is_arc

class TracedPath extends RefCounted:
	var steps: Array = []
	var targets_hit: Dictionary = {}
	var cursor_index: int = -1

enum TraceMode { PHYSICAL = 0, PLANNED = 1 }

const MAX_HITS := 256
const DEFAULT_BOUNDS := Rect2(0, 0, 1920, 1080)

static func trace_ray(initial_ray: Ray, surfaces: Array, game_state: GameState, bounds: Rect2 = DEFAULT_BOUNDS) -> TracedPath:
	return trace(initial_ray.origin.coords, initial_ray.direction, surfaces, game_state, bounds, initial_ray)

static func trace(origin: Vector2, direction: Direction, surfaces: Array, game_state: GameState, bounds: Rect2 = DEFAULT_BOUNDS, shared_ray: Ray = null, _target_dist: float = -1.0, mode: int = TraceMode.PHYSICAL, post_cursor_mode: int = TraceMode.PHYSICAL, plan_entries: Array = [], cache: TransformCache = null, cursor_pos: Vector2 = Vector2(INF, INF)) -> TracedPath:
	var path := TracedPath.new()
	if direction.is_zero_length():
		return path
	if cache == null:
		cache = TransformCache.new()

	var state_copy := game_state.copy()
	var transform_stack: Array = []
	var frame := MobiusTransform.identity()
	if shared_ray == null:
		shared_ray = Ray.from_coords(origin, direction)
	var ray := Ray.from_coords(origin, direction)
	var last_hit_segment: Segment = null
	var last_hit_orig_surf: Surface = null
	var current_mode: int = mode
	var plan_index := 0
	var plan_matched := true
	var cursor_injected := false
	var frame_dirty := true
	var norm_surfaces: Array = []
	var norm_to_surface: Dictionary = {}
	var aim_point_pt: Point
	if cursor_pos.x != INF:
		aim_point_pt = Point.at(cursor_pos)
	else:
		aim_point_pt = Point.at(direction.end.coords)
	var aim_in_frame: Vector2 = aim_point_pt.coords
	var step_left_blocked := false
	var step_right_blocked := false
	var hit_count := 0

	while hit_count < MAX_HITS:
		# --- Frame computation ---
		if frame_dirty:
			frame = MobiusTransform.identity()
			for t in transform_stack:
				frame = cache.compose_cached(frame, t.mobius)
			var cached_norm = cache.get_normalized(frame.id)
			if cached_norm != null:
				norm_surfaces = cached_norm.surfaces
				norm_to_surface = cached_norm.mapping
			else:
				norm_surfaces = _build_normalized(surfaces, frame, norm_to_surface, cache)
				cache.set_normalized(frame.id, norm_surfaces, norm_to_surface.duplicate())
			frame_dirty = false
			if transform_stack.is_empty():
				aim_in_frame = aim_point_pt.coords
			else:
				var frame_inv := cache.invert_cached(frame)
				aim_in_frame = frame_inv.apply(aim_point_pt.coords)
			if last_hit_orig_surf != null:
				last_hit_segment = null
				for ns in norm_surfaces:
					var ns_surf: Surface = ns
					if norm_to_surface.get(ns_surf.segment) == last_hit_orig_surf:
						last_hit_segment = ns_surf.segment
						break
				last_hit_orig_surf = null

		# --- Build norm segments ---
		var norm_segments: Array = []
		for ns in norm_surfaces:
			norm_segments.append(ns.segment)

		# --- Build stage hitpoints ---
		var carrier_hits := Intersection.find_all_hits(ray, norm_segments, last_hit_segment)
		var origin_hp := Intersection.HitRecord.new(0.0, ray.origin.coords, null, Side.Value.LEFT, false)

		# No carriers and no cursor → escape/return and done
		var cursor_reachable := not cursor_injected and plan_index >= plan_entries.size() and plan_matched
		if carrier_hits.size() == 0 and not cursor_reachable:
			var vis_origin := frame.apply(ray.origin.coords)
			var vis_dir := (frame.apply(ray.origin.coords + ray.direction.to_vector().normalized()) - vis_origin).normalized()
			var escape_end := _clip_to_bounds(vis_origin, vis_dir, bounds)
			var return_start := _clip_to_bounds(vis_origin, -vis_dir, bounds)
			if vis_origin != escape_end:
				path.steps.append(Step.new(vis_origin, escape_end, frame.id, null, shared_ray, frame, (vis_origin + escape_end) / 2.0, false))
			if return_start != vis_origin:
				path.steps.append(Step.new(return_start, vis_origin, frame.id, null, shared_ray, frame, (return_start + vis_origin) / 2.0, false))
			break

		# Assemble and sort hitpoint list
		var hitpoints: Array = carrier_hits.duplicate()
		hitpoints.append(origin_hp)
		var cursor_hp: Intersection.HitRecord = null
		if cursor_reachable:
			var cursor_t := Intersection.project_point_on_ray(ray, aim_in_frame)
			cursor_hp = Intersection.HitRecord.new(cursor_t, aim_in_frame, null, Side.Value.LEFT, false)
			hitpoints.append(cursor_hp)
		hitpoints = Intersection.projective_sort(hitpoints)

		# --- Walk stage hitpoints ---
		var _arc: bool = frame.maps_lines_to_arcs()
		var step_origin_pos := ray.origin.coords
		var walk_t := 0.0
		var trace_done := false
		var stage_ended := false
		var has_wrapped := false

		for hp_idx in hitpoints.size():
			var hp: Intersection.HitRecord = hitpoints[hp_idx]
			hit_count += 1
			if hit_count > MAX_HITS:
				trace_done = true
				break

			var vis_start := frame.apply(step_origin_pos)
			var vis_end := frame.apply(hp.point.coords)
			var vis_via := frame.apply((step_origin_pos + hp.point.coords) / 2.0)
			var is_wrap := hp.t < walk_t
			var is_null_seg := hp.segment == null
			var is_cursor := hp == cursor_hp
			var is_origin := is_null_seg and not is_cursor
			var step_hit: Intersection.HitRecord = null if is_null_seg else hp

			# --- Zero-length skip ---
			if vis_start == vis_end:
				if is_origin:
					if hp_idx == 0:
						var vis_dir2 := (frame.apply(step_origin_pos + ray.direction.to_vector().normalized()) - vis_start).normalized()
						var escape_end := _clip_to_bounds(vis_start, vis_dir2, bounds)
						var return_start := _clip_to_bounds(vis_start, -vis_dir2, bounds)
						if vis_start != escape_end:
							path.steps.append(Step.new(vis_start, escape_end, frame.id, null, shared_ray, frame, (vis_start + escape_end) / 2.0, false))
						if return_start != vis_start:
							path.steps.append(Step.new(return_start, vis_start, frame.id, null, shared_ray, frame, (return_start + vis_start) / 2.0, false))
					trace_done = true
					break
				if is_cursor:
					path.cursor_index = path.steps.size()
					cursor_injected = true
					current_mode = post_cursor_mode
				walk_t = hp.t
				step_origin_pos = hp.point.coords
				continue

			if is_wrap and not is_null_seg:
				has_wrapped = true

			# --- Origin: escape to bounds or block ---
			if is_origin:
				if has_wrapped:
					if is_wrap:
						var vis_dir := (vis_end - vis_start).normalized()
						var esc := _clip_to_bounds(vis_start, -vis_dir, bounds)
						var ret := _clip_to_bounds(vis_end, vis_dir, bounds)
						path.steps.append(Step.new(vis_start, esc, frame.id, null, shared_ray, frame, (vis_start + esc) / 2.0, false))
						path.steps.append(Step.new(ret, vis_end, frame.id, null, shared_ray, frame, (ret + vis_end) / 2.0, false))
					else:
						path.steps.append(Step.new(vis_start, vis_end, frame.id, null, shared_ray, frame, vis_via, _arc))
				else:
					var vis_dir2 := (frame.apply(step_origin_pos + ray.direction.to_vector().normalized()) - vis_start).normalized()
					var escape_end := _clip_to_bounds(vis_start, vis_dir2, bounds)
					var return_start := _clip_to_bounds(vis_start, -vis_dir2, bounds)
					if vis_start != escape_end:
						path.steps.append(Step.new(vis_start, escape_end, frame.id, null, shared_ray, frame, (vis_start + escape_end) / 2.0, false))
					if return_start != vis_start:
						path.steps.append(Step.new(return_start, vis_start, frame.id, null, shared_ray, frame, (return_start + vis_start) / 2.0, false))
				trace_done = true
				break

			# --- Generate visual step ---
			if is_wrap:
				var vis_dir := (vis_end - vis_start).normalized()
				var esc := _clip_to_bounds(vis_start, -vis_dir, bounds)
				var ret := _clip_to_bounds(vis_end, vis_dir, bounds)
				path.steps.append(Step.new(vis_start, esc, frame.id, null, shared_ray, frame, (vis_start + esc) / 2.0, false))
				path.steps.append(Step.new(ret, vis_end, frame.id, step_hit, shared_ray, frame, (ret + vis_end) / 2.0, false))
			else:
				path.steps.append(Step.new(vis_start, vis_end, frame.id, step_hit, shared_ray, frame, vis_via, _arc))

			# --- Cursor check ---
			if is_cursor:
				path.cursor_index = path.steps.size()
				cursor_injected = true
				current_mode = post_cursor_mode
				ray = Ray.from_coords(hp.point.coords, ray.direction)
				last_hit_segment = null
				stage_ended = true
				break

			# --- Target tracking ---
			var orig_surf: Surface = norm_to_surface.get(hp.segment)
			if orig_surf and orig_surf.is_target and hp.on_segment:
				path.targets_hit[orig_surf.id] = true

			# --- Blockage ---
			step_left_blocked = step_left_blocked or hp.blocked_left
			step_right_blocked = step_right_blocked or hp.blocked_right

			if hp.at_endpoint > 0 and not (step_left_blocked and step_right_blocked):
				for ns in norm_surfaces:
					var ns_surf: Surface = ns
					if ns_surf.segment == hp.segment:
						continue
					var ep := Intersection.at_which_endpoint(hp.point.coords, ns_surf.segment)
					if ep > 0:
						var sides := Intersection.endpoint_blocked_sides(hp.point.coords, ns_surf.segment, ray, ep)
						step_left_blocked = step_left_blocked or sides[0]
						step_right_blocked = step_right_blocked or sides[1]

			var fully_blocked := step_left_blocked and step_right_blocked

			# --- Effect application ---
			var norm_surf: Surface = null
			for ns in norm_surfaces:
				if ns.segment == hp.segment:
					norm_surf = ns
					break

			var apply_effect := false
			var effect_config: SideConfig = null
			var lookup_side: Side.Value = hp.side
			if frame.conjugating:
				lookup_side = Side.Value.RIGHT if hp.side == Side.Value.LEFT else Side.Value.LEFT

			if current_mode == TraceMode.PHYSICAL:
				if norm_surf and fully_blocked:
					effect_config = norm_surf.active_side_config(lookup_side, state_copy)
					if effect_config != null and effect_config.effect != null:
						if effect_config.effect.is_terminal():
							trace_done = true
							break
						if effect_config.effect.is_transformative():
							apply_effect = true
							if plan_index < plan_entries.size():
								if orig_surf.id == plan_entries[plan_index].surface_id:
									plan_index += 1
								else:
									plan_matched = false
							else:
								plan_matched = false
			elif current_mode == TraceMode.PLANNED:
				if orig_surf and plan_index < plan_entries.size():
					var entry: PlanManager.PlanEntry = plan_entries[plan_index]
					if orig_surf.id == entry.surface_id:
						effect_config = norm_surf.active_side_config(entry.side, state_copy) if norm_surf else null
						if effect_config != null and effect_config.effect != null and effect_config.effect.is_transformative():
							apply_effect = true
						plan_index += 1

			if fully_blocked:
				step_left_blocked = false
				step_right_blocked = false

			if apply_effect:
				var tracked: TrackedTransform = effect_config.effect.get_tracked_transform()
				transform_stack.append(tracked)
				var new_origin := tracked.inverse.mobius.apply(hp.point.coords)
				ray = Ray.from_coords(new_origin, ray.direction)
				last_hit_orig_surf = orig_surf
				last_hit_segment = null
				frame_dirty = true
				stage_ended = true
				break

			last_hit_segment = hp.segment
			last_hit_orig_surf = null
			walk_t = hp.t
			step_origin_pos = hp.point.coords

		if trace_done:
			break
		if not stage_ended:
			break

	return path

static func _build_normalized(surfaces: Array, frame: MobiusTransform, out_mapping: Dictionary, cache: TransformCache = null) -> Array:
	out_mapping.clear()
	if frame.id == MobiusTransform.IDENTITY_ID:
		for surf in surfaces:
			out_mapping[surf.segment] = surf
		return surfaces

	var inv: MobiusTransform
	if cache:
		inv = cache.invert_cached(frame)
	else:
		inv = frame.invert()
	var result: Array = []
	for surf in surfaces:
		var s := cache.apply_point_forward(inv, surf.segment.start.coords) if cache else inv.apply(surf.segment.start.coords)
		var e := cache.apply_point_forward(inv, surf.segment.end.coords) if cache else inv.apply(surf.segment.end.coords)
		var v: Vector2
		if is_inf(surf.segment.via.coords.x) or is_inf(surf.segment.via.coords.y):
			v = Vector2(INF, INF)
		else:
			v = cache.apply_point_forward(inv, surf.segment.via.coords) if cache else inv.apply(surf.segment.via.coords)
		var new_seg := Segment.from_coords(s, e, v)
		var state := GameState.new()
		var left := _normalize_config(surf.active_side_config(Side.Value.LEFT, state), new_seg)
		var right := _normalize_config(surf.active_side_config(Side.Value.RIGHT, state), new_seg)
		var new_surf := Surface.new(new_seg, left, right, surf.is_target, surf.player_solid)
		out_mapping[new_surf.segment] = surf
		result.append(new_surf)
	return result

static func _normalize_config(config: SideConfig, norm_seg: Segment) -> SideConfig:
	if config == null or config.effect == null:
		return config
	var norm_effect: Effect = config.effect.normalized(norm_seg.get_carrier())
	if norm_effect != config.effect:
		return SideConfig.new(norm_effect, config.interactive)
	return config

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
