class_name Point
extends RefCounted

enum Provenance { ORIGIN, BOUNCE, IMAGE, CORNER, CURSOR, SEGMENT_START, SEGMENT_END, SEGMENT_VIA }

static var _next_id: int = 1

var id: int
var position: Vector2
var provenance: Provenance

func _init(p_position: Vector2, p_provenance: Provenance = Provenance.ORIGIN) -> void:
	id = _next_id
	_next_id += 1
	position = p_position
	provenance = p_provenance

static func reset_id_counter() -> void:
	_next_id = 1
