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

static func trace(origin: Vector2, direction: Direction, surfaces: Array, game_state: GameState) -> TracedPath:
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
			var escape_end: Vector2 = ray.origin + dir_vec * 10000.0
			var return_start: Vector2 = ray.origin - dir_vec * 10000.0
			path.steps.append(Step.new(ray.origin, escape_end, frame_id, null))
			path.steps.append(Step.new(return_start, ray.origin, frame_id, null))
			break

		if hit.t < 0.0:
			var dir_vec: Vector2 = ray.direction.to_vector().normalized()
			var escape_end: Vector2 = ray.origin + dir_vec * 10000.0
			var return_start: Vector2 = hit.point - dir_vec * 10000.0
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

		assert(false, "TransformativeEffect/ProjectiveEffect not implemented until Stage 20b/47")
		break

	return path
