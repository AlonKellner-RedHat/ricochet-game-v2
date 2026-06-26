extends GutTest

const H := preload("res://tests/test_helpers.gd")
const TOL := Vector2(1.0, 1.0)

func before_each() -> void:
	H.reset_counters()

# --- Helpers ---

# Vertical line at x=300, from (300,100) to (300,500)
func _standard_line() -> Segment:
	return Segment.from_coords(Vector2(300, 100), Vector2(300, 500), Vector2(300, 300))

# --- Test 1: exit direction from RIGHT side ---

func test_stage75b_exit_direction_from_right() -> void:
	var seg := _standard_line()
	var effect := LineDirectionalProjection.new(Vector2(1, 0))
	var hit := Vector2(300, 300)
	var right_side := seg.determine_side(Vector2(200, 300))
	var result := effect.apply_forward(hit, seg, right_side)
	assert_not_null(result, "apply_forward should return a Ray")
	var dir := result.direction.to_normalized()
	assert_almost_eq(absf(dir.x), 1.0, 0.01, "Exit should be along normal (horizontal)")
	assert_almost_eq(dir.y, 0.0, 0.01, "Exit y should be 0")

# --- Test 2: exit direction from LEFT side ---

func test_stage75b_exit_direction_from_left() -> void:
	var seg := _standard_line()
	var effect := LineDirectionalProjection.new(Vector2(1, 0))
	var hit := Vector2(300, 300)
	var left_side := seg.determine_side(Vector2(400, 300))
	var result := effect.apply_forward(hit, seg, left_side)
	assert_not_null(result, "apply_forward should return a Ray")
	var dir := result.direction.to_normalized()
	assert_almost_eq(absf(dir.x), 1.0, 0.01, "Exit should be along normal (horizontal)")
	assert_almost_eq(dir.y, 0.0, 0.01, "Exit y should be 0")
	# Opposite side should produce opposite direction
	var right_side := seg.determine_side(Vector2(200, 300))
	var other := effect.apply_forward(hit, seg, right_side).direction.to_normalized()
	assert_almost_eq(dir.x + other.x, 0.0, 0.01,
		"Opposite sides should produce opposite directions")

# --- Test 3: hit position independent ---

func test_stage75b_hit_position_independent() -> void:
	var seg := _standard_line()
	var effect := LineDirectionalProjection.new(Vector2(1, 0))
	var side := seg.determine_side(Vector2(200, 300))
	var hits := [Vector2(300, 150), Vector2(300, 300), Vector2(300, 450)]
	var first_dir := effect.apply_forward(hits[0], seg, side).direction.to_normalized()
	for i in range(1, hits.size()):
		var dir := effect.apply_forward(hits[i], seg, side).direction.to_normalized()
		assert_almost_eq(dir, first_dir, Vector2(0.01, 0.01),
			"Hit at position %d should produce same direction as position 0" % i)

# --- Test 4: diagonal normal ---

func test_stage75b_diagonal_normal() -> void:
	var seg := _standard_line()
	var effect := LineDirectionalProjection.new(Vector2(1, 1))
	var side := seg.determine_side(Vector2(200, 300))
	var result := effect.apply_forward(Vector2(300, 300), seg, side)
	var dir := result.direction.to_normalized()
	var expected := Vector2(1, 1).normalized()
	assert_almost_eq(absf(dir.x), absf(expected.x), 0.01,
		"Diagonal normal: |x| should be ~0.707")
	assert_almost_eq(absf(dir.y), absf(expected.y), 0.01,
		"Diagonal normal: |y| should be ~0.707")

# --- Test 5: back_propagate on segment ---

func test_stage75b_back_propagate_on_segment() -> void:
	var seg := _standard_line()
	var effect := LineDirectionalProjection.new(Vector2(1, 0))
	var result = effect.back_propagate(Vector2(500, 250), seg)
	assert_not_null(result, "Should return point on segment")
	assert_almost_eq(result, Vector2(300, 250), TOL,
		"Projecting (500,250) along normal (1,0) should hit line at (300,250)")

# --- Test 6: back_propagate outside segment ---

