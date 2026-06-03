class_name SweepRunner
extends RefCounted

var _bounds_min := Vector2(0, 0)
var _bounds_max := Vector2(1920, 1080)
var _grid_size := 5
var _fuzz_count := 10
var _fuzz_seed := 42

func configure(grid_size: int = 5, fuzz_count: int = 10, fuzz_seed: int = 42) -> SweepRunner:
	_grid_size = grid_size
	_fuzz_count = fuzz_count
	_fuzz_seed = fuzz_seed
	return self

func set_bounds(bounds_min: Vector2, bounds_max: Vector2) -> SweepRunner:
	_bounds_min = bounds_min
	_bounds_max = bounds_max
	return self

func build_positions(custom_positions: Array[Vector2] = []) -> Array[Vector2]:
	var positions: Array[Vector2] = []

	for y in _grid_size:
		for x in _grid_size:
			var px: float
			var py: float
			if _grid_size > 1:
				px = _bounds_min.x + (_bounds_max.x - _bounds_min.x) * x / (_grid_size - 1)
				py = _bounds_min.y + (_bounds_max.y - _bounds_min.y) * y / (_grid_size - 1)
			else:
				px = (_bounds_min.x + _bounds_max.x) / 2.0
				py = (_bounds_min.y + _bounds_max.y) / 2.0
			positions.append(Vector2(px, py))

	var rng := RandomNumberGenerator.new()
	rng.seed = _fuzz_seed
	for i in _fuzz_count:
		var fx := rng.randf_range(_bounds_min.x, _bounds_max.x)
		var fy := rng.randf_range(_bounds_min.y, _bounds_max.y)
		positions.append(Vector2(fx, fy))

	positions.append_array(custom_positions)

	return positions

func sweep(scene: Node, custom_positions: Array[Vector2] = []) -> Dictionary:
	var checker := InvariantChecker.new()
	checker.setup(scene)

	var positions := build_positions(custom_positions)
	var total := positions.size() * positions.size()
	var failures: Array[Dictionary] = []

	for player_pos in positions:
		for cursor_pos in positions:
			var violations := checker.check_all(player_pos, cursor_pos)
			if violations.size() > 0:
				failures.append({
					"player_pos": player_pos,
					"cursor_pos": cursor_pos,
					"violations": violations,
				})

	return {
		"total_combos": total,
		"position_count": positions.size(),
		"pass_count": total - failures.size(),
		"fail_count": failures.size(),
		"failures": failures,
	}
