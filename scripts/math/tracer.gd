class_name Tracer
extends RefCounted

class Step extends RefCounted:
	var start: Vector2
	var end: Vector2
	var frame_id: int
	var hit: RefCounted

	func _init(p_start: Vector2, p_end: Vector2, p_frame_id: int, p_hit: RefCounted = null) -> void:
		start = p_start
		end = p_end
		frame_id = p_frame_id
		hit = p_hit

class TracedPath extends RefCounted:
	var steps: Array = []
	var targets_hit: Dictionary = {}

const MAX_HITS := 256
const DEFAULT_BOUNDS := Rect2(0, 0, 1920, 1080)

static func trace(origin: Vector2, direction: Direction, surfaces: Array, game_state: GameState, bounds: Rect2 = DEFAULT_BOUNDS) -> TracedPath:
	var path := TracedPath.new()

	if direction.is_zero_length():
		return path

	var state_copy := game_state.copy()
	var segments: Array = []
	var segment_to_surface: Dictionary = {}
	for surf in surfaces:
		segments.append(surf.segment)
		segment_to_surface[surf.segment] = surf

	var ray := Ray.new(origin, direction)
	var frame_id := MobiusTransform.IDENTITY_ID
	var excluded: Array = []

	for i in MAX_HITS:
		var hit = Intersection.find_earliest_hit(ray, segments, excluded)

		if hit == null:
			var dir_vec: Vector2 = ray.direction.to_vector().normalized()
			var escape_end: Vector2 = _clip_to_bounds_edge(ray.origin, dir_vec, bounds)
			var return_start: Vector2 = _clip_to_bounds_edge(ray.origin, -dir_vec, bounds)
			path.steps.append(Step.new(ray.origin, escape_end, frame_id, null))
			path.steps.append(Step.new(return_start, ray.origin, frame_id, null))
			break

		if hit.t < 0.0:
			var dir_vec: Vector2 = ray.direction.to_vector().normalized()
			var escape_end: Vector2 = _clip_to_bounds_edge(ray.origin, dir_vec, bounds)
			var return_start: Vector2 = _clip_to_bounds_edge(hit.point, -dir_vec, bounds)
			path.steps.append(Step.new(ray.origin, escape_end, frame_id, null))
			path.steps.append(Step.new(return_start, hit.point, frame_id, hit))
		else:
			path.steps.append(Step.new(ray.origin, hit.point, frame_id, hit))

		var surf = segment_to_surface.get(hit.segment)
		if surf and surf.is_target:
			path.targets_hit[surf.id] = true

		var config: SideConfig = null
		if surf:
			config = surf.active_side_config(hit.side, state_copy)

		if config == null or config.effect == null:
			excluded.append(hit.segment)
			ray = Ray.new(hit.point, ray.direction)
			continue

		if config.effect is TerminalEffect:
			break

		if config.effect is TransformativeEffect:
			var mobius: MobiusTransform = config.effect.get_mobius()
			var dir_vec: Vector2 = ray.direction.to_vector().normalized()
			var forward_point: Vector2 = hit.point + dir_vec
			var reflected_forward: Vector2 = mobius.apply(forward_point)
			var reflected_origin: Vector2 = mobius.apply(hit.point)
			var new_dir := Direction.new(reflected_origin, reflected_forward)
			excluded = []
			ray = Ray.new(reflected_origin, new_dir)
			frame_id = mobius.id
			continue

		assert(false, "ProjectiveEffect not implemented until Stage 47")
		break

	return path

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
