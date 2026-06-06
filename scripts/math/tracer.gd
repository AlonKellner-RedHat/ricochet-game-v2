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

const DEFAULT_BOUNDS := Rect2(0, 0, 1920, 1080)

static func trace(_origin: Vector2, _direction: Direction, _surfaces: Array, _game_state: GameState, _bounds: Rect2 = DEFAULT_BOUNDS, _shared_ray: Ray = null, _target_dist: float = -1.0) -> TracedPath:
	return TracedPath.new()

static func trace_ray(initial_ray: Ray, surfaces: Array, game_state: GameState, bounds: Rect2 = DEFAULT_BOUNDS) -> TracedPath:
	return trace(initial_ray.origin, initial_ray.direction, surfaces, game_state, bounds, initial_ray)
