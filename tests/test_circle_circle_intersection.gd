extends GutTest

func test_two_circles_two_intersections() -> void:
	var c1 := GeneralizedCircle.from_circle(Vector2(0, 0), 5.0)
	var c2 := GeneralizedCircle.from_circle(Vector2(6, 0), 5.0)
	var hits := Intersection.intersect_circles(c1, c2)
	assert_eq(hits.size(), 2, "Two intersecting circles should have 2 intersection points")
	for h in hits:
		assert_almost_eq(absf(c1.evaluate(h)), 0.0, 1e-6, "Point should lie on circle 1")
		assert_almost_eq(absf(c2.evaluate(h)), 0.0, 1e-6, "Point should lie on circle 2")

func test_two_circles_tangent() -> void:
	var c1 := GeneralizedCircle.from_circle(Vector2(0, 0), 5.0)
	var c2 := GeneralizedCircle.from_circle(Vector2(10, 0), 5.0)
	var hits := Intersection.intersect_circles(c1, c2)
	assert_eq(hits.size(), 1, "Tangent circles should have 1 intersection point")
	assert_almost_eq(hits[0].x, 5.0, 1e-6)
	assert_almost_eq(hits[0].y, 0.0, 1e-6)

func test_two_circles_separated() -> void:
	var c1 := GeneralizedCircle.from_circle(Vector2(0, 0), 3.0)
	var c2 := GeneralizedCircle.from_circle(Vector2(10, 0), 3.0)
	var hits := Intersection.intersect_circles(c1, c2)
	assert_eq(hits.size(), 0, "Separated circles should have no intersections")

func test_two_circles_contained() -> void:
	var c1 := GeneralizedCircle.from_circle(Vector2(0, 0), 10.0)
	var c2 := GeneralizedCircle.from_circle(Vector2(1, 0), 3.0)
	var hits := Intersection.intersect_circles(c1, c2)
	assert_eq(hits.size(), 0, "Contained circle should have no intersections")

func test_two_circles_concentric() -> void:
	var c1 := GeneralizedCircle.from_circle(Vector2(5, 5), 10.0)
	var c2 := GeneralizedCircle.from_circle(Vector2(5, 5), 7.0)
	var hits := Intersection.intersect_circles(c1, c2)
	assert_eq(hits.size(), 0, "Concentric circles should have no intersections")

func test_line_circle_two_intersections() -> void:
	var circ := GeneralizedCircle.from_circle(Vector2(0, 0), 5.0)
	var line := GeneralizedCircle.from_line(0.0, 1.0, -3.0)  # y = 3
	var hits := Intersection.intersect_circles(line, circ)
	assert_eq(hits.size(), 2, "Line through circle should have 2 intersections")
	for h in hits:
		assert_almost_eq(h.y, 3.0, 1e-6, "Intersection should be on y=3 line")
		assert_almost_eq(absf(circ.evaluate(h)), 0.0, 1e-6, "Point should lie on circle")

func test_line_circle_tangent() -> void:
	var circ := GeneralizedCircle.from_circle(Vector2(0, 0), 5.0)
	var line := GeneralizedCircle.from_line(0.0, 1.0, -5.0)  # y = 5
	var hits := Intersection.intersect_circles(line, circ)
	assert_eq(hits.size(), 1, "Tangent line should have 1 intersection")
	assert_almost_eq(hits[0].y, 5.0, 1e-6)

func test_line_circle_no_intersection() -> void:
	var circ := GeneralizedCircle.from_circle(Vector2(0, 0), 5.0)
	var line := GeneralizedCircle.from_line(0.0, 1.0, -10.0)  # y = 10
	var hits := Intersection.intersect_circles(line, circ)
	assert_eq(hits.size(), 0, "Distant line should have no intersections")

func test_circle_line_order_independent() -> void:
	var circ := GeneralizedCircle.from_circle(Vector2(0, 0), 5.0)
	var line := GeneralizedCircle.from_line(0.0, 1.0, -3.0)  # y = 3
	var hits_lc := Intersection.intersect_circles(line, circ)
	var hits_cl := Intersection.intersect_circles(circ, line)
	assert_eq(hits_lc.size(), hits_cl.size(), "Order should not affect count")
	if hits_lc.size() == hits_cl.size() and hits_lc.size() > 0:
		for h_lc in hits_lc:
			var found := false
			for h_cl in hits_cl:
				if h_lc.distance_to(h_cl) < 1e-6:
					found = true
					break
			assert_true(found, "Same points regardless of argument order")

