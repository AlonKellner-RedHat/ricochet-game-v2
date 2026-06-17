class_name Planner
extends RefCounted

class PlannedPath extends RefCounted:
	var steps: Array = []
	var origin: Vector2
	var target: Vector2

static func _compute_image(target: Vector2, entries: Array, surfaces: Array, game_state: GameState, cache: TransformCache = null) -> Variant:
	var image := target
	for i in range(entries.size() - 1, -1, -1):
		var entry: PlanManager.PlanEntry = entries[i]
		var surf := _find_surface(entry.surface_id, surfaces)
		if surf == null:
			return null
		var config: SideConfig = surf.active_side_config(entry.side, game_state)
		if config == null or config.effect == null or not config.effect.is_transformative():
			return null
		var inv_mobius: MobiusTransform = config.effect.get_inverse_mobius()
		image = cache.apply_point(inv_mobius, image) if cache else inv_mobius.apply(image)
	return image

static func compute_aim_direction(origin: Vector2, cursor: Vector2, plan_entries: Array, surfaces: Array, game_state: GameState, cache: TransformCache = null) -> Direction:
	if plan_entries.size() == 0:
		return Direction.from_coords(origin, cursor)

	var image = _compute_image(cursor, plan_entries, surfaces, game_state, cache)
	if image == null:
		return Direction.from_coords(origin, cursor)
	if is_nan(image.x) or is_nan(image.y) or is_inf(image.x) or is_inf(image.y):
		return Direction.from_coords(origin, cursor)

	var dir := Direction.from_coords(origin, image)
	if dir.is_zero_length():
		return Direction.from_coords(origin, cursor)
	return dir

static func plan_transformative_subchain(
	sub_origin: Vector2,
	sub_target: Vector2,
	entries: Array,
	surfaces: Array,
	game_state: GameState,
	cache: TransformCache = null
) -> PlannedPath:
	var path := PlannedPath.new()
	path.origin = sub_origin
	path.target = sub_target

	if entries.size() == 0:
		return path

	var image = _compute_image(sub_target, entries, surfaces, game_state, cache)
	if image == null:
		return path

	var aim_dir := Direction.from_coords(sub_origin, image)
	if aim_dir.is_zero_length():
		return path

	var aim_ray := Ray.from_coords(sub_origin, aim_dir)
	var current_point := sub_origin

	for i in entries.size():
		var entry: PlanManager.PlanEntry = entries[i]
		var surf := _find_surface(entry.surface_id, surfaces)
		if surf == null:
			break
		var carrier := surf.segment.get_carrier()
		var hits := Intersection.intersect_line_with_carrier(aim_ray, carrier)

		if not carrier.is_line():
			var on_seg_hits: Array = []
			for hit in hits:
				if Intersection.is_on_segment(hit.point, surf.segment):
					on_seg_hits.append(hit)
			hits = on_seg_hits

		if hits.size() == 0:
			break

		var best_hit: Dictionary = _select_best_hit(hits)
		var bounce_point: Vector2 = best_hit.point

		var step := Tracer.Step.new(current_point, bounce_point, MobiusTransform.IDENTITY_ID, null)
		path.steps.append(step)

		var config: SideConfig = surf.active_side_config(entry.side, game_state)
		var mobius: MobiusTransform = config.effect.get_mobius()
		image = cache.apply_point(mobius, image) if cache else mobius.apply(image)

		current_point = bounce_point
		aim_dir = Direction.from_coords(current_point, image)
		if aim_dir.is_zero_length():
			break
		aim_ray = Ray.from_coords(current_point, aim_dir)

	if current_point != sub_target:
		var final_step := Tracer.Step.new(current_point, sub_target, MobiusTransform.IDENTITY_ID, null)
		path.steps.append(final_step)

	return path

static func _find_surface(surface_id: int, surfaces: Array) -> Surface:
	for surf in surfaces:
		if surf.id == surface_id:
			return surf
	return null

static func _select_best_hit(hits: Array) -> Dictionary:
	var best: Dictionary = hits[0]
	for i in range(1, hits.size()):
		var hit: Dictionary = hits[i]
		if hit.t > 0.0 and (best.t <= 0.0 or hit.t < best.t):
			best = hit
		elif hit.t <= 0.0 and best.t <= 0.0 and hit.t < best.t:
			best = hit
	return best
