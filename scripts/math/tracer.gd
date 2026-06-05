class_name Tracer
extends RefCounted

class Step extends RefCounted:
	var start: Vector2
	var end: Vector2
	var frame_id: int
	var hit: RefCounted
	var ray: Ray
	var frame: MobiusTransform

	func _init(p_start: Vector2, p_end: Vector2, p_frame_id: int, p_hit: RefCounted = null, p_ray: Ray = null, p_frame: MobiusTransform = null) -> void:
		start = p_start
		end = p_end
		frame_id = p_frame_id
		hit = p_hit
		ray = p_ray
		frame = p_frame

class TracedPath extends RefCounted:
	var steps: Array = []
	var targets_hit: Dictionary = {}

const MAX_HITS := 256
const DEFAULT_BOUNDS := Rect2(0, 0, 1920, 1080)

static func trace_ray(initial_ray: Ray, surfaces: Array, game_state: GameState, bounds: Rect2 = DEFAULT_BOUNDS) -> TracedPath:
	return trace(initial_ray.origin, initial_ray.direction, surfaces, game_state, bounds, initial_ray)

static func trace(origin: Vector2, direction: Direction, surfaces: Array, game_state: GameState, bounds: Rect2 = DEFAULT_BOUNDS, shared_ray: Ray = null, target_dist: float = -1.0) -> TracedPath:
	var path := TracedPath.new()

	if direction.is_zero_length():
		return path

	var state_copy := game_state.copy()
	var frame := MobiusTransform.identity()
	var provenance_ray: Ray = shared_ray if shared_ray != null else Ray.new(origin, direction)
	var ray := provenance_ray
	var excluded: Array = []
	var target_passed := target_dist < 0.0
	var accumulated_dist := 0.0
	var frame_dirty := true
	var normalized_surfaces: Array = []
	var norm_to_surface: Dictionary = {}

	for i in MAX_HITS:
		if frame_dirty:
			normalized_surfaces = _build_normalized(surfaces, frame, norm_to_surface)
			frame_dirty = false

		var norm_segments: Array = []
		for ns in normalized_surfaces:
			norm_segments.append(ns.segment)

		var hit = Intersection.find_earliest_hit(ray, norm_segments, excluded)

		if not target_passed:
			var dir_vec: Vector2 = ray.direction.to_vector()
			var dir_len: float = dir_vec.length()
			var remaining_to_target: float = target_dist - accumulated_dist
			var t_target: float = remaining_to_target / dir_len if dir_len > 0.0 else -1.0
			if remaining_to_target > 0.01 and t_target > 0.0 and (hit == null or hit.t < 0.0 or t_target < hit.t):
				var target_point: Vector2 = ray.origin + dir_vec.normalized() * (target_dist - accumulated_dist)
				var tgt_vis_start: Vector2 = frame.apply(ray.origin)
				var tgt_vis_end: Vector2 = frame.apply(target_point)
				path.steps.append(Step.new(tgt_vis_start, tgt_vis_end, frame.id, null, provenance_ray, frame))
				accumulated_dist = target_dist
				target_passed = true
				ray = Ray.new(target_point, ray.direction)
				continue

		if hit == null:
			var vis_origin: Vector2 = frame.apply(ray.origin)
			var vis_dir: Vector2 = (frame.apply(ray.origin + ray.direction.to_vector().normalized()) - vis_origin).normalized()
			var escape_end: Vector2 = _clip_to_bounds_edge(vis_origin, vis_dir, bounds)
			var return_start: Vector2 = _clip_to_bounds_edge(vis_origin, -vis_dir, bounds)
			path.steps.append(Step.new(vis_origin, escape_end, frame.id, null, provenance_ray, frame))
			path.steps.append(Step.new(return_start, vis_origin, frame.id, null, provenance_ray, frame))
			break

		var vis_start: Vector2 = frame.apply(ray.origin)
		var vis_end: Vector2 = frame.apply(hit.point)

		var step_len: float = ray.origin.distance_to(hit.point)
		if hit.t < 0.0:
			var vis_dir: Vector2 = (vis_end - vis_start).normalized()
			var escape_end: Vector2 = _clip_to_bounds_edge(vis_start, -vis_dir, bounds)
			var return_start: Vector2 = _clip_to_bounds_edge(vis_end, vis_dir, bounds)
			path.steps.append(Step.new(vis_start, escape_end, frame.id, null, provenance_ray, frame))
			path.steps.append(Step.new(return_start, vis_end, frame.id, hit, provenance_ray, frame))
		else:
			path.steps.append(Step.new(vis_start, vis_end, frame.id, hit, provenance_ray, frame))
		accumulated_dist += step_len
		if not target_passed and accumulated_dist >= target_dist:
			target_passed = true

		var orig_surf: Surface = norm_to_surface.get(hit.segment)
		if orig_surf and orig_surf.is_target:
			path.targets_hit[orig_surf.id] = true

		var config: SideConfig = null
		if orig_surf:
			config = orig_surf.active_side_config(hit.side, state_copy)

		if config == null or config.effect == null:
			excluded.append(hit.segment)
			ray = Ray.new(hit.point, ray.direction)
			continue

		if config.effect is TerminalEffect:
			break

		if config.effect is TransformativeEffect:
			var mobius: MobiusTransform = config.effect.get_mobius()
			var inv_mobius: MobiusTransform = config.effect.get_inverse_mobius()
			frame = frame.compose(mobius)
			var new_origin: Vector2 = inv_mobius.apply(hit.point)
			excluded = []
			ray = Ray.new(new_origin, ray.direction)
			frame_dirty = true
			continue

		assert(false, "ProjectiveEffect not implemented until Stage 47")
		break

	return path

