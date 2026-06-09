class_name VisualConverter
extends RefCounted

const POINTS_PER_FULL_CIRCLE := 256
const MAX_ARC_RADIUS := 100000.0

static func is_arc(start: Vector2, via: Vector2, end_v: Vector2) -> bool:
	if is_inf(end_v.x) or is_inf(end_v.y):
		return false
	if is_inf(start.x) or is_inf(start.y):
		return false
	if start.distance_squared_to(end_v) < 1e-10:
		return false
	var seg := Segment.new(start, end_v, via)
	var carrier := seg.get_carrier()
	if carrier.is_line():
		return false
	return carrier.radius() < MAX_ARC_RADIUS

static func arc_params(start: Vector2, via: Vector2, end_v: Vector2) -> Dictionary:
	var seg := Segment.new(start, end_v, via)
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

	var point_count := maxi(4, int(POINTS_PER_FULL_CIRCLE * span / TAU))

	var draw_start := sa
	var draw_end := ea
	if clockwise:
		draw_start = ea
		draw_end = sa

	return {
		"center": ctr,
		"radius": r,
		"start_angle": draw_start,
		"end_angle": draw_end,
		"clockwise": clockwise,
		"point_count": point_count,
		"span": span,
	}
