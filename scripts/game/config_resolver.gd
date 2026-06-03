class_name ConfigResolver
extends RefCounted

func resolve(side: Side.Value, _game_state: GameState) -> SideConfig:
	return null

class FixedResolver extends ConfigResolver:
	var left: SideConfig
	var right: SideConfig

	func _init(p_left: SideConfig, p_right: SideConfig) -> void:
		left = p_left
		right = p_right

	func resolve(side: Side.Value, _game_state: GameState) -> SideConfig:
		if side == Side.Value.LEFT:
			return left
		return right
