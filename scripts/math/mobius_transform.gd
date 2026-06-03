class_name MobiusTransform
extends RefCounted

var id: int

static var IDENTITY_ID := 0

func _init(p_id: int) -> void:
	id = p_id

static func identity() -> MobiusTransform:
	return MobiusTransform.new(IDENTITY_ID)