func test_two_lines_intersection() -> void:
	var l1 := GeneralizedCircle.from_line(1.0, 0.0, -5.0)   # x = 5
	var l2 := GeneralizedCircle.from_line(0.0, 1.0, -3.0)   # y = 3
	var hits := Intersection.intersect_circles(l1, l2)
	assert_eq(hits.size(), 1, "Two non-parallel lines should intersect")
	assert_almost_eq(hits[0].x, 5.0, 1e-6)
	assert_almost_eq(hits[0].y, 3.0, 1e-6)

func test_two_lines_parallel() -> void:
	var l1 := GeneralizedCircle.from_line(0.0, 1.0, -3.0)   # y = 3
	var l2 := GeneralizedCircle.from_line(0.0, 1.0, -7.0)   # y = 7
	var hits := Intersection.intersect_circles(l1, l2)
	assert_eq(hits.size(), 0, "Parallel lines should not intersect")

func test_diagonal_circles() -> void:
	var c1 := GeneralizedCircle.from_circle(Vector2(100, 200), 50.0)
	var c2 := GeneralizedCircle.from_circle(Vector2(130, 240), 50.0)
	var hits := Intersection.intersect_circles(c1, c2)
	assert_eq(hits.size(), 2, "Overlapping circles at diagonal offset")
	for h in hits:
		var dist1 := absf(h.distance_to(c1.center()) - c1.radius())
		var dist2 := absf(h.distance_to(c2.center()) - c2.radius())
		assert_almost_eq(dist1, 0.0, 1e-4, "Point on circle 1 (geometric distance)")
		assert_almost_eq(dist2, 0.0, 1e-4, "Point on circle 2 (geometric distance)")

# --- Inversive pullback tests ---

func _build_inversion_mobius(center: Vector2, r: float) -> MobiusTransform:
	var r2 := r * r
	var ctr_mod2 := center.x * center.x + center.y * center.y
	return MobiusTransform.new(
		center, Vector2(r2 - ctr_mod2, 0.0),
		Vector2(1.0, 0.0), Vector2(-center.x, center.y), true)

func _build_translation_mobius(offset: Vector2) -> MobiusTransform:
	return MobiusTransform.new(
		Vector2(1.0, 0.0), offset,
		Vector2.ZERO, Vector2(1.0, 0.0), false)

func test_ray_to_line_basic() -> void:
	var ray := Ray.from_coords(Vector2(1, 2), Direction.from_coords(Vector2.ZERO,Vector2(3, 4)))
	var line := Intersection.ray_to_line(ray)
	assert_true(line.is_line(), "Ray should produce a line (a=0)")
	assert_almost_eq(absf(line.evaluate(Vector2(1, 2))), 0.0, 1e-10, "Origin should be on line")
	assert_almost_eq(absf(line.evaluate(Vector2(4, 6))), 0.0, 1e-10, "Origin+dir should be on line")

func test_ray_to_line_horizontal() -> void:
	var ray := Ray.from_coords(Vector2(0, 5), Direction.from_coords(Vector2.ZERO,Vector2(1, 0)))
	var line := Intersection.ray_to_line(ray)
	assert_almost_eq(absf(line.evaluate(Vector2(100, 5))), 0.0, 1e-10)
	assert_true(absf(line.evaluate(Vector2(100, 6))) > 0.5, "Off-line point should not evaluate to 0")

func test_inversive_pullback_identity_frame() -> void:
	var carrier := GeneralizedCircle.from_circle(Vector2(100, 0), 50.0)
	var ray := Ray.from_coords(Vector2(0, 0), Direction.from_coords(Vector2.ZERO,Vector2(1, 0)))
	var frame := MobiusTransform.identity()

	var pullback_hits := Intersection.inversive_pullback_intersect(ray, carrier, frame)
	var direct_hits := Intersection._intersect_ray_carrier(ray, carrier)

	assert_eq(pullback_hits.size(), direct_hits.size(), "Same number of hits")
	pullback_hits.sort_custom(func(a, b): return a["t"] < b["t"])
	direct_hits.sort_custom(func(a, b): return a["t"] < b["t"])
	for i in pullback_hits.size():
		assert_almost_eq(pullback_hits[i]["t"], direct_hits[i]["t"], 1e-4, "t values match")
		assert_almost_eq(pullback_hits[i]["point"].distance_to(direct_hits[i]["point"]), 0.0, 1e-4, "Points match")

