extends GutTest

func _carrier_desc(carrier: GeneralizedCircle) -> String:
	if carrier.is_line():
		if absf(carrier.b) > absf(carrier.c):
			return "vert x=%.1f" % (-carrier.d / carrier.b)
		else:
			return "horiz y=%.1f" % (-carrier.d / carrier.c)
	else:
		return "circle c=(%.1f,%.1f) r=%.1f" % [carrier.center().x, carrier.center().y, carrier.radius()]

func _carrier_dist(point: Vector2, carrier: GeneralizedCircle) -> float:
	var f := carrier.evaluate(point)
	var gx := 2.0 * carrier.a * point.x + carrier.b
	var gy := 2.0 * carrier.a * point.y + carrier.c
	var grad := sqrt(gx * gx + gy * gy)
	if grad < 1e-10:
		return INF
	return absf(f) / grad

func _min_carrier_dist(point: Vector2, surfaces: Array) -> Array:
	var min_d := INF
	var nearest := ""
	for surf in surfaces:
		var s: Surface = surf
		var d := _carrier_dist(point, s.segment.get_carrier())
		if d < min_d:
			min_d = d
			nearest = _carrier_desc(s.segment.get_carrier())
	return [min_d, nearest]

func _parse_step_index(text: String) -> int:
	var regex := RegEx.new()
	regex.compile("step (\\d+) visual")
	var m := regex.search(text)
	return int(m.get_string(1)) if m else -1

func _parse_endpoint(text: String) -> Vector2:
	var regex := RegEx.new()
	regex.compile("endpoint \\(([\\d.-]+), ([\\d.-]+)\\)")
	var m := regex.search(text)
	return Vector2(float(m.get_string(1)), float(m.get_string(2))) if m else Vector2(INF, INF)

