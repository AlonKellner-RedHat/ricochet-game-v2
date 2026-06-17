extends GutTest

const H := preload("res://tests/test_helpers.gd")
const TOL := Vector2(0.5, 0.5)

func before_each() -> void:
	H.reset_counters()

# --- Line reflection correctness ---

func test_vertical_line_reflection() -> void:
	var carrier := GeneralizedCircle.from_line(1.0, 0.0, -500.0)
	var refl := ReflectionEffect.new(carrier)
	var result := refl.get_mobius().apply(Vector2(300, 400))
	assert_almost_eq(result, Vector2(700, 400), TOL, "Vertical x=500: (300,400) → (700,400)")

func test_horizontal_line_reflection() -> void:
	var carrier := GeneralizedCircle.from_line(0.0, 1.0, -500.0)
	var refl := ReflectionEffect.new(carrier)
	var result := refl.get_mobius().apply(Vector2(300, 400))
	assert_almost_eq(result, Vector2(300, 600), TOL, "Horizontal y=500: (300,400) → (300,600)")

func test_diagonal_line_reflection() -> void:
	var carrier := GeneralizedCircle.from_line(1.0, -1.0, 0.0)
	var refl := ReflectionEffect.new(carrier)
	var result := refl.get_mobius().apply(Vector2(300, 100))
	assert_almost_eq(result, Vector2(100, 300), TOL, "Diagonal y=x: (300,100) → (100,300)")

# --- Self-inverse property ---

func test_horizontal_reflection_self_inverse() -> void:
	var carrier := GeneralizedCircle.from_line(0.0, 1.0, -500.0)
	var refl := ReflectionEffect.new(carrier)
	var m := refl.get_mobius()
	var z := Vector2(300, 400)
	var result := m.apply(m.apply(z))
	assert_almost_eq(result, z, TOL, "T(T(z)) = z for horizontal line")

func test_diagonal_reflection_self_inverse() -> void:
	var carrier := GeneralizedCircle.from_line(1.0, -1.0, 0.0)
	var refl := ReflectionEffect.new(carrier)
	var m := refl.get_mobius()
	var z := Vector2(300, 100)
	var result := m.apply(m.apply(z))
	assert_almost_eq(result, z, TOL, "T(T(z)) = z for diagonal line")

# --- Circle reflection ---

func test_circle_reflection_point_on_circle_fixed() -> void:
	var carrier := GeneralizedCircle.from_circle(Vector2(960, 540), 200.0)
	var refl := ReflectionEffect.new(carrier)
	var on_circle := Vector2(960, 340)
	var result := refl.get_mobius().apply(on_circle)
	assert_almost_eq(result, on_circle, TOL, "Point on circle maps to itself")

func test_circle_reflection_equals_inversion() -> void:
	var carrier := GeneralizedCircle.from_circle(Vector2(960, 540), 200.0)
	var refl := ReflectionEffect.new(carrier)
	var inv := CircleInversionEffect.new(carrier)
	var z := Vector2(800, 400)
	var r_result := refl.get_mobius().apply(z)
	var i_result := inv.get_mobius().apply(z)
	assert_almost_eq(r_result, i_result, TOL,
		"ReflectionEffect on circle matches CircleInversionEffect")

func test_circle_reflection_self_inverse() -> void:
	var carrier := GeneralizedCircle.from_circle(Vector2(960, 540), 200.0)
	var refl := ReflectionEffect.new(carrier)
	var m := refl.get_mobius()
	var z := Vector2(800, 400)
	var result := m.apply(m.apply(z))
	assert_almost_eq(result, z, TOL, "T(T(z)) = z for circle carrier")

# --- Semi-circle trace produces reflected steps ---

func test_semicircle_interior_hit_reflects() -> void:
	var seg := Segment.from_coords(
		Vector2(1160, 540), Vector2(760, 540), Vector2(960, 340))
	var carrier := seg.get_carrier()
	var refl := ReflectionEffect.new(carrier)
	var config := SideConfig.new(refl, true)
	var surf := Surface.new(seg, config, config, false, false)
	var room := RoomBuilder.create_room_surfaces(Rect2(0, 0, 1920, 1080))
	var surfaces: Array = room + [surf]
	var player := Vector2(600, 540)
	var cursor := Vector2(960, 400)
	var aim := Direction.from_coords(player, cursor)
	var path := Tracer.trace(player, aim, surfaces, GameState.new())
	var has_reflected := false
	for step in path.steps:
		if step.frame_id != 0:
			has_reflected = true
			break
	assert_true(has_reflected, "Ray hitting semicircle interior should produce reflected steps")
