extends GutTest

const H := preload("res://tests/test_helpers.gd")

func before_each() -> void:
	H.reset_counters()

# --- Gradient-based carrier distance (numerically stable for all carrier types) ---

static func _carrier_dist(point: Vector2, carrier: GeneralizedCircle) -> float:
	var f := carrier.evaluate(point)
	var gx := 2.0 * carrier.a * point.x + carrier.b
	var gy := 2.0 * carrier.a * point.y + carrier.c
	var grad := sqrt(gx * gx + gy * gy)
	if grad < 1e-10:
		return INF
	return absf(f) / grad

static func _min_carrier_dist(point: Vector2, surfaces: Array) -> float:
	var min_d := INF
	for surf in surfaces:
		var s: Surface = surf
		var d := _carrier_dist(point, s.segment.get_carrier())
		if d < min_d:
			min_d = d
	return min_d

static func _is_at_bounds(p: Vector2) -> bool:
	var bounds := Rect2(0, 0, 1920, 1080)
	return (p.x <= bounds.position.x + 2.0 or p.x >= bounds.end.x - 2.0 or
		p.y <= bounds.position.y + 2.0 or p.y >= bounds.end.y - 2.0)

# ==========================================================================
# TDD: These tests should FAIL before the fix, PASS after
# ==========================================================================