static func trace_planned(origin: Vector2, direction: Direction, plan_entries: Array, surfaces: Array, game_state: GameState, cursor: Vector2, shared_ray: Ray = null) -> TracedPath:
	var path := TracedPath.new()

	if direction.is_zero_length() or plan_entries.size() == 0:
		return path

	var frame := MobiusTransform.identity()
	var provenance_ray: Ray = shared_ray if shared_ray != null else Ray.new(origin, direction)
	var ray := provenance_ray
	for entry_idx in plan_entries.size():
		var entry: PlanManager.PlanEntry = plan_entries[entry_idx]
		var surf := _find_surface_by_id(entry.surface_id, surfaces)
		if surf == null:
			break

		var norm_carrier: GeneralizedCircle
		if frame.id == MobiusTransform.IDENTITY_ID:
			norm_carrier = surf.segment.get_carrier()
		else:
			var inv := frame.invert()
			var s: Vector2 = inv.apply(surf.segment.start)
			var e: Vector2 = inv.apply(surf.segment.end)
			var v: Vector2
			if is_inf(surf.segment.via.x) or is_inf(surf.segment.via.y):
				v = Vector2(INF, INF)
			else:
				v = inv.apply(surf.segment.via)
			norm_carrier = Segment.new(s, e, v).get_carrier()

		var hits := Intersection.intersect_line_with_carrier(ray, norm_carrier)
		if hits.size() == 0:
			break

		var best: Dictionary = hits[0]
		for j in range(1, hits.size()):
			if hits[j].t > 0.0 and (best.t <= 0.0 or hits[j].t < best.t):
				best = hits[j]
			elif hits[j].t <= 0.0 and best.t <= 0.0 and hits[j].t < best.t:
				best = hits[j]

		if best.point == ray.origin:
			break

		var vis_start: Vector2 = frame.apply(ray.origin)
		var vis_end: Vector2 = frame.apply(best.point)
		path.steps.append(Step.new(vis_start, vis_end, frame.id, null, provenance_ray, frame))

		var config: SideConfig = surf.active_side_config(entry.side, game_state)
		if config != null and config.effect is TransformativeEffect:
			var mobius: MobiusTransform = config.effect.get_mobius()
			var inv_mobius: MobiusTransform = config.effect.get_inverse_mobius()
			frame = frame.compose(mobius)
			ray = Ray.new(inv_mobius.apply(best.point), ray.direction)
		else:
			ray = Ray.new(best.point, ray.direction)

	var vis_last: Vector2 = frame.apply(ray.origin)
	if vis_last.distance_to(cursor) > 0.01:
		path.steps.append(Step.new(vis_last, cursor, frame.id, null, provenance_ray, frame))

	return path

static func _find_surface_by_id(surface_id: int, surfaces: Array) -> Surface:
	for surf in surfaces:
		if surf.id == surface_id:
			return surf
	return null

static func _build_normalized(surfaces: Array, frame: MobiusTransform, out_mapping: Dictionary) -> Array:
	out_mapping.clear()
	if frame.id == MobiusTransform.IDENTITY_ID:
		for surf in surfaces:
			out_mapping[surf.segment] = surf
		return surfaces

	var inv := frame.invert()
	var result: Array = []
	for surf in surfaces:
		var s: Vector2 = inv.apply(surf.segment.start)
		var e: Vector2 = inv.apply(surf.segment.end)
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

static func transform_all(surfaces: Array, mobius: MobiusTransform) -> Array:
	var result: Array = []
	for surf in surfaces:
		var s: Vector2 = mobius.apply(surf.segment.start)
		var e: Vector2 = mobius.apply(surf.segment.end)
		var v: Vector2
		if is_inf(surf.segment.via.x) or is_inf(surf.segment.via.y):
			v = Vector2(INF, INF)
		else:
			v = mobius.apply(surf.segment.via)
		var new_seg := Segment.new(s, e, v)
		var state := GameState.new()
		var left: SideConfig = surf.active_side_config(Side.Value.LEFT, state)
		var right: SideConfig = surf.active_side_config(Side.Value.RIGHT, state)
		var new_surf := Surface.new(new_seg, left, right, surf.is_target, surf.player_solid)
		result.append(new_surf)
	return result

static func _clip_to_bounds_edge(origin: Vector2, dir: Vector2, bounds: Rect2) -> Vector2:
	var min_t := INF
	if dir.x > 0.0:
		var t: float = (bounds.end.x - origin.x) / dir.x
		min_t = minf(min_t, t)
	elif dir.x < 0.0:
		var t: float = (bounds.position.x - origin.x) / dir.x
		min_t = minf(min_t, t)
	if dir.y > 0.0:
		var t: float = (bounds.end.y - origin.y) / dir.y
		min_t = minf(min_t, t)
	elif dir.y < 0.0:
		var t: float = (bounds.position.y - origin.y) / dir.y
		min_t = minf(min_t, t)
	if is_inf(min_t) or min_t < 0.0:
		min_t = 100.0
	return origin + dir * min_t
