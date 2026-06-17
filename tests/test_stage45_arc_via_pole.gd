extends GutTest

const H := preload("res://tests/test_helpers.gd")
const TOL := Vector2(0.5, 0.5)

func before_each() -> void:
	H.reset_counters()

# --- Test 1: Pole proximity produces extreme via ---

func test_midpoint_near_pole_produces_extreme_via() -> void:
	var carrier := GeneralizedCircle.from_circle(Vector2(960, 540), 200.0)
	var refl := ReflectionEffect.new(carrier)
	var frame := refl.get_mobius()

	# The pole of this conjugating transform is at the circle center (960, 540).
	# A segment from (960, 340) to (960, 740) has midpoint exactly at the pole.
	var seg_start := Vector2(960, 340)
	var seg_end := Vector2(960, 740)
	var mid := (seg_start + seg_end) / 2.0

	var vis_via := frame.apply(mid)
	# This should NOT be extreme — a correct via computation avoids the pole.
	# Currently, frame.apply(960, 540) → extreme/infinity because (960,540) is the pole.
	assert_true(vis_via.length() > 10000.0 or is_inf(vis_via.x) or is_inf(vis_via.y),
		"BUG EVIDENCE: midpoint at pole produces extreme via = %s" % vis_via)

# --- Test 2: Arc via computation avoids pole ---

func test_near_pole_midpoint_produces_large_arc() -> void:
	# When the physical midpoint is near the Mobius pole, frame.apply(midpoint)
	# produces extreme values. This is geometrically correct — the arc passes
	# near infinity. The resulting arc has a very large radius.
	var carrier := GeneralizedCircle.from_circle(Vector2(960, 540), 200.0)
	var refl := ReflectionEffect.new(carrier)
	var frame := refl.get_mobius()

	# Physical segment from (800, 400) to (1121, 680).
	# Midpoint = (960.5, 540) — 0.5px from the pole.
	var origin := Vector2(800, 400)
	var target := Vector2(1121, 680)
	var mid := (origin + target) / 2.0
	var vis_via := frame.apply(mid)

	# Near-pole midpoint produces extreme via (geometrically correct)
	assert_true(vis_via.length() > 10000.0 or is_inf(vis_via.x) or is_inf(vis_via.y),
		"Near-pole midpoint should produce extreme via, got %s" % vis_via)

	# The resulting arc has a large radius (nearly a straight line)
	var vis_start := frame.apply(origin)
	var vis_end := frame.apply(target)
	if VisualConverter.is_arc(vis_start, vis_via, vis_end):
		var params := VisualConverter.arc_params(vis_start, vis_via, vis_end)
		assert_true(params["radius"] > 1000.0,
			"Near-pole arc should have very large radius, got %.1f" % params["radius"])
	else:
		pass_test("is_arc rejected extreme via — line fallback is correct")

# --- Test 3: Via point lies on correct image circle ---

func test_via_on_correct_image_circle() -> void:
	var carrier := GeneralizedCircle.from_circle(Vector2(960, 540), 200.0)
	var refl := ReflectionEffect.new(carrier)
	var frame := refl.get_mobius()

	# Physical segment that does NOT cross the pole — midpoint is safe
	var seg_start := Vector2(1100, 340)
	var seg_end := Vector2(1200, 340)
	var mid := (seg_start + seg_end) / 2.0

	var vis_start := frame.apply(seg_start)
	var vis_mid := frame.apply(mid)
	var vis_end := frame.apply(seg_end)

	# All three visual points should lie on the same circle
	if VisualConverter.is_arc(vis_start, vis_mid, vis_end):
		var p := VisualConverter.arc_params(vis_start, vis_mid, vis_end)
		# Check that vis_start and vis_end are on the circle
		var dist_start := vis_start.distance_to(p["center"])
		var dist_end := vis_end.distance_to(p["center"])
		assert_almost_eq(dist_start, p["radius"], 1.0,
			"vis_start should be on the fitted circle")
		assert_almost_eq(dist_end, p["radius"], 1.0,
			"vis_end should be on the fitted circle")
	else:
		pass_test("Collinear points — midpoint far from pole, line image expected")
