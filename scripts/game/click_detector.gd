class_name ClickDetector
extends RefCounted

const CLICK_TOLERANCE := 8.0

var _last_cycle_position := Vector2.ZERO
var _last_cycle_index := -1

func detect_click(cursor_pos: Vector2, surfaces: Array) -> Dictionary:
	var best_surface: Surface = null
	var best_side: Side.Value = Side.Value.LEFT
	var best_dist := INF

	for surf in surfaces:
		var dist := _distance_to_segment(cursor_pos, surf.segment)
		if dist > CLICK_TOLERANCE:
			continue

		var side: Side.Value = surf.segment.determine_side(cursor_pos)
		var config: SideConfig = surf.active_side_config(side, GameState.new())
		if not config.interactive:
			continue

		if dist < best_dist:
			best_dist = dist
			best_surface = surf
			best_side = side

	if best_surface == null:
		return {}

	return {"surface": best_surface, "side": best_side, "distance": best_dist}

func detect_hover(cursor_pos: Vector2, surfaces: Array) -> Dictionary:
	return detect_click(cursor_pos, surfaces)

static func _distance_to_segment(point: Vector2, segment: Segment) -> float:
	var a := segment.start.coords
	var b := segment.end.coords
	var ab := b - a
	var ap := point - a
	var ab_len_sq := ab.length_squared()

	if ab_len_sq == 0.0:
		return point.distance_to(a)

	var t := clampf(ab.dot(ap) / ab_len_sq, 0.0, 1.0)
	var nearest := a + ab * t
	return point.distance_to(nearest)
