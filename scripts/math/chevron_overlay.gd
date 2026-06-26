class_name ChevronOverlay
extends RefCounted

var side: int = -1
var has_incoming: bool = true
var has_outgoing: bool = true
var outgoing_side: int = -1
var incoming_color: Color = Color.WHITE
var outgoing_color: Color = Color.WHITE
var gradient_color: Color = Color.WHITE

static func hover(p_side: int, p_has_outgoing: bool, p_outgoing_side: int,
		hover_color: Color, p_has_incoming: bool = true) -> ChevronOverlay:
	var o := ChevronOverlay.new()
	o.side = p_side
	o.has_incoming = p_has_incoming
	o.has_outgoing = p_has_outgoing
	o.outgoing_side = p_outgoing_side
	o.incoming_color = hover_color
	o.outgoing_color = hover_color
	o.gradient_color = hover_color
	return o

static func plan(p_side: int, p_has_outgoing: bool, p_outgoing_side: int,
		p_incoming_color: Color, p_outgoing_color: Color,
		p_gradient_color: Color, p_has_incoming: bool = true) -> ChevronOverlay:
	var o := ChevronOverlay.new()
	o.side = p_side
	o.has_incoming = p_has_incoming
	o.has_outgoing = p_has_outgoing
	o.outgoing_side = p_outgoing_side
	o.incoming_color = p_incoming_color
	o.outgoing_color = p_outgoing_color
	o.gradient_color = p_gradient_color
	return o
