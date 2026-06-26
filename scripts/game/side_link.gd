class_name SideLink
extends RefCounted

var surface: Surface
var side: Side.Value
var outgoing: SideLink

static func from_self(surf: Surface, p_side: Side.Value) -> SideLink:
	var link := SideLink.new()
	link.surface = surf
	link.side = p_side
	link.outgoing = link
	return link

static func from_pair(surf_a: Surface, side_a: Side.Value,
		surf_b: Surface, side_b: Side.Value) -> SideLink:
	var a := SideLink.new()
	var b := SideLink.new()
	a.surface = surf_a
	a.side = side_a
	a.outgoing = b
	b.surface = surf_b
	b.side = side_b
	b.outgoing = a
	return a
