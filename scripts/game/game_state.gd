class_name GameState
extends RefCounted

var flags: Dictionary = {}

func _init(p_flags: Dictionary = {}) -> void:
	flags = p_flags

func copy() -> GameState:
	var new_flags: Dictionary = {}
	for key in flags:
		var val = flags[key]
		if val is Dictionary:
			new_flags[key] = val.duplicate(true)
		elif val is Array:
			new_flags[key] = val.duplicate(true)
		else:
			new_flags[key] = val
	return GameState.new(new_flags)
