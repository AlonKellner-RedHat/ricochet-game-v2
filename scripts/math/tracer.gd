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
	return trace(initial_ray.origin, initial_ray.direction, surfaces, game_state, bounds, initial_ray)

static func trace(origin: Vector2, direction: Direction, surfaces: Array, game_state: GameState, bounds: Rect2 = DEFAULT_BOUNDS, shared_ray: Ray = null, _target_dist: float = -1.0, mode: int = TraceMode.PHYSICAL, post_cursor_mode: int = TraceMode.PHYSICAL, plan_entries: Array = [], cache: TransformCache = null) -> TracedPath:
	var path := TracedPath.new()
	if direction.is_zero_length():
		return path
	if cache == null:
		cache = TransformCache.new()

	var state_copy := game_state.copy()
	var frame := MobiusTransform.identity()
	if shared_ray == null:
		shared_ray = Ray.new(origin, direction)
	var ray := Ray.new(origin, direction)
	var last_hit_segment: Segment = null
	var last_hit_orig_surf: Surface = null
	var current_mode: int = mode
	var plan_index := 0
	var plan_matched := true
	var aim_injected := false
	var cursor_injected := false
	var frame_dirty := true
	var norm_surfaces: Array = []
	var norm_to_surface: Dictionary = {}
	var aim_point: Vector2 = direction.end

	for _i in MAX_HITS:
		if frame_dirty:
			var cached_norm = cache.get_normalized(frame.id)
			if cached_norm != null:
				norm_surfaces = cached_norm.surfaces
				norm_to_surface = cached_norm.mapping
			else:
				norm_surfaces = _build_normalized(surfaces, frame, norm_to_surface, cache)
				cache.set_normalized(frame.id, norm_surfaces, norm_to_surface.duplicate())
			frame_dirty = false
			if last_hit_orig_surf != null:
				last_hit_segment = null
				for ns in norm_surfaces:
					var ns_surf: Surface = ns
					if norm_to_surface.get(ns_surf.segment) == last_hit_orig_surf:
						last_hit_segment = ns_surf.segment
						break
				last_hit_orig_surf = null

		var norm_segments: Array = []
		for ns in norm_surfaces:
			norm_segments.append(ns.segment)

		var hit: Intersection.HitRecord = Intersection.find_nearest_hit(ray, norm_segments, Vector2(NAN, NAN), last_hit_segment)

		# --- Virtual hitpoint competition ---
		var best_t := INF
		var best_type := ""

		# Carrier hit (forward only for now; beyond handled as fallback)
		if hit != null and hit.t > 0.0:
			best_t = hit.t
			best_type = "carrier"

		# Aim point — construction-defined, always on ray
		if not aim_injected:
			var vh := _try_virtual_hit(ray, aim_point, "aim", best_t, best_type)
			if not vh.is_empty():
				best_t = vh["t"]; best_type = vh["type"]

		# Cursor — same position as aim, but only when plan complete + matched
		var cursor_reachable := not cursor_injected and plan_index >= plan_entries.size() and plan_matched
		if cursor_reachable and aim_injected:
			var vh := _try_virtual_hit(ray, aim_point, "cursor", best_t, best_type)
			if not vh.is_empty():
				best_t = vh["t"]; best_type = vh["type"]

		# Player — waypoint or block depending on plan state
		if not cursor_reachable:
			var player_label := "player_block" if (plan_matched and frame.id == MobiusTransform.IDENTITY_ID) else "player_waypoint"
			var vh := _try_virtual_hit(ray, origin, player_label, best_t, best_type)
			if not vh.is_empty():
				best_t = vh["t"]; best_type = vh["type"]

		# Beyond carrier hit as fallback
		if best_type == "" and hit != null:
			best_t = hit.t
			best_type = "carrier"

		# --- Process winner ---
		var _arc: bool = frame.maps_lines_to_arcs()
		if best_type == "aim":
			var _vs := frame.apply(ray.origin)
			var _ve := frame.apply(aim_point)
			var _vv := frame.apply((ray.origin + aim_point) / 2.0)
			path.steps.append(Step.new(_vs, _ve, frame.id, null, shared_ray, frame, _vv, _arc))
			aim_injected = true
			if not cursor_injected and plan_index >= plan_entries.size() and plan_matched:
				path.cursor_index = path.steps.size()
				cursor_injected = true
				current_mode = post_cursor_mode
			ray = Ray.new(aim_point, ray.direction)
			continue

		if best_type == "cursor":
			var _vs2 := frame.apply(ray.origin)
			var _ve2 := frame.apply(aim_point)
			var _vv2 := frame.apply((ray.origin + aim_point) / 2.0)
			path.steps.append(Step.new(_vs2, _ve2, frame.id, null, shared_ray, frame, _vv2, _arc))
			path.cursor_index = path.steps.size()
			cursor_injected = true
			current_mode = post_cursor_mode
			ray = Ray.new(aim_point, ray.direction)
			continue

		if best_type == "player_block":
			var _vs3 := frame.apply(ray.origin)
			var _ve3 := frame.apply(origin)
			var _vv3 := frame.apply((ray.origin + origin) / 2.0)
			path.steps.append(Step.new(_vs3, _ve3, frame.id, null, shared_ray, frame, _vv3, _arc))
			break

		if best_type == "player_waypoint":
			var _vs4 := frame.apply(ray.origin)
			var _ve4 := frame.apply(origin)
			var _vv4 := frame.apply((ray.origin + origin) / 2.0)
			path.steps.append(Step.new(_vs4, _ve4, frame.id, null, shared_ray, frame, _vv4, _arc))
			ray = Ray.new(origin, ray.direction)
			continue

		if best_type == "":
			var vis_origin := frame.apply(ray.origin)
			var vis_dir := (frame.apply(ray.origin + ray.direction.to_vector().normalized()) - vis_origin).normalized()
			var escape_end := _clip_to_bounds(vis_origin, vis_dir, bounds)
			var return_start := _clip_to_bounds(vis_origin, -vis_dir, bounds)
			if vis_origin != escape_end:
				path.steps.append(Step.new(vis_origin, escape_end, frame.id, null, shared_ray, frame, (vis_origin + escape_end) / 2.0, false))
			if return_start != vis_origin:
				path.steps.append(Step.new(return_start, vis_origin, frame.id, null, shared_ray, frame, (return_start + vis_origin) / 2.0, false))
			break

		# best_type == "carrier"
		var vis_start := frame.apply(ray.origin)
		var vis_end := frame.apply(hit.point)
		var vis_via := frame.apply((ray.origin + hit.point) / 2.0)
		if hit.t < 0.0:
			var vis_dir := (vis_end - vis_start).normalized()
			var esc := _clip_to_bounds(vis_start, -vis_dir, bounds)
			var ret := _clip_to_bounds(vis_end, vis_dir, bounds)
			path.steps.append(Step.new(vis_start, esc, frame.id, null, shared_ray, frame, (vis_start + esc) / 2.0, false))
			path.steps.append(Step.new(ret, vis_end, frame.id, hit, shared_ray, frame, (ret + vis_end) / 2.0, false))
		else:
			path.steps.append(Step.new(vis_start, vis_end, frame.id, hit, shared_ray, frame, vis_via, frame.maps_lines_to_arcs()))

		var orig_surf: Surface = norm_to_surface.get(hit.segment)
		if orig_surf and orig_surf.is_target and hit.on_segment:
			path.targets_hit[orig_surf.id] = true

		# Find the NORMALIZED surface for effect lookup (has normalized carrier Möbius)
		var norm_surf: Surface = null
		for ns in norm_surfaces:
			if ns.segment == hit.segment:
				norm_surf = ns
				break

		var apply_effect := false
		var effect_config: SideConfig = null
		# Anti-conformal frame (odd reflections) reverses orientation → flip side for config lookup
		var lookup_side: Side.Value = hit.side
		if frame.conjugating:
			lookup_side = Side.Value.RIGHT if hit.side == Side.Value.LEFT else Side.Value.LEFT

		if current_mode == TraceMode.PHYSICAL:
			if norm_surf and hit.on_segment:
				effect_config = norm_surf.active_side_config(lookup_side, state_copy)
				if effect_config != null and effect_config.effect != null:
					if effect_config.effect.is_terminal():
						break
					if effect_config.effect.is_transformative():
						apply_effect = true
						# Track plan matching for cursor reachability
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

		if apply_effect:
			var mobius: MobiusTransform = effect_config.effect.get_mobius()
			var inv_mobius: MobiusTransform = effect_config.effect.get_inverse_mobius()
			frame = cache.compose_cached(frame, mobius)
			var new_origin := cache.apply_point_cached(inv_mobius, hit.point)
			ray = Ray.new(new_origin, ray.direction)
			last_hit_orig_surf = orig_surf
			last_hit_segment = null
			frame_dirty = true
			continue

		last_hit_segment = hit.segment
		last_hit_orig_surf = null
		ray = Ray.new(hit.point, ray.direction)

	return path

static func _try_virtual_hit(ray: Ray, point: Vector2, label: String, best_t: float, best_type: String) -> Dictionary:
	var t := Intersection.project_point_on_ray(ray, point)
	if t > 0.0 and t < best_t:
		return {"t": t, "type": label}
	if t == 0.0 and best_type == "":
		return {"t": 0.0, "type": label}
	return {}

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
		var s := cache.apply_point_forward(inv, surf.segment.start) if cache else inv.apply(surf.segment.start)
		var e := cache.apply_point_forward(inv, surf.segment.end) if cache else inv.apply(surf.segment.end)
		var v: Vector2
		if is_inf(surf.segment.via.x) or is_inf(surf.segment.via.y):
			v = Vector2(INF, INF)
		else:
			v = cache.apply_point_forward(inv, surf.segment.via) if cache else inv.apply(surf.segment.via)
		var new_seg := Segment.new(s, e, v)
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