func test_visual_endpoints_on_original_carriers() -> void:
	var scene: Node = load("res://scenes/test_levels/three_mirrors.tscn").instantiate()
	scene.gravity = Vector2.ZERO
	add_child_autofree(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var surfaces: Array = scene.surfaces
	var renderer := scene.get_node("PathRenderer")
	var player := scene.get_node("Player")
	var cursor := scene.get_node("Cursor")

	player.position = Vector2(1229.4, 516.7)
	cursor.position = Vector2(1000.0, 550.0)

	renderer._compute_trace()

	var path: Tracer.TracedPath = renderer.get_planned_path()
	assert_not_null(path, "Should have a planned path")
	assert_gt(path.steps.size(), 4, "Should have enough steps to trigger deep frames")

	var max_dist := 0.0
	var worst_step := -1
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		if step.hit == null or step.hit.segment == null:
			continue
		var end_pos := step.end
		if is_inf(end_pos.x) or is_inf(end_pos.y):
			continue
		if _is_at_bounds(end_pos):
			continue
		var dist := _min_carrier_dist(end_pos, surfaces)
		if dist > max_dist:
			max_dist = dist
			worst_step = i
		assert_lt(dist, 5.0,
			"Step %d visual endpoint %s should be within 5px of an original carrier (got %.2f)" % [i, end_pos, dist])

	gut.p("Max carrier distance: %.4f at step %d" % [max_dist, worst_step])

func test_normalized_coords_from_aggregated_frame() -> void:
	var scene := _build_scene()
	var surfaces: Array = scene.surfaces

	var mirror_bottom: Surface = scene.mirror_bottom
	var mirror_tracked := (mirror_bottom.active_side_config(
		Side.Value.LEFT, GameState.new()).effect as TransformativeEffect).get_tracked_transform()

	var conj_n2s := {}
	var conj_norms := Tracer._build_normalized(
		surfaces, mirror_tracked.mobius, conj_n2s, null, [mirror_tracked])

	var conj_inv_surf: Surface = null
	for ns in conj_norms:
		if conj_n2s.get(ns.segment) == scene.inversion:
			conj_inv_surf = ns
			break
	assert_not_null(conj_inv_surf, "Should find inversion in CONJ norms")
	var norm_inv_tracked := (conj_inv_surf.active_side_config(
		Side.Value.LEFT, GameState.new()).effect as TransformativeEffect).get_tracked_transform()

	var arc_stack := [mirror_tracked, norm_inv_tracked]
	var arc_frame := MobiusTransform.identity()
	arc_frame = arc_frame.compose(mirror_tracked.mobius)
	arc_frame = arc_frame.compose(norm_inv_tracked.mobius)
	var arc_frame_inv := arc_frame.invert()

	var arc_n2s := {}
	var arc_norms := Tracer._build_normalized(
		surfaces, arc_frame, arc_n2s, null, arc_stack)

	for i in arc_norms.size():
		var norm_surf: Surface = arc_norms[i]
		var orig_surf: Surface = arc_n2s.get(norm_surf.segment)
		if orig_surf == null:
			continue
		if norm_surf.segment == orig_surf.segment:
			continue

		var expected_start := arc_frame_inv.apply(orig_surf.segment.start.coords)
		var expected_end := arc_frame_inv.apply(orig_surf.segment.end.coords)
		var _expected_via := arc_frame_inv.apply(orig_surf.segment.via.coords)

		if is_inf(expected_start.x) or is_inf(expected_start.y):
			continue
		if is_inf(norm_surf.segment.start.coords.x) or is_inf(norm_surf.segment.start.coords.y):
			continue

		var err_start := norm_surf.segment.start.coords.distance_to(expected_start)
		var err_end := norm_surf.segment.end.coords.distance_to(expected_end)

		assert_lt(err_start, 1e-6,
			"Surface %d start should match frame_inv.apply(original) (err=%.6f)" % [orig_surf.id, err_start])
		if not (is_inf(expected_end.x) or is_inf(expected_end.y) or is_inf(norm_surf.segment.end.coords.x)):
			assert_lt(err_end, 1e-6,
				"Surface %d end should match frame_inv.apply(original) (err=%.6f)" % [orig_surf.id, err_end])

# --- Scene builder (same as test_stage51) ---

func _build_scene() -> Dictionary:
	var room_walls := RoomBuilder.create_room_surfaces(Rect2(160, 90, 1600, 900))
	var mirror_left := _mirror_line(Vector2(500, 200), Vector2(500, 700))
	var mirror_right := _mirror_line(Vector2(1400, 300), Vector2(1400, 800))
	var mirror_bottom := _mirror_line(Vector2(700, 800), Vector2(1200, 800))
	var mirror_mid := _mirror_right_line(Vector2(960, 200), Vector2(960, 500))
	var inv_seg := Segment.from_coords(Vector2(1100, 400), Vector2(1100, 700), Vector2(1230, 550))
	var inv_effect := CircleInversionEffect.new(inv_seg.get_carrier())
	var inv_surf := Surface.new(inv_seg, SideConfig.new(inv_effect, true), SideConfig.new(null, false), false, true)
	var screen_bounds := _screen_bounds()
	var surfaces: Array = []
	surfaces.append_array(room_walls)
	surfaces.append(mirror_left)
	surfaces.append(mirror_right)
	surfaces.append(mirror_bottom)
	surfaces.append(mirror_mid)
	surfaces.append(inv_surf)
	surfaces.append_array(screen_bounds)
	return {
		"surfaces": surfaces,
		"inversion": inv_surf,
		"mirror_bottom": mirror_bottom,
	}

func _mirror_line(start: Vector2, end_v: Vector2) -> Surface:
	var mid := (start + end_v) / 2.0
	var seg := Segment.from_coords(start, end_v, mid)
	var refl := ReflectionEffect.new(seg.get_carrier())
	return Surface.new(seg, SideConfig.new(refl, true), SideConfig.new(null, false), false, false)

func _mirror_right_line(start: Vector2, end_v: Vector2) -> Surface:
	var mid := (start + end_v) / 2.0
	var seg := Segment.from_coords(start, end_v, mid)
	var refl := ReflectionEffect.new(seg.get_carrier())
	return Surface.new(seg, SideConfig.new(null, false), SideConfig.new(refl, true), false, false)

func _screen_bounds() -> Array:
	var result: Array = []
	var bounds_defs := [
		[Vector2(0, 0), Vector2(1920, 0)],
		[Vector2(1920, 0), Vector2(1920, 1080)],
		[Vector2(1920, 1080), Vector2(0, 1080)],
		[Vector2(0, 1080), Vector2(0, 0)],
	]
	for bd in bounds_defs:
		var s: Vector2 = bd[0]
		var e: Vector2 = bd[1]
		var config := SideConfig.new(null, false)
		result.append(Surface.new(Segment.from_coords(s, e, (s + e) / 2.0), config, config, false, false))
	return result