func test_stage75b_back_propagate_outside_segment() -> void:
	var seg := _standard_line()
	var effect := LineDirectionalProjection.new(Vector2(1, 0))
	var result = effect.back_propagate(Vector2(500, 600), seg)
	assert_null(result, "Point at y=600 projects to (300,600) which is outside segment")

# --- Test 7: back_propagate parallel ---

func test_stage75b_back_propagate_parallel() -> void:
	var seg := _standard_line()
	var effect := LineDirectionalProjection.new(Vector2(0, 1))
	var result = effect.back_propagate(Vector2(500, 300), seg)
	assert_null(result, "Normal parallel to line should return null")

# --- Test 8: S16 - no NaN/Inf ---

func test_stage75b_S16_no_nan_inf() -> void:
	var seg := _standard_line()
	var effect := LineDirectionalProjection.new(Vector2(1, 0))
	var side := seg.determine_side(Vector2(200, 300))
	var ray := effect.apply_forward(Vector2(300, 300), seg, side)
	assert_false(is_nan(ray.origin.coords.x), "origin.x not NaN")
	assert_false(is_nan(ray.origin.coords.y), "origin.y not NaN")
	assert_false(is_inf(ray.origin.coords.x), "origin.x not Inf")
	assert_false(is_inf(ray.origin.coords.y), "origin.y not Inf")
	var dir := ray.direction.to_normalized()
	assert_false(is_nan(dir.x), "direction.x not NaN")
	assert_false(is_nan(dir.y), "direction.y not NaN")
	var proj = effect.back_propagate(Vector2(500, 300), seg)
	if proj != null:
		assert_false(is_nan(proj.x), "back_propagate x not NaN")
		assert_false(is_nan(proj.y), "back_propagate y not NaN")

# --- Test 9: kind is projective ---

func test_stage75b_kind_is_projective() -> void:
	var effect := LineDirectionalProjection.new(Vector2(1, 0))
	assert_eq(effect.kind(), Effect.Kind.PROJECTIVE, "Kind should be PROJECTIVE")

# --- Test 10: project_back exits opposite ---

func test_stage75b_project_back_exits_opposite() -> void:
	var seg := _standard_line()
	var through := LineDirectionalProjection.new(Vector2(1, 0), false)
	var back := LineDirectionalProjection.new(Vector2(1, 0), true)
	var hit := Vector2(300, 300)
	var side := seg.determine_side(Vector2(200, 300))
	var through_dir := through.apply_forward(hit, seg, side).direction.to_normalized()
	var back_dir := back.apply_forward(hit, seg, side).direction.to_normalized()
	assert_almost_eq(through_dir.x + back_dir.x, 0.0, 0.01,
		"Through and back should have opposite directions")

# --- Test 11: color and name ---

func test_stage75b_color_and_name() -> void:
	var through := LineDirectionalProjection.new(Vector2(1, 0), false)
	var back := LineDirectionalProjection.new(Vector2(1, 0), true)
	assert_eq(through.get_display_color(), Color(1.0, 0.8, 0.2),
		"Through should be yellow-orange")
	assert_eq(back.get_display_color(), Color(1.0, 0.4, 0.1),
		"Back should be red-orange")
	assert_eq(through.get_display_name(), "line_directional",
		"Through display name")
	assert_eq(back.get_display_name(), "line_directional_back",
		"Back display name")

# --- Test 12: default is through ---

func test_stage75b_default_is_through() -> void:
	var normal := Vector2(1, 0)
	var effect := LineDirectionalProjection.new(normal)
	assert_eq(effect.get_display_color(), Color(1.0, 0.8, 0.2),
		"Default should be through (yellow-orange)")
	assert_eq(effect.get_display_name(), "line_directional",
		"Default display name")
	var seg := _standard_line()
	var side := seg.determine_side(Vector2(200, 300))
	var explicit := LineDirectionalProjection.new(normal, false)
	var dir_default := effect.apply_forward(Vector2(300, 300), seg, side).direction.to_normalized()
	var dir_explicit := explicit.apply_forward(Vector2(300, 300), seg, side).direction.to_normalized()
	assert_almost_eq(dir_default, dir_explicit, Vector2(0.01, 0.01),
		"Default and explicit false should produce same direction")