func _parse_trace_name(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("VISUAL-ON-CARRIER: (\\w+) step")
	var m := regex.search(text)
	return m.get_string(1) if m else ""

func test_investigate_visual_on_carrier():
	var json_path := "user://violations.json"
	if not FileAccess.file_exists(json_path):
		pending("No violations.json found")
		return

	var file := FileAccess.open(json_path, FileAccess.READ)
	var json = JSON.parse_string(file.get_as_text())
	file.close()

	var carrier_violations := []
	for entry in json:
		if "VISUAL-ON-CARRIER" in str(entry["violation"]):
			carrier_violations.append(entry)

	gut.p("=== VISUAL-ON-CARRIER Deep Investigation ===")
	gut.p("Total violations to investigate: %d" % carrier_violations.size())
	gut.p("")

	# Reset ID counters ONCE before scene load (matching sweep test)
	Surface.reset_id_counter()
	MobiusTransform.reset_id_counter()

	var scene_path: String = carrier_violations[0]["scene"]
	var scene: Node = load(scene_path).instantiate()
	scene.gravity = Vector2.ZERO
	add_child_autofree(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var surfaces: Array = scene.surfaces
	gut.p("=== Scene Carriers (%d surfaces) ===" % surfaces.size())
	for i in surfaces.size():
		var surf: Surface = surfaces[i]
		gut.p("  Surface %d (id=%d): %s" % [i, surf.id, _carrier_desc(surf.segment.get_carrier())])
	gut.p("")

	var renderer := scene.get_node_or_null("PathRenderer")
	var game_mgr := scene.get_node_or_null("GameManager")
	var player_node := scene.get_node_or_null("Player")
	var cursor_node := scene.get_node_or_null("Cursor")

	var rows := []
	var reproduced_count := 0
	var not_reproduced_count := 0

	for vi in carrier_violations.size():
		var entry = carrier_violations[vi]
		var pp: Array = entry["player_pos"]
		var cp: Array = entry["cursor_pos"]
		var player_pos := Vector2(pp[0], pp[1])
		var cursor_pos := Vector2(cp[0], cp[1])
		var v_text: String = entry["violation"]
		var step_idx := _parse_step_index(v_text)
		var expected_ep := _parse_endpoint(v_text)
		var trace_name := _parse_trace_name(v_text)

		var plan_data: Array = entry["plan"]
		if player_node:
			player_node.position = player_pos
		if cursor_node:
			cursor_node.position = cursor_pos
		if game_mgr and "plan" in game_mgr:
			game_mgr.plan.clear()
			for pe in plan_data:
				game_mgr.plan.add_entry(int(pe["surface_id"]), int(pe["side"]))

		renderer._compute_trace()

		var path: Tracer.TracedPath = null
		if trace_name == "physical":
			path = renderer.get_traced_path()
		elif trace_name == "planned":
			path = renderer.get_planned_path()

		if path == null or step_idx >= path.steps.size():
			gut.p("--- #%d UNREPRODUCIBLE: step %d out of range (total=%d) ---" % [
				vi, step_idx, path.steps.size() if path else 0])
			gut.p("  %s" % v_text)
			gut.p("  plan=%s" % str(plan_data))
			not_reproduced_count += 1
			rows.append({
				"vi": vi, "reproduced": false, "step": step_idx, "frame_id": -1,
				"dist_orig": -1.0, "dist_inv": -1.0, "hit_on_carrier": -1.0,
				"end_recon": -1.0,
			})
			continue

		var step: Tracer.Step = path.steps[step_idx]
		var end_pos := step.end
		var ep_match := end_pos.distance_to(expected_ep) < 1.0

		if not ep_match:
			gut.p("--- #%d ENDPOINT MISMATCH: actual=%s expected=%s dist=%.2f ---" % [
				vi, end_pos, expected_ep, end_pos.distance_to(expected_ep)])
			gut.p("  %s" % v_text)
			gut.p("  plan=%s" % str(plan_data))
			not_reproduced_count += 1
			rows.append({
				"vi": vi, "reproduced": false, "step": step_idx,
				"frame_id": step.frame_id,
				"dist_orig": -1.0, "dist_inv": -1.0, "hit_on_carrier": -1.0,
				"end_recon": -1.0,
			})
			continue

		reproduced_count += 1

		# 1. dist_to_original: min distance from step.end to original carriers
		var orig_result := _min_carrier_dist(end_pos, surfaces)
		var dist_orig: float = orig_result[0]
		var nearest_orig: String = orig_result[1]

		# 2. dist_via_inverse: back-transform step.end to physical space, check original carriers
		var dist_inv := INF
		var nearest_inv := ""
		if step.frame != null:
			var frame_inv: MobiusTransform = step.frame.invert()
			var phys_point: Vector2 = frame_inv.apply(end_pos)
			if not (is_inf(phys_point.x) or is_inf(phys_point.y)):
				var inv_result := _min_carrier_dist(phys_point, surfaces)
				dist_inv = inv_result[0]
				nearest_inv = inv_result[1]

		# 3. hit_on_carrier: hitpoint distance to its own hit segment's carrier
		var hit_on_carrier := -1.0
		if step.hit != null and step.hit.segment != null:
			hit_on_carrier = _carrier_dist(step.hit.point.coords, step.hit.segment.get_carrier())

		# 4. end_reconstruction: step.end vs frame.apply(hitpoint)
		var end_recon := -1.0
		if step.hit != null and step.frame != null:
			var reconstructed: Vector2 = step.frame.apply(step.hit.point.coords)
			if not (is_inf(reconstructed.x) or is_inf(reconstructed.y)):
				end_recon = end_pos.distance_to(reconstructed)

		gut.p("--- #%d REPRODUCED ---" % vi)
		gut.p("  %s" % v_text)
		gut.p("  plan=%s  frame_id=%d" % [str(plan_data), step.frame_id])
		gut.p("  dist_to_original=%.4f  nearest=%s" % [dist_orig, nearest_orig])
		gut.p("  dist_via_inverse=%.4f  nearest=%s" % [dist_inv, nearest_inv])
		gut.p("  hit_on_carrier=%.6f" % hit_on_carrier)
		gut.p("  end_reconstruction=%.6f" % end_recon)
		gut.p("")

		rows.append({
			"vi": vi, "reproduced": true, "step": step_idx,
			"frame_id": step.frame_id,
			"dist_orig": dist_orig, "dist_inv": dist_inv,
			"hit_on_carrier": hit_on_carrier, "end_recon": end_recon,
		})

	gut.p("")
	gut.p("=== REPRODUCTION SUMMARY ===")
	gut.p("Reproduced: %d / %d" % [reproduced_count, carrier_violations.size()])
	gut.p("Not reproduced: %d" % not_reproduced_count)
	gut.p("")
	gut.p("=== DATA TABLE (reproduced only) ===")
	gut.p("%-4s %-5s %-8s %-14s %-14s %-14s %-14s" % [
		"#", "Step", "FrID", "DistOrig", "DistInverse", "HitOnCarr", "EndRecon"])
	gut.p("-".repeat(80))
	for r in rows:
		if not r["reproduced"]:
			continue
		gut.p("%-4d %-5d %-8d %-14.4f %-14.4f %-14.6f %-14.6f" % [
			r["vi"], r["step"], r["frame_id"],
			r["dist_orig"], r["dist_inv"],
			r["hit_on_carrier"], r["end_recon"]])

	gut.p("")
	gut.p("=== NOT REPRODUCED ===")
	for r in rows:
		if r["reproduced"]:
			continue
		gut.p("  #%d step=%d frame_id=%d" % [r["vi"], r["step"], r["frame_id"]])

	pass_test("Investigation complete — see diagnostic output above")
