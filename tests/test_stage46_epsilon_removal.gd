extends GutTest

# TDD tests for epsilon removal from TrackedTransform.is_inverse_of().
# Provenance-based cancellation: reference equality, not geometry tolerance.

func _circle_segment() -> Segment:
	var seg := Segment.from_coords(
		Vector2(1160, 540), Vector2(760, 540), Vector2(960, 340))
	seg.get_carrier()
	return seg

func _circle_effect(seg: Segment) -> ReflectionEffect:
	return ReflectionEffect.new(seg.get_carrier())

# --- Provenance chain tests (Stage 1: FAIL before fix, PASS after) ---

func test_incremental_norm_preserves_segment_identity() -> void:
	var seg := _circle_segment()
	var effect := _circle_effect(seg)
	var tracked := effect.get_tracked_transform()
	var result := seg.transformed(tracked.inverse)
	assert_same(result, seg,
		"Self-inverse transform on own carrier must return same segment object")

func test_incremental_norm_preserves_carrier_identity() -> void:
	var seg := _circle_segment()
	var effect := _circle_effect(seg)
	var tracked := effect.get_tracked_transform()
	var result := seg.transformed(tracked.inverse)
	assert_same(result.get_carrier(), seg.get_carrier(),
		"Carrier must be preserved through self-inverse transform")

func test_incremental_norm_preserves_effect_identity() -> void:
	var seg := _circle_segment()
	var effect := _circle_effect(seg)
	var tracked := effect.get_tracked_transform()
	var norm_seg := seg.transformed(tracked.inverse)
	var norm_effect := effect.normalized(norm_seg.get_carrier())
	assert_same(norm_effect, effect,
		"Effect normalized with preserved carrier must return self")

func test_incremental_norm_preserves_tracked_transform() -> void:
	var seg := _circle_segment()
	var effect := _circle_effect(seg)
	var tracked := effect.get_tracked_transform()
	var norm_seg := seg.transformed(tracked.inverse)
	var norm_effect: TransformativeEffect = effect.normalized(norm_seg.get_carrier())
	assert_same(norm_effect.get_tracked_transform(), tracked,
		"TrackedTransform must be preserved through normalization chain")

# --- Anti-regression tests (provenance semantics) ---

func test_different_carrier_objects_do_not_cancel() -> void:
	var seg := _circle_segment()
	var carrier1 := seg.get_carrier()
	var carrier2 := GeneralizedCircle.from_circle(
		carrier1.center(), carrier1.radius())
	assert_ne(carrier1, carrier2, "Precondition: different objects")
	var m := _circle_effect(seg).get_mobius()
	var t1 := TrackedTransform.from_self_inverse(m, carrier1)
	var t2 := TrackedTransform.from_self_inverse(m, carrier2)
	assert_false(t1.is_inverse_of(t2),
		"Different carrier objects must not cancel (provenance, not geometry)")

func test_different_surfaces_same_geometry_do_not_cancel() -> void:
	var seg1 := Segment.from_coords(
		Vector2(1160, 540), Vector2(760, 540), Vector2(960, 340))
	seg1.get_carrier()
	var seg2 := Segment.from_coords(
		Vector2(1160, 540), Vector2(760, 540), Vector2(960, 340))
	seg2.get_carrier()
	var e1 := ReflectionEffect.new(seg1.get_carrier())
	var e2 := ReflectionEffect.new(seg2.get_carrier())
	var t1 := e1.get_tracked_transform()
	var t2 := e2.get_tracked_transform()
	assert_false(t1.is_inverse_of(t2),
		"Effects from different surfaces must not cancel even with same geometry")