func test_inversive_pullback_with_inversion() -> void:
	var inv_center := Vector2(350, 250)
	var inv_r := 50.0
	var visual_carrier := GeneralizedCircle.from_circle(Vector2(1500, 750), 50.0)

	var inv_m := _build_inversion_mobius(inv_center, inv_r)
	var portal_m := _build_translation_mobius(Vector2(-1000, 0))
	var frame := portal_m.compose(inv_m)
	var frame_inv := frame.invert()

	var test_angle := 0.5
	var vis_point := Vector2(1500 + 50.0 * cos(test_angle), 750 + 50.0 * sin(test_angle))
	var norm_point := frame_inv.apply(vis_point)
	var ray_dir := (norm_point - Vector2(0, 0)).normalized()
	var ray := Ray.from_coords(Vector2(0, 0), Direction.from_coords(Vector2.ZERO,ray_dir))

	var hits := Intersection.inversive_pullback_intersect(ray, visual_carrier, frame)
	assert_true(hits.size() >= 1, "Should find at least one hit")

	var best_dist := INF
	for h in hits:
		var vis_hit := frame.apply(h["point"])
		var dist := absf(vis_hit.distance_to(visual_carrier.center()) - visual_carrier.radius())
		if dist < best_dist:
			best_dist = dist
	assert_almost_eq(best_dist, 0.0, 1.0, "Visual hit should be within 1px of carrier")

func test_inversive_pullback_with_two_transforms() -> void:
	var inv := _build_inversion_mobius(Vector2(350, 250), 50.0)
	var portal := _build_translation_mobius(Vector2(-1000, 0))
	var frame := portal.compose(inv)
	var frame_inv := frame.invert()

	var visual_carrier := GeneralizedCircle.from_circle(Vector2(1500, 750), 50.0)

	var vis_point := Vector2(1550, 750)
	var norm_point := frame_inv.apply(vis_point)
	var ray_origin := Vector2(0, 0)
	var ray_dir := (norm_point - ray_origin).normalized()
	var ray := Ray.from_coords(ray_origin, Direction.from_coords(Vector2.ZERO, ray_dir))

	var hits := Intersection.inversive_pullback_intersect(ray, visual_carrier, frame)
	assert_true(hits.size() >= 1, "Should find at least one hit")

	var best_dist := INF
	for h in hits:
		var vis_hit := frame.apply(h["point"])
		var dist := absf(vis_hit.distance_to(visual_carrier.center()) - visual_carrier.radius())
		if dist < best_dist:
			best_dist = dist
	assert_almost_eq(best_dist, 0.0, 5.0, "Visual error with portal+inversion should be small")

func test_inversive_pullback_miss() -> void:
	var carrier := GeneralizedCircle.from_circle(Vector2(100, 100), 10.0)
	var ray := Ray.from_coords(Vector2(0, 0), Direction.from_coords(Vector2.ZERO,Vector2(0, 1)))
	var frame := MobiusTransform.identity()
	var hits := Intersection.inversive_pullback_intersect(ray, carrier, frame)
	assert_eq(hits.size(), 0, "Ray missing carrier should return no hits")

func test_equal_radius_symmetric() -> void:
	var c1 := GeneralizedCircle.from_circle(Vector2(0, 0), 10.0)
	var c2 := GeneralizedCircle.from_circle(Vector2(10, 0), 10.0)
	var hits := Intersection.intersect_circles(c1, c2)
	assert_eq(hits.size(), 2, "Equal radius overlapping circles")
	assert_almost_eq(hits[0].x, 5.0, 1e-6, "Midpoint x for equal radii")
	assert_almost_eq(hits[1].x, 5.0, 1e-6, "Midpoint x for equal radii")
	assert_almost_eq(hits[0].y, -hits[1].y, 1e-6, "Symmetric y for equal radii")
