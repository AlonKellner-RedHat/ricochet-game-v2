class_name VisualConverter
extends RefCounted

const POINTS_PER_FULL_CIRCLE := 256
const MAX_ARC_RADIUS := 100000.0
const DEFAULT_BOUNDS := Rect2(0, 0, 1920, 1080)

static func prepare_for_display(path: Tracer.TracedPath, bounds: Rect2) -> Tracer.TracedPath:
	var has_inf := false
	for step: Tracer.Step in path.steps:
		if is_inf(step.via.x) and is_inf(step.via.y):
			has_inf = true
			break
	if not has_inf:
		return path

	var grown := bounds.grow(1.0)
	var result := Tracer.TracedPath.new()
	result.targets_hit = path.targets_hit
	result.cursor_index = path.cursor_index
	var cursor_shift := 0
	for i in path.steps.size():
		var step: Tracer.Step = path.steps[i]
		if not (is_inf(step.via.x) and is_inf(step.via.y)):
			result.steps.append(step)
			continue
		var start_in := grown.has_point(step.start)
		var end_in := grown.has_point(step.end)
		if step.hit != null or (start_in and end_in):
			var vis_dir := (step.end - step.start).normalized()
			if vis_dir == Vector2.ZERO:
				var via_mid := (step.start + step.end) / 2.0
				result.steps.append(Tracer.Step.new(step.start, step.end, step.frame_id, step.hit, step.ray, step.frame, via_mid, false))
				continue
			var esc := _clip_to_bounds(step.start, -vis_dir, bounds)
			var ret := _clip_to_bounds(step.end, vis_dir, bounds)
			var via_out := (step.start + esc) / 2.0 if step.start != esc else step.start
			var via_in := (ret + step.end) / 2.0 if ret != step.end else step.end
			result.steps.append(Tracer.Step.new(step.start, esc, step.frame_id, null, step.ray, step.frame, via_out, false))
			result.steps.append(Tracer.Step.new(ret, step.end, step.frame_id, step.hit, step.ray, step.frame, via_in, false))
			if i < path.cursor_index:
				cursor_shift += 1
		elif start_in:
			var vis_dir := (step.end - step.start).normalized()
			var clip := _clip_to_bounds(step.start, vis_dir, bounds)
			var via_mid := (step.start + clip) / 2.0
			result.steps.append(Tracer.Step.new(step.start, clip, step.frame_id, step.hit, step.ray, step.frame, via_mid, false))
		elif end_in:
			var vis_dir := (step.end - step.start).normalized()
			var clip := _clip_to_bounds(step.end, -vis_dir, bounds)
			var via_mid := (clip + step.end) / 2.0
			result.steps.append(Tracer.Step.new(clip, step.end, step.frame_id, step.hit, step.ray, step.frame, via_mid, false))
		else:
			var via_mid := (step.start + step.end) / 2.0
			result.steps.append(Tracer.Step.new(step.start, step.end, step.frame_id, step.hit, step.ray, step.frame, via_mid, false))
	if path.cursor_index >= 0:
		result.cursor_index = path.cursor_index + cursor_shift
	return result

static func _clip_to_bounds(origin: Vector2, dir: Vector2, bounds: Rect2) -> Vector2:
	var min_t := INF
	if dir.x > 0.0:
		min_t = minf(min_t, (bounds.end.x - origin.x) / dir.x)
	elif dir.x < 0.0:
		min_t = minf(min_t, (bounds.position.x - origin.x) / dir.x)
	if dir.y > 0.0:
		min_t = minf(min_t, (bounds.end.y - origin.y) / dir.y)
	elif dir.y < 0.0:
		min_t = minf(min_t, (bounds.position.y - origin.y) / dir.y)
	if is_inf(min_t) or min_t < 0.0:
		min_t = 100.0
	return origin + dir * min_t

static func is_arc(start: Vector2, via: Vector2, end_v: Vector2) -> bool:
	if is_inf(end_v.x) or is_inf(end_v.y):
		return false
	if is_inf(start.x) or is_inf(start.y):
		return false
	if start == end_v:
		return false
	var seg := Segment.from_coords(start, end_v, via)
	var carrier := seg.get_carrier()
	if carrier.is_line():
		return false
	return carrier.radius() < MAX_ARC_RADIUS

static func arc_params(start: Vector2, via: Vector2, end_v: Vector2) -> Dictionary:
	var seg := Segment.from_coords(start, end_v, via)
	var carrier := seg.get_carrier()
	if carrier.is_line():
		return {"center": Vector2.ZERO, "radius": 0.0, "start_angle": 0.0, "end_angle": 0.0, "clockwise": false, "point_count": 2, "span": 0.0}
	var ctr := carrier.center()
	var r := carrier.radius()

	var sa := (start - ctr).angle()
	var ea := (end_v - ctr).angle()

	var cross := (start - ctr).cross(via - ctr)
	var clockwise := cross < 0.0

	var span: float
	if clockwise:
		span = sa - ea
		if span < 0.0:
			span += TAU
	else:
		span = ea - sa
		if span < 0.0:
			span += TAU

	var via_angle := (via - ctr).angle()
	var via_diff: float
	if clockwise:
		via_diff = fposmod(sa - via_angle, TAU)
	else:
		via_diff = fposmod(via_angle - sa, TAU)
	if via_diff > span:
		clockwise = not clockwise
		span = TAU - span

	var point_count := maxi(4, int(POINTS_PER_FULL_CIRCLE * span / TAU))

	var draw_start := sa
	var draw_end := sa + span * (-1.0 if clockwise else 1.0)

	return {
		"center": ctr,
		"radius": r,
		"start_angle": draw_start,
		"end_angle": draw_end,
		"clockwise": clockwise,
		"point_count": point_count,
		"span": span,
	}
