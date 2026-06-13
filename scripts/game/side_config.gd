class_name SideConfig
extends RefCounted

var effect: Effect
var state_change = null
var interactive: bool

func _init(p_effect: Effect = null, p_interactive: bool = false, p_state_change = null) -> void:
	effect = p_effect
	interactive = p_interactive
	state_change = p_state_change
